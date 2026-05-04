module Main where

import Lib

main = do
  cFiles <- allCFiles
  putStrLn $ "C files:" ++ show cFiles
