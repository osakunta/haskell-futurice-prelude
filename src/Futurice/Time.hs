{-# LANGUAGE DataKinds              #-}
{-# LANGUAGE FlexibleContexts       #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE KindSignatures         #-}
{-# LANGUAGE OverloadedStrings      #-}
{-# LANGUAGE TypeFamilies           #-}
-- | Influenced by <http://hackage.haskell.org/package/time-units-1.0.0/docs/Data-Time-Units.html>.
module Futurice.Time (
    NDT (..),
    TimeUnit (..),
    IsTimeUnit (..),
    -- * Conversions
    -- ** NominalDiffTime
    toNominalDiffTime,
    fromNominalDiffTime,
    -- ** Units
    ndtConvert,
    ndtConvert',
    -- * Internal
    AsScientific,
    ) where

import Futurice.Prelude
import Prelude ()

import Control.Lens       (Prism', prism', ( # ))
import Data.Aeson         (FromJSON (..), ToJSON (..))
import Data.Binary        (Binary (..))
import Data.Binary.Tagged (HasSemanticVersion, HasStructuralInfo)
import Data.Fixed         (Fixed, HasResolution)
import Data.Swagger       (NamedSchema (..), ToSchema (..))
import GHC.TypeLits
       (KnownNat, KnownSymbol, Nat, Symbol, natVal, symbolVal)
import Lucid              (ToHtml (..))
import Test.QuickCheck    (Arbitrary (..), CoArbitrary (..))

import Text.PrettyPrint.ANSI.Leijen.AnsiPretty (AnsiPretty (..))

import qualified Data.Aeson         as Aeson
import qualified Data.Csv           as Csv
import qualified Data.Scientific    as Scientific
import qualified Data.Text.Encoding as TE
import qualified Lucid

data TimeUnit
    = Fortnights
    | Weeks
    | Days
    | Hours
    | Minutes
    | Seconds
  deriving (Eq, Ord, Show, Typeable, Enum, Bounded)

class (KnownNat (InSeconds tu), KnownSymbol (TimeUnitSfx tu))
    => IsTimeUnit (tu :: TimeUnit)
  where
    type InSeconds   tu :: Nat
    type TimeUnitSfx tu :: Symbol

instance IsTimeUnit 'Seconds where
    type InSeconds   'Seconds    = 1
    type TimeUnitSfx 'Seconds    = "s"
instance IsTimeUnit 'Minutes where
    type InSeconds   'Minutes    = 60
    type TimeUnitSfx 'Minutes    = "m"
instance IsTimeUnit 'Hours where
    type InSeconds   'Hours      = 3600
    type TimeUnitSfx 'Hours      = "h"
instance IsTimeUnit 'Days where
    type InSeconds   'Days       = 86400
    type TimeUnitSfx 'Days       = "d"
instance IsTimeUnit 'Weeks where
    type InSeconds   'Weeks      = 604800
    type TimeUnitSfx 'Weeks      = "w"
instance IsTimeUnit 'Fortnights where
    type InSeconds   'Fortnights = 1209600
    type TimeUnitSfx 'Fortnights = "fn"

-- | Nominal diff time with unit
newtype NDT (tu :: TimeUnit) a = NDT a
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Generic)

instance Hashable a => Hashable (NDT tu a) where
    hashWithSalt salt (NDT x) = hashWithSalt salt x

instance NFData a => NFData (NDT tu a) where
    rnf (NDT x) = rnf x

instance Binary a => Binary (NDT tu a) where
    put (NDT x) = put x
    get = fmap NDT get

-- | /TODO/ prepend unit
instance AnsiPretty a => AnsiPretty (NDT tu a) where
    ansiPretty (NDT x) = ansiPretty x

-- | /TODO/ use unit
instance HasStructuralInfo a => HasStructuralInfo (NDT tu a)
instance HasSemanticVersion (NDT tu a)

instance Arbitrary a => Arbitrary (NDT tu a) where
    arbitrary      = NDT <$> arbitrary
    shrink (NDT x) = NDT <$> shrink x

instance CoArbitrary a => CoArbitrary (NDT tu a) where
    coarbitrary (NDT x) = coarbitrary x

-- | Instances are encoded / decoded as is. I.e. unit is irrelevant
--
-- /TODO/: encode as object?
instance AsScientific a => FromJSON (NDT tu a) where
    parseJSON x = do
        s <- parseJSON x
        maybe (fail "Cannot convert from scientific") (pure . NDT) (s ^? _Scientific)

instance AsScientific a => ToJSON (NDT tu a) where
    toJSON (NDT x) = toJSON (_Scientific # x)

instance (ToJSON a, Show a, IsTimeUnit tu) => ToHtml (NDT tu a) where
    toHtmlRaw = toHtml
    toHtml (NDT x) = Lucid.span_
        [ Lucid.data_ "futu-value" $ TE.decodeUtf8 (json ^. strict) ]
        $ toHtmlRaw $ show x <> nbsp <> sfx
      where
        json = Aeson.encode x
        sfx  = symbolVal (Proxy :: Proxy (TimeUnitSfx tu))
        nbsp = "&nbsp;" :: String

instance Num a => Num (NDT tu a) where
    NDT x + NDT y = NDT (x + y)
    NDT x - NDT y = NDT (x - y)
    NDT x * NDT y = NDT (x * y)
    negate (NDT x) = NDT (negate x)
    abs (NDT x)  = NDT (abs x)
    signum (NDT x) = NDT (signum x)
    fromInteger = NDT . fromInteger

instance Csv.ToField a => Csv.ToField (NDT tu a) where
    toField (NDT x) = Csv.toField x

instance Csv.FromField a => Csv.FromField (NDT tu a) where
    parseField = fmap NDT . Csv.parseField

instance (ToSchema a,  IsTimeUnit tu) => ToSchema (NDT tu a) where
    declareNamedSchema _ = do
        NamedSchema _ schema <- declareNamedSchema (Proxy :: Proxy a)
        pure $ NamedSchema (Just $ "NDT " <> sfx ^. packed) schema
     where
       sfx  = symbolVal (Proxy :: Proxy (TimeUnitSfx tu))

-------------------------------------------------------------------------------
-- Helper class to convert from/to Scientific
-------------------------------------------------------------------------------

class AsScientific a where
    _Scientific :: Prism' Scientific a

instance AsScientific Int where
    _Scientific = prism' fromIntegral Scientific.toBoundedInteger

instance HasResolution a => AsScientific (Fixed a) where
    _Scientific = prism' scientificFromReal scientificToRational

scientificFromReal :: Real a => a -> Scientific
scientificFromReal =
    either fst fst . Scientific.fromRationalRepetend Nothing . toRational

scientificToRational :: Fractional a => Scientific -> Maybe a
scientificToRational = Just . fromRational . toRational

-------------------------------------------------------------------------------
-- Functions
-------------------------------------------------------------------------------

fromNominalDiffTime :: NominalDiffTime -> NDT 'Seconds Integer
fromNominalDiffTime = NDT . truncate

toNominalDiffTime :: NDT 'Seconds Integer -> NominalDiffTime
toNominalDiffTime (NDT x) = fromInteger x

ndtConvert
    :: forall t u a. (IsTimeUnit t, IsTimeUnit u, Fractional a)
    => NDT t a -> NDT u a
ndtConvert (NDT x) = NDT $
    -- first multiply, then divide. Important when using fixed-precision data types
    (x * fromInteger (natVal pt)) / fromInteger (natVal pu)
  where
    pt = Proxy :: Proxy (InSeconds t)
    pu = Proxy :: Proxy (InSeconds u)

-- | Like 'ndtConvert', but may change the carrier from integral type
ndtConvert'
    :: (IsTimeUnit t, IsTimeUnit u, Fractional a, Integral b)
    => NDT t b -> NDT u a
ndtConvert' = ndtConvert . fmap fromIntegral
