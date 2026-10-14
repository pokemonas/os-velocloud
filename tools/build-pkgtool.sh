#!/bin/sh
# Build FreeBSD's pkg(8) for Linux (to create packages and the repository).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
VER=${1:-2.8.4}
[ -x "$HERE/pkg/src/pkg" ] && { echo "already built: $HERE/pkg/src/pkg"; exit 0; }
rm -rf "$HERE/pkg"
git clone -q --depth 1 --branch "$VER" https://github.com/freebsd/pkg.git "$HERE/pkg"
cd "$HERE/pkg"
./configure > configure.log 2>&1 || { tail -20 configure.log; exit 1; }
make -j"$(nproc)" > make.log 2>&1 || { tail -30 make.log; exit 1; }
./src/pkg -v
