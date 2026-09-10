#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 CERN
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Container ENTRYPOINT: apply the compiler selection from $GCC_VERSION /
# $CLANG_VERSION (falling back to the image defaults), then exec the command.
# Also exports CC/CXX/FC and prepends the gcc-toolset lib64 to LD_LIBRARY_PATH so
# downstream builds link the selected libstdc++. Safe to bypass: the shim dir is
# already on PATH with the default selection baked at build time, so a `docker
# run` that overrides the entrypoint still gets the default compiler.
set -euo pipefail
/opt/bits/bin/bits-cc-select || true
STATE_DIR=/opt/bits/cc
libdir="$(cat "$STATE_DIR/gcc-libdir" 2>/dev/null || true)"
[ -n "$libdir" ] && export LD_LIBRARY_PATH="${libdir}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export CC="${CC:-gcc}" CXX="${CXX:-g++}" FC="${FC:-gfortran}"
if [ "$#" -eq 0 ]; then exec /bin/bash; else exec "$@"; fi
