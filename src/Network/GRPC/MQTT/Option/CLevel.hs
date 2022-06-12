{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE TemplateHaskellQuotes #-}

-- | This module exports the 'CLevel' datatype and definitions.
--
-- == Zstd Compression Levels
--
-- #zstd-compression-levels#
--
-- Zstandard offers compression levels for controlling how the algorithm favors
-- speed vs. compression ratio. The supported range for a compression levels is
-- from 1 to 22.
--
-- * @'CLevel' 1@ is the achieves the fastest compression speed.
--
-- * @'CLevel' 19@ is slow, but yields a high compression ratio.
--
-- * @'CLevel' 20@ through @'CLevel' 22@ are labeled "ultra". These settings are
--   slow and require more memory, but result in the highest compression ratios.
--
-- [Zstandard's docs](raw.githack.com/facebook/zstd/release/doc/zstd_manual.html)
-- detail compression levels under the "introduction" section.
--
-- == Protobuf Options
--
-- TODO
--
-- === File Options
--
-- TODO
--
-- === Service Options
--
-- TODO
--
-- === Method Options
--
-- TODO
--
-- @since 0.1.0.0
module Network.GRPC.MQTT.Option.CLevel
  ( -- * CLevel
    CLevel (CLevel, getCLevel),

    -- * Construction
    fromCLevel,
    toCLevel,
    setCLevels,

    -- * Predicates
    isCLevel,
  )
where

----------------------------------------------------------------------------------

import Codec.Compression.Zstd qualified as Zstd

import Data.Data (Data)

import Language.Haskell.TH.Syntax (Lift)

import Proto3.Suite.Class
  ( Finite (enumerate),
    Named (nameOf),
    Primitive (decodePrimitive, encodePrimitive, primType),
  )
import Proto3.Suite.DotProto qualified as DotProto

import Proto3.Wire.Class (ProtoEnum (fromProtoEnum, toProtoEnumMay))
import Proto3.Wire.Decode qualified as Decode
import Proto3.Wire.Encode qualified as Encode

import Relude

import Text.Show qualified as Show

----------------------------------------------------------------------------------

import Network.GRPC.MQTT.Proto
  ( DatumRep (DRepIdent),
    ProtoDatum,
    castDatum,
    castFiniteRep,
    datumRep,
  )

import Proto3.Wire.Decode.Extra qualified as Decode

-- CLevel ------------------------------------------------------------------------

-- | 'CLevel' is an enumeration capturing all compression levels that zstandard
-- supports. See ["Compression Levels" section](#zstd-compression-levels) for
-- documentation on zstandard's compression levels.
--
-- Constructing 'CLevel' should be done via 'toCLevel' unless the underlying 'Int'
-- value is known to always be between @1@ and @22@ (inclusively).
--
-- @since 0.1.0.0
newtype CLevel = CLevel {getCLevel :: Int}
  deriving newtype (Eq, Ord)
  deriving stock (Data, Generic, Lift, Typeable)
  deriving anyclass (Named)

-- |
-- @'minBound' == 'CLevel' 1@
--
-- @'maxBound' == 'CLevel' 22@
--
-- @since 0.1.0.0
instance Bounded CLevel where
  minBound = CLevel 1
  maxBound = CLevel Zstd.maxCLevel

-- |
-- >>> show (CLevel 10)
-- "CLevel10"
--
-- @since 0.1.0.0
instance Show CLevel where
  show (CLevel x) = "CLevel" ++ show x

-- | @since 0.1.0.0
instance ProtoEnum CLevel where
  toProtoEnumMay x = toCLevel x
  fromProtoEnum x = fromCLevel x

-- | @since 0.1.0.0
instance Finite CLevel where
  enumerate _ = map makeEnum setCLevels
    where
      makeEnum :: IsString s => CLevel -> (s, Int32)
      makeEnum x = (showEnum x, fromCLevel x)

      showEnum :: IsString s => CLevel -> s
      showEnum (CLevel x) = fromString ("CLEVEL_" ++ show x)

-- | @since 0.1.0.0
instance Primitive CLevel where
  encodePrimitive n x = Encode.enum n x

  decodePrimitive = do
    result <- Decode.enum
    case result of
      Right enum -> pure enum
      Left int32 ->
        let issue :: LText
            issue = "CLevel invalid " <> show int32 <> " (out of bounds)"
         in Decode.throwE (Decode.WireTypeError issue)

  primType proxy =
    let name = nameOf @CLevel proxy
        path = DotProto.Path ["haskell", "grpc", "mqtt", name]
     in DotProto.Named (DotProto.Dots path)

-- CLevel - Construction --------------------------------------------------------

-- | Convert a 'CLevel' value to an 'Integral' value.
--
-- @since 0.1.0.0
fromCLevel :: Integral a => CLevel -> a
fromCLevel (CLevel x) = fromIntegral x

-- | Constructs a 'CLevel' from an 'Integral' value, if the value corresponds to
-- compression level that is supported by zstandard, otherwise yields 'Nothing'.
--
-- @since 0.1.0.0
toCLevel :: Integral a => a -> Maybe CLevel
toCLevel n
  | isCLevel n = Just (CLevel (fromIntegral n))
  | otherwise = Nothing

-- | 'setCLevel' is a list containing all compression levels supported by
-- zstandard.
--
-- @since 0.1.0.0
setCLevels :: [CLevel]
setCLevels = map CLevel [1 .. 22]

-- CLevel - Predicates ----------------------------------------------------------

-- | Predicate that tests if a given integral value is corresponds to a
-- compression level supported by zstandard.
--
-- @since 0.1.0.0
isCLevel :: Integral a => a -> Bool
isCLevel x =
  let lower = fromCLevel minBound
      upper = fromCLevel maxBound
   in lower <= x && x <= upper
