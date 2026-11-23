# Changelog

## [0.1.1](https://github.com/SherlockInSpace/cxx-cmake-container/compare/v0.1.0...v0.1.1) (2026-11-23)


### Build

* **docker:** move the base image and snapshot to November 2026 ([be7d5cd](https://github.com/SherlockInSpace/cxx-cmake-container/commit/be7d5cd2421cd58c27e3708ef23ea98fec4769c2)), closes [#37](https://github.com/SherlockInSpace/cxx-cmake-container/issues/37)

## 0.1.0 (2026-11-23)


### Bug Fixes

* **docker:** bootstrap packages drift past the snapshot and break every build ([dfc9c17](https://github.com/SherlockInSpace/cxx-cmake-container/commit/dfc9c17970c1c0d345dd2d9472840d88fbc721da)), closes [#32](https://github.com/SherlockInSpace/cxx-cmake-container/issues/32)
* **docker:** create dev's ccache directory so a cache volume is writable ([f743e9d](https://github.com/SherlockInSpace/cxx-cmake-container/commit/f743e9dce07f52861950d25bf5f3c4805968d0ee)), closes [#17](https://github.com/SherlockInSpace/cxx-cmake-container/issues/17)
* **docker:** fail apt-get update on an unreachable archive so apt-retry retries it ([5d1392c](https://github.com/SherlockInSpace/cxx-cmake-container/commit/5d1392c020243d28aea2dad5460a785857ca25b1)), closes [#29](https://github.com/SherlockInSpace/cxx-cmake-container/issues/29)


### Build

* **docker:** ci stage on ubuntu:26.04 with snapshot-pinned apt and the GCC 15 toolchain ([#22](https://github.com/SherlockInSpace/cxx-cmake-container/issues/22)) ([8a1b56b](https://github.com/SherlockInSpace/cxx-cmake-container/commit/8a1b56b825f7b335908c51e5c0da6f5866149323))
* **docker:** CMake 4.3.1, baseline dependencies and quality tooling ([b657674](https://github.com/SherlockInSpace/cxx-cmake-container/commit/b65767427f57fdce42e0a0cfcc40c11e2bfe88b9)), closes [#3](https://github.com/SherlockInSpace/cxx-cmake-container/issues/3)
* **docker:** dev stage (non-root user, zsh, sudo) ([905208d](https://github.com/SherlockInSpace/cxx-cmake-container/commit/905208da4641c76fda3fea72df45b86bf9c54214)), closes [#4](https://github.com/SherlockInSpace/cxx-cmake-container/issues/4)
* **docker:** retry apt when the snapshot service is flaky ([bc73219](https://github.com/SherlockInSpace/cxx-cmake-container/commit/bc7321929378230a568fd1015f3b3b8d6a90465f)), closes [#29](https://github.com/SherlockInSpace/cxx-cmake-container/issues/29)
* **docker:** retry the CMake and doxygen-awesome-css downloads ([981a569](https://github.com/SherlockInSpace/cxx-cmake-container/commit/981a569d668ea4d0bc73e9b24914ea569717c97f)), closes [#29](https://github.com/SherlockInSpace/cxx-cmake-container/issues/29)
* **docker:** write the base digest in the FROM line ([c7c0f0f](https://github.com/SherlockInSpace/cxx-cmake-container/commit/c7c0f0f18395387400dda2f9d4b01e401bf13e63)), closes [#16](https://github.com/SherlockInSpace/cxx-cmake-container/issues/16)
