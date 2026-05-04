#!/usr/bin/env stack
-- stack --snapshot ghc-9.10.3 script --extra-dep acme-missiles-0.3@rev:0

import Acme.Missiles ( launchMissiles )

main :: IO ()
main = launchMissiles
