<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# bits-containers — content specification

This is the **contract** every bits-containers image satisfies. An image is a
*minimal official-distro base* plus exactly the content below — no third-party
builder base, nothing undeclared. The machine-readable sources of truth are
`platforms.yaml`, `packages/*.txt`, and `compilers/install-compilers.sh`; this
document explains *what* and *why*.

## 1. Base

A minimal official image (`almalinux:N-minimal`, `ubuntu:NN.NN`), chosen per
platform in `platforms.yaml`. The one addition to "minimal" on EL is `dnf`
(the `-minimal` images ship only `microdnf`), needed to enable CRB/EPEL and
install `gcc-toolset`; caches are cleaned after.

## 2. Build tools  (`packages/build-tools.{el,deb}.txt`)

autotools (autoconf/automake/libtool/m4), bison/flex, make, patch, perl,
**GNU tar + gzip** (byte-reproducible package tarballs — `--sort`/`--mtime`,
`gzip -n`), unzip, texinfo + gettext/autopoint (alidist recipes are
autotools-first), swig, pkg-config, `strace` + `environment-modules` (`bits
preload`), a baseline `gfortran`, and `perf` on EL (Adaptyst's
`system_requirement`, checked *inside* the container).

## 3. System libraries recipes take via prefer_system  (`packages/dev-libs.*.txt`)

The `-devel` headers for libraries bits configures against rather than building:
krb5 (curl GSS-API, xrootd KRB5), libuuid (Davix/xrootd), openssl, zlib, bzip2,
xz/lzma, libpng, freetype, libxml2, lz4, ncurses, readline, and the X11 + GL/GLU
headers that `lcg.bits` `Xdevel`/`opengl` `system_requirement` checks compile
against. **Deliberately excluded:** heavy libraries (mysql, fftw, glfw, tbb, …)
— recipes BUILD those from source (e.g. GLFW compiles against the X11 `-devel`
added here).

> Source of truth: seeded from the proven `bits-console/docker/bits-builder`
> sets, then extended by a review of the `prefer_system` / `system_requirement`
> checks of **all** recipes (surfaced with `scripts/extract-system-deps.py`).
> Added from that review: the mandatory `system_requirement` shims (apr,
> apr-util, cyrus-sasl, subversion, elfutils/libdw, snappy, perl `EXTERN.h`) and
> the tools `git` + `rsync` (the latter used by `CMakeRecipe`'s own `Prepare`);
> plus the lightweight `prefer_system` libraries xerces-c (Geant4 GDML), sqlite,
> libuv and libunwind.
>
> Deliberately EXCLUDED (and why): heavy libraries recipes build from source —
> mysql, hdf5, tbb, glfw; GPU/kernel image variants — cuda/nvcc, kernel-devel;
> legacy motif (add only if the ROOT/Geant4 closure pulls it); system python
> (bits builds Python); and checks already covered by the compiler (omp.h) or
> ncurses (termcap.h) or that are macOS-only (the Brewfile covers those).
> Because the image installs the whole list as one transaction, the new package
> NAMES (some live in EPEL/CRB, already enabled) are confirmed by the first real
> `make build` on each platform.

## 4. Compiler matrix  (`compilers/install-compilers.sh`)

Each platform ships the GCC majors (and clang) named in its `platforms.yaml`
row, from **distro packages only** — never a from-source compiler build:

| Distro | GCC major `<v>` | clang `<v>` |
|--------|-----------------|-------------|
| EL     | `gcc-toolset-<v>` (under `/opt/rh/…`) | distro `clang` (single stream; `CLANG_VERSIONS` advisory) |
| Ubuntu | `gcc-<v>`/`g++-<v>`/`gfortran-<v>` (toolchain PPA if needed) | `clang-<v>` |

**Provisioning mode** (build arg `COMPILER_SOURCE`, Make target picks it):

- `distro` (default) — distro packages only; the build **fails loud** if a
  requested version is not packaged, so an image never silently ships fewer
  compilers than its row promises.
- `source` — build every requested GCC major (and clang) FROM SOURCE into
  `/opt/bits/gcc/<v>` and `/opt/bits/llvm/<v>`, at the full versions pinned in
  `compilers/source-versions.conf`. Slower and larger; for platforms/versions no
  distro packages (e.g. `gcc-toolset-15` on an older EL).
- `auto` — distro where packaged, source for the rest (the distro step runs
  `--best-effort`, recording the gaps; the source step fills them). The typical
  choice for a platform with partial availability.

The runtime shim resolves a source-built `/opt/bits/gcc/<v>` with precedence over
the distro `gcc-toolset`/suffixed binaries, so `$GCC_VERSION` selection and every
downstream consumer are identical regardless of how the compiler was provisioned.

## 5. Runtime compiler selection — the key contract  (`entrypoint/bits-cc-*.sh`)

`$GCC_VERSION` (and `$CLANG_VERSION`) select the active compiler at `docker run`
time; the shim repoints the **plain** names `gcc/g++/gfortran/cc/c++` (and
`clang/clang++`) — first on `$PATH` — at the chosen version, hiding the
EL-`gcc-toolset` vs Ubuntu-`gcc-<v>` difference. This is exactly what the
`GCC-Toolchain`/`Clang-Toolchain` `prefer_system` probes and the many recipes
that call `cc`/`c++` directly expect, so:

- the probe sees a new-enough plain `gcc` → `prefer_system` passes → the compiler
  is **disabled and pruned from the build graph** (no multi-GB rebuild, out of
  every hash);
- with no `$GCC_VERSION`, the image default (first listed) is baked at build
  time and works even if the entrypoint is bypassed;
- `gfortran` always stays GNU (clang has no Fortran); a gcc remains present on
  the clang axis for libstdc++.

## 6. macOS parallel  (`macos/Brewfile`)

macOS has no container; `brew bundle --file=macos/Brewfile` + the Xcode Command
Line Tools provides the same content guarantee. See `macos/README.md`.

## 7. Relationship to the rest of bits

- Platform names match `bits --architecture` and the keys in
  `bits-console/config/platforms.yaml` — keep the two in sync when a platform's
  image reference changes.
- These images are where the Phase-4 "container model" of the toolchain plan
  (`claude/atlas-bits-toolchain-plan-*`) lands: provider of `$GCC_VERSION`/
  `$CLANG_VERSION`, so compiler versions and container updates don't gratuitously
  rebuild the stack.
