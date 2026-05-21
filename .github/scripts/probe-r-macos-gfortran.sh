#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: probe-r-macos-gfortran.sh --target VERSION --arch ARCH --work-dir PATH

Downloads the R/macOS GNU Fortran package, expands it without installing, and
checks the bundled runtime archives against the requested macOS build target.
This is a diagnostic probe only; it does not select the compiler used by CI.
USAGE
}

target=""
arch=""
work_dir=""
pkg_url="https://mac.r-project.org/tools/gfortran-14.2-universal.pkg"
pkg_sha256="ec462d465f093eeee0623d2b5d327bd1038313b985034b766462957e36d7aadd"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target)
      target="$2"
      shift 2
      ;;
    --arch)
      arch="$2"
      shift 2
      ;;
    --work-dir)
      work_dir="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$target" ] || [ -z "$arch" ] || [ -z "$work_dir" ]; then
  usage >&2
  exit 2
fi

case "$arch" in
  arm64)
    triplet="aarch64-apple-darwin20.0"
    ;;
  x86_64)
    triplet="x86_64-apple-darwin20.0"
    ;;
  *)
    echo "::error::Unsupported arch for R/macOS gfortran probe: ${arch}"
    exit 2
    ;;
esac

pkg="${work_dir}/gfortran-14.2-universal.pkg"
expanded="${work_dir}/gfortran-14.2-expanded"
prefix="${expanded}/gfortran.pkg/Payload/opt/gfortran"
runtime_dir="${prefix}/lib/gcc/${triplet}/14.2.0"

mkdir -p "$work_dir"

echo "R/macOS GNU Fortran probe"
echo "Package URL: ${pkg_url}"
echo "Expected SHA-256: ${pkg_sha256}"
echo "Requested tuple: arch=${arch}, target=${target}, triplet=${triplet}"

curl -fsSL --retry 3 --retry-delay 5 -o "$pkg" "$pkg_url"
actual_sha256="$(shasum -a 256 "$pkg" | awk '{print $1}')"
echo "Actual SHA-256: ${actual_sha256}"
if [ "$actual_sha256" != "$pkg_sha256" ]; then
  echo "::error::Unexpected R/macOS gfortran package checksum"
  exit 1
fi

pkgutil --expand-full "$pkg" "$expanded"

echo "Expanded package prefix: ${prefix}"
if [ ! -d "$prefix" ]; then
  echo "::error::Expanded package does not contain expected /opt/gfortran payload"
  exit 1
fi

for compiler in \
  "${prefix}/bin/gfortran" \
  "${prefix}/bin/${triplet}-gfortran"
do
  if [ -f "$compiler" ]; then
    echo "Compiler: ${compiler}"
    file "$compiler"
    lipo -archs "$compiler" || true
    otool -l "$compiler" | awk '
      /LC_BUILD_VERSION/ { in_build = 1; next }
      in_build && /minos/ { print "compiler minos " $2; in_build = 0 }
      /LC_VERSION_MIN_MACOSX/ { in_old = 1; next }
      in_old && /version/ { print "compiler minos " $2; in_old = 0 }
    ' || true
  else
    echo "::warning::Compiler not found in expanded package: ${compiler}"
  fi
done

if [ ! -d "$runtime_dir" ]; then
  echo "::error::Runtime archive directory not found: ${runtime_dir}"
  exit 1
fi

archives=()
for name in libgfortran.a libquadmath.a libgcc.a libgomp.a; do
  archive="${runtime_dir}/${name}"
  if [ -f "$archive" ]; then
    archives+=("$archive")
  else
    echo "::error::Expected runtime archive not found: ${archive}"
    exit 1
  fi
done

echo "Runtime archive directory: ${runtime_dir}"
for archive in "${archives[@]}"; do
  echo "Archive: ${archive}"
  lipo -archs "$archive" || true
done

"${GITHUB_WORKSPACE:-$(pwd)}/.github/scripts/verify-macos-static-archives.sh" \
  --target "$target" \
  --arch "$arch" \
  --mode warn \
  "${archives[@]}"
