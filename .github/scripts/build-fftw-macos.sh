#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: build-fftw-macos.sh VERSION DEPLOYMENT_TARGET PREFIX" >&2
  exit 2
fi

version="$1"
deployment_target="$2"
prefix="$3"
expected_sha256=""

case "$version" in
  3.3.10)
    expected_sha256="56c932549852cddcfafdab3820b0200c7742675be92179e59e6215b340e26467"
    ;;
  *)
    echo "Unsupported FFTW version: $version" >&2
    exit 2
    ;;
esac

curl -L --fail --retry 5 --retry-delay 10 -o fftw.tar.gz "https://www.fftw.org/fftw-${version}.tar.gz"
actual_sha256="$(shasum -a 256 fftw.tar.gz | awk '{print $1}')"
if [ "$actual_sha256" != "$expected_sha256" ]; then
  echo "FFTW source SHA-256 mismatch" >&2
  echo "Expected: $expected_sha256" >&2
  echo "Actual:   $actual_sha256" >&2
  exit 1
fi
tar -xzf fftw.tar.gz
cd "fftw-${version}"

./configure \
  --prefix="$prefix" \
  --enable-single \
  --enable-threads \
  --enable-shared --disable-static \
  CFLAGS="-mmacosx-version-min=${deployment_target}" \
  LDFLAGS="-mmacosx-version-min=${deployment_target}"
make -j"$(sysctl -n hw.ncpu)"
make install
