#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 CERN
# SPDX-License-Identifier: GPL-3.0-or-later
#
# install-cuda.sh — install the NVIDIA CUDA toolkit (nvcc + libraries) from the
# official NVIDIA repositories, into a bits-containers CUDA flavor image (see
# ../Dockerfile.cuda). bits never builds CUDA: the `cuda` recipe is a
# system_requirement that only checks `command -v nvcc`, so the toolkit must be
# present in the image for any --defaults cuda build.
#
# IMPORTANT host-compiler compatibility: nvcc supports a bounded GCC range per
# CUDA release (e.g. CUDA 12.4 tops out at gcc 13; gcc 15 needs CUDA 13.x). The
# CUDA_VERSION for a platform must therefore cover its gcc majors — this is why
# the version is chosen per-platform in platforms.yaml (cuda:).
#
# Env: CUDA_VERSION = major.minor, e.g. "13.3"  (required)
set -euo pipefail
CUDA_VERSION="${CUDA_VERSION:?install-cuda: CUDA_VERSION (major.minor) is required}"
cv_dash="${CUDA_VERSION/./-}"                 # 13.3 -> 13-3 (package suffix)
m="$(uname -m)"
. /etc/os-release

if command -v dnf >/dev/null 2>&1; then
  el="${VERSION_ID%%.*}"
  repoarch="$([ "$m" = aarch64 ] && echo sbsa || echo x86_64)"
  dnf -y install dnf-plugins-core || true
  dnf config-manager --add-repo \
    "https://developer.download.nvidia.com/compute/cuda/repos/rhel${el}/${repoarch}/cuda-rhel${el}.repo"
  dnf -y install "cuda-toolkit-${cv_dash}" || {
    echo "install-cuda: cuda-toolkit-${cv_dash} unavailable for rhel${el}/${repoarch}." >&2
    echo "  available:" >&2; dnf -q list available 'cuda-toolkit-*' 2>/dev/null | sed 's/^/    /' >&2 || true
    exit 1; }
  dnf clean all
elif command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  ubu="${VERSION_ID//./}"                     # 24.04 -> 2404
  repoarch="$([ "$m" = aarch64 ] && echo sbsa || echo x86_64)"
  apt-get update; apt-get install -y --no-install-recommends wget ca-certificates gnupg
  wget -qO /tmp/cuda-keyring.deb \
    "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${ubu}/${repoarch}/cuda-keyring_1.1-1_all.deb"
  dpkg -i /tmp/cuda-keyring.deb; rm -f /tmp/cuda-keyring.deb
  apt-get update
  apt-get install -y --no-install-recommends "cuda-toolkit-${cv_dash}" \
    || { echo "install-cuda: cuda-toolkit-${cv_dash} unavailable for ubuntu${ubu}/${repoarch}." >&2; exit 1; }
  rm -rf /var/lib/apt/lists/*
else
  echo "install-cuda: no dnf/apt-get" >&2; exit 2
fi

# Stable /usr/local/cuda -> the versioned toolkit (nvcc lives in its bin/).
[ -e /usr/local/cuda ] || ln -sfn "/usr/local/cuda-${CUDA_VERSION}" /usr/local/cuda || true
command -v nvcc >/dev/null || [ -x "/usr/local/cuda/bin/nvcc" ] || {
  echo "install-cuda: nvcc not found after install" >&2; exit 1; }
echo "install-cuda: installed CUDA ${CUDA_VERSION}."
