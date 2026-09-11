#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 CERN
# SPDX-License-Identifier: GPL-3.0-or-later
#
# In-image smoke test (run via `make test-<plat>`): verify the CONTENT contract
# and that $GCC_VERSION selection actually switches the plain compiler names.
# Runs INSIDE a built image; GCC_VERSIONS/CLANG_VERSIONS are passed by the Makefile.
set -euo pipefail
fail=0; note(){ echo "  $*"; }; bad(){ echo "FAIL: $*" >&2; fail=1; }

echo "## build tools + dev-lib headers"
for t in make bison flex autoconf automake libtool patch tar gzip unzip m4 swig strace gcc gfortran; do
  command -v "$t" >/dev/null || bad "missing tool: $t"
done
command -v c++ >/dev/null || bad "no c++ sibling (GCC-Toolchain prefer_system needs it)"
test -f /usr/include/uuid/uuid.h || bad "missing uuid/uuid.h"
test -f /usr/include/gssapi/gssapi.h -o -f /usr/include/gssapi.h || bad "missing gssapi header"

echo "## GCC selection via \$GCC_VERSION (this is the Phase-2/Phase-4 contract)"
printf 'int main(){return 0;}\n' > /tmp/t.cpp
printf '      program t\n      end\n' > /tmp/t.f
for v in ${GCC_VERSIONS:-}; do
  GCC_VERSION="$v" /opt/bits/bin/bits-cc-select
  maj=$(gcc -dumpversion | cut -d. -f1)
  if [ "$maj" = "$v" ]; then note "GCC_VERSION=$v -> gcc major $maj  OK"; else bad "GCC_VERSION=$v -> gcc major $maj (expected $v)"; fi
  gcc  -xc++ /tmp/t.cpp -c -o /tmp/t.o 2>/dev/null || bad "gcc(v$v) cannot compile C++"
  gfortran /tmp/t.f -c -o /tmp/tf.o 2>/dev/null   || bad "gfortran(v$v) cannot compile Fortran"
  for n in gcc g++ gfortran cc c++; do command -v "$n" >/dev/null || bad "v$v: $n not on PATH"; done
done

echo "## clang selection via \$CLANG_VERSION"
for v in ${CLANG_VERSIONS:-}; do
  CLANG_VERSION="$v" /opt/bits/bin/bits-cc-select || true
  if command -v clang >/dev/null; then note "clang present: $(clang --version | head -1)"; else bad "CLANG_VERSION=$v but no clang on PATH"; fi
done

if command -v nvcc >/dev/null 2>&1; then
  echo "## CUDA (nvcc present -> CUDA flavor image)"
  note "$(nvcc --version | tail -1)"
  # nvcc uses the selected gcc as host compiler; compiling a trivial .cu needs no GPU.
  printf '__global__ void k(){}\nint main(){return 0;}\n' > /tmp/t.cu
  nvcc -c /tmp/t.cu -o /tmp/t.cu.o 2>/tmp/nvcc.err \
    || bad "nvcc cannot compile a trivial .cu with host gcc $(gcc -dumpversion): $(tail -1 /tmp/nvcc.err)"
fi

echo
if [ "$fail" = 0 ]; then echo "SMOKE OK"; else echo "SMOKE FAILED" >&2; fi
exit $fail
