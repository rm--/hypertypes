{-# LANGUAGE NoImplicitPrelude, DataKinds, TypeFamilies, RankNTypes #-}
{-# LANGUAGE MultiParamTypeClasses, FlexibleInstances, DefaultSignatures, FlexibleContexts #-}
{-# LANGUAGE ConstraintKinds, TypeOperators, ScopedTypeVariables, UndecidableInstances #-}

module AST.Unify.Constraints
    ( TypeConstraints(..)
    , HasTypeConstraints(..)
    , TypeConstraintsAre
    , MonadScopeConstraints(..)
    ) where

import Algebra.Lattice (JoinSemiLattice(..))
import Algebra.PartialOrd (PartialOrd(..))
import AST
import AST.Class.Combinators (And)
import Data.Proxy (Proxy(..))

import Prelude.Compat

class (PartialOrd c, JoinSemiLattice c) => TypeConstraints c where
    -- | Remove scope constraints
    --
    -- When generalizing unification variables into universally
    -- quantified variables, and then into fresh unification variables
    -- upon instantiation, some constraints need to be carried over,
    -- and the "scope" constraints need to be erased.
    generalizeConstraints :: c -> c

class
    TypeConstraints (TypeConstraintsOf ast) =>
    HasTypeConstraints (ast :: Knot -> *) where

    type TypeConstraintsOf ast

    -- | Verify constraints on the ast and apply the given child
    -- verifier on children
    verifyConstraints ::
        (Applicative m, ChildrenWithConstraint ast childOp) =>
        Proxy childOp ->
        TypeConstraintsOf ast ->
        (TypeConstraintsOf ast -> m ()) ->
        (forall child. childOp child => TypeConstraintsOf child -> Tree p child -> m (Tree q child)) ->
        Tree ast p -> m (Tree ast q)
    -- | A default implementation for when the verification only needs
    -- to propagate the unchanged constraints to the direct AST
    -- children
    {-# INLINE verifyConstraints #-}
    default verifyConstraints ::
        forall m childOp p q.
        ( ChildrenWithConstraint ast (childOp `And` TypeConstraintsAre (TypeConstraintsOf ast))
        , Applicative m
        ) =>
        Proxy childOp ->
        TypeConstraintsOf ast ->
        (TypeConstraintsOf ast -> m ()) ->
        (forall child. childOp child => TypeConstraintsOf child -> Tree p child -> m (Tree q child)) ->
        Tree ast p -> m (Tree ast q)
    verifyConstraints _ constraints _ update =
        children (Proxy :: Proxy (childOp `And` TypeConstraintsAre (TypeConstraintsOf ast)))
        (update constraints)

class TypeConstraintsOf ast ~ constraints => TypeConstraintsAre constraints ast
instance TypeConstraintsOf ast ~ constraints => TypeConstraintsAre constraints ast

class Monad m => MonadScopeConstraints c m where
    scopeConstraints :: m c
