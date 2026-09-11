# bits-containers

Make-driven build & publish of **minimal-OS toolchain images** for bits — one
clearly-specified image per platform, built FROM a minimal official distro base
(no third-party builder base), carrying the build tools, the system `-devel`
libraries recipes take via `prefer_system`, and a **runtime-selectable** GCC/clang
matrix (`$GCC_VERSION` / `$CLANG_VERSION`).

The full content contract is in **[`spec/CONTENT.md`](spec/CONTENT.md)**. The
platform matrix is the single source of truth in **`platforms.yaml`**.

## Layout

```
platforms.yaml              the matrix (name, base, arch, gcc, clang, install_dir)
Dockerfile                  one parameterized, pkg-manager-detecting build
packages/*.txt              build tools + dev-lib headers (EL and Debian/Ubuntu)
compilers/container-fingerprint.sh    fingerprint of output-affecting content
compilers/install-cuda.sh             NVIDIA CUDA toolkit (cuda platforms)
Dockerfile.cuda             CUDA flavor overlay (base image + NVIDIA toolkit)
compilers/install-cuda.sh   installs the CUDA toolkit for the flavor
macos/Brewfile              the macOS (no-container) parallel content set
scripts/platforms.py        matrix parser used by the Makefile
scripts/extract-system-deps.py   derive system-dep hints from recipes (an aid)
test/smoke.sh               in-image contract + selection test
Makefile                    build / push / test / matrix / check
```

## Quickstart

```bash
make matrix                         # see the platforms
make check                          # validate matrix + lint (no Docker needed)
make build-x86_64-el9               # build one image
make test-x86_64-el9                # smoke-test it (exercises each GCC it ships)
make push-x86_64-el9                # publish to $REGISTRY
make build                          # everything

# compilers from source (for versions a distro does not package):
make build-src-x86_64-el10          # build all compilers from source
make build-auto-x86_64-el10         # distro where available, source for the rest

# CUDA flavor (needs nvcc in the builder; base image must exist first):
make build-x86_64-el9 && make build-cuda-x86_64-el9   # -> x86_64-el9-cuda
make test-cuda-x86_64-el9                              # smoke incl. nvcc
```

Override with `ENGINE=podman`, `REGISTRY=…`, `TAG=…`, `BUILD_FLAGS='--pull'`.

Use a selected compiler at run time:

```bash
docker run --rm -e GCC_VERSION=15 $REGISTRY/x86_64-el9:latest gcc --version
```

## Adding a platform or compiler version

Edit `platforms.yaml` (add a row, or add a major to `gcc:`/`clang:`), then
`make build-<name>`. The image build fails loud if a requested compiler version
is not packaged on that distro — the `verify:` notes flag the ones to confirm.

## Status

v1 scaffold. Package *names* are verified (carried from
`bits-console/docker/bits-builder`); the per-distro **compiler version
availability** (`gcc-toolset-15` on EL9/EL10, `gcc-15`/clang on Ubuntu, the
`ubuntu:26.04` base tag) is marked `verify:` in `platforms.yaml` and is
confirmed by the first real `make build` on each platform. Where a version is
not packaged, use `make build-auto-<plat>` (or `build-src-`) to fill it from
the stack's compiler is built by bits, not the image (see ADR-0012).
