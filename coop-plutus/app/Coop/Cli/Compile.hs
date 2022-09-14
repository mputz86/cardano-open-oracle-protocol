{-# OPTIONS_GHC -Wno-orphans #-}

module Coop.Cli.Compile (CompileOpts (..), CompileMode (..), compile) where

import Coop.Plutus (certV, fsV, mkAuthMp, mkCertMp, mkFsMp)
import Coop.Plutus.Aux (mkOneShotMintingPolicy)
import Coop.Types (CoopPlutus (CoopPlutus, cp'certV, cp'fsV, cp'mkAuthMp, cp'mkCertMp, cp'mkFsMp, cp'mkNftMp))
import Data.Aeson (encode)
import Data.ByteString.Lazy (writeFile)
import Plutarch (Config (Config), TracingMode (DoTracing, NoTracing))
import Plutarch qualified (compile)

data CompileMode = COMPILE_PROD | COMPILE_DEBUG deriving stock (Show, Read, Eq)

data CompileOpts = CompileOpts
  { co'Mode :: CompileMode
  , co'File :: FilePath
  }
  deriving stock (Show, Eq)

compile :: CompileOpts -> IO ()
compile opts = do
  let cfg = case co'Mode opts of
        COMPILE_PROD -> Config NoTracing
        COMPILE_DEBUG -> Config DoTracing
  mkNftMp' <- either (\err -> fail $ "Failed compiling mkNftMp with " <> show err) pure (Plutarch.compile cfg mkOneShotMintingPolicy)
  mkAuthMp' <- either (\err -> fail $ "Failed compiling mkAuthMp with " <> show err) pure (Plutarch.compile cfg mkAuthMp)
  mkCertMp' <- either (\err -> fail $ "Failed compiling mkCertMp with " <> show err) pure (Plutarch.compile cfg mkCertMp)
  certV' <- either (\err -> fail $ "Failed compiling certV with " <> show err) pure (Plutarch.compile cfg certV)
  mkFsMp' <- either (\err -> fail $ "Failed compiling mkFsMp with " <> show err) pure (Plutarch.compile cfg mkFsMp)
  fsV' <- either (\err -> fail $ "Failed compiling fsV with " <> show err) pure (Plutarch.compile cfg fsV)

  let cs =
        CoopPlutus
          { cp'mkNftMp = mkNftMp'
          , cp'mkAuthMp = mkAuthMp'
          , cp'mkCertMp = mkCertMp'
          , cp'certV = certV'
          , cp'mkFsMp = mkFsMp'
          , cp'fsV = fsV'
          }
  Data.ByteString.Lazy.writeFile (co'File opts) (encode cs)
  return ()