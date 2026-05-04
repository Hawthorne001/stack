-- | Stack recompiles when a file required for compilation is dirty.

import           Control.Monad ( unless )
import           Data.Foldable ( for_ )
import           StackTest

main :: IO ()
main = for_ (words "foo bar baz bin") $ \x -> do
  writeFile "some-text-file.txt" x
  stackCheckStdout ["run"] $ \y ->
    unless (x == y) $ error $ concat
      [ "Expected: "
      , show x
      , "\nActual:  "
      , show y
      ]
