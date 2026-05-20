#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: build-pfunit-macos.sh VERSION FORTRAN_COMPILER PREFIX" >&2
  exit 2
fi

version="$1"
fortran_compiler="$2"
prefix="$3"

git clone --depth 1 --branch "$version" --recursive \
  https://github.com/Goddard-Fortran-Ecosystem/pFUnit.git pfunit-src
cmake -S pfunit-src -B pfunit-build \
  -DSKIP_MPI=YES \
  -DSKIP_OPENMP=YES \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_Fortran_COMPILER="$fortran_compiler" \
  -DCMAKE_INSTALL_PREFIX="$prefix"
cmake --build pfunit-build -j"$(sysctl -n hw.ncpu)"
cmake --install pfunit-build
