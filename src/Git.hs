{-# LANGUAGE ExtendedDefaultRules #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fno-warn-type-defaults #-}

module Git
  ( cleanAndResetToMaster
  , cleanAndResetToStaging
  , cleanup
  , fetchIfStale
  , fetch
  , push
  , checkoutAtMergeBase
  , autoUpdateBranchExists
  , commit
  , headHash
  ) where

import Data.Semigroup ((<>))
import qualified Data.Text as T
import Data.Text (Text)
import Data.Time.Clock (UTCTime, addUTCTime, diffUTCTime, getCurrentTime)
import Shelly
import System.Directory (getModificationTime, getHomeDirectory)
import Utils (Options(..), UpdateEnv(..), branchName, canFail)

default (T.Text)

clean :: Sh ()
clean = cmd "git" "clean" "-fdx"

cleanAndResetTo :: Text -> Text -> Sh ()
cleanAndResetTo branch target = do
  cmd "git" "reset" "--hard"
  clean
  cmd "git" "checkout" "-B" branch target
  cmd "git" "reset" "--hard" target
  clean

cleanAndResetToMaster :: Sh ()
cleanAndResetToMaster = cleanAndResetTo "master" "upstream/master"

cleanAndResetToStaging :: Sh ()
cleanAndResetToStaging = cleanAndResetTo "staging" "upstream/staging"

cleanup :: Text -> Sh ()
cleanup branchName = do
  cleanAndResetToMaster
  canFail $ cmd "git" "branch" "-D" branchName

staleFetchHead :: IO Bool
staleFetchHead = do
  home <- getHomeDirectory
  let fetchHead = home <> "/.cache/nixpkgs/.git/FETCH_HEAD"
  oneHourAgo <- addUTCTime (fromInteger $ -60 * 60) <$> getCurrentTime
  fetchedLast <- getModificationTime fetchHead
  return (fetchedLast < oneHourAgo)

fetchIfStale :: Sh ()
fetchIfStale =
  whenM
    (liftIO staleFetchHead)
    fetch

fetch :: Sh ()
fetch = canFail $ cmd "git" "fetch" "-q" "--prune" "--multiple" "upstream" "origin"

push :: UpdateEnv -> Sh ()
push updateEnv =
  run_
    "git"
    (["push", "--force", "--set-upstream", "origin", branchName updateEnv] ++
     ["--dry-run" | dryRun (options updateEnv)])

checkoutAtMergeBase :: Text -> Sh ()
checkoutAtMergeBase branchName = do
  base <-
    T.strip <$> cmd "git" "merge-base" "upstream/master" "upstream/staging"
  cmd "git" "checkout" "-B" branchName base

autoUpdateBranchExists :: Text -> Sh Bool
autoUpdateBranchExists packageName = do
  remotes <-
    map T.strip . T.lines <$> (silently $ cmd "git" "branch" "--remote")
  return $ ("origin/auto-update/" <> packageName) `elem` remotes

commit :: Text -> Sh ()
commit = cmd "git" "commit" "-am"

headHash :: Sh Text
headHash = cmd "git" "rev-parse" "HEAD"
