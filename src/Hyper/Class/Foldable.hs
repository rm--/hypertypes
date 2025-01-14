-- | A variant of 'Foldable' for 'Hyper.Type.HyperType's

{-# LANGUAGE FlexibleContexts #-}

module Hyper.Class.Foldable
    ( HFoldable(..)
    , hfolded1
    , htraverse_, htraverse1_
    ) where

import Control.Lens (Fold, folding)
import GHC.Generics
import Hyper.Class.Nodes (HNodes(..), HWitness(..), _HWitness, (#>))
import Hyper.Type (type (#))

import Hyper.Internal.Prelude

-- | A variant of 'Foldable' for 'Hyper.Type.HyperType's
class HNodes h => HFoldable h where
    -- | 'HFoldable' variant of 'foldMap'
    --
    -- Gets a function from @h@'s nodes (trees along witnesses that they are nodes of @h@)
    -- into a monoid and concats its results for all nodes.
    hfoldMap ::
        Monoid a =>
        (forall n. HWitness h n -> p # n -> a) ->
        h # p ->
        a
    {-# INLINE hfoldMap #-}
    default hfoldMap ::
        ( Generic1 h, HFoldable (Rep1 h), HWitnessType h ~ HWitnessType (Rep1 h)
        , Monoid a
        ) =>
        (forall n. HWitness h n -> p # n -> a) ->
        h # p ->
        a
    hfoldMap f = hfoldMap (f . (_HWitness %~ id)) . from1

instance HFoldable (Const a) where
    {-# INLINE hfoldMap #-}
    hfoldMap _ = mempty

instance (HFoldable a, HFoldable b) => HFoldable (a :*: b) where
    {-# INLINE hfoldMap #-}
    hfoldMap f (x :*: y) =
        hfoldMap (f . HWitness . L1) x <>
        hfoldMap (f . HWitness . R1) y

instance (HFoldable a, HFoldable b) => HFoldable (a :+: b) where
    {-# INLINE hfoldMap #-}
    hfoldMap f (L1 x) = hfoldMap (f . HWitness . L1) x
    hfoldMap f (R1 x) = hfoldMap (f . HWitness . R1) x

deriving newtype instance HFoldable h => HFoldable (M1 i m h)
deriving newtype instance HFoldable h => HFoldable (Rec1 h)

-- | 'HFoldable' variant for 'Control.Lens.folded' for 'Hyper.Type.HyperType's with a single node type.
--
-- Avoids using @RankNTypes@ and thus can be composed with other optics.
{-# INLINE hfolded1 #-}
hfolded1 ::
    forall h n p.
    ( HFoldable h
    , HNodesConstraint h ((~) n)
    ) =>
    Fold (h # p) (p # n)
hfolded1 =
    folding (hfoldMap @_ @[p # n] (Proxy @((~) n) #> pure))

-- | 'HFoldable' variant of 'Data.Foldable.traverse_'
--
-- Applise a given action on all subtrees
-- (represented as trees along witnesses that they are nodes of @h@)
{-# INLINE htraverse_ #-}
htraverse_ ::
    (Applicative f, HFoldable h) =>
    (forall c. HWitness h c -> m # c -> f ()) ->
    h # m ->
    f ()
htraverse_ f = sequenceA_ . hfoldMap (fmap (:[]) . f)

-- | 'HFoldable' variant of 'Data.Foldable.traverse_' for 'Hyper.Type.HyperType's with a single node type (avoids using @RankNTypes@)
{-# INLINE htraverse1_ #-}
htraverse1_ ::
    forall f h n p.
    ( Applicative f, HFoldable h
    , HNodesConstraint h ((~) n)
    ) =>
    (p # n -> f ()) ->
    h # p ->
    f ()
htraverse1_ f = htraverse_ (Proxy @((~) n) #> f)
