#!/bin/sh
# Checks a built image against test/expected-versions.env. Each tool has to
# report the version listed there and versions.txt has to name the same base
# digest and snapshot. Then a C++23 probe that finds OpenSSL and GoogleTest
# is built with g++ and clang++ and run. Runs in both stages and writes only
# to a temp dir.
set -eu

. "$(dirname "$0")/expected-versions.env"

fail() {
    echo "FAIL $1"
    echo "FAIL $1" >&2
    exit 1
}

# The expected value has to equal the reported one or be a prefix of it up to
# a dot. GCC=15.2 accepts 15.2.0, CMAKE=4.3.1 accepts only 4.3.1.
version() { # row expected tool reported
    case "$4" in
        "$2" | "$2".*) echo "ok   $1: $3 $4" ;;
        *) fail "$1: $3 reports '$4', expected $2" ;;
    esac
}

# The version is the last word of the first line for every tool here.
last_word() {
    "$@" 2>/dev/null | head -n1 | sed 's/.* //'
}

version GCC "$GCC" gcc "$(last_word gcc -dumpfullversion)"
version GCC "$GCC" g++ "$(last_word g++ -dumpfullversion)"
version BINUTILS "$BINUTILS" ld "$(last_word ld --version)"
version GLIBC "$GLIBC" ldd "$(last_word ldd --version)"
version CMAKE "$CMAKE" cmake "$(last_word cmake --version)"
version NINJA "$NINJA" ninja "$(last_word ninja --version)"
version CLANG "$CLANG" clang "$(last_word clang -dumpversion)"
version CLANG "$CLANG" clang++ "$(last_word clang++ -dumpversion)"
version GTEST "$GTEST" gtest "$(last_word pkg-config --modversion gtest)"
version GCOVR "$GCOVR" gcovr "$(last_word gcovr --version)"
version DOXYGEN "$DOXYGEN" doxygen "$(last_word doxygen --version)"

versions_txt=/etc/cxx-cmake-container/versions.txt
digest="$(sed -n 's/^base-image: .*@//p' "$versions_txt")"
snapshot="$(sed -n 's/^ubuntu-snapshot: //p' "$versions_txt")"
[ "$digest" = "$UBUNTU_DIGEST" ] \
    || fail "UBUNTU_DIGEST: versions.txt has '$digest', expected $UBUNTU_DIGEST"
echo "ok   UBUNTU_DIGEST: versions.txt $digest"
[ "$snapshot" = "$UBUNTU_SNAPSHOT" ] \
    || fail "UBUNTU_SNAPSHOT: versions.txt has '$snapshot', expected $UBUNTU_SNAPSHOT"
echo "ok   UBUNTU_SNAPSHOT: versions.txt $snapshot"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 4.3)
project(p CXX)
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
find_package(OpenSSL REQUIRED)
find_package(GTest CONFIG REQUIRED)
add_executable(probe probe.cpp)
target_link_libraries(probe PRIVATE OpenSSL::Crypto GTest::gtest_main)
CMAKE

cat > "$tmp/probe.cpp" <<'CPP'
#include <expected>
#include <print>
#include <string>

#include <gtest/gtest.h>
#include <openssl/crypto.h>

std::expected<int, std::string> half(int n) {
    if (n % 2 != 0) {
        return std::unexpected("odd");
    }
    return n / 2;
}

TEST(Probe, ExpectedAndPrint) {
    EXPECT_EQ(half(4).value(), 2);
    EXPECT_EQ(half(3).error(), "odd");
    std::println("{}", OpenSSL_version(OPENSSL_VERSION));
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

for cxx in g++ clang++; do
    build="$tmp/build-$cxx"
    step PROBE "configure with $cxx" \
        cmake -S "$tmp" -B "$build" -G Ninja -DCMAKE_CXX_COMPILER="$cxx"
    step PROBE "build with $cxx" cmake --build "$build"
    step PROBE "run the $cxx binary" "$build/probe"
done

echo "smoke test passed"
