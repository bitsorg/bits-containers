#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 CERN
# SPDX-License-Identifier: GPL-3.0-or-later
#
# container-fingerprint.sh — compute a deterministic fingerprint of the image's
# OUTPUT-AFFECTING content: the versions of the linked -devel libraries
# (packages/dev-libs.*.txt) + the curated toolchain set (fingerprint.conf) + the
# EXACT versions of every installed gcc/clang. Writes:
#   /opt/bits/container-fingerprint.json   full sorted manifest
#   /opt/bits/container-fingerprint.hash   sha256 of the manifest (short id)
#
# Purpose: (1) provenance — trace any built artifact to the lib/tool versions it
# was built against; (2) an input for bits `dependency_tracking: strict`, which
# folds this hash into a package's identity so a real ABI/codegen change (an
# openssl bump, a gcc patch bump) invalidates the cache while irrelevant image
# churn does not. Runs at image-build time (see ../Dockerfile). Pure shell +
# coreutils (sha256sum) — no python/rpm-python needed.
set -euo pipefail
SRC="${BITS_SRC:-/opt/bits/src}"
CONF="${SRC}/fingerprint.conf"
OUT_JSON="${OUT_JSON:-/opt/bits/container-fingerprint.json}"
OUT_HASH="${OUT_HASH:-/opt/bits/container-fingerprint.hash}"

if command -v rpm >/dev/null 2>&1; then FAM=el; else FAM=deb; fi
tmp="$(mktemp)"

# --- linked libs (dev-libs.<fam>.txt) + curated toolchain set (fingerprint.conf) ---
pkgs="$(grep -vhE '^[[:space:]]*#|^[[:space:]]*$' "${SRC}/packages/dev-libs.${FAM}.txt" 2>/dev/null | sed 's/#.*//;s/[[:space:]]*$//')"
pkgs+=$'\n'"$(awk -v f="$FAM" '$1==f {print $2}' "$CONF" 2>/dev/null)"

pkgver() { # name -> "pkg <name> <version|MISSING>"
  local p="$1" v
  if [ "$FAM" = el ]; then
    if rpm -q "$p" >/dev/null 2>&1; then v="$(rpm -q --qf '%{VERSION}-%{RELEASE}' "$p" 2>/dev/null)"; else v=MISSING; fi
  else
    v="$(dpkg-query -W -f '${Version}' "$p" 2>/dev/null || true)"; [ -n "$v" ] || v=MISSING
  fi
  printf 'pkg %s %s\n' "$p" "$v"
}
while IFS= read -r p; do [ -n "$p" ] && pkgver "$p"; done <<< "$pkgs" >> "$tmp"

# --- exact compiler versions (prefer_system compiler is otherwise only 'gccNN' in the arch) ---
emit_gcc() { # path -> "cc <key> <fullversion>"
  local g="$1" key ver
  case "$g" in
    /opt/bits/gcc/*)        key="gcc-src-$(basename "$(dirname "$(dirname "$g")")")" ;;
    /opt/rh/gcc-toolset-*)  key="$(printf '%s' "$g" | sed -E 's#/opt/rh/(gcc-toolset-[0-9]+)/.*#\1#')" ;;
    /usr/bin/gcc-*)         key="$(basename "$g")"; [[ "$key" =~ ^gcc-[0-9]+$ ]] || return 0 ;;
    *)                      key="gcc" ;;
  esac
  ver="$("$g" -dumpfullversion 2>/dev/null || "$g" -dumpversion 2>/dev/null || echo '?')"
  printf 'cc %s %s\n' "$key" "$ver"
}
emit_clang() {
  local c="$1" key ver
  case "$c" in
    /opt/bits/llvm/*) key="clang-src-$(basename "$(dirname "$(dirname "$c")")")" ;;
    /usr/bin/clang-*) key="$(basename "$c")"; [[ "$key" =~ ^clang-[0-9]+$ ]] || return 0 ;;
    *)                key="clang" ;;
  esac
  ver="$("$c" --version 2>/dev/null | sed -nE 's/.*version ([0-9]+(\.[0-9]+)*).*/\1/p' | head -1)"
  printf 'cc %s %s\n' "$key" "${ver:-?}"
}
for g in /opt/bits/gcc/*/bin/gcc /opt/rh/gcc-toolset-*/root/usr/bin/gcc /usr/bin/gcc-* /usr/bin/gcc; do
  [ -x "$g" ] && emit_gcc "$g"
done 2>/dev/null | sort -u >> "$tmp" || true
for c in /opt/bits/llvm/*/bin/clang /usr/bin/clang-* /usr/bin/clang; do
  [ -x "$c" ] && emit_clang "$c"
done 2>/dev/null | sort -u >> "$tmp" || true

# --- deterministic manifest + hash ---
sort -u "$tmp" > "${tmp}.sorted"
hash="$(sha256sum "${tmp}.sorted" | cut -d' ' -f1)"
mkdir -p "$(dirname "$OUT_JSON")"
{
  printf '{\n  "family": "%s",\n  "hash": "%s",\n  "entries": [\n' "$FAM" "$hash"
  sed 's/"/\\"/g' "${tmp}.sorted" | awk 'NR>1{printf ",\n"} {printf "    \"%s\"", $0} END{print ""}'
  printf '  ]\n}\n'
} > "$OUT_JSON"
printf '%s\n' "$hash" > "$OUT_HASH"
rm -f "$tmp" "${tmp}.sorted"
echo "container-fingerprint: $hash  ($(wc -l < "$OUT_JSON") lines in $OUT_JSON)"
