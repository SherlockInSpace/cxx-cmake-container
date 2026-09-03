# cxx-cmake-container — versioned build environments for the cxx-cmake family.
#
# Multi-stage layout (stages land one issue at a time):
#   ci   — root, GCC 15 + Clang 22 toolchains, CMake 4.3.1, the baseline
#          dependencies and quality tooling, apt pinned to an Ubuntu snapshot.
#          This is the image GitHub Actions job containers run, so it
#          deliberately has no user account, no sudo and no interactive
#          comforts.
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
# Step 3: CMake 4.3.1 from the official Kitware release tarball.
#
# No Ubuntu archive ships CMake >= 4.3 (resolute has 4.2.3), and the library
# template requires 4.3; 4.3.1 is the pin Wrynose 6.0.2 carries, so the image
# matches the Yocto build exactly. The tarball is picked by `uname -m` and
# checked against a SHA256 hard-coded per architecture — the values are those
# published in cmake-4.3.1-SHA-256.txt alongside the release. Bumping the
# version means updating both hashes; a mismatch fails the build, never falls
# through. `--strip-components=1` drops the cmake-4.3.1-linux-<arch>/ prefix
# so bin/ and share/ land directly under /usr/local; the tarball's doc/ (HTML
# manual, ~60 MB) and man/ are excluded — a CI image never renders them, and
# cmake needs only bin/ and share/cmake-4.3/ at runtime.
#
# CMAKE_VERSION is the single source of truth for this step and versions.txt.
# It is not a build-time knob: the hashes below are keyed to it.
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
# Step 4: baseline dependencies and quality tooling (apt, snapshot-pinned).
#
# ninja-build   the generator CI and CPM builds use (1.13.2, Wrynose's pin).
# libssl-dev    OpenSSL, the library template's one baseline dependency.
# libgtest-dev  GoogleTest/GoogleMock; on resolute these ship the CMake
# libgmock-dev  package config, so `find_package(GTest CONFIG)` works.
# clang-22 …    second compiler and the clang-tidy/clang-format the house
#               style is enforced with; libclang-rt-22-dev brings the
#               sanitizer runtimes. Versioned packages ONLY: the unversioned
#               `clang`, `clang-tidy` and `clang-format` metapackages on
#               resolute still resolve to LLVM 21 and would pull a second
#               toolchain in beside this one.
# doxygen       API docs, with graphviz for the diagrams.
# gcovr         coverage reports from the gcc/gcov data.
#
# The assertion below fails the build if any LLVM 21 package other than an
# explicit allow-list, or any /usr/bin/*-21 executable, sneaks in through a
# dependency. The allow-list is exactly the three shared libraries resolute's
# doxygen has a hard Depends on for its clang-assisted parsing (libclang1-21,
# libclang-cpp21, libllvm21): private runtime libraries under
# /usr/lib/llvm-21 with no executables, not a toolchain anything can build
# with. Membership is keyed on dpkg's source package rather than a name
# pattern: every LLVM 21 binary package (libc++-21-dev, libomp-21-dev,
# python3-clang-21, lldb-21, ...) is built from llvm-toolchain-21, so any
# of them outside the allow-list fails the build and a future dependency
# cannot widen the LLVM 21 footprint unnoticed.
#
# Unversioned clang/clang++/clang-tidy/clang-format names are plain symlinks
# under /usr/local/bin. update-alternatives exists to arbitrate between
# several installed versions; here exactly one LLVM is installed by design,
# so alternatives would add a priority scheme for a choice that never has to
# be made. /usr/local/bin also keeps the links out of dpkg's tree, so they
# can never collide with a packaged /usr/bin/clang.
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
# Step 5: doxygen-awesome-css, pinned to the commit of a release tag.
#
# The library template's docs build resolves the Doxygen theme from the image
# (local-only dependency policy: builds resolve from the baseline and never
# download), so the theme has to be here. The individual files are fetched
# from raw.githubusercontent.com at the pinned commit — a tag can be moved,
# a commit hash cannot — and each is checked against a SHA256 computed from
# that commit and hard-coded here. All of upstream's stylesheet and script
# assets are installed, plus its LICENSE (MIT), so a Doxyfile can pick any
# combination without another image bump.
#
# The TAG/COMMIT pair is the single source of truth for this step and
# versions.txt; bumping it means recomputing every hash below.
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
# /etc/cxx-cmake-container/versions.txt records what this image was built
# from — base digest, snapshot ID, architecture, the toolchain versions and
# the non-apt inputs (CMake tarball, doxygen-awesome-css commit) — followed by
# the complete installed-package manifest, so a published image can always be
# traced back to its exact inputs.
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
