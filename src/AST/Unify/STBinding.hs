{-# LANGUAGE NoImplicitPrelude, TypeFamilies, TemplateHaskell #-}

module AST.Unify.STBinding
    ( STVar, stBindingState
    ) where

import AST.Unify (Binding(..), UVar)
import AST.Unify.Term (UTerm(..))
import Control.Lens (makePrisms)
import Control.Lens.Operators
import Control.Monad.ST.Class (MonadST(..))
import Data.STRef (STRef, newSTRef, readSTRef, writeSTRef)

import Prelude.Compat

newtype STVar s t = STVar (STRef s (UTerm (STVar s) t))
makePrisms ''STVar

instance Eq (STVar s a) where
    STVar x == STVar y = x == y

stBindingState ::
    (MonadST m, UVar m ~ STVar (World m)) =>
    Binding m t
stBindingState =
    Binding
    { lookupVar = liftST . readSTRef . (^. _STVar)
    , newVar = \t -> newSTRef t & liftST <&> STVar
    , bindVar = \v t -> writeSTRef (v ^. _STVar) t & liftST
    }
