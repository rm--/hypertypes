{-# LANGUAGE UndecidableInstances, ScopedTypeVariables, TemplateHaskell, FlexibleInstances #-}

module Hyper.Type.Prune
    ( Prune(..)
    ) where

import           Hyper
import           Hyper.Class.Traversable
import           Hyper.Class.Unify (Unify)
import           Hyper.Type.Combinator.Compose (Compose(..))
import           Hyper.Infer
import           Hyper.Unify.New (newUnbound)
import           Hyper.TH.Internal.Instances (makeCommonInstances)
import qualified Control.Lens as Lens
import           Control.Lens.Operators
import           Data.Constraint (Dict(..), withDict)
import           Data.Proxy (Proxy(..))
import           GHC.Generics (Generic)

import           Prelude.Compat

data Prune k =
    Pruned | Unpruned (k # Prune)
    deriving Generic

makeCommonInstances [''Prune]
Lens.makePrisms ''Prune
makeKTraversableAndBases ''Prune
makeZipMatch ''Prune

-- `KPointed` and `KApplicative` instances in the spirit of `Maybe`

instance KPointed Prune where
    pureK f = Unpruned (f W_Prune_Prune)

instance KApply Prune where
    zipK Pruned _ = Pruned
    zipK _ Pruned = Pruned
    zipK (Unpruned x) (Unpruned y) = Pair x y & Unpruned

instance RNodes Prune
instance c Prune => Recursively c Prune
instance RTraversable Prune

type instance InferOf (Compose Prune t) = InferOf t

instance
    ( Infer m t
    , KPointed (InferOf t)
    , KTraversable (InferOf t)
    ) =>
    Infer m (Compose Prune t) where
    inferBody (MkCompose Pruned) =
        withDict (inferContext (Proxy @m) (Proxy @t)) $
        pureK (Proxy @(Unify m) #> MkContainedK newUnbound)
        & sequenceK
        <&> (MkCompose Pruned, )
    inferBody (MkCompose (Unpruned (MkCompose x))) =
        mapK
        ( \_ (MkCompose (InferChild i)) ->
            i <&> (\(InferredChild r t) -> InferredChild (MkCompose r) t)
            & InferChild
        ) x
        & inferBody
        <&> Lens._1 %~ MkCompose . Unpruned . MkCompose
    inferContext m t = withDict (inferContext m t) Dict