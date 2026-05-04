-- | Various tests of Stack's sanity.

import           Control.Monad ( unless )
import           StackTest
import           System.Directory ( doesFileExist )

main :: IO ()
main = do
  stack ["--version"]
  stack ["--help"]
  removeDirIgnore "acme-missiles-0.2"
  removeDirIgnore "acme-missiles-0.3"
  stack ["unpack", "acme-missiles-0.2"]
  stack ["unpack", "acme-missiles"]
  stackErr ["command-does-not-exist"]
  stackErr ["unpack", "invalid-package-name-"]

  -- When running outside of IntegrationSpec.hs, this will use the
  -- stack.yaml from Stack itself
  exists <- doesFileExist "../../../../../stack.yaml"
  unless exists $ stackErr ["build"]

  doesNotExist "stack.yaml"

  let scriptFile = if isWindows then "./script.bat" else "./script.sh"
  stack [defaultSnapshotArg, "exec", scriptFile]
