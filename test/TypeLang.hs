{-# LANGUAGE MultiParamTypeClasses, StandaloneDeriving, UndecidableInstances #-}
{-# LANGUAGE TemplateHaskell, TypeFamilies, FlexibleInstances, FlexibleContexts #-}

module TypeLang where

import           AST
import           AST.Class.Infer.ScopeLevel
import           AST.Class.Instantiate
import           AST.Term.FuncType
import           AST.Term.RowExtend
import           AST.Term.Scheme
import           AST.Term.Scope
import           AST.Unify
import           AST.Unify.Constraints
import           AST.Unify.IntMapBinding
import           AST.Unify.Term
import           Algebra.Lattice
import           Algebra.PartialOrd
import           Control.Applicative
import qualified Control.Lens as Lens
import           Control.Lens.Operators
import           Data.STRef
import           Data.Set (Set, singleton)
import qualified Text.PrettyPrint as Pretty
import           Text.PrettyPrint.HughesPJClass (Pretty(..))

data Typ k
    = TInt
    | TFun (FuncType Typ k)
    | TRec (Tie k Row)
    | TVar String

data Row k
    = REmpty
    | RExtend (RowExtend String Typ Row k)
    | RVar String

data RConstraints = RowConstraints
    { _rForbiddenFields :: Set String
    , _rScope :: QuantificationScope
    } deriving (Eq, Show)

data Types k = Types
    { _tTyp :: Tie k Typ
    , _tRow :: Tie k Row
    }

Lens.makePrisms ''Typ
Lens.makePrisms ''Row
Lens.makeLenses ''RConstraints
Lens.makeLenses ''Types
makeChildrenAndZipMatch [''Typ, ''Row, ''Types]

deriving instance SubTreeConstraint Typ f Show => Show (Typ f)
deriving instance SubTreeConstraint Row f Show => Show (Row f)

instance SubTreeConstraint Typ k Pretty => Pretty (Typ k) where
    pPrint TInt = Pretty.text "Int"
    pPrint (TFun x) = pPrint x
    pPrint (TRec x) = pPrint x
    pPrint (TVar s) = '#':s & Pretty.text

instance SubTreeConstraint Row k Pretty => Pretty (Row k) where
    pPrint REmpty = Pretty.text "{}"
    pPrint (RExtend x) = pPrint x
    pPrint (RVar s) = '#':s & Pretty.text

instance HasChild Types Typ where getChild = tTyp
instance HasChild Types Row where getChild = tRow

instance PartialOrd RConstraints where
    RowConstraints f0 s0 `leq` RowConstraints f1 s1 = f0 `leq` f1 && s0 `leq` s1

instance JoinSemiLattice RConstraints where
    RowConstraints f0 s0 \/ RowConstraints f1 s1 = RowConstraints (f0 \/ f1) (s0 \/ s1)

instance RowConstraints RConstraints where
    type RowConstraintsKey RConstraints = String
    forbidden = rForbiddenFields

instance HasTypeConstraints Typ where
    type TypeConstraintsOf Typ = QuantificationScope
    applyConstraints _ _ _ _ TInt = pure TInt
    applyConstraints _ _ _ _ (TVar v) = TVar v & pure
    applyConstraints _ c _ u (TFun f) = monoChildren (u c) f <&> TFun
    applyConstraints _ c _ u (TRec r) = u (RowConstraints mempty c) r <&> TRec

instance HasTypeConstraints Row where
    type TypeConstraintsOf Row = RConstraints
    applyConstraints _ _ _ _ REmpty = pure REmpty
    applyConstraints _ _ _ _ (RVar x) = RVar x & pure
    applyConstraints p c e u (RExtend x) =
        applyRowConstraints p c (^. rScope) (e . (`RowConstraints` mempty) . singleton) u RExtend x

type IntInferState = (Tree Types IntBindingState, Tree Types (Const Int))

emptyIntInferState :: IntInferState
emptyIntInferState =
    ( Types emptyIntBindingState emptyIntBindingState
    , Types (Const 0) (Const 0)
    )

type STInferState s = Tree Types (Const (STRef s Int))

type instance SchemeType (Tree Pure Typ) = Typ
instance Recursive (Unify m) Typ => Instantiate m (Tree Pure Typ)

instance HasQuantifiedVar Typ where
    type QVar Typ = String
    quantifiedVar = _TVar

instance HasQuantifiedVar Row where
    type QVar Row = String
    quantifiedVar = _RVar

instance HasFuncType Typ where
    funcType = _TFun

instance HasScopeTypes v Typ a => HasScopeTypes v Typ (a, x) where
    scopeTypes = Lens._1 . scopeTypes

instance HasScopeTypes v Typ a => HasScopeTypes v Typ (a, x, y) where
    scopeTypes = Lens._1 . scopeTypes

rStructureMismatch ::
    (Alternative m, Recursive (Unify m) Row) =>
    Tree (UTermBody (UVar m)) Row -> Tree (UTermBody (UVar m)) Row -> m (Tree Row (UVar m))
rStructureMismatch (UTermBody c0 (RExtend r0)) (UTermBody c1 (RExtend r1)) =
    rowStructureMismatch (newTerm . RExtend) (c0, r0) (c1, r1) <&> RExtend
rStructureMismatch _ _ = empty
