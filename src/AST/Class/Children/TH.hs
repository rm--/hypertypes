{-# LANGUAGE NoImplicitPrelude, TemplateHaskell, LambdaCase #-}

module AST.Class.Children.TH
    ( makeChildren
    , -- Internals for use in TH for sub-classes
      CtrTypePattern(..), CtrCase(..)
    , parts, matchType, applicativeStyle, isPolymorphic
    ) where

import           AST.Class.Children (Children(..))
import           AST.Class.Children.Mono (ChildOf)
import           AST.Knot (Knot(..), RunKnot, Tie)
import qualified Control.Lens as Lens
import           Control.Lens.Operators
import           Control.Monad.Trans.Class (MonadTrans(..))
import           Control.Monad.Trans.State (StateT(..), evalStateT, gets, modify)
import qualified Data.Map as Map
import           Data.Set (Set)
import qualified Data.Set as Set
import           Language.Haskell.TH
import qualified Language.Haskell.TH.Datatype as D

import           Prelude.Compat

makeChildren :: Name -> DecsQ
makeChildren typeName = makeTypeInfo typeName >>= makeChildrenForType

data TypeInfo = TypeInfo
    { tiInstance :: Type
    , tiVar :: Name
    , tiContents :: TypeContents
    , tiCons :: [D.ConstructorInfo]
    } deriving Show

data TypeContents = TypeContents
    { tcChildren :: Set Type
    , tcEmbeds :: Set Type
    , tcOthers :: Set Type
    } deriving Show

instance Semigroup TypeContents where
    TypeContents x0 x1 x2 <> TypeContents y0 y1 y2 =
        TypeContents (x0 <> y0) (x1 <> y1) (x2 <> y2)

instance Monoid TypeContents where
    mempty = TypeContents mempty mempty mempty

makeTypeInfo :: Name -> Q TypeInfo
makeTypeInfo name =
    do
        info <- D.reifyDatatype name
        (dst, var) <- parts info
        contents <- evalStateT (childrenTypes var (AppT dst (VarT var))) mempty
        pure TypeInfo
            { tiInstance = dst
            , tiVar = var
            , tiContents = contents
            , tiCons = D.datatypeCons info
            }

makeChildrenForType :: TypeInfo -> DecsQ
makeChildrenForType info =
    do
        inst <-
            instanceD (pure ctx) (appT (conT ''Children) (pure (tiInstance info)))
            [ tySynInstD ''ChildrenConstraint
                (pure (TySynEqn [tiInstance info, VarT constraintVar] childrenConstraint))
            , InlineP 'children Inline FunLike AllPhases & PragmaD & pure
            , funD 'children (tiCons info <&> pure . ccClause . makeChildrenCtr (tiVar info))
            ]
        mono <-
            case Set.toList (tcChildren contents) of
            [x] | Set.null (tcEmbeds contents) ->
                tySynInstD ''ChildOf
                (pure (TySynEqn [tiInstance info] x))
                <&> (:[])
            _ -> pure []
        inst : mono & pure
    where
        contents = tiContents info
        ctx = childrenContext info
        childrenConstraint =
            (Set.toList (tcChildren contents) <&> (VarT constraintVar `AppT`))
            <> (Set.toList (tcEmbeds contents) <&>
                \x -> ConT ''ChildrenConstraint `AppT` x `AppT` VarT constraintVar)
            <> Set.toList (tcOthers contents)
            & toTuple

constraintVar :: Name
constraintVar = mkName "constraint"

toTuple :: Foldable t => t Type -> Type
toTuple xs = foldl AppT (TupleT (length xs)) xs

childrenContext :: TypeInfo -> [Pred]
childrenContext info =
    tiCons info <&> makeChildrenCtr (tiVar info) >>= ccContext & Set.fromList & Set.toList

parts :: D.DatatypeInfo -> Q (Type, Name)
parts info =
    case D.datatypeVars info of
    [] -> fail "expected type constructor which requires arguments"
    xs ->
        case last xs of
        SigT (VarT var) (ConT knot) | knot == ''Knot -> pure (res, var)
        VarT var -> pure (res, var)
        _ -> fail "expected last argument to be a knot variable"
        where
            res = foldl AppT (ConT (D.datatypeName info)) (init xs <&> stripSigT)
    where
        stripSigT (SigT x _) = x
        stripSigT x = x

childrenTypes ::
    Name -> Type -> StateT (Set Type) Q TypeContents
childrenTypes var typ =
    do
        did <- gets (^. Lens.contains typ)
        if did
            then pure mempty
            else modify (Lens.contains typ .~ True) *> add (matchType var typ)
    where
        add (NodeFofX ast) = pure mempty { tcChildren = Set.singleton ast }
        add (XofF ast) =
            case unapply ast of
            (ConT name, as) -> childrenTypesFromTypeName name as
            (x@VarT{}, as) -> pure mempty { tcEmbeds = Set.singleton (foldl AppT x as) }
            _ -> pure mempty
        add (Tof _ pat) = add pat
        add Other{} = pure mempty

unapply :: Type -> (Type, [Type])
unapply =
    go []
    where
        go as (AppT f a) = go (a:as) f
        go as x = (x, as)

matchType :: Name -> Type -> CtrTypePattern
matchType var (ConT runKnot `AppT` VarT k `AppT` (PromotedT knot `AppT` ast))
    | runKnot == ''RunKnot && knot == 'Knot && k == var =
        NodeFofX ast
matchType var (ConT tie `AppT` VarT k `AppT` ast)
    | tie == ''Tie && k == var =
        NodeFofX ast
matchType var (ast `AppT` VarT knot)
    | knot == var && ast /= ConT ''RunKnot =
        XofF ast
matchType var x@(AppT t typ) =
    -- TODO: check if applied over a functor-kinded type.
    case matchType var typ of
    Other{} -> Other x
    pat -> Tof t pat
matchType _ t = Other t

data CtrTypePattern
    = NodeFofX Type
    | XofF Type
    | Tof Type CtrTypePattern
    | Other Type
    deriving Show

childrenTypesFromTypeName ::
    Name -> [Type] -> StateT (Set Type) Q TypeContents
childrenTypesFromTypeName name args =
    reifyInstances ''ChildrenConstraint [typ, VarT constraintVar] & lift
    >>=
    \case
    [] ->
        do
            info <- D.reifyDatatype name & lift
            let substs =
                    zip (D.datatypeVars info) args
                    >>= filterVar
                    & Map.fromList
            (_, var) <- parts info & lift
            D.datatypeCons info >>= D.constructorFields
                <&> D.applySubstitution substs
                & traverse (childrenTypes var)
                <&> mconcat
    [TySynInstD ccI (TySynEqn [typI, VarT cI] x)]
        | ccI == ''ChildrenConstraint ->
            case unapply typI of
            (ConT n1, argsI) | n1 == name ->
                case traverse getVar argsI of
                Nothing ->
                    error ("TODO: Support Children constraint of flexible instances " <> show typ)
                Just argNames ->
                    childrenTypesFromChildrenConstraint cI (D.applySubstitution substs x)
                    where
                        substs = zip argNames args & Map.fromList
            _ -> error ("ReifyInstances brought wrong typ: " <> show (name, typI))
    xs -> error ("Malformed ChildrenConstraint instance: " <> show xs)
    where
        filterVar (VarT n, x) = [(n, x)]
        filterVar (SigT t _, x) = filterVar (t, x)
        filterVar _ = []
        typ = foldl AppT (ConT name) args
        getVar (VarT x) = Just x
        getVar _ = Nothing

childrenTypesFromChildrenConstraint ::
    Name -> Type -> StateT (Set Type) Q TypeContents
childrenTypesFromChildrenConstraint c0 c@(AppT (VarT c1) x)
    | c0 == c1 = pure mempty { tcChildren = Set.singleton x }
    | otherwise = error ("TODO: Unsupported ChildrenContraint " <> show c)
childrenTypesFromChildrenConstraint c0 constraints =
    case unapply constraints of
    (ConT cc1, [x, VarT c1])
        | cc1 == ''ChildrenConstraint && c0 == c1 ->
            pure mempty { tcEmbeds = Set.singleton x }
    (TupleT{}, xs) ->
        traverse (childrenTypesFromChildrenConstraint c0) xs <&> mconcat
    _ -> pure mempty { tcOthers = Set.singleton (D.applySubstitution subst constraints) }
    where
        subst = mempty & Lens.at c0 ?~ VarT constraintVar

makeChildrenCtr :: Name -> D.ConstructorInfo -> CtrCase
makeChildrenCtr var info =
    CtrCase
    { ccClause =
        Clause
        [VarP proxy, VarP func, ConP (D.constructorName info) (cVars <&> VarP)]
        (NormalB body) []
    , ccContext = pats >>= ctxForPat
    }
    where
        proxy = mkName "_p"
        func = mkName "_f"
        cVars =
            [0::Int ..] <&> show <&> ('x':) <&> mkName
            & take (length (D.constructorFields info))
        body =
            zipWith AppE
            (pats <&> bodyForPat)
            (cVars <&> VarE)
            & applicativeStyle (ConE (D.constructorName info))
        pats = D.constructorFields info <&> matchType var
        bodyForPat NodeFofX{} = VarE func
        bodyForPat XofF{} = VarE 'children `AppE` VarE proxy `AppE` VarE func
        bodyForPat (Tof _ pat) = VarE 'traverse `AppE` bodyForPat pat
        bodyForPat Other{} = VarE 'pure
        ctxForPat (Tof t pat) = [ConT ''Traversable `AppT` t | isPolymorphic t] ++ ctxForPat pat
        ctxForPat (XofF t) = [ConT ''Children `AppT` t | isPolymorphic t]
        ctxForPat _ = []

applicativeStyle :: Exp -> [Exp] -> Exp
applicativeStyle f =
    foldl ap (AppE (VarE 'pure) f)
    where
        ap x y = InfixE (Just x) (VarE '(<*>)) (Just y)

data CtrCase =
    CtrCase
    { ccClause :: Clause
    , ccContext :: [Pred]
    }

isPolymorphic :: Type -> Bool
isPolymorphic VarT{} = True
isPolymorphic (AppT x y) = isPolymorphic x || isPolymorphic y
isPolymorphic (ParensT x) = isPolymorphic x
isPolymorphic ConT{} = False
isPolymorphic ArrowT{} = False
isPolymorphic ListT{} = False
isPolymorphic EqualityT{} = False
isPolymorphic TupleT{} = False
isPolymorphic UnboxedTupleT{} = False
isPolymorphic UnboxedSumT{} = False
isPolymorphic _ =
    -- TODO: Cover all cases
    True
