#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 CERN
# SPDX-License-Identifier: GPL-3.0-or-later
"""Read platforms.yaml and emit matrix fields for the Makefile/scripts.

Usage:
  platforms.py names                 -> all platform names, space-separated
  platforms.py get <name> <field>    -> one field (base|arch|gcc|clang|install_dir)
  platforms.py row  <name>           -> TAB-separated: name base arch gcc clang install_dir
  platforms.py check                 -> validate the file; non-zero on error

No third-party deps: uses PyYAML if present, else a tiny line parser for this
file's fixed shape.
"""
import sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
PFILE = os.path.join(HERE, "..", "platforms.yaml")
FIELDS = ("name", "base", "arch", "gcc", "clang", "install_dir")

def load():
    txt = open(PFILE, encoding="utf-8").read()
    try:
        import yaml
        data = yaml.safe_load(txt) or {}
        plats = data.get("platforms", []) or []
        out = []
        for p in plats:
            d = {k: str(p.get(k, "")) for k in FIELDS}
            d.setdefault("arch", "")
            if not d["arch"]:
                d["arch"] = d["name"]
            out.append(d)
        return out
    except ImportError:
        pass
    # Minimal fallback parser for this file's "- key: value" block shape.
    out, cur = [], None
    for line in txt.splitlines():
        s = line.strip()
        if s.startswith("- name:"):
            if cur:
                out.append(cur)
            cur = {k: "" for k in FIELDS}
            cur["name"] = s.split(":", 1)[1].strip().strip('"')
        elif cur is not None and ":" in s and not s.startswith("#"):
            k, _, v = s.partition(":")
            k = k.strip().lstrip("- ")
            if k in FIELDS:
                cur[k] = v.strip().strip('"')
    if cur:
        out.append(cur)
    for d in out:
        if not d.get("arch"):
            d["arch"] = d["name"]
    return out

def main(argv):
    plats = load()
    by = {p["name"]: p for p in plats}
    if not argv or argv[0] == "names":
        print(" ".join(p["name"] for p in plats)); return 0
    if argv[0] == "check":
        ok = True
        for p in plats:
            for k in ("base", "gcc", "install_dir"):
                if not p.get(k):
                    print("ERROR: %s missing %s" % (p["name"], k), file=sys.stderr); ok = False
        return 0 if ok else 1
    if argv[0] == "get" and len(argv) == 3:
        p = by.get(argv[1])
        if not p:
            print("unknown platform: %s" % argv[1], file=sys.stderr); return 2
        print(p.get(argv[2], "")); return 0
    if argv[0] == "row" and len(argv) == 2:
        p = by.get(argv[1])
        if not p:
            print("unknown platform: %s" % argv[1], file=sys.stderr); return 2
        print("\t".join(p[k] for k in FIELDS)); return 0
    print(__doc__, file=sys.stderr); return 2

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
