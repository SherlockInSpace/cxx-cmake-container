#!/bin/sh
# Checks the yocto stage: versions.txt names the SDK in expected-versions.env,
# and in the SDK environment a probe that finds util, spdlog and GoogleTest in
# the target sysroot cross-compiles to aarch64. Nothing it builds is run.
# Writes only to a temp dir.
set -eu

. "$(dirname "$0")/expected-versions.env"

fail() {
    echo "FAIL $1"
    echo "FAIL $1" >&2
    exit 1
}

versions_txt=/etc/cxx-cmake-container/versions.txt
meta="$(sed -n 's/^meta-cxx-cmake: //p' "$versions_txt")"
sdk="$(sed -n 's/^yocto-sdk: \([^ ]*\) .*/\1/p' "$versions_txt")"
[ "$meta" = "$META_CXX_CMAKE" ] \
    || fail "META_CXX_CMAKE: versions.txt has '$meta', expected $META_CXX_CMAKE"
echo "ok   META_CXX_CMAKE: versions.txt $meta"
[ "$sdk" = "$YOCTO_SDK" ] \
    || fail "YOCTO_SDK: versions.txt has '$sdk', expected $YOCTO_SDK"
echo "ok   YOCTO_SDK: versions.txt $sdk"

# The environment script reads variables that may be unset.
set +u
. "$YOCTO_SDK_ENV"
set -u
[ -d "${OECORE_TARGET_SYSROOT:-}" ] \
    || fail "SDK: $YOCTO_SDK_ENV did not set OECORE_TARGET_SYSROOT"
echo "ok   SDK: target sysroot $OECORE_TARGET_SYSROOT"

# $CXX is the cross compiler plus its flags, so it is left unquoted.
gcc_version="$($CXX -dumpfullversion)"
case "$gcc_version" in
    "$YOCTO_GCC" | "$YOCTO_GCC".*) echo "ok   YOCTO_GCC: $gcc_version" ;;
    *) fail "YOCTO_GCC: the SDK's g++ reports '$gcc_version', expected $YOCTO_GCC" ;;
esac
case "$(command -v cmake)" in
    "$OECORE_NATIVE_SYSROOT"/*) ;;
    *) fail "CMAKE: cmake is $(command -v cmake), not the SDK's" ;;
esac
cmake_version="$(cmake --version | head -n1 | sed 's/.* //')"
[ "$cmake_version" = "$CMAKE" ] \
    || fail "CMAKE: the SDK's cmake reports '$cmake_version', expected $CMAKE"
echo "ok   CMAKE: the SDK's cmake $cmake_version"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 4.3)
project(p CXX)
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
find_package(GTest CONFIG REQUIRED)
find_package(spdlog CONFIG REQUIRED)
find_package(util CONFIG REQUIRED)
add_executable(probe probe.cpp)
target_link_libraries(probe PRIVATE GTest::gtest_main spdlog::spdlog util::util)
CMAKE

cat > "$tmp/probe.cpp" <<'CPP'
#include <gtest/gtest.h>
#include <spdlog/spdlog.h>
#include <util/bloom.hpp>

TEST(Probe, Bloom) {
    util::Bloom filter;
    filter.insert("probe");
    spdlog::info("probe inserted");
    EXPECT_TRUE(filter.contains("probe"));
}
CPP

# Show the log only when a step fails, so a passing run is one line per step.
step() { # row description command...
    row="$1"; what="$2"; shift 2
    if "$@" > "$tmp/log" 2>&1; then
        echo "ok   $row: $what"
    else
        cat "$tmp/log" >&2
        fail "$row: $what"
    fi
}

# No -DCMAKE_TOOLCHAIN_FILE: the SDK environment sets CMAKE_TOOLCHAIN_FILE.
step PROBE "configure in the SDK environment" cmake -S "$tmp" -B "$tmp/build" -G Ninja
util_dir="$(sed -n 's/^util_DIR:PATH=//p' "$tmp/build/CMakeCache.txt")"
case "$util_dir" in
    "$OECORE_TARGET_SYSROOT"/*) echo "ok   PROBE: util from $util_dir" ;;
    *) fail "PROBE: util came from '$util_dir', not the target sysroot" ;;
esac
step PROBE "cross-compile" cmake --build "$tmp/build"
readelf -h "$tmp/build/probe" | grep -q 'Machine:.*AArch64' \
    || fail "PROBE: the binary is not aarch64"
echo "ok   PROBE: the binary is aarch64"

echo "yocto smoke test passed"
