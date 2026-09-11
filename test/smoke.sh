#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 CERN
# SPDX-License-Identifier: GPL-3.0-or-later
#
# In-image smoke test (run via `make test-<plat>`): verify the CONTENT contract —
# base build tools, dev-lib headers, and the BASE bootstrap compiler bits uses to
# build GCC-Toolchain. The image installs no per-axis compilers; bits builds the
# stack's compiler itself, so there is no $GCC_VERSION selection to test here.
set -euo pipefail
fail=0; note(){ echo "  $*"; }; bad(){ echo "FAIL: $*" >&2; fail=1; }

[ -f /opt/bits/container-fingerprint.hash ] && echo "## container fingerprint: $(cat /opt/bits/container-fingerprint.hash)"

echo "## build tools + dev-lib headers + base compiler"
for t in make bison flex autoconf automake libtool patch tar gzip unzip m4 swig strace gcc g++ gfortran; do
  command -v "$t" >/dev/null || bad "missing tool: $t"
done
command -v c++ >/dev/null || bad "no c++ sibling (GCC-Toolchain bootstrap needs it)"
test -f /usr/include/uuid/uuid.h || bad "missing uuid/uuid.h"
test -f /usr/include/gssapi/gssapi.h -o -f /usr/include/gssapi.h || bad "missing gssapi header"

echo "## base compiler can build C++ and Fortran"
printf 'int main(){return 0;}\n' > /tmp/t.cpp && g++ /tmp/t.cpp -c -o /tmp/t.o 2>/dev/null || bad "g++ cannot compile C++"
printf '      program t\n      end\n' > /tmp/t.f && gfortran /tmp/t.f -c -o /tmp/tf.o 2>/dev/null || bad "gfortran cannot compile Fortran"
note "gcc: $(gcc --version | head -1)"

if command -v nvcc >/dev/null 2>&1; then
  echo "## CUDA (nvcc present -> CUDA flavor image)"
  note "$(nvcc --version | tail -1)"
  printf '__global__ void k(){}\nint main(){return 0;}\n' > /tmp/t.cu
  nvcc -c /tmp/t.cu -o /tmp/t.cu.o 2>/tmp/nvcc.err \
    || bad "nvcc cannot compile a trivial .cu with host gcc $(gcc -dumpversion): $(tail -1 /tmp/nvcc.err)"
fi

echo
if [ "$fail" = 0 ]; then echo "SMOKE OK"; else echo "SMOKE FAILED" >&2; fi
exit $fail
