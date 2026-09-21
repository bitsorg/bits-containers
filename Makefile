# SPDX-FileCopyrightText: 2026 CERN
# SPDX-License-Identifier: GPL-3.0-or-later
#
# bits-containers — build & publish minimal-OS toolchain images.
# The matrix lives in platforms.yaml (read via scripts/platforms.py); nothing
# here hard-codes platforms.
#
#   make matrix                 # show the platform matrix
#   make build                  # build every platform image
#   make build-x86_64-el9       # build one
#   make push / push-<plat>     # push to $(REGISTRY)
#   make test / test-<plat>     # run the in-image smoke test
#   make shell-<plat>           # interactive shell in the image
#   make check                  # validate matrix + lint shell/python
#   make fingerprint[-<plat>]   # recompute + adopt the container-fingerprint pin
#                               # (fingerprints/<plat>.hash; keeps own_hash reuse stable)
#
#   ENGINE=podman REGISTRY=... TAG=... BUILD_FLAGS='--pull' make build-x86_64-el9
SHELL := /bin/bash
ENGINE    ?= docker
REGISTRY  ?= gitlab-registry.cern.ch/bits/containers
TAG       ?= latest
BUILD_FLAGS ?= --pull
# APT_MIRROR: fast Ubuntu mirror for the .deb bases. Defaults to the SWITCH
# (Swiss academic) mirror over http — apt verifies packages by GPG signature, so
# http needs no ca-certificates in the minimal base. Override or set empty for
# the distro default: make build APT_MIRROR=http://<your-site-mirror>/ubuntu
APT_MIRROR ?= http://mirror.switch.ch/ftp/mirror/ubuntu
PLAT  := python3 scripts/platforms.py
PLATFORMS := $(shell $(PLAT) names)
CUDA_PLATFORMS := $(shell for p in $(shell $(PLAT) names); do [ -n "$$($(PLAT) get $$p cuda)" ] && echo $$p; done)

# Only concrete (non-pattern) targets go here. Per-platform targets like
# build-x86_64-el9 are produced by pattern rules (build-%, push-%, …); marking
# them .PHONY would make GNU make SKIP the pattern-rule search for them
# ("Nothing to be done"). Pattern-rule targets don't name files, so they already
# re-run every invocation without being phony.
.PHONY: help matrix check build push test build-cuda push-cuda test-cuda fingerprint

help:
	@sed -n '4,/^[^#]/p' Makefile | sed '$$d' | sed 's/^# \{0,1\}//'
	@echo; echo "platforms: $(PLATFORMS)"

matrix:
	@printf '%-20s %-22s %-10s %-7s %-16s %s\n' NAME BASE GCC CLANG INSTALL_DIR CUDA; \
	for p in $(PLATFORMS); do \
	  IFS=$$'\t' read -r n b a g c d cu < <($(PLAT) row $$p); \
	  printf '%-20s %-22s %-10s %-7s %-16s %s\n' "$$n" "$$b" "$$g" "$$c" "$$d" "$$cu"; \
	done
	@echo; echo "cuda flavors: $(CUDA_PLATFORMS)"

check:
	@$(PLAT) check && echo "matrix OK"
	@bash -n test/smoke.sh && echo "shell OK"
	@python3 -m py_compile scripts/platforms.py scripts/extract-system-deps.py && echo "python OK"

build: $(addprefix build-,$(PLATFORMS))
push:  $(addprefix push-,$(PLATFORMS))
test:  $(addprefix test-,$(PLATFORMS))

build-%:
	@base=$$($(PLAT) get $* base); \
	img=$(REGISTRY)/$*:$(TAG); \
	pin=""; [ -f fingerprints/$*.hash ] && pin="$$(cat fingerprints/$*.hash)"; \
	echo "==> build $$img  FROM $$base$${pin:+  (pinned fingerprint $$pin)}"; \
	$(ENGINE) build $(BUILD_FLAGS) \
	  --build-arg BASE_IMAGE="$$base" \
	  --build-arg APT_MIRROR="$(APT_MIRROR)" \
	  $${pin:+--build-arg PINNED_FINGERPRINT="$$pin"} \
	  -t "$$img" .

push-%:
	@img=$(REGISTRY)/$*:$(TAG); echo "==> push $$img"; $(ENGINE) push "$$img"

# Run the smoke test inside the image, exercising every GCC the platform ships.
test-%:
	@img=$(REGISTRY)/$*:$(TAG); \
	echo "==> smoke $$img"; \
	$(ENGINE) run --rm -v "$(PWD)/test:/bits-test:ro" "$$img" /bits-test/smoke.sh

shell-%:
	@$(ENGINE) run --rm -it $(REGISTRY)/$*:$(TAG)

# ── CUDA flavor: overlay the NVIDIA toolkit on a base image -> <plat>-cuda ─────
build-cuda: $(addprefix build-cuda-,$(CUDA_PLATFORMS))
push-cuda:  $(addprefix push-cuda-,$(CUDA_PLATFORMS))
test-cuda:  $(addprefix test-cuda-,$(CUDA_PLATFORMS))

build-cuda-%:
	@cuda=$$($(PLAT) get $* cuda); \
	[ -n "$$cuda" ] || { echo "platform $* has no 'cuda:' version in platforms.yaml" >&2; exit 1; }; \
	baseimg=$(REGISTRY)/$*:$(TAG); img=$(REGISTRY)/$*-cuda:$(TAG); \
	$(ENGINE) image inspect "$$baseimg" >/dev/null 2>&1 \
	  || echo "note: base $$baseimg not present locally — 'make build-$*' first, or ensure it is pullable"; \
	echo "==> build $$img  FROM $$baseimg  (cuda $$cuda)"; \
	$(ENGINE) build --build-arg BASE_IMAGE="$$baseimg" --build-arg CUDA_VERSION="$$cuda" \
	  -f Dockerfile.cuda -t "$$img" .

push-cuda-%:
	@img=$(REGISTRY)/$*-cuda:$(TAG); echo "==> push $$img"; $(ENGINE) push "$$img"

test-cuda-%:
	@img=$(REGISTRY)/$*-cuda:$(TAG); \
	echo "==> smoke $$img (incl. nvcc)"; \
	$(ENGINE) run --rm -v "$(PWD)/test:/bits-test:ro" "$$img" /bits-test/smoke.sh

# ── Fingerprint pin ───────────────────────────────────────────────────────────
# Keep the container fingerprint STABLE across image rebuilds so incidental
# package drift does not rehash the own_hash toolchain (an expensive rebuild).
# build-% pins from fingerprints/<plat>.hash when it exists. `make fingerprint[-%]`
# rebuilds UNPINNED, reads the freshly computed hash out of the image, and writes
# the lock — the deliberate "adopt a new baseline" step (review + commit the
# fingerprints/ diff). Prefer `fingerprint-<plat>` to adopt ONE platform; the
# aggregate `fingerprint` rewrites EVERY lock (and aborts mid-way on a failure).
# While pinned, a genuine ABI/codegen drift is hidden until you run it; do that
# before a certified/production build.
fingerprint: $(addprefix fingerprint-,$(PLATFORMS))

fingerprint-%:
	@base=$$($(PLAT) get $* base); \
	probe=bits-fp-probe-$*:latest; \
	echo "==> fingerprint $* — building UNPINNED probe image to compute the real hash"; \
	$(ENGINE) build $(BUILD_FLAGS) \
	  --build-arg BASE_IMAGE="$$base" \
	  --build-arg APT_MIRROR="$(APT_MIRROR)" \
	  -t "$$probe" .; \
	mkdir -p fingerprints; \
	fp=$$($(ENGINE) run --rm "$$probe" cat /opt/bits/container-fingerprint.hash); \
	$(ENGINE) rmi -f "$$probe" >/dev/null 2>&1 || true; \
	[ -n "$$fp" ] || { echo "ERROR: empty fingerprint for $*" >&2; exit 1; }; \
	printf '%s\n' "$$fp" > fingerprints/$*.hash; \
	echo "==> fingerprints/$*.hash = $$fp   (review 'git diff fingerprints/', commit, then 'make build-$*')"
