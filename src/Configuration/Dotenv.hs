-- |
-- Module      :  Configuration.Dotenv.Types
-- Copyright   :  © 2015–2020 Stack Builders Inc.
-- License     :  MIT
--
-- Maintainer  :  Stack Builders <hackage@stackbuilders.com>
-- Stability   :  experimental
-- Portability :  portable
--
-- This module contains common functions to load and read dotenv files.
{-# LANGUAGE RecordWildCards #-}

module Configuration.Dotenv
  ( -- * Dotenv Load Functions
    load
  , loadFile
  , parseFile
  , onMissingFile
      -- * Dotenv Types
  , module Configuration.Dotenv.Types
  ) where

import           Configuration.Dotenv.Environment    (getEnvironment, lookupEnv,
                                                      setEnv)
import           Configuration.Dotenv.Parse          (configParser)
import           Configuration.Dotenv.ParsedVariable (interpolateParsedVariables)
import           Configuration.Dotenv.Types          (Config (..), defaultConfig)
import           Control.Monad.Trans                 (lift)
import           Control.Monad.Reader                (ReaderT, ask, runReaderT)
import           Control.Exception                   (throw)
import           Control.Monad                       (unless, when)
import           Control.Monad.Catch
import           Control.Monad.IO.Class              (MonadIO (..))
import           Data.List                           (intersectBy, union,
                                                      unionBy)
import           System.IO.Error                     (isDoesNotExistError)
import           Text.Megaparsec                     (errorBundlePretty, parse)

-- | Monad Stack for the application
type DotEnv m a = ReaderT Config m a

-- | Loads the given list of options into the environment. Optionally
-- override existing variables with values from Dotenv files.
load ::
     MonadIO m
  => Bool -- ^ Override existing settings?
  -> [(String, String)] -- ^ List of values to be set in environment
  -> m ()
load override kv =
  runReaderT (mapM_ applySetting kv) defaultConfig {configOverride = override}

-- | @loadFile@ parses the environment variables defined in the dotenv example
-- file and checks if they are defined in the dotenv file or in the environment.
-- It also allows to override the environment variables defined in the environment
-- with the values defined in the dotenv file.
loadFile ::
     MonadIO m
  => Config -- ^ Dotenv configuration
  -> m ()
loadFile config@Config {..} = do
  environment <- liftIO getEnvironment
  readVars <- fmap concat (mapM parseFile configPath)
  neededVars <- fmap concat (mapM parseFile configExamplePath)
  let coincidences = (environment `union` readVars) `intersectEnvs` neededVars
      cmpEnvs env1 env2 = fst env1 == fst env2
      intersectEnvs = intersectBy cmpEnvs
      unionEnvs = unionBy cmpEnvs
      vars =
        if (not . null) neededVars
          then if length neededVars == length coincidences
                 then readVars `unionEnvs` neededVars
                 else error $
                      "Missing env vars! Please, check (this/these) var(s) (is/are) set:" ++
                      concatMap ((++) " " . fst) neededVars
          else readVars
  unless allowDuplicates $ (lookUpDuplicates . map fst) vars
  runReaderT (mapM_ applySetting vars) config

-- | Parses the given dotenv file and returns values /without/ adding them to
-- the environment.
parseFile ::
     MonadIO m
  => FilePath -- ^ A file containing options to read
  -> m [(String, String)] -- ^ Variables contained in the file
parseFile f = do
  contents <- liftIO $ readFile f
  case parse configParser f contents of
    Left e        -> error $ errorBundlePretty e
    Right options -> liftIO $ interpolateParsedVariables options

applySetting ::
     MonadIO m
  => (String, String) -- ^ A key-value pair to set in the environment
  -> DotEnv m (String, String)
applySetting kv@(k, v) = do
  Config {..} <- ask
  if configOverride
    then info kv >> setEnv'
    else do
      res <- lift . liftIO $ lookupEnv k
      case res of
        Nothing -> info kv >> setEnv'
        Just _  -> return kv
  where
    setEnv' = lift . liftIO $ setEnv k v >> return kv

-- | The function logs in console when a variable is loaded into the
-- environment.
info :: MonadIO m => (String, String) -> DotEnv m ()
info (key, value) = do
  Config {..} <- ask
  when configVerbose $
    lift . liftIO $
    putStrLn $ "[INFO]: Load env '" ++ key ++ "' with value '" ++ value ++ "'"

-- | The helper allows to avoid exceptions in the case of missing files and
-- perform some action instead.
--
-- @since 0.3.1.0
onMissingFile ::
     MonadCatch m
  => m a -- ^ Action to perform that may fail because of missing file
  -> m a -- ^ Action to perform if file is indeed missing
  -> m a
onMissingFile f h = catchIf isDoesNotExistError f (const h)

-- | The helper throws an exception if the allow duplicate is set to False.
forbidDuplicates :: MonadIO m => String -> m ()
forbidDuplicates key =
  throw $
  userError $
  "[ERROR]: Env '" ++
  key ++
  "' is duplicated in a dotenv file. Please, fix that (or remove --no-dups)."

lookUpDuplicates :: MonadIO m => [String] -> m ()
lookUpDuplicates [] = return ()
lookUpDuplicates [_] = return ()
lookUpDuplicates (x:xs) =
  if x `elem` xs
    then forbidDuplicates x
    else lookUpDuplicates xs
