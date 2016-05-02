{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PatternSynonyms       #-}
{-# LANGUAGE PolyKinds             #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE UndecidableInstances  #-}
-- | Tools for ad-hoc reader monad environments.
--
-- A bit like in @vinyl@ - package, but reimplemented for @generics-sop@ data
-- structures.
--
-- TODO: move to own package once stabilised.
module Futurice.Has (
    Has(..),
    IsElem(..),
    IsElem',
    IsSubset(..),
    IsSubset',
    type (<::),
    ) where

import Control.Lens      (Lens', Prism', lens, set, view)
import Generics.SOP      (I (..), NP (..), NS (..))
import Generics.SOP.Lens (headLens, tailLens, uni, _S, _Z)

import Futurice.Peano

-- | Poor man 'Has' type-class. Useful with reader and state monads.
--
-- The inversed type parameterds are also handy for specifying reader environment:
--
-- @
-- foobarAction
--    :: (MonadIO m, MonadReader env m, All (Has env) '[ConfFoo, ConfBar])
--    => m ()
-- @
class Has r f where
    field :: Lens' r f

-- | n-ary products from "Generics.SOP" 'Has' all fields in it.
--
-- This is extremly handy for specifying ad-hoc environments.
instance IsElem x xs (Index x xs) => Has (NP I xs) x where
    field = proj . uni

-- | The dictionary-less version of 'IsElem'.
class i ~ Index a xs => IsElem' a xs i
instance IsElem' x (x ': xs) 'PZ
instance ('PS i ~ Index x (y ': ys), IsElem' x ys i) => IsElem' x (y ': ys) ('PS i)

-- | Class to look into products and sums thru lenses and prisms.
class IsElem' a xs i => IsElem a xs i where
    proj :: forall f. Lens'  (NP f xs) (f a)
    inj  :: forall f. Prism' (NS f xs) (f a)

instance IsElem x (x ': xs) 'PZ where
    proj = headLens
    inj  = _Z

instance ('PS i ~ Index x (y ': ys), IsElem x ys i) => IsElem x (y ': ys) ('PS i) where
    proj = tailLens . proj
    inj  = _S . inj

-- | The dictionary-less version of 'IsSubset'.
class (is ~ Image xs ys) => IsSubset' xs ys is
instance IsSubset' '[] ys '[]
instance (IsElem' x ys i, IsSubset' xs ys is) => IsSubset' (x ': xs) ys (i ': is)

-- | Class to look into subsets thru lenses and prisms
--
-- TODO: add  @injs@ - prism
class IsSubset' xs ys is => IsSubset xs ys is where
    projs :: forall f. Lens' (NP f ys) (NP f xs)

instance IsSubset '[] ys '[] where
    projs = lens (const Nil) const

instance (IsElem x ys i, IsSubset xs ys is) => IsSubset (x ': xs) ys (i ': is) where
    projs = lens v s
      where
        v ys = view proj ys :* view projs ys
        s :: NP f ys -> NP f (x ': xs) -> NP f ys
        s ys (x :* xs) = set proj x (set projs xs ys)

type xs <:: ys = IsSubset' xs ys (Image xs ys)
