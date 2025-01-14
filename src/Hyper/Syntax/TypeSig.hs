-- | Type signatures

{-# LANGUAGE UndecidableInstances, TemplateHaskell, FlexibleInstances, FlexibleContexts #-}

module Hyper.Syntax.TypeSig
    ( TypeSig(..), tsType, tsTerm, W_TypeSig(..)
    ) where

import           Generics.Constraints (Constraints)
import           Hyper
import           Hyper.Infer
import           Hyper.Syntax.Scheme
import           Hyper.Unify (UnifyGen, unify)
import           Hyper.Unify.Generalize (instantiateWith)
import           Hyper.Unify.Term (UTerm(..))
import           Text.PrettyPrint ((<+>))
import qualified Text.PrettyPrint as Pretty
import           Text.PrettyPrint.HughesPJClass (Pretty(..), maybeParens)

import           Hyper.Internal.Prelude

data TypeSig vars term h = TypeSig
    { _tsTerm :: h :# term
    , _tsType :: h :# Scheme vars (TypeOf term)
    } deriving Generic

makeLenses ''TypeSig
makeCommonInstances [''TypeSig]
makeHTraversableApplyAndBases ''TypeSig

instance
    Constraints (TypeSig vars term h) Pretty =>
    Pretty (TypeSig vars term h) where
    pPrintPrec lvl p (TypeSig term typ) =
        pPrintPrec lvl 1 term <+> Pretty.text ":" <+> pPrintPrec lvl 1 typ
        & maybeParens (p > 1)

type instance InferOf (TypeSig _ t) = InferOf t

instance
    ( MonadScopeLevel m
    , HasInferredType term
    , HasInferredValue (TypeOf term)
    , HTraversable vars
    , HTraversable (InferOf term)
    , HNodesConstraint (InferOf term) (UnifyGen m)
    , HNodesConstraint vars (MonadInstantiate m)
    , UnifyGen m (TypeOf term)
    , Infer m (TypeOf term)
    , Infer m term
    ) =>
    Infer m (TypeSig vars term) where

    inferBody (TypeSig x s) =
        do
            InferredChild xI xR <- inferChild x
            InferredChild sI sR <- inferChild s
            (t, ()) <- instantiateWith (pure ()) USkolem (sR ^. _HFlip)
            xR & inferredType (Proxy @term) #%%~ unify t
                <&> (TypeSig xI sI, )
        & localLevel
