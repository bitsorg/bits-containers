# SPDX-FileCopyrightText: 2026 CERN
# SPDX-License-Identifier: GPL-3.0-or-later
#
# bits-containers — one parameterized Dockerfile that turns a MINIMAL OFFICIAL
# distro base into a fully-specified bits build toolchain image. Works for the
# EL (dnf/microdnf) and Ubuntu (apt) bases alike by detecting the package
# manager. The content is defined entirely by:
#   packages/{build-tools,dev-libs}.{el,deb}.txt   (system libs + tools)
#   compilers/install-compilers.sh                 (the GCC/clang matrix)
#   entrypoint/bits-cc-*.sh                         ($GCC_VERSION/$CLANG_VERSION shim)
# See spec/CONTENT.md for the contract every image satisfies.
#
# Build args come from the platforms.yaml row (the Makefile passes them):
#   BASE_IMAGE, GCC_VERSIONS, CLANG_VERSIONS, DEFAULT_GCC, DEFAULT_CLANG
ARG BASE_IMAGE=almalinux:9-minimal
FROM ${BASE_IMAGE}

ARG GCC_VERSIONS="13 14 15"
ARG CLANG_VERSIONS=""
ARG DEFAULT_GCC=""
ARG DEFAULT_CLANG=""
# Provisioning: distro (default) | source (build all from source) | auto
# (distro where packaged, source fallback for the rest).
ARG COMPILER_SOURCE="distro"
# Optional fast APT mirror (e.g. a site-local Ubuntu mirror). Empty = distro
# default. On slow/distant default mirrors this is the biggest lever.
ARG APT_MIRROR=""

USER root
SHELL ["/bin/bash", "-c"]

COPY packages/ /opt/bits/src/packages/
COPY compilers/ /opt/bits/src/compilers/
COPY entrypoint/bits-cc-select.sh /opt/bits/bin/bits-cc-select
COPY entrypoint/bits-cc-entry.sh  /opt/bits/bin/bits-cc-entry
COPY fingerprint.conf /opt/bits/src/fingerprint.conf

# 1) Package-manager bootstrap + base build tools + dev-lib headers.
#    almalinux:*-minimal ships microdnf only; add dnf once (the single concession
#    to "minimal") so CRB/EPEL and gcc-toolset are provisionable, then clean.
RUN set -eux; \
    if command -v microdnf >/dev/null 2>&1 && ! command -v dnf >/dev/null 2>&1; then \
        microdnf -y install dnf && microdnf clean all; \
    fi; \
    if command -v dnf >/dev/null 2>&1; then \
        dnf -y install dnf-plugins-core epel-release || true; \
        { dnf config-manager --set-enabled crb \
          || dnf config-manager --set-enabled powertools \
          || dnf config-manager --set-enabled PowerTools; } || true; \
        pkgs="$(grep -vhE '^[[:space:]]*#|^[[:space:]]*$' \
                 /opt/bits/src/packages/build-tools.el.txt \
                 /opt/bits/src/packages/dev-libs.el.txt | sed 's/#.*//')"; \
        dnf -y install $pkgs; { dnf -y install which || true; }; dnf clean all; \
    elif command -v apt-get >/dev/null 2>&1; then \
        export DEBIAN_FRONTEND=noninteractive; \
        printf 'Acquire::ForceIPv4 "true";\nAcquire::Retries "3";\nAcquire::http::Timeout "30";\n' \
          > /etc/apt/apt.conf.d/99bits-net; \
        if [ -n "${APT_MIRROR}" ]; then \
          for f in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources; do \
            [ -f "$f" ] && sed -i -E \
              "s#https?://([a-z.]*\.)?archive\.ubuntu\.com/ubuntu#${APT_MIRROR}#g; s#https?://security\.ubuntu\.com/ubuntu#${APT_MIRROR}#g" \
              "$f"; \
          done; \
        fi; \
        apt-get update; \
        pkgs="$(grep -vhE '^[[:space:]]*#|^[[:space:]]*$' \
                 /opt/bits/src/packages/build-tools.deb.txt \
                 /opt/bits/src/packages/dev-libs.deb.txt | sed 's/#.*//')"; \
        apt-get install -y --no-install-recommends $pkgs; \
        { apt-get install -y --no-install-recommends which || true; }; \
        { apt-get install -y --no-install-recommends linux-perf \
          || apt-get install -y --no-install-recommends linux-tools-generic || true; }; \
        rm -rf /var/lib/apt/lists/*; \
    else echo "bits-containers: no supported package manager in base" >&2; exit 1; fi

# 2) The compiler matrix. COMPILER_SOURCE picks how: distro packages, a
#    from-source build, or auto (distro where packaged, source for the rest).
RUN set -eux; C=/opt/bits/src/compilers; \
    case "${COMPILER_SOURCE}" in \
      distro) GCC_VERSIONS="${GCC_VERSIONS}" CLANG_VERSIONS="${CLANG_VERSIONS}" "$C/install-compilers.sh" ;; \
      source) GCC_VERSIONS="${GCC_VERSIONS}" CLANG_VERSIONS="${CLANG_VERSIONS}" "$C/build-compilers-from-source.sh" ;; \
      auto)   GCC_VERSIONS="${GCC_VERSIONS}" CLANG_VERSIONS="${CLANG_VERSIONS}" "$C/install-compilers.sh" --best-effort; \
              "$C/build-compilers-from-source.sh" --missing ;; \
      *) echo "bits-containers: bad COMPILER_SOURCE=${COMPILER_SOURCE} (distro|source|auto)" >&2; exit 2 ;; \
    esac

# 3) Bake the default selection (first listed wins) and materialize the shim.
RUN set -eux; mkdir -p /opt/bits/cc; \
    dg="${DEFAULT_GCC}"; [ -n "$dg" ] || { set -- ${GCC_VERSIONS}; dg="$1"; }; \
    echo "$dg" > /opt/bits/cc/default-gcc; \
    dc="${DEFAULT_CLANG}"; [ -n "$dc" ] || { set -- ${CLANG_VERSIONS}; dc="${1:-}"; }; \
    echo "$dc" > /opt/bits/cc/default-clang; \
    /opt/bits/bin/bits-cc-select; \
    libdir="$(cat /opt/bits/cc/gcc-libdir 2>/dev/null || true)"; \
    if [ -n "$libdir" ]; then echo "$libdir" > /etc/ld.so.conf.d/bits-gcc-toolset.conf; ldconfig || true; fi

# 3b) Fingerprint the output-affecting content (linked -devel libs + toolchain +
#     exact compiler versions) for provenance and dependency_tracking: strict.
RUN /opt/bits/src/compilers/container-fingerprint.sh

# The shim dir is first on PATH, so plain gcc/g++/gfortran/cc/c++ are the default
# compiler even when the entrypoint is bypassed; $GCC_VERSION re-points at runtime.
ENV PATH=/opt/bits/cc/bin:${PATH}

# 4) Sanity — fail the image build if the contract isn't met.
RUN set -eux; \
    command -v gcc >/dev/null && gcc --version | head -1; \
    command -v c++ >/dev/null || { echo "no c++ sibling" >&2; exit 1; }; \
    command -v gfortran >/dev/null && gfortran --version | head -1; \
    for t in make bison flex autoconf automake libtool patch tar gzip unzip m4 swig strace; do \
      command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 1; }; \
    done; \
    test -f /usr/include/uuid/uuid.h

ENTRYPOINT ["/opt/bits/bin/bits-cc-entry"]
CMD ["/bin/bash"]
