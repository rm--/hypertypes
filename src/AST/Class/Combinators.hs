{-# LANGUAGE NoImplicitPrelude, KindSignatures, DataKinds, FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses, ConstraintKinds, UndecidableSuperClasses #-}
{-# LANGUAGE UndecidableInstances #-}

-- TODO: Document and find good names!

module AST.Class.Combinators
    ( And
    , NoConstraint
    , HasChildrenConstraint
    , TieHasConstraint
    , proxyNoConstraint
    ) where

import AST.Class.Children (Children(..))
import AST.Knot (Knot, Tie)
import Data.Proxy (Proxy(..))

-- Join two classes for usage with `children`/`ChildrenConstraint` or `Recursive`.
class    (c0 k, c1 k) => And c0 c1 (k :: Knot -> *)
instance (c0 k, c1 k) => And c0 c1 k

class    NoConstraint (k :: Knot -> *)
instance NoConstraint k

class    ChildrenConstraint k c => HasChildrenConstraint c k
instance ChildrenConstraint k c => HasChildrenConstraint c k

class    constraint (Tie outer k) => TieHasConstraint constraint outer k
instance constraint (Tie outer k) => TieHasConstraint constraint outer k

proxyNoConstraint :: Proxy NoConstraint
proxyNoConstraint = Proxy
