#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 CERN
# SPDX-License-Identifier: GPL-3.0-or-later
#
# install-compilers.sh — install the requested GCC/clang majors from DISTRO
# PACKAGES (no from-source build). Runs during `docker build`.
#
#   EL    : GCC -> gcc-toolset-<v> (/opt/rh/...);  clang -> distro `clang`
#   Ubuntu: GCC -> gcc-<v>/g++-<v>/gfortran-<v> (toolchain PPA if needed);
#           clang -> clang-<v>
#
# Default: FAIL LOUD if a requested version is not packaged. With --best-effort
# (used by COMPILER_SOURCE=auto): do not fail — record the majors that could not
# be installed to /opt/bits/cc/missing-gcc and /opt/bits/cc/missing-clang, so the
# from-source builder can fill them in a second pass.
#
# Env: GCC_VERSIONS (required), CLANG_VERSIONS (optional)
set -euo pipefail
BEST_EFFORT=0; [ "${1:-}" = "--best-effort" ] && BEST_EFFORT=1
GCC_VERSIONS="${GCC_VERSIONS:-}"; CLANG_VERSIONS="${CLANG_VERSIONS:-}"
[ -n "$GCC_VERSIONS" ] || { echo "install-compilers: GCC_VERSIONS is required" >&2; exit 2; }
mkdir -p /opt/bits/cc; : > /opt/bits/cc/missing-gcc; : > /opt/bits/cc/missing-clang
miss_gcc(){ echo "$1" >> /opt/bits/cc/missing-gcc; }
miss_clang(){ echo "$1" >> /opt/bits/cc/missing-clang; }
fail_or_record(){ # kind major message
  if [ "$BEST_EFFORT" = 1 ]; then echo "install-compilers: $3 (best-effort: deferring $1 $2 to source build)" >&2
    [ "$1" = gcc ] && miss_gcc "$2" || miss_clang "$2"; return 0
  fi
  echo "install-compilers: $3" >&2; exit 1
}

if command -v dnf >/dev/null 2>&1; then FAM=el
elif command -v apt-get >/dev/null 2>&1; then FAM=deb
else echo "install-compilers: no dnf/apt-get" >&2; exit 2; fi
echo "install-compilers: family=$FAM gcc='$GCC_VERSIONS' clang='$CLANG_VERSIONS' best_effort=$BEST_EFFORT"

if [ "$FAM" = el ]; then
  dnf -y install dnf-plugins-core epel-release || true
  { dnf config-manager --set-enabled crb || dnf config-manager --set-enabled powertools \
    || dnf config-manager --set-enabled PowerTools; } || true
  # On EL exactly ONE gcc major is the BASE system compiler (the `gcc` package);
  # every OTHER major comes via gcc-toolset-<N>. gcc-toolset-<default> does not
  # exist (e.g. EL10's default is gcc 14 -> no gcc-toolset-14). gcc is present
  # already (build-tools pulls gcc-gfortran), so dumpversion gives the default.
  sysmaj="$(gcc -dumpversion 2>/dev/null | cut -d. -f1)"
  for v in $GCC_VERSIONS; do
    if [ -n "$sysmaj" ] && [ "$v" = "$sysmaj" ]; then
      echo "== system gcc $v (base packages; the default major has no gcc-toolset)"
      dnf -y install gcc gcc-c++ gcc-gfortran \
        || fail_or_record gcc "$v" "base gcc packages unavailable"
    else
      echo "== gcc-toolset-$v"
      dnf -y install "gcc-toolset-$v" "gcc-toolset-$v-gcc-c++" "gcc-toolset-$v-gcc-gfortran" \
        || fail_or_record gcc "$v" "gcc-toolset-$v not available on this EL release"
    fi
  done
  if [ -n "$CLANG_VERSIONS" ]; then
    if dnf -y install clang llvm; then
      echo "install-compilers: EL ships one clang stream ($(clang --version 2>/dev/null | head -1)); CLANG_VERSIONS advisory."
    else
      for v in $CLANG_VERSIONS; do fail_or_record clang "$v" "distro clang not available"; done
    fi
  fi
  dnf clean all || true
else
  export DEBIAN_FRONTEND=noninteractive; apt-get update
  _ppa=0
  for v in $GCC_VERSIONS; do
    echo "== gcc/g++/gfortran-$v"
    if ! apt-get install -y --no-install-recommends "gcc-$v" "g++-$v" "gfortran-$v"; then
      if [ "$_ppa" = 0 ]; then
        apt-get install -y --no-install-recommends software-properties-common || true
        add-apt-repository -y ppa:ubuntu-toolchain-r/test || true; apt-get update || true; _ppa=1
      fi
      apt-get install -y --no-install-recommends "gcc-$v" "g++-$v" "gfortran-$v" \
        || fail_or_record gcc "$v" "gcc-$v unavailable even with the toolchain PPA"
    fi
  done
  for v in $CLANG_VERSIONS; do
    echo "== clang-$v"
    apt-get install -y --no-install-recommends "clang-$v" \
      || fail_or_record clang "$v" "clang-$v not in apt (add apt.llvm.org for this release)"
  done
  rm -rf /var/lib/apt/lists/*
fi
echo "install-compilers: done (missing-gcc='$(tr '\n' ' ' </opt/bits/cc/missing-gcc)' missing-clang='$(tr '\n' ' ' </opt/bits/cc/missing-clang)')."
