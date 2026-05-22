#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: build-hamlib-macos.sh BRANCH DEPLOYMENT_TARGET PREFIX" >&2
  exit 2
fi

branch="$1"
deployment_target="$2"
prefix="$3"
expected_commit=""

case "$branch" in
  4.7.1)
    expected_commit="d042479a9f8095ba1a8e103a977c3614d7233cb2"
    ;;
  *)
    echo "Unsupported Hamlib branch/tag: $branch" >&2
    exit 2
    ;;
esac

git clone --depth 1 --branch "$branch" \
  https://github.com/Hamlib/Hamlib.git hamlib-src
cd hamlib-src
actual_commit="$(git rev-parse HEAD)"
if [ "$actual_commit" != "$expected_commit" ]; then
  echo "Hamlib checkout commit mismatch" >&2
  echo "Expected: $expected_commit" >&2
  echo "Actual:   $actual_commit" >&2
  exit 1
fi
./bootstrap
./configure \
  --prefix="$prefix" \
  --disable-shared --enable-static \
  --without-cxx-binding \
  CFLAGS="-mmacosx-version-min=${deployment_target}" \
  LDFLAGS="-mmacosx-version-min=${deployment_target}"
make -j"$(sysctl -n hw.ncpu)"
make install
