<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# macOS toolchain (Homebrew)

macOS builds run on the host (no container). The equivalent of a bits-containers
image is this repo's `Brewfile` plus the Xcode Command Line Tools.

## Provision

```bash
xcode-select --install                 # Apple clang + macOS SDK (prerequisite)
brew bundle --file=macos/Brewfile      # the bits build content set
```

## Compiler axes on macOS

- **gcc axis** — `brew install gcc` provides `gfortran` and a versioned `g++-NN`.
  `GCC-Toolchain` is `:(?!osx)`-excluded on macOS, so gcc is never built; the
  default cc/c++ are Apple clang unless you point `$CC`/`$CXX` at brew gcc.
- **clang axis** — Apple clang (from the CLT) is the default; `brew llvm` provides
  a specific LLVM clang. `Clang-Toolchain`'s probe is presence-only on macOS
  (Apple clang versions do not map to LLVM majors), so no numeric floor is
  applied here.

## Keeping the list honest

The formulae above are seeded from the recipes' own macOS hints. Regenerate the
candidate set and diff it in:

```bash
scripts/extract-system-deps.py brew ../lcg.bits ../common.bits ../*.bits
```
