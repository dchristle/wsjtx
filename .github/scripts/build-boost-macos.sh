#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "Usage: build-boost-macos.sh VERSION ARCH DEPLOYMENT_TARGET PREFIX" >&2
  exit 2
fi

version="$1"
arch="$2"
deployment_target="$3"
prefix="$4"
version_underscores=${version//./_}
boost_arch=x86
expected_sha256=""

case "$version" in
  1.85.0)
    expected_sha256="7009fe1faa1697476bdc7027703a2badb84e849b7b0baad5086b087b971f8617"
    ;;
  *)
    echo "Unsupported Boost version: $version" >&2
    exit 2
    ;;
esac

if [ "$arch" = "arm64" ]; then
  boost_arch=arm
fi

curl -L --fail --retry 5 --retry-delay 10 -o boost.tar.bz2 "https://archives.boost.io/release/${version}/source/boost_${version_underscores}.tar.bz2"
actual_sha256="$(shasum -a 256 boost.tar.bz2 | awk '{print $1}')"
if [ "$actual_sha256" != "$expected_sha256" ]; then
  echo "Boost source SHA-256 mismatch" >&2
  echo "Expected: $expected_sha256" >&2
  echo "Actual:   $actual_sha256" >&2
  exit 1
fi
tar -xjf boost.tar.bz2
cd "boost_${version_underscores}"

./bootstrap.sh --prefix="$prefix" --with-libraries=log
./b2 -j"$(sysctl -n hw.ncpu)" \
  toolset=clang \
  variant=release \
  link=shared \
  runtime-link=shared \
  threading=multi \
  cxxstd=11 \
  cflags="-mmacosx-version-min=${deployment_target}" \
  cxxflags="-mmacosx-version-min=${deployment_target}" \
  linkflags="-mmacosx-version-min=${deployment_target}" \
  architecture="$boost_arch" \
  address-model=64 \
  install
