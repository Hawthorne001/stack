#!/usr/bin/env sh

set -exu

stack_bin=$("$STACK_EXE" path --resolver ghc-9.10.2 --compiler-bin)

export STACK_ROOT=$(pwd)/fake-root

mkdir -p "${STACK_ROOT}"/hooks

echo "echo '${stack_bin}/ghc'" > "${STACK_ROOT}"/hooks/ghc-install.sh
chmod +x "${STACK_ROOT}"/hooks/ghc-install.sh

"$STACK_EXE" --no-install-ghc --resolver ghc-9.10.2 ghc -- --info
"$STACK_EXE" --no-install-ghc --resolver ghc-9.10.2 runghc foo.hs
