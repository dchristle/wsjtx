#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: verify-macos-static-archives.sh --target VERSION --arch ARCH PATH...

Verifies static archives before they are linked into deployable macOS binaries:
  * expected architecture
  * object-member deployment targets not newer than --target
USAGE
}

target=""
arch=""
archives=()
max_member_errors=25

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
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        archives+=("$1")
        shift
      done
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      archives+=("$1")
      shift
      ;;
  esac
done

if [ -z "$target" ] || [ -z "$arch" ] || [ "${#archives[@]}" -eq 0 ]; then
  usage >&2
  exit 2
fi

version_gt() {
  awk -v a="$1" -v b="$2" '
    BEGIN {
      split(a, av, ".")
      split(b, bv, ".")
      for (i = 1; i <= 3; i++) {
        ai = av[i] + 0
        bi = bv[i] + 0
        if (ai > bi) exit 0
        if (ai < bi) exit 1
      }
      exit 1
    }'
}

check_archive() {
  local archive="$1"
  local fail=0
  local archs
  local line
  local member=""
  local in_build=0
  local in_old=0
  local minos
  local reported=0
  local suppressed=0

  if [ ! -f "$archive" ]; then
    echo "::error::Static archive does not exist: ${archive}"
    return 1
  fi

  archs=$(lipo -archs "$archive" 2>/dev/null || true)
  if [ -n "$archs" ] && ! printf '%s\n' "$archs" | tr ' ' '\n' | grep -qx "$arch"; then
    echo "::error file=${archive}::Expected architecture ${arch}, found: ${archs}"
    fail=1
  fi

  while IFS= read -r line; do
    case "$line" in
      *".a("*"):")
        member="${line%:}"
        in_build=0
        in_old=0
        ;;
      *"LC_BUILD_VERSION"*)
        in_build=1
        in_old=0
        ;;
      *"LC_VERSION_MIN_MACOSX"*)
        in_build=0
        in_old=1
        ;;
      *" minos "*)
        if [ "$in_build" -eq 1 ]; then
          set -- $line
          minos="$2"
          if version_gt "$minos" "$target"; then
            if [ "$reported" -lt "$max_member_errors" ]; then
              echo "::error file=${archive}::${member} requires macOS ${minos}, newer than archive target ${target}"
            else
              suppressed=$((suppressed + 1))
            fi
            reported=$((reported + 1))
            fail=1
          fi
          in_build=0
        fi
        ;;
      *" version "*)
        if [ "$in_old" -eq 1 ]; then
          set -- $line
          minos="$2"
          if version_gt "$minos" "$target"; then
            if [ "$reported" -lt "$max_member_errors" ]; then
              echo "::error file=${archive}::${member} requires macOS ${minos}, newer than archive target ${target}"
            else
              suppressed=$((suppressed + 1))
            fi
            reported=$((reported + 1))
            fail=1
          fi
          in_old=0
        fi
        ;;
    esac
  done < <(otool -l "$archive" 2>/dev/null || true)

  if [ "$suppressed" -gt 0 ]; then
    echo "::error file=${archive}::Suppressed ${suppressed} additional archive member deployment-target errors"
  fi

  return "$fail"
}

overall=0
for archive in "${archives[@]}"; do
  check_archive "$archive" || overall=1
done

if [ "$overall" -ne 0 ]; then
  exit "$overall"
fi

echo "All checked static archives match arch ${arch} and target macOS ${target}."
