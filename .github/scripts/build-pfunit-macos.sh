#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 6 ]; then
  echo "Usage: build-pfunit-macos.sh VERSION FORTRAN_COMPILER PREFIX DEPLOYMENT_TARGET FORTRAN_FLAGS LINKER_FLAGS" >&2
  exit 2
fi

version="$1"
fortran_compiler="$2"
prefix="$3"
deployment_target="$4"
fortran_flags="$5"
linker_flags="$6"
sdkroot="$(xcrun --sdk macosx --show-sdk-path)"
c_compiler="$(xcrun --find cc)"

git clone --depth 1 --branch "$version" --recursive \
  https://github.com/Goddard-Fortran-Ecosystem/pFUnit.git pfunit-src
cmake -S pfunit-src -B pfunit-build \
  -DSKIP_MPI=YES \
  -DSKIP_OPENMP=YES \
  -DENABLE_TESTS=OFF \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_C_COMPILER="$c_compiler" \
  -DCMAKE_Fortran_COMPILER="$fortran_compiler" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
  -DCMAKE_OSX_SYSROOT="$sdkroot" \
  -DCMAKE_Fortran_FLAGS="$fortran_flags" \
  -DCMAKE_EXE_LINKER_FLAGS="$linker_flags" \
  -DCMAKE_INSTALL_PREFIX="$prefix"
cmake --build pfunit-build --target install -j"$(sysctl -n hw.ncpu)"
