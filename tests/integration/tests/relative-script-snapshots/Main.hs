-- Stack's script interpreter supports snapshot locations that are relative
-- local file paths.

import           StackTest

main :: IO ()
main = stack ["subdir/script.hs"]
