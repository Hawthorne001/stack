#!/usr/bin/env stack
-- stack --snapshot mySnapshot.yaml script

import           Acme.Missiles ( launchMissiles )

main :: IO ()
main = launchMissiles
