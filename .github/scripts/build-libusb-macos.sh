#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: build-libusb-macos.sh VERSION DEPLOYMENT_TARGET PREFIX" >&2
  exit 2
fi

version="$1"
deployment_target="$2"
prefix="$3"
expected_sha256=""

case "$version" in
  1.0.27)
    expected_sha256="ffaa41d741a8a3bee244ac8e54a72ea05bf2879663c098c82fc5757853441575"
    ;;
  *)
    echo "Unsupported libusb version: $version" >&2
    exit 2
    ;;
esac

curl -L --fail --retry 5 --retry-delay 10 -o libusb.tar.bz2 "https://github.com/libusb/libusb/releases/download/v${version}/libusb-${version}.tar.bz2"
actual_sha256="$(shasum -a 256 libusb.tar.bz2 | awk '{print $1}')"
if [ "$actual_sha256" != "$expected_sha256" ]; then
  echo "libusb source SHA-256 mismatch" >&2
  echo "Expected: $expected_sha256" >&2
  echo "Actual:   $actual_sha256" >&2
  exit 1
fi
tar -xjf libusb.tar.bz2
cd "libusb-${version}"

./configure \
  --prefix="$prefix" \
  --enable-shared --disable-static \
  CFLAGS="-mmacosx-version-min=${deployment_target}" \
  LDFLAGS="-mmacosx-version-min=${deployment_target}"
make -j"$(sysctl -n hw.ncpu)"
make install
