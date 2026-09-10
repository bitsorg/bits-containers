#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 CERN
# SPDX-License-Identifier: GPL-3.0-or-later
#
# bits-cc-select — point the plain compiler names (gcc/g++/gfortran/cc/c++ and
# clang/clang++) at the version selected by $GCC_VERSION / $CLANG_VERSION, by
# (re)writing symlinks in $SHIM_DIR. $SHIM_DIR is first on PATH (set in the
# Dockerfile), so every build — bits recipes included — sees the selected
# compiler under its plain name, which is exactly what the Phase-2 prefer_system
# probes and the recipes that call cc/c++ directly expect.
#
# Resolution (hides the EL/Ubuntu packaging difference):
#   EL     gcc -> /opt/rh/gcc-toolset-<v>/root/usr/bin   (gcc-toolset layout)
#   Ubuntu gcc -> gcc-<v> / g++-<v> / gfortran-<v>        (suffixed binaries)
#   clang      -> clang-<v> (Ubuntu) else the single system clang (EL)
#
# With no $GCC_VERSION it uses the image default baked at build time
# (/opt/bits/cc/default-gcc). Writes /opt/bits/cc/gcc-libdir so the entry script
# can add the gcc-toolset lib64 to LD_LIBRARY_PATH at runtime.
set -euo pipefail
SHIM_DIR="${SHIM_DIR:-/opt/bits/cc/bin}"
STATE_DIR="$(dirname "$SHIM_DIR")"
mkdir -p "$SHIM_DIR"
link() { ln -sfn "$1" "$SHIM_DIR/$2"; }

gv="${GCC_VERSION:-}"; [ -n "$gv" ] || gv="$(cat "$STATE_DIR/default-gcc" 2>/dev/null || true)"
: > "$STATE_DIR/gcc-libdir"
if [ -n "$gv" ]; then
  src="/opt/bits/gcc/$gv"; ts="/opt/rh/gcc-toolset-$gv/root/usr"
  if [ -x "$src/bin/gcc" ]; then
    # from-source build (COMPILER_SOURCE=source|auto) — takes precedence.
    link "$src/bin/gcc" gcc; link "$src/bin/gcc" cc
    link "$src/bin/g++" g++; link "$src/bin/g++" c++
    [ -x "$src/bin/gfortran" ] && link "$src/bin/gfortran" gfortran
    printf '%s\n' "$src/lib64" > "$STATE_DIR/gcc-libdir"
  elif [ -x "$ts/bin/gcc" ]; then
    link "$ts/bin/gcc" gcc; link "$ts/bin/gcc" cc
    link "$ts/bin/g++" g++; link "$ts/bin/g++" c++
    [ -x "$ts/bin/gfortran" ] && link "$ts/bin/gfortran" gfortran
    printf '%s\n' "$ts/lib64" > "$STATE_DIR/gcc-libdir"
  elif command -v "gcc-$gv" >/dev/null 2>&1; then
    link "$(command -v "gcc-$gv")" gcc; link "$(command -v "gcc-$gv")" cc
    link "$(command -v "g++-$gv")" g++; link "$(command -v "g++-$gv")" c++
    command -v "gfortran-$gv" >/dev/null 2>&1 && link "$(command -v "gfortran-$gv")" gfortran
  else
    echo "bits-cc-select: GCC_VERSION=$gv not installed in this image" >&2; exit 1
  fi
fi

cv="${CLANG_VERSION:-}"; [ -n "$cv" ] || cv="$(cat "$STATE_DIR/default-clang" 2>/dev/null || true)"
if [ -n "$cv" ]; then
  if [ -x "/opt/bits/llvm/$cv/bin/clang" ]; then
    link "/opt/bits/llvm/$cv/bin/clang" clang
    [ -x "/opt/bits/llvm/$cv/bin/clang++" ] && link "/opt/bits/llvm/$cv/bin/clang++" clang++
  elif command -v "clang-$cv" >/dev/null 2>&1; then
    link "$(command -v "clang-$cv")" clang
    command -v "clang++-$cv" >/dev/null 2>&1 && link "$(command -v "clang++-$cv")" clang++
  elif command -v clang >/dev/null 2>&1; then
    link "$(command -v clang)" clang
    command -v clang++ >/dev/null 2>&1 && link "$(command -v clang++)" clang++
  fi
fi
