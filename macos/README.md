<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# macOS toolchain (Homebrew)

macOS builds run on the host (no container). The equivalent of a bits-containers
image is a Homebrew installation plus the Xcode Command Line Tools — but unlike
the Linux images, **the macOS content set is not maintained in this repo.** It is
derived from the recipes, which are the single source of truth for both platforms:

- Linux → `packages/*.txt` (baked into the image).
- macOS → the recipes' own `homebrew_formula:` declarations + the bits base
  formulae, materialised on demand by bits.

So there is no `Brewfile` to keep in sync here; `macos/Brewfile` is only a pointer.

## Provision

```bash
xcode-select --install                    # Apple clang + macOS SDK (prerequisite)

# Generate the config-accurate Brewfile and install it. bits records the file in
# your local build area at <work-dir>/<arch>/Brewfile (work-dir defaults to ./sw),
# keyed to the architecture and recipes your current configuration resolves.
bits brew -a osx_arm64                     # or your osx_* architecture
brew bundle --file sw/osx_arm64/Brewfile
```

Or skip the explicit step and let the build install formulae as it resolves:

```bash
bits build --brew ...                      # runs `brew install <formula>` on demand
```

## Compiler axes on macOS

- **gcc axis** — `brew install gcc` provides `gfortran` and a versioned `g++-NN`.
  `GCC-Toolchain` is `:(?!osx)`-excluded on macOS, so gcc is never built; the
  default cc/c++ are Apple clang unless you point `$CC`/`$CXX` at brew gcc.
- **clang axis** — Apple clang (from the CLT) is the default; `brew llvm` provides
  a specific LLVM clang. `Clang-Toolchain`'s probe is presence-only on macOS
  (Apple clang versions do not map to LLVM majors), so no numeric floor applies.

## Auditing macOS coverage

To see which formulae the recipes request on macOS (a candidate diff, not an
authoritative list), use:

```bash
scripts/extract-system-deps.py brew ../lcg.bits ../common.bits ../*.bits
```
