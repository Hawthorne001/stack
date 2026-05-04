-- | Stack can avoid re-running successful test suites.

import          Control.Monad ( unless, when )
import          StackTest
import          System.Directory ( doesFileExist, removeFile )

main :: IO ()
main = do
  stack ["test"]
  exists1 <- doesFileExist "testRan"
  unless exists1 $ error "exists1 should be True"
  removeFile "testRan"
  stack ["test", "--no-rerun-tests"]
  exists2 <- doesFileExist "testRan"
  when exists2 $ error "exists2 should be False"
