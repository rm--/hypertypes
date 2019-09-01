-- | 'Arbitrary' instance for annotated ASTs, respecting scopes.

{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS -fno-warn-orphans #-} -- Arbitrary instances

module AST.Knot.Ann.Arbitrary
    ( ArbitraryWithContext(..)
    , ArbitraryWithContextOf
    ) where

import AST.Knot (Node)
import AST.Knot.Ann (Ann(..))
import Test.QuickCheck (Arbitrary(..), Gen)

import Prelude.Compat hiding (any)

-- Useful for ASTs
class Arbitrary a => ArbitraryWithContext a where
    type Context a
    arbitraryCtx :: Context a -> Gen a

type ArbitraryWithContextOf c a = (ArbitraryWithContext a, Context a ~ c)

instance (Arbitrary a, Arbitrary (Node k (Ann a))) => Arbitrary (Ann a k) where
    arbitrary = Ann <$> arbitrary <*> arbitrary

instance (Arbitrary a, ArbitraryWithContext (Node k (Ann a))) => ArbitraryWithContext (Ann a k) where
    type Context (Ann a k) = Context (Node k (Ann a))
    arbitraryCtx ctx = Ann <$> arbitrary <*> arbitraryCtx ctx
