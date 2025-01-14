-- | A 'Hyper.Type.HyperType' to express the simplest plain form of a nested higher-kinded data structure.
--
-- The value level [hyperfunctions](http://hackage.haskell.org/package/hyperfunctions)
-- equivalent of 'Pure' is called @self@ in
-- [Hyperfunctions papers](https://arxiv.org/abs/1309.5135).

{-# LANGUAGE UndecidableInstances, TemplateHaskell, FlexibleContexts #-}
module Hyper.Type.Pure
    ( Pure(..), _Pure, W_Pure(..)
    ) where

import Control.Lens (iso)
import Hyper.TH.Traversable (makeHTraversableApplyAndBases)
import Hyper.Type (type (#), type (:#))
import Text.PrettyPrint.HughesPJClass (Pretty(..))

import Hyper.Internal.Prelude

-- | A 'Hyper.Type.HyperType' to express the simplest plain form of a nested higher-kinded data structure
newtype Pure h = Pure (h :# Pure)
    deriving stock Generic

makeHTraversableApplyAndBases ''Pure
makeCommonInstances [''Pure]

-- | An 'Iso' from 'Pure' to its content.
--
-- Using `_Pure` rather than the 'Pure' data constructor is recommended,
-- because it helps the type inference know that 'Pure' is parameterized with a 'Hyper.Type.HyperType'.
{-# INLINE _Pure #-}
_Pure :: Iso (Pure # h) (Pure # j) (h # Pure) (j # Pure)
_Pure = iso (\(Pure x) -> x) Pure

instance Pretty (h :# Pure) => Pretty (Pure h) where
    pPrintPrec lvl p (Pure x) = pPrintPrec lvl p x
