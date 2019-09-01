{-# LANGUAGE TemplateHaskell #-}

module AST.Infer.ScopeLevel
    ( ScopeLevel(..), _ScopeLevel
    , MonadScopeLevel(..)
    ) where

import           Algebra.PartialOrd (PartialOrd(..))
import           AST.Unify.Constraints (TypeConstraints(..))
import           Control.DeepSeq (NFData)
import           Data.Binary (Binary)
import           Control.Lens (makePrisms)
import           GHC.Generics (Generic)
import qualified Text.PrettyPrint as Pretty
import           Text.PrettyPrint.HughesPJClass (Pretty(..))

import           Prelude.Compat

-- | A representation of scope nesting level,
-- for use in let-generalization and skolem escape detection.
--
-- See ["Efficient generalization with levels"](http://okmij.org/ftp/ML/generalization.html#levels)
-- for a detailed explanation.
--
-- Commonly used as the 'AST.Unify.Constraints.TypeConstraintsOf' of terms.
--
-- /Note/: The 'Ord' instance is only for use as a 'Data.Map.Map' key, not a
-- logical ordering, for which 'PartialOrd' is used.
newtype ScopeLevel = ScopeLevel Int
    deriving stock (Eq, Ord, Show, Generic)
makePrisms ''ScopeLevel

instance PartialOrd ScopeLevel where
    {-# INLINE leq #-}
    ScopeLevel x `leq` ScopeLevel y = x >= y

instance Semigroup ScopeLevel where
    {-# INLINE (<>) #-}
    ScopeLevel x <> ScopeLevel y = ScopeLevel (min x y)

instance Monoid ScopeLevel where
    {-# INLINE mempty #-}
    mempty = ScopeLevel maxBound

instance TypeConstraints ScopeLevel where
    {-# INLINE generalizeConstraints #-}
    generalizeConstraints _ = mempty
    toScopeConstraints = id

instance Pretty ScopeLevel where
    pPrint (ScopeLevel x) = Pretty.text "scope#" <> pPrint x

instance NFData ScopeLevel
instance Binary ScopeLevel

-- | A class of 'Monad's which maintain a scope level,
-- where the level can be locally increased for computations.
class Monad m => MonadScopeLevel m where
    localLevel :: m a -> m a
