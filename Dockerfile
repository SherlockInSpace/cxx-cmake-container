# Build environments for the cxx-cmake family. ci has the toolchain and runs
# as root for GitHub Actions job containers. dev adds a dev user, sudo and
# zsh and is the stage people run. apt uses an Ubuntu snapshot
# (UBUNTU_SNAPSHOT); set it empty to use the live archive.
#
# Build: docker build --target dev -t cxx-cmake-container:dev-local .

# ubuntu:26.04 (resolute) by its multi-arch index digest (linux/amd64 and
# linux/arm64/v8), so both arches get the same manifest list. The digest is
# resolute-20260811.1 from `docker buildx imagetools inspect ubuntu:26.04` on
# 2026-09-03. Bump the tag and the digest together.
ARG UBUNTU_DIGEST=sha256:2260313b31c8c011cd2eebe728008efac1b3982be73eb71348ea2648d2c0e09b
FROM ubuntu:26.04@${UBUNTU_DIGEST} AS ci

# One ARG for the FROM line and versions.txt. Global ARGs are not visible to
# RUN, so the stage declares it again.
ARG UBUNTU_DIGEST

# Apt snapshot (https://snapshot.ubuntu.com). The same ID gives the same
# package set months later. Empty uses the live archive: a fallback for when
# the snapshot service is down, never for CI.
ARG UBUNTU_SNAPSHOT=20260901T000000Z

# Set by BuildKit (amd64 / arm64); recorded in versions.txt.
ARG TARGETARCH

# ARG, not ENV, so the setting stays out of the published image.
ARG DEBIAN_FRONTEND=noninteractive

# The snapshot is HTTPS and the base image has no CA bundle, so ca-certificates
# comes from the live archive first. Then point apt at the snapshot.
# snapshot.ubuntu.com drops out for minutes at a time (503s, once a 404), and a
# cold build spends about 25 minutes downloading from it, so one hiccup used to
# fail the whole image. apt retries each file with backoff, and apt-retry
# repeats a failed update or install a few times before giving up.
RUN <<'EOF'
set -eu
cat > /etc/apt/apt.conf.d/80-retries <<'CONF'
Acquire::Retries "10";
Acquire::http::Timeout "60";
CONF
cat > /usr/local/sbin/apt-retry <<'SH'
#!/bin/sh
# apt-retry update | apt-retry install <packages...>
# Runs apt-get up to 6 times, waiting 30, 60, 90... seconds between tries.
set -u
: "${1:?usage: apt-retry update | apt-retry install <packages...>}"
n=1
while :; do
    if apt-get "$@"; then exit 0; fi
    if [ "$n" -ge 6 ]; then
        echo "apt-get $1 failed 6 times; if the errors above are download failures, snapshot.ubuntu.com is down (see README)" >&2
        exit 1
    fi
    sleep $((n * 30)); n=$((n + 1))
done
SH
chmod 0755 /usr/local/sbin/apt-retry
apt-retry update
apt-retry install -y --no-install-recommends ca-certificates

snapshot_field=""
if [ -n "${UBUNTU_SNAPSHOT}" ]; then
    snapshot_field="Snapshot: ${UBUNTU_SNAPSHOT}"
fi

# The stock file differs per arch: amd64 archive.ubuntu.com, arm64
# ports.ubuntu.com/ubuntu-ports. The snapshot service has no ports tree and on
# 26.04 arm64 is a first-class archive arch, so both use archive.ubuntu.com.
# Same layout as stock; both stanzas get the same Snapshot: field.
cat > /etc/apt/sources.list.d/ubuntu.sources <<SOURCES
# Managed by the cxx-cmake-container Dockerfile.
# archive.ubuntu.com on every architecture. When Snapshot: is present, package
# resolution and .deb downloads come from snapshot.ubuntu.com/ubuntu/<ID>;
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

# Snapshot: (apt 3.2) sends the package cache, apt-cache policy and every .deb
# download to https://snapshot.ubuntu.com/ubuntu/<ID>/. apt-get update still
# fetches the index from the live URIs:, so the live archive has to be
# reachable then. Putting the snapshot in URIs: would remove that, and with
# it the one-line --build-arg UBUNTU_SNAPSHOT= fallback.
#
# Drop the live lists fetched for ca-certificates; from here on everything
# resolves against the snapshot.
rm -rf /var/lib/apt/lists/*
EOF

# The toolchain and what a CMake/CPM build and its CI steps need (git/curl
# for CPM, ccache for the CI cache, python3 for helper scripts). gcc/g++ are
# the release metapackages, gcc-15 (15.2.x) on resolute, and already ship the
# unversioned gcc/g++/cc/c++/gcov links, so no update-alternatives.
RUN <<'EOF'
set -eu
apt-retry update
apt-retry install -y --no-install-recommends \
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

# CMake 4.3.1 from Kitware's tarball: no Ubuntu archive has CMake >= 4.3
# (resolute has 4.2.3) and Wrynose 6.0.2 uses 4.3.1. Hashes are from
# cmake-4.3.1-SHA-256.txt on the release page; bump CMAKE_VERSION and both
# together. doc/ and man/ are skipped (~60 MB).
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

# Baseline dependencies and quality tools. Versioned LLVM packages only:
# unversioned clang/clang-tidy/clang-format on resolute are still LLVM 21.
# The clang symlinks go in /usr/local/bin; with one LLVM installed there is
# nothing for update-alternatives to choose between.
RUN <<'EOF'
set -eu
apt-retry update
apt-retry install -y --no-install-recommends \
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

# doxygen-awesome-css v2.4.2, the Doxygen theme the library's docs build
# takes from the image. Fetched by commit (a tag can move) and each file is
# checked by SHA256; bumping the tag means recomputing every hash below.
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

# The base image ships an `ubuntu` user and group at UID/GID 1000. dev puts
# the host user on 1000, where a leftover account would collide. Remove it so
# no UID >= 1000 exists in ci.
RUN <<'EOF'
set -eu
userdel -r ubuntu
if getent group ubuntu >/dev/null; then
    groupdel ubuntu
fi
EOF

# /etc/cxx-cmake-container/versions.txt: the image's inputs and the installed
# packages, so a published image can be traced back.
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
apt-retry update
apt-retry install -y --no-install-recommends \
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
