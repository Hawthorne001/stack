-- | The test's project has project packages A, B and C (which has no library).
--
-- In terms of main libraries, the dependencies are (->- is 'depends on'):
--
--     A ->- B
--
-- In terms of executables (including test suites):
--
--     B ->- A and C ->- A
--
-- As, overall, A ->- B and B ->- A, packages A and B cannot be built
-- 'all-in-one'.
--
-- This integration test passes when A is named myPackageA and B is named
-- 0myPackageB, but it fails when B is renamed myPackageB. That must be a bug in
-- Stack.

import           Control.Monad ( unless )
import           Data.List ( isInfixOf )
import           StackTest

main :: IO ()
main = do
  -- FIXME: Make 'clean' unnecessary (see #1411)
  stack ["clean"]
  stackCheckStderr ["test", "--coverage"] $ \out -> do
    unless ("The coverage report for myPackageA's test-suite test1 is available at" `isInfixOf` out) $
      fail "Didn't get expected report for test1"
    unless ("[S-6829]" `isInfixOf` out) $
      fail "Didn't get expected empty report for test2"
  -- Test then build works too.
  stack ["clean"]
  stack ["test"]
  stack ["build"]
