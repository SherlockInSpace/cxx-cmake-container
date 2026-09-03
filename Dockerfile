# cxx-cmake-container — versioned build environments for the cxx-cmake family.
#
# Multi-stage layout (stages land one issue at a time):
#   ci   — root, GCC 15 toolchain, apt pinned to an Ubuntu snapshot. This is the
#          image GitHub Actions job containers run, so it deliberately has no
#          user account, no sudo and no interactive comforts.
#   dev  — (later) builds on ci with a UID-mapped user and editor tooling.
#
# Build:   docker build --target ci -t cxx-cmake-container:ci-local .
# Pin:     docker build --build-arg UBUNTU_SNAPSHOT=<ID> ...   (CI always pins)
# Live:    docker build --build-arg UBUNTU_SNAPSHOT= ...       (fallback only)

# ---------------------------------------------------------------------------
# Base image: ubuntu:26.04 (resolute), pinned by the multi-arch *index* digest
# so amd64 and arm64 builds resolve to the same published manifest list.
# Digest = resolute-20260811.1, taken from
# `docker buildx imagetools inspect ubuntu:26.04` on 2026-09-03; the index lists
# linux/amd64 and linux/arm64/v8. Bump the tag and digest together.
#
# The digest lives in one global ARG so the FROM line and the versions.txt
# manifest can never disagree; it is re-declared inside the stage below
# because global ARGs are not visible to RUN steps.
# ---------------------------------------------------------------------------
ARG UBUNTU_DIGEST=sha256:2260313b31c8c011cd2eebe728008efac1b3982be73eb71348ea2648d2c0e09b
FROM ubuntu:26.04@${UBUNTU_DIGEST} AS ci

# Re-declared (no default) to pull the global value into this stage for
# versions.txt.
ARG UBUNTU_DIGEST

# Apt snapshot ID (https://snapshot.ubuntu.com). Pinning package resolution
# to a fixed point in the archive's history makes rebuilds reproducible: the
# same Dockerfile and the same ID yield the same package set, months later.
# An empty value disables pinning and uses the live archive — a documented
# fallback for when the snapshot service is unavailable, never for CI.
ARG UBUNTU_SNAPSHOT=20260901T000000Z

# Populated by BuildKit (amd64 / arm64); recorded in versions.txt.
ARG TARGETARCH

# ARG rather than ENV: silence debconf during the build without leaking the
# setting into the runtime environment of the published image.
ARG DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# Step 1: trust store, then point apt at the snapshot.
#
# apt reaches snapshot.ubuntu.com over HTTPS, and the base image ships no CA
# bundle, so ca-certificates has to come from the live archive first.
#
# The stock ubuntu.sources differs per architecture: amd64 uses
# archive.ubuntu.com, arm64 uses ports.ubuntu.com/ubuntu-ports. The snapshot
# service does not serve the ports tree, and on 26.04 arm64 is a first-class
# archive architecture, so both arches are rewritten to archive.ubuntu.com.
# Both stanzas (release/-updates/-backports and -security) get the same
# `Snapshot:` field; the layout mirrors the stock file to keep it recognisable.
#
# What `Snapshot:` pins (apt 3.2): the package cache, `apt-cache policy` and
# every .deb download come from https://snapshot.ubuntu.com/ubuntu/<ID>/.
# `apt-get update` still fetches index metadata from the live URIs: as well,
# so the live archive must be reachable at update time. Pointing URIs: at the
# snapshot directly would remove that dependency, at the cost of the
# one-line `--build-arg UBUNTU_SNAPSHOT=` fallback to the live archive.
# ---------------------------------------------------------------------------
RUN <<'EOF'
set -eu
apt-get update
apt-get install -y --no-install-recommends ca-certificates

snapshot_field=""
if [ -n "${UBUNTU_SNAPSHOT}" ]; then
    snapshot_field="Snapshot: ${UBUNTU_SNAPSHOT}"
fi

cat > /etc/apt/sources.list.d/ubuntu.sources <<SOURCES
# Managed by the cxx-cmake-container Dockerfile.
# archive.ubuntu.com on every architecture. When Snapshot: is present, package
# resolution and .deb downloads are pinned to snapshot.ubuntu.com/ubuntu/<ID>;
# apt-get update still fetches index metadata from the live URIs: as well.

Types: deb
URIs: http://archive.ubuntu.com/ubuntu/
Suites: resolute resolute-updates resolute-backports
Components: main universe restricted multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
${snapshot_field}

Types: deb
URIs: http://archive.ubuntu.com/ubuntu/
Suites: resolute-security
Components: main universe restricted multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
${snapshot_field}
SOURCES

# Drop the live-archive lists fetched for ca-certificates; everything from
# here on is re-resolved against the snapshot.
rm -rf /var/lib/apt/lists/*
EOF

# ---------------------------------------------------------------------------
# Step 2: the toolchain and baseline tools.
#
# `gcc` and `g++` are the release metapackages: on resolute they resolve to
# gcc-15 (15.2.x) and already provide the unversioned gcc/g++/cc/c++/gcov
# links, so there is no update-alternatives dance to keep in sync.
# The rest is the minimum a CMake/CPM build and its CI steps need:
# binutils/make (build), git/curl (CPM fetch, checkout), pkg-config
# (find_package fallbacks), ccache (CI cache), python3 (helper scripts),
# xz-utils/file (tarballs, artefact inspection).
# ---------------------------------------------------------------------------
RUN <<'EOF'
set -eu
apt-get update
apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    binutils \
    make \
    git \
    curl \
    pkg-config \
    ccache \
    python3 \
    xz-utils \
    file \
    ca-certificates
rm -rf /var/lib/apt/lists/*
EOF

# ---------------------------------------------------------------------------
# Step 3: no stock user.
#
# The base image ships an `ubuntu` user and group at UID/GID 1000. The ci
# stage runs as root (GitHub Actions job containers expect that), and the
# later dev stage maps the host user onto UID 1000 — a leftover account there
# would collide. Remove it so no UID >= 1000 exists in ci.
# ---------------------------------------------------------------------------
RUN <<'EOF'
set -eu
userdel -r ubuntu
if getent group ubuntu >/dev/null; then
    groupdel ubuntu
fi
EOF

# ---------------------------------------------------------------------------
# Step 4: build manifest.
#
# /etc/cxx-cmake-container/versions.txt records what this image was built
# from — base digest, snapshot ID, architecture — followed by the complete
# installed-package manifest, so a published image can always be traced back
# to its exact inputs.
# ---------------------------------------------------------------------------
RUN <<'EOF'
set -eu
mkdir -p /etc/cxx-cmake-container
{
    echo "base-image: ubuntu:26.04@${UBUNTU_DIGEST}"
    echo "ubuntu-snapshot: ${UBUNTU_SNAPSHOT:-<live archive>}"
    echo "target-arch: ${TARGETARCH}"
    echo "gcc: $(gcc -dumpfullversion)"
    echo
    echo "# installed packages (dpkg-query -W)"
    dpkg-query -W -f '${binary:Package}=${Version}\n' | sort
} > /etc/cxx-cmake-container/versions.txt
EOF
