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

patch_exact_line() {
  local file="$1"
  local from="$2"
  local to="$3"
  local tmp="${file}.tmp"

  awk -v from="$from" -v to="$to" '
    $0 == from {
      print to
      next
    }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"

  if ! grep -Fqx "$to" "$file"; then
    echo "Failed to patch pFUnit dependency file: $file" >&2
    exit 1
  fi
}

gftl_shared_v1_cmake="pfunit-src/extern/fArgParse/extern/gFTL-shared/src/v1/CMakeLists.txt"
patch_exact_line \
  "$gftl_shared_v1_cmake" \
  "add_executable (demo.x demo.F90)" \
  "add_executable (demo.x EXCLUDE_FROM_ALL demo.F90)"

gftl_shared_src_cmake="pfunit-src/extern/fArgParse/extern/gFTL-shared/src/CMakeLists.txt"
patch_exact_line \
  "$gftl_shared_src_cmake" \
  "if (TARGET GFTL::gftl-v2)" \
  "if (FALSE)"

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
