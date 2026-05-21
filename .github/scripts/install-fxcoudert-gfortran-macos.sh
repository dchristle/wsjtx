#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: install-fxcoudert-gfortran-macos.sh --target VERSION --arch ARCH --work-dir PATH --prefix PATH [--github-output]

Downloads the fxcoudert GNU Fortran package selected for the requested macOS
build tuple, expands it without using the macOS installer, and prepares a
relocated compiler prefix for CI.
USAGE
}

target=""
arch=""
work_dir=""
prefix=""
github_output=0

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
    --prefix)
      prefix="$2"
      shift 2
      ;;
    --github-output)
      github_output=1
      shift
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

if [ -z "$target" ] || [ -z "$arch" ] || [ -z "$work_dir" ] || [ -z "$prefix" ]; then
  usage >&2
  exit 2
fi

case "${arch}:${target}" in
  x86_64:10.13)
    package_name="gfortran-6.3-Sierra"
    package_url="https://github.com/fxcoudert/gfortran-for-macOS/releases/download/6.3/gfortran-6.3-Sierra.dmg"
    package_sha256="38b81bc878dba41cfdbb0c335aec5a97554a5d1766fb3e3ca6be7da0df9e8e09"
    package_path="gfortran.pkg"
    runtime_dir="lib/gcc/x86_64-apple-darwin16/6.3.0"
    ;;
  *)
    echo "::error::Unsupported fxcoudert gfortran tuple: arch=${arch}, target=${target}"
    exit 2
    ;;
esac

dmg="${work_dir}/${package_name}.dmg"
expanded="${work_dir}/${package_name}-expanded"
mount_point=""

detach_dmg() {
  if [ -n "$mount_point" ] && [ -d "$mount_point" ]; then
    hdiutil detach "$mount_point" >/dev/null || true
  fi
}
trap detach_dmg EXIT

mkdir -p "$work_dir"

echo "fxcoudert GNU Fortran install"
echo "Package URL: ${package_url}"
echo "Expected SHA-256: ${package_sha256}"
echo "Requested tuple: arch=${arch}, target=${target}"
echo "Install prefix: ${prefix}"

curl -fsSL --retry 3 --retry-delay 5 -o "$dmg" "$package_url"
actual_sha256="$(shasum -a 256 "$dmg" | awk '{print $1}')"
echo "Actual SHA-256: ${actual_sha256}"
if [ "$actual_sha256" != "$package_sha256" ]; then
  echo "::error::Unexpected fxcoudert gfortran package checksum"
  exit 1
fi

attach_output="$(hdiutil attach -nobrowse -readonly "$dmg" 2>&1)"
mount_point="$(printf '%s\n' "$attach_output" | awk '/\/Volumes\// { print $NF; exit }')"
if [ -z "$mount_point" ] || [ ! -d "$mount_point" ]; then
  echo "::error::Unable to determine mounted DMG path"
  exit 1
fi

pkg="${mount_point}/${package_path}"
if [ ! -e "$pkg" ]; then
  echo "::error::Expected package not found in DMG: ${pkg}"
  exit 1
fi

pkgutil --expand-full "$pkg" "$expanded"
payload_prefix="${expanded}/Payload/usr/local/gfortran"
if [ ! -d "$payload_prefix" ]; then
  echo "::error::Expanded package does not contain expected /usr/local/gfortran payload"
  exit 1
fi

mkdir -p "$(dirname "$prefix")"
ditto "$payload_prefix" "$prefix"

spec="${prefix}/lib/libgfortran.spec"
if [ ! -f "$spec" ]; then
  echo "::error::Expected libgfortran spec not found: ${spec}"
  exit 1
fi
spec_tmp="${spec}.tmp"
sed 's/-lquadmath/libquadmath.a%s/' "$spec" > "$spec_tmp"
mv "$spec_tmp" "$spec"

compiler="${prefix}/bin/gfortran"
if [ ! -x "$compiler" ]; then
  echo "::error::Expected gfortran compiler not found: ${compiler}"
  exit 1
fi

sdkroot="$(xcrun --sdk macosx --show-sdk-path)"
libgfortran="${prefix}/lib/libgfortran.a"
libquadmath="${prefix}/lib/libquadmath.a"
libgcc="${prefix}/${runtime_dir}/libgcc.a"
libgomp="${prefix}/lib/libgomp.a"

archives=("$libgfortran" "$libquadmath" "$libgcc" "$libgomp")
for archive in "${archives[@]}"; do
  if [ ! -f "$archive" ]; then
    echo "::error::Expected runtime archive not found: ${archive}"
    exit 1
  fi
done

"${GITHUB_WORKSPACE:-$(pwd)}/.github/scripts/verify-macos-static-archives.sh" \
  --target "$target" \
  --arch "$arch" \
  --mode error \
  "${archives[@]}"

echo "Compiler: ${compiler}"
file "$compiler"
otool -L "$compiler"

runtime_link_flags="${libgfortran} ${libquadmath} ${libgcc}"
fortran_runtime_flags="-static-libgcc -static-libgfortran -isysroot ${sdkroot}"
runtime_archives="${archives[*]}"

if [ "$github_output" -eq 1 ]; then
  github_output_file="${GITHUB_OUTPUT:-/dev/stdout}"
  {
    echo "path=${compiler}"
    echo "prefix=${prefix}"
    echo "original_prefix=/usr/local/gfortran"
    echo "fortran_runtime_flags=${fortran_runtime_flags}"
    echo "runtime_link_flags=${runtime_link_flags}"
    echo "runtime_archives=${runtime_archives}"
    echo "libgomp=${libgomp}"
  } >> "$github_output_file"
fi
