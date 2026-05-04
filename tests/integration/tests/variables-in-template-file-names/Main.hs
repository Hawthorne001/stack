-- | A Stack project template can be populated with the name of the Stack
-- project.

import           Control.Monad ( unless )
import           StackTest
import           System.Directory ( doesFileExist )

main :: IO ()
main = do
  removeDirIgnore "myPackage"
  stack ["new", "myPackage", "./template.hsfiles"]
  exists <- doesFileExist "myPackage/myPackage.cabal"
  unless exists $ error "does not exist"
