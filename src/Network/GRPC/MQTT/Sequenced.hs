{-
  Copyright (c) 2021 Arista Networks, Inc.
  Use of this source code is governed by the Apache License 2.0
  that can be found in the COPYING file.
-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE RecordWildCards #-}

module Network.GRPC.MQTT.Sequenced
  ( PublishToStream (..),
    mkPacketizedPublish,
    mkStreamPublish,
    mkStreamRead,
  )
where

--------------------------------------------------------------------------------

import Control.Monad.Except (throwError)

import Data.ByteString.Lazy qualified as LByteString
import Data.Sequence ((|>))
import Data.Sequence qualified as Seq
import Data.Vector (Vector)
import Data.Vector qualified as Vector

import Network.GRPC.HighLevel.Server (toBS)

import Network.MQTT.Client (MQTTClient, QoS (QoS1), publishq)
import Network.MQTT.Topic (Topic)

import Proto3.Suite (Message, toLazyByteString)

import Relude

import UnliftIO (MonadUnliftIO)
import UnliftIO.Async qualified as Async

--------------------------------------------------------------------------------

import Network.GRPC.MQTT.Message.Packet (Packet)
import Network.GRPC.MQTT.Message.Packet qualified as Packet
import Network.GRPC.MQTT.Types (Batched (Batched))
import Network.GRPC.MQTT.Wrapping
  ( unwrapStreamChunk,
    wrapStreamChunk,
  )

import Proto.Mqtt (RemoteError)

--------------------------------------------------------------------------------

mkStreamRead ::
  forall io a.
  (MonadIO io, Message a) =>
  ExceptT RemoteError IO LByteString ->
  io (ExceptT RemoteError IO (Maybe a))
mkStreamRead readRequest = do
  -- NOTE: The type signature should be left here to bind the message type
  -- @a@, otherwise it is easy for the @Message@ instance used by the
  -- @fromByteString@ in @unwrapStreamChunk@ to resolve to some other type,
  -- resulting in a parse error.

  reqsRef :: IORef (Maybe (Vector a)) <- newIORef (Just Vector.empty)

  let readNextChunk :: ExceptT RemoteError IO ()
      readNextChunk = do
        bytes <- readRequest
        case unwrapStreamChunk bytes of
          Left err -> do
            atomicWriteIORef reqsRef Nothing
            throwError err
          Right xs -> do
            atomicWriteIORef reqsRef xs

  let readStreamChunk :: ExceptT RemoteError IO (Maybe a)
      readStreamChunk =
        readIORef reqsRef >>= \case
          Nothing -> pure Nothing
          Just reqs ->
            if Vector.null reqs
              then readNextChunk >> readStreamChunk
              else liftIO do
                atomicWriteIORef reqsRef (Just $ Vector.tail reqs)
                return (Just $ Vector.head reqs)

  return readStreamChunk

mkPacketizedPublish ::
  MonadUnliftIO io =>
  MQTTClient ->
  Int64 ->
  Topic ->
  LByteString ->
  io ()
mkPacketizedPublish client msgLimit topic bytes =
  let packets :: Vector (Packet ByteString)
      packets = Packet.splitPackets (fromIntegral msgLimit) (toStrict bytes)
   in Async.forConcurrently_ packets \packet -> do
        let encoded :: LByteString
            encoded = Packet.wireWrapPacket packet
         in liftIO (publishq client topic encoded False QoS1 [])

data PublishToStream a = PublishToStream
  { -- | A function to publish one data element.
    publishToStream :: a -> IO ()
  , -- | This function should be called to indicate that streaming is
    -- completed.
    publishToStreamCompleted :: IO ()
  }

mkStreamPublish ::
  forall r io.
  (Message r, MonadIO io) =>
  Int64 ->
  Batched ->
  (forall t. Message t => t -> IO ()) ->
  io (PublishToStream r)
mkStreamPublish msgLimit useBatch publish = do
  chunksRef <- newIORef ((Seq.empty, 0) :: (Seq ByteString, Int64))

  let seqToVector :: Seq t -> Vector t
      seqToVector = Vector.fromList . toList

  let accumulatedSend :: r -> IO ()
      accumulatedSend a = do
        (accChunks, accSize) <- readIORef chunksRef
        let chunk = toLazyByteString a
            sz = LByteString.length chunk
        if accSize + sz > msgLimit
          then do
            unless (Seq.null accChunks) $
              publish $ wrapStreamChunk $ Just $ seqToVector accChunks
            atomicWriteIORef chunksRef (Seq.singleton (toStrict chunk), sz)
          else do
            atomicWriteIORef chunksRef (accChunks |> toStrict chunk, accSize + sz)

  let unaccumulatedSend :: r -> IO ()
      unaccumulatedSend = publish . wrapStreamChunk . Just . Vector.singleton . toBS

  let streamingDone :: IO ()
      streamingDone = do
        (accChunks, _) <- readIORef chunksRef
        unless (Seq.null accChunks) $
          publish $ wrapStreamChunk $ Just $ seqToVector accChunks
        -- Send end of stream indicator
        publish $ wrapStreamChunk Nothing
        atomicWriteIORef chunksRef (Seq.empty, 0)

  return $
    PublishToStream
      { publishToStream = if useBatch == Batched then accumulatedSend else unaccumulatedSend
      , publishToStreamCompleted = streamingDone
      }
