module Network.IRC.DCC.FileTransfer
  ( acceptFile
  , resumeFile
  ) where

import           Network.IRC.DCC.Internal

import           Control.Error
import           Control.Monad                      (unless)
import           Data.ByteString.Char8              (ByteString, length, null)
import           Network.Socket.ByteString.Extended
import           Path                               (File, Path, Rel,
                                                     fromRelFile)
import           Prelude                            hiding (length, null)
import           System.IO                          (BufferMode (NoBuffering), IOMode (WriteMode, AppendMode))
import           System.IO.Streams                  (OutputStream,
                                                     withFileAsOutputExt, write)

type Output = OutputStream ByteString

acceptFile :: Integral a
           => OfferFile
           -> (PortNumber -> ExceptT String IO ())
           -> (a -> IO ())
           -> ExceptT String IO ()
acceptFile (OfferFile tt f) =
    download (fileName f) WriteMode 0 tt

resumeFile :: Integral a
           => AcceptResumeFile
           -> (PortNumber -> ExceptT String IO ())
           -> (a -> IO ())
           -> ExceptT String IO ()
resumeFile (AcceptResumeFile tt f pos) =
    download (fileName f) AppendMode (fromIntegral pos) tt

download :: Integral a
         => Path Rel File
         -> IOMode
         -> a
         -> TransferType
         -> (PortNumber -> ExceptT String IO ())
         -> (a -> IO ())
         -> ExceptT String IO ()
download fn mode pos tt onListen onChunk =
    withSocket tt onListen $
        toFile (fromRelFile fn) . stream pos onChunk
  where withSocket (Active i p) = withActiveSocket i p
        withSocket (Passive i _) = withPassiveSocket i
        toFile f = withFileAsOutputExt f mode NoBuffering

stream :: Integral a
       => a
       -> (a -> IO ())
       -> Socket
       -> Output
       -> IO ()
stream pos onChunk sock h =
  do buf <- recv sock (4096 * 1024)
     unless (null buf) $
            do let l = fromIntegral (length buf)
               onChunk l
               let pos' = pos + l
               sendPosition sock pos'
               Just buf `write` h
               stream pos' onChunk sock h

sendPosition :: Integral a => Socket -> a -> IO ()
sendPosition sock = sendAll sock . toNetworkByteOrder
