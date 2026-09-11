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
#   make test / test-<plat>     # run the in-image smoke test over its GCC set
#   make shell-<plat>           # interactive shell in the image
#   make check                  # validate matrix + lint shell/python
#
#   ENGINE=podman REGISTRY=... TAG=... BUILD_FLAGS='--pull' make build-x86_64-el9
SHELL := /bin/bash
ENGINE    ?= docker
REGISTRY  ?= gitlab-registry.cern.ch/buncic/bits-containers
TAG       ?= latest
BUILD_FLAGS ?= --pull
COMPILER_SOURCE ?= distro   # distro | source | auto
PLAT  := python3 scripts/platforms.py
PLATFORMS := $(shell $(PLAT) names)
CUDA_PLATFORMS := $(shell for p in $(shell $(PLAT) names); do [ -n "$$($(PLAT) get $$p cuda)" ] && echo $$p; done)

.PHONY: help matrix check build push test $(addprefix build-,$(PLATFORMS)) \
        $(addprefix push-,$(PLATFORMS)) $(addprefix test-,$(PLATFORMS)) \
        $(addprefix shell-,$(PLATFORMS)) \
        $(addprefix build-src-,$(PLATFORMS)) $(addprefix build-auto-,$(PLATFORMS)) \
        build-cuda push-cuda test-cuda $(addprefix build-cuda-,$(CUDA_PLATFORMS)) \
        $(addprefix push-cuda-,$(CUDA_PLATFORMS)) $(addprefix test-cuda-,$(CUDA_PLATFORMS))

help:
	@sed -n '2,20p' Makefile | sed 's/^# \{0,1\}//'
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
	@bash -n entrypoint/bits-cc-select.sh entrypoint/bits-cc-entry.sh \
	         compilers/install-compilers.sh test/smoke.sh && echo "shell OK"
	@python3 -m py_compile scripts/platforms.py scripts/extract-system-deps.py && echo "python OK"

build: $(addprefix build-,$(PLATFORMS))
push:  $(addprefix push-,$(PLATFORMS))
test:  $(addprefix test-,$(PLATFORMS))

build-%:
	@base=$$($(PLAT) get $* base); gcc=$$($(PLAT) get $* gcc); clang=$$($(PLAT) get $* clang); \
	img=$(REGISTRY)/$*:$(TAG); \
	echo "==> build $$img  FROM $$base  (gcc='$$gcc' clang='$$clang' compilers=$(COMPILER_SOURCE))"; \
	$(ENGINE) build $(BUILD_FLAGS) \
	  --build-arg BASE_IMAGE="$$base" \
	  --build-arg GCC_VERSIONS="$$gcc" \
	  --build-arg CLANG_VERSIONS="$$clang" \
	  --build-arg COMPILER_SOURCE="$(COMPILER_SOURCE)" \
	  -t "$$img" .

# Convenience: source-built or auto (distro+source) compilers for one platform.
build-src-%:
	@$(MAKE) build-$* COMPILER_SOURCE=source
build-auto-%:
	@$(MAKE) build-$* COMPILER_SOURCE=auto

push-%:
	@img=$(REGISTRY)/$*:$(TAG); echo "==> push $$img"; $(ENGINE) push "$$img"

# Run the smoke test inside the image, exercising every GCC the platform ships.
test-%:
	@img=$(REGISTRY)/$*:$(TAG); gcc=$$($(PLAT) get $* gcc); clang=$$($(PLAT) get $* clang); \
	echo "==> smoke $$img  (gcc='$$gcc' clang='$$clang')"; \
	$(ENGINE) run --rm -e GCC_VERSIONS="$$gcc" -e CLANG_VERSIONS="$$clang" \
	  -v "$(PWD)/test:/bits-test:ro" "$$img" /bits-test/smoke.sh

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
	@img=$(REGISTRY)/$*-cuda:$(TAG); gcc=$$($(PLAT) get $* gcc); clang=$$($(PLAT) get $* clang); \
	echo "==> smoke $$img (incl. nvcc)"; \
	$(ENGINE) run --rm -e GCC_VERSIONS="$$gcc" -e CLANG_VERSIONS="$$clang" \
	  -v "$(PWD)/test:/bits-test:ro" "$$img" /bits-test/smoke.sh
