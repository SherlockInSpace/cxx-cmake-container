# cxx-cmake-container — versioned build environments for the cxx-cmake family.
#
# Multi-stage layout (stages land one issue at a time):
#   ci   — root, GCC 15 + Clang 22, CMake 4.3.1, the baseline dependencies
#          and quality tools, apt fixed at an Ubuntu snapshot. GitHub Actions
#          job containers run this one, so it has no user account, no sudo
#          and no interactive comforts.
#   dev  — ci plus a dev user, sudo and zsh; the stage people run.
#
# Build:   docker build --target dev -t cxx-cmake-container:dev-local .
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
# Step 3: CMake 4.3.1 from Kitware's release tarball.
#
# No Ubuntu archive ships CMake >= 4.3 (resolute has 4.2.3); Wrynose 6.0.2
# uses 4.3.1. Hashes are from cmake-4.3.1-SHA-256.txt on the release page;
# bump CMAKE_VERSION and both together. doc/ and man/ are skipped (~60 MB).
# ---------------------------------------------------------------------------
ARG CMAKE_VERSION=4.3.1

RUN <<'EOF'
set -eu
case "$(uname -m)" in
    x86_64)
        arch=x86_64
        sha256=208d76804009cbe8ec9aea0aa052c857c6e59bd289b43b9941c99324dc78b1d8
        ;;
    aarch64)
        arch=aarch64
        sha256=2c0eca48ac7d0e3a8b4120b801d48903b0630c8ff1e73c44a90398a300dec1ac
        ;;
    *)
        echo "unsupported architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

tarball="cmake-${CMAKE_VERSION}-linux-${arch}.tar.gz"
url="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/${tarball}"

curl -fsSL -o "/tmp/${tarball}" "${url}"
echo "${sha256}  /tmp/${tarball}" | sha256sum -c -
tar --strip-components=1 -C /usr/local -xzf "/tmp/${tarball}" \
    --exclude="cmake-${CMAKE_VERSION}-linux-${arch}/doc" \
    --exclude="cmake-${CMAKE_VERSION}-linux-${arch}/man"
rm -f "/tmp/${tarball}"

test "$(cmake --version | head -n1)" = "cmake version ${CMAKE_VERSION}"
EOF

# ---------------------------------------------------------------------------
# Step 4: baseline dependencies and quality tooling.
#
# Versioned LLVM packages only: unversioned clang/clang-tidy/clang-format on
# resolute still resolve to LLVM 21. The check below allows the three LLVM 21
# libraries doxygen depends on and fails on anything else built from
# llvm-toolchain-21. The clang symlinks go in /usr/local/bin: one LLVM is
# installed, so there is nothing for update-alternatives to choose between.
# ---------------------------------------------------------------------------
RUN <<'EOF'
set -eu
apt-get update
apt-get install -y --no-install-recommends \
    ninja-build \
    libssl-dev \
    libgtest-dev \
    libgmock-dev \
    clang-22 \
    clang-tidy-22 \
    clang-format-22 \
    libclang-rt-22-dev \
    doxygen \
    graphviz \
    gcovr
rm -rf /var/lib/apt/lists/*

# We only want LLVM 22 in this image. We can't exclude LLVM 21 outright
# because Ubuntu's doxygen depends on three LLVM 21 libraries (libclang-cpp21,
# libclang1-21, libllvm21) to parse C++. So we allow those three and nothing
# else from LLVM 21.
#
# dpkg-query lists every installed package with the source package it was
# built from. All LLVM 21 packages come from the source package
# llvm-toolchain-21, whatever the binary is called, so we match on that
# instead of keeping a list of names. comm -23 drops the three we allow and
# leaves the rest. comm wants both inputs sorted the same way, which is what
# the temp file and LC_ALL=C are for. If anything is left, we fail the build
# and print it.
#
# The libraries are harmless. A clang-21 binary in /usr/bin would not be, so
# we check for that separately.
llvm21_allowed="$(mktemp)"
printf '%s\n' libclang-cpp21 libclang1-21 libllvm21 | LC_ALL=C sort > "${llvm21_allowed}"
llvm21_extra="$(dpkg-query -W -f '${source:Package} ${Package}\n' \
    | awk '$1 == "llvm-toolchain-21" { print $2 }' | LC_ALL=C sort \
    | LC_ALL=C comm -23 - "${llvm21_allowed}")"
rm -f "${llvm21_allowed}"
if [ -n "${llvm21_extra}" ]; then
    echo "unexpected LLVM 21 packages present; only LLVM 22 is allowed:" >&2
    echo "${llvm21_extra}" >&2
    exit 1
fi
if ls /usr/bin | grep -E -- '-21$'; then
    echo "LLVM 21 executables present in /usr/bin; only LLVM 22 is allowed" >&2
    exit 1
fi

for tool in clang clang++ clang-tidy clang-format; do
    ln -s "/usr/bin/${tool}-22" "/usr/local/bin/${tool}"
done
EOF

# ---------------------------------------------------------------------------
# Step 5: doxygen-awesome-css v2.4.2.
#
# The library's docs build takes the Doxygen theme from the image. We fetch
# by commit (a tag can move) and check each file's SHA256; bumping the tag
# means recomputing every hash below.
# ---------------------------------------------------------------------------
ARG DOXYGEN_AWESOME_CSS_TAG=v2.4.2
ARG DOXYGEN_AWESOME_CSS_COMMIT=d52eafe3e9303399fda15661f3d7bb8fe3d7eabc

RUN <<'EOF'
set -eu
dest=/usr/share/doxygen-awesome-css
base="https://raw.githubusercontent.com/jothepro/doxygen-awesome-css/${DOXYGEN_AWESOME_CSS_COMMIT}"
mkdir -p "${dest}"

while read -r sha256 name; do
    curl -fsSL -o "${dest}/${name}" "${base}/${name}"
    echo "${sha256}  ${dest}/${name}" | sha256sum -c -
done <<'FILES'
5ec49e2dfd097f6b5384e3aae0476eab47748e311fc70e207925f8fcc37477b9 doxygen-awesome.css
dc7ddd235375b71ecb0af920faa6b925ee9445ac617f3bc962b0b0db97da7b4f doxygen-awesome-sidebar-only.css
c1939ca910d2282068482abc72e9edcf9835e4de153ebe8b428cbace92ed4c2c doxygen-awesome-sidebar-only-darkmode-toggle.css
de752867789ed21154983c22ef34441137b4cc558d5a2f92013f5b894483e5a4 doxygen-awesome-darkmode-toggle.js
009b4c9982c18bc68c6366321298316e9054a620e37b99de1276ff6a1e2c65a0 doxygen-awesome-fragment-copy-button.js
f9fe333b516cdc259a25475b0ca472e8e091fd7abf9020e54949c4677a7a427f doxygen-awesome-paragraph-link.js
a7d6a4d59809b650afd011af6fc8805075aeb5e310940fb9583a42652fe87ba8 doxygen-awesome-interactive-toc.js
805b4dd5371a0c602ae112deb698e84a5bed7af3d78ba76cde8022229a893542 doxygen-awesome-tabs.js
e3da754c3f657cc78594fa2e8a3283665f78c743df2485fa9e498a8973051191 LICENSE
FILES

chmod 0644 "${dest}"/*
EOF

# ---------------------------------------------------------------------------
# Step 6: no stock user.
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
# Step 7: build manifest.
#
# /etc/cxx-cmake-container/versions.txt: the image's inputs plus the
# installed-package list, so a published image can be traced back.
# ---------------------------------------------------------------------------
RUN <<'EOF'
set -eu
mkdir -p /etc/cxx-cmake-container
{
    echo "base-image: ubuntu:26.04@${UBUNTU_DIGEST}"
    echo "ubuntu-snapshot: ${UBUNTU_SNAPSHOT:-<live archive>}"
    echo "target-arch: ${TARGETARCH}"
    echo "gcc: $(gcc -dumpfullversion)"
    echo "clang: $(clang-22 -dumpversion)"
    echo "cmake: ${CMAKE_VERSION}"
    echo "ninja: $(ninja --version)"
    echo "doxygen-awesome-css: ${DOXYGEN_AWESOME_CSS_TAG}" \
        "(${DOXYGEN_AWESOME_CSS_COMMIT})"
    echo
    echo "# installed packages (dpkg-query -W)"
    dpkg-query -W -f '${binary:Package}=${Version}\n' | sort
} > /etc/cxx-cmake-container/versions.txt
EOF

# dev: ci plus a user account, sudo and zsh. ci stays root because GitHub
# Actions job containers need it; dev is the only stage a person runs. UID
# and GID are the build-time ids. docker/entrypoint.sh moves dev to
# HOST_UID/HOST_GID at start when they are set, so the published image fits
# any host without a rebuild.
FROM ci AS dev

ARG DEBIAN_FRONTEND=noninteractive
ARG UID=1000
ARG GID=1000

# ubuntu.sources came from ci, so this resolves against the same snapshot.
RUN <<'EOF'
set -eu
apt-get update
apt-get install -y --no-install-recommends \
    sudo \
    zsh
rm -rf /var/lib/apt/lists/*
EOF

# ci removed the stock ubuntu account, so 1000 is free. The entrypoint runs
# as dev and needs the sudo rule to remap its own account.
RUN <<'EOF'
set -eu
groupadd --gid "${GID}" dev
useradd --uid "${UID}" --gid dev --create-home --shell /usr/bin/zsh dev
echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev
chmod 0440 /etc/sudoers.d/dev
install -d -o dev -g dev /work
EOF

COPY --chown=dev:dev docker/zshrc /home/dev/.zshrc
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh

USER dev
WORKDIR /work
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["zsh"]
