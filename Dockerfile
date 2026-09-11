# SPDX-FileCopyrightText: 2026 CERN
# SPDX-License-Identifier: GPL-3.0-or-later
#
# bits-containers — one parameterized Dockerfile that turns a MINIMAL OFFICIAL
# distro base into a bits build environment: base OS + build tools + dev-lib
# headers + a BASE bootstrap compiler. The stack's real compiler (GCC-Toolchain)
# is built by bits, not the image, so one minimal image per (OS, arch) serves
# every compiler axis. Content is defined by:
#   packages/{build-tools,dev-libs}.{el,deb}.txt   (system libs + tools + base gcc)
# See spec/CONTENT.md for the contract every image satisfies.
#
# Build args (the Makefile passes them from the platforms.yaml row):
#   BASE_IMAGE, APT_MIRROR
ARG BASE_IMAGE=almalinux:9-minimal
FROM ${BASE_IMAGE}

# Optional fast APT mirror (e.g. a site-local Ubuntu mirror). Empty = distro
# default. On slow/distant default mirrors this is the biggest lever.
ARG APT_MIRROR=""

USER root
SHELL ["/bin/bash", "-c"]

COPY packages/ /opt/bits/src/packages/
COPY compilers/ /opt/bits/src/compilers/
COPY fingerprint.conf /opt/bits/src/fingerprint.conf

# 1) Package-manager bootstrap + base build tools + dev-lib headers.
#    almalinux:*-minimal ships microdnf only; add dnf once (the single concession
#    to "minimal") so CRB/EPEL are provisionable, then clean.
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

# 2) Fingerprint the output-affecting content (linked -devel libs + toolchain +
#    the base compiler version) for provenance and dependency_tracking: strict.
RUN /opt/bits/src/compilers/container-fingerprint.sh

# 3) Sanity — fail the image build if the contract isn't met.
RUN set -eux; \
    command -v gcc >/dev/null && gcc --version | head -1; \
    command -v c++ >/dev/null || { echo "no c++ sibling" >&2; exit 1; }; \
    command -v gfortran >/dev/null && gfortran --version | head -1; \
    for t in make bison flex autoconf automake libtool patch tar gzip unzip m4 swig strace; do \
      command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 1; }; \
    done; \
    test -f /usr/include/uuid/uuid.h

CMD ["/bin/bash"]
