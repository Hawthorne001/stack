-- | Stack's init command skips unreachable directories.

import           Control.Exception ( IOException, catch)
import           StackTest
import           System.Directory

main :: IO ()
main = do
  removeFileIgnore "stack.yaml"
  createDirectory "unreachabledir" `catch` \(e :: IOException) -> pure ()
  setPermissions  "unreachabledir" emptyPermissions
  stack ["init"]
