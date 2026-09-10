#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 CERN
# SPDX-License-Identifier: GPL-3.0-or-later
"""Extract system-dependency hints from bits recipes, to keep the image/Brewfile
content specs honest against what recipes actually require.

Recipes express system deps in three ways, in decreasing structure:
  * `homebrew_formula: <name>`            — macOS, fully structured (best signal)
  * `brew --prefix <name>` in a script    — macOS, inline
  * dnf/apt/yum install <pkgs> in a        — Linux, inline in prefer_system_check /
    prefer_system_check / system_requirement   system_requirement_check (least structured)

Usage:
  extract-system-deps.py brew  <repo-or-glob> [more...]   # macOS formulae (sorted set)
  extract-system-deps.py linux <repo-or-glob> [more...]   # Linux install-hint tokens
  extract-system-deps.py all   <repo-or-glob> [more...]   # both, annotated

This is an AID, not the source of truth: Linux hints are embedded in shell and
can't be extracted perfectly, so packages/*.txt stay curated (seeded from
bits-console/docker/bits-builder) and this tool flags additions to consider.
"""
import sys, os, re, glob

RE_BREW_FORMULA = re.compile(r'^\s*homebrew_formula:\s*(.+?)\s*$', re.M)
RE_BREW_PREFIX  = re.compile(r'brew\s+--prefix\s+([A-Za-z0-9@._+-]+)')
RE_PKG_INSTALL  = re.compile(r'\b(?:dnf|yum|apt-get|apt)\s+(?:-y\s+)?install\s+([^\n;&|]+)')

def iter_recipes(args):
    for a in args:
        if os.path.isdir(a):
            yield from glob.glob(os.path.join(a, "*.sh"))
        else:
            yield from glob.glob(a)

def scan(args):
    brew, brew_prefix, linux = set(), set(), set()
    for f in iter_recipes(args):
        try:
            s = open(f, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for m in RE_BREW_FORMULA.finditer(s):
            for tok in m.group(1).replace(",", " ").split():
                brew.add(tok.strip('"\''))
        for m in RE_BREW_PREFIX.finditer(s):
            brew_prefix.add(m.group(1))
        for m in RE_PKG_INSTALL.finditer(s):
            for tok in m.group(1).split():
                if tok.startswith("-") or "$" in tok or "%" in tok:
                    continue
                linux.add(tok)
    return brew, brew_prefix, linux

def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr); return 2
    mode, args = argv[0], argv[1:]
    brew, brew_prefix, linux = scan(args)
    if mode in ("brew", "all"):
        print("# homebrew_formula: declarations")
        for x in sorted(brew): print(x)
        print("\n# brew --prefix <name> (inline macOS hints)")
        for x in sorted(brew_prefix): print(x)
    if mode in ("linux", "all"):
        if mode == "all": print("\n# Linux install-hint tokens (inline; review before trusting)")
        for x in sorted(linux): print(x)
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
