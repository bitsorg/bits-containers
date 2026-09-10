#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 CERN
# SPDX-License-Identifier: GPL-3.0-or-later
#
# build-compilers-from-source.sh — build the requested GCC majors (and optionally
# clang/LLVM) FROM SOURCE into per-version prefixes the selection shim understands:
#   GCC   -> /opt/bits/gcc/<major>     (bin/gcc, bin/g++, bin/gfortran)
#   LLVM  -> /opt/bits/llvm/<major>    (bin/clang, bin/clang++)
# Used by the Dockerfile when COMPILER_SOURCE=source (all requested) or =auto
# (only the majors distro packaging could not provide, via --missing).
#
# Full versions come from source-versions.conf (explicit, part of the spec).
# This is SLOW and makes larger images — it exists for platforms/versions a
# distro does not package (e.g. gcc-toolset-15 on an older EL). Set BOOTSTRAP=1
# for a full 3-stage GCC bootstrap (slower, higher assurance); default is a
# single-stage build for speed.
#
# Env: GCC_VERSIONS, CLANG_VERSIONS  (space-separated majors); JOBS; BOOTSTRAP
set -euo pipefail
SELFDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VER_CONF="${SELFDIR}/source-versions.conf"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"
GCC_VERSIONS="${GCC_VERSIONS:-}"; CLANG_VERSIONS="${CLANG_VERSIONS:-}"

if [ "${1:-}" = "--missing" ]; then
  GCC_VERSIONS="$(cat /opt/bits/cc/missing-gcc 2>/dev/null || true)"
  CLANG_VERSIONS="$(cat /opt/bits/cc/missing-clang 2>/dev/null || true)"
fi
[ -n "${GCC_VERSIONS}${CLANG_VERSIONS}" ] || { echo "build-from-source: nothing to build."; exit 0; }

full_for() { awk -v k="$1" -v m="$2" '$1==k && $2==m {print $3; exit}' "${VER_CONF}"; }

# Build prerequisites (best-effort; the base already has make/gcc/bison/flex/xz).
if command -v dnf >/dev/null 2>&1; then
  dnf -y install gcc gcc-c++ make cmake ninja-build wget xz flex bison || true
elif command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive; apt-get update || true
  apt-get install -y --no-install-recommends gcc g++ make cmake ninja-build wget xz-utils flex bison || true
fi

build_gcc() {
  local maj="$1" full pfx t; full="$(full_for gcc "$maj")"
  [ -n "$full" ] || { echo "build-from-source: no source-versions.conf row for gcc $maj" >&2; return 1; }
  pfx="/opt/bits/gcc/$maj"; t="/tmp/gccsrc-$maj"
  echo "== gcc $full -> $pfx"
  rm -rf "$t"; mkdir -p "$t"; cd "$t"
  wget -q "https://ftp.gnu.org/gnu/gcc/gcc-$full/gcc-$full.tar.xz"
  tar xf "gcc-$full.tar.xz"; cd "gcc-$full"
  ./contrib/download_prerequisites
  mkdir build; cd build
  ../configure --prefix="$pfx" --enable-languages=c,c++,fortran \
               --disable-multilib --disable-nls ${BOOTSTRAP:+} $( [ -z "${BOOTSTRAP:-}" ] && echo --disable-bootstrap )
  make -j"$JOBS"; make install
  cd /; rm -rf "$t"
}

build_llvm() {
  local maj="$1" full pfx t; full="$(full_for llvm "$maj")"
  [ -n "$full" ] || { echo "build-from-source: no source-versions.conf row for llvm $maj" >&2; return 1; }
  pfx="/opt/bits/llvm/$maj"; t="/tmp/llvmsrc-$maj"
  echo "== llvm/clang $full -> $pfx"
  rm -rf "$t"; mkdir -p "$t"; cd "$t"
  wget -q "https://github.com/llvm/llvm-project/releases/download/llvmorg-$full/llvm-project-$full.src.tar.xz"
  tar xf "llvm-project-$full.src.tar.xz"; cd "llvm-project-$full.src"
  cmake -S llvm -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_ENABLE_PROJECTS="clang;clang-tools-extra" \
        -DLLVM_TARGETS_TO_BUILD=host -DCMAKE_INSTALL_PREFIX="$pfx"
  cmake --build build --target install -- -j"$JOBS"
  cd /; rm -rf "$t"
}

for v in ${GCC_VERSIONS}; do build_gcc "$v"; done
for v in ${CLANG_VERSIONS}; do build_llvm "$v"; done
echo "build-compilers-from-source: done."
