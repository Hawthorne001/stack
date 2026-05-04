{-# LANGUAGE TemplateHaskell #-}

module Main where

import qualified Data.ByteString as B
import           Data.FileEmbed ( embedFile )
import           System.IO ( stdout )

main :: IO ()
main = B.hPut stdout $(embedFile "some-text-file.txt")
