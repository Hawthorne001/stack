-- | Stack creates lock files.

import           Control.Monad ( unless, when )
import           Data.List ( isInfixOf )
import           StackTest

main :: IO ()
main = do
  stack ["--stack-yaml", "stack1.yaml", "build"]
  lock1 <- readFile "stack1.yaml.lock"
  unless ("acme-box" `isInfixOf` lock1) $
    error "Package acme-box wasn't found in Stack lock file"
  stack ["--stack-yaml", "stack2.yaml", "build"]
  lock2 <- readFile "stack2.yaml.lock"
  when ("acme-box" `isInfixOf` lock2) $
    error "Package acme-box shouldn't be in Stack lock file anymore"
