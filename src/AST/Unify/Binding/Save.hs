{-# LANGUAGE ScopedTypeVariables, FlexibleContexts #-}

module AST.Unify.Binding.Save
    ( save
    ) where

import           AST
import           AST.Class.Has (HasChild(..))
import           AST.Class.Unify (Unify(..), UVarOf, BindingDict(..))
import           AST.Unify.Binding (Binding, _Binding, UVar(..))
import           AST.Unify.Term (UTerm(..), uBody)
import qualified Control.Lens as Lens
import           Control.Lens.Operators
import           Control.Monad.Trans.Class (MonadTrans(..))
import           Control.Monad.Trans.State (StateT(..))
import           Data.Constraint (withDict)
import           Data.Proxy (Proxy(..))
import qualified Data.Sequence as Sequence

import           Prelude.Compat

saveUTerm ::
    forall m typeVars t.
    ( Unify m t
    , Recursively (HasChild typeVars) t
    ) =>
    Tree (UTerm (UVarOf m)) t ->
    StateT (Tree typeVars Binding, [m ()]) m (Tree (UTerm UVar) t)
saveUTerm (UUnbound c) = UUnbound c & pure
saveUTerm (USkolem c) = USkolem c & pure
saveUTerm (UToVar v) = saveVar v <&> UToVar
saveUTerm (UTerm u) = uBody saveBody u <&> UTerm
saveUTerm UInstantiated{} = error "converting bindings during instantiation"
saveUTerm UResolving{} = error "converting bindings after resolution"
saveUTerm UResolved{} = error "converting bindings after resolution"
saveUTerm UConverted{} = error "converting variable again"

saveVar ::
    ( Unify m t
    , Recursively (HasChild typeVars) t
    ) =>
    Tree (UVarOf m) t ->
    StateT (Tree typeVars Binding, [m ()]) m (Tree UVar t)
saveVar v =
    lookupVar binding v & lift
    >>=
    \case
    UConverted i -> pure (UVar i)
    srcBody ->
        do
            pb <- Lens.use (Lens._1 . getChild)
            let r = pb ^. _Binding & Sequence.length
            UConverted r & bindVar binding v & lift
            Lens._2 %= (<> [bindVar binding v srcBody])
            dstBody <- saveUTerm srcBody
            Lens._1 . getChild .= (pb & _Binding %~ (Sequence.|> dstBody))
            UVar r & pure

saveBody ::
    forall m typeVars t.
    ( Unify m t
    , Recursively (HasChild typeVars) t
    ) =>
    Tree t (UVarOf m) ->
    StateT (Tree typeVars Binding, [m ()]) m (Tree t UVar)
saveBody =
    withDict (unifyRecursive (Proxy @m) (Proxy @t)) $
    withDict (recursive @(HasChild typeVars) @t) $
    traverseKWith (Proxy @'[Unify m, Recursively (HasChild typeVars)]) saveVar

save ::
    ( Unify m t
    , Recursively (HasChild typeVars) t
    ) =>
    Tree t (UVarOf m) ->
    StateT (Tree typeVars Binding) m (Tree t UVar)
save collection =
    StateT $
    \dstState ->
    do
        (r, (finalState, recover)) <- runStateT (saveBody collection) (dstState, [])
        (r, finalState) <$ sequence_ recover
