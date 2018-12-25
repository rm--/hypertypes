{-# LANGUAGE NoImplicitPrelude, TemplateHaskell, TypeFamilies, DataKinds #-}

module AST.Unify.IntMapBinding
    ( IntBindingState, emptyIntBindingState
    , intBindingState
    , increase
    ) where

import           AST.Knot (Tree)
import           AST.Unify (UVar, Binding(..))
import           AST.Unify.Term
import qualified Control.Lens as Lens
import           Control.Lens (ALens')
import           Control.Lens.Operators
import           Control.Monad.State (MonadState(..), modify)
import           Data.Functor.Const (Const(..))
import           Data.IntMap (IntMap)
import           Data.Maybe (fromMaybe)

import           Prelude.Compat

data IntBindingState t = IntBindingState
    { _nextFreeVar :: {-# UNPACK #-} !Int
    , _varBindings :: IntMap (UTerm (Const Int) t)
    }
Lens.makeLenses ''IntBindingState

emptyIntBindingState :: IntBindingState t
emptyIntBindingState = IntBindingState 0 mempty

increase ::
    MonadState s m =>
    ALens' s Int -> m Int
increase l =
    do
        r <- Lens.use (Lens.cloneLens l)
        r <$ modify (Lens.cloneLens l +~ 1)

intBindingState ::
    (MonadState s m, UVar m ~ Const Int) =>
    ALens' s (Tree IntBindingState t) ->
    Binding m t
intBindingState l =
    Binding
    { lookupVar =
        \k ->
        Lens.use (Lens.cloneLens l . varBindings . Lens.at (k ^. Lens._Wrapped))
        <&> fromMaybe (error "variable not found!")
    , newVar =
        \x ->
        do
            k <- increase (Lens.cloneLens l . nextFreeVar) <&> Const
            k <$ bind k x
    , bindVar = bind
    }
    where
        bind k v = Lens.cloneLens l . varBindings . Lens.at (k ^. Lens._Wrapped) ?= v
