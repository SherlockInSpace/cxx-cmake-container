# cxx-cmake-container

Versioned build-environment images for the cxx-cmake template family. Images
will be published to GHCR under semver tags (never `latest`), in two stages —
`ci` and `dev` — for amd64 and arm64.

**Status:** under construction; scope and progress are tracked in the issues.

Sibling repos:

- [cxx-cmake](https://github.com/SherlockInSpace/cxx-cmake)
- [cxx-cmake-app](https://github.com/SherlockInSpace/cxx-cmake-app)
- [meta-cxx-cmake](https://github.com/SherlockInSpace/meta-cxx-cmake)

## Smoke test

`test/smoke.sh` checks a built image against `test/expected-versions.env`. Each
tool has to report the version listed there and
`/etc/cxx-cmake-container/versions.txt` has to name the same base digest and
snapshot ID. Then a small C++23 project that finds OpenSSL and GoogleTest is
configured with Ninja, built with g++ and clang++ and run. It works in both
stages:

```sh
docker run --rm -v "$PWD/test:/test:ro" cxx-cmake-container:ci-local /test/smoke.sh
docker run --rm -v "$PWD/test:/test:ro" -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) \
  cxx-cmake-container:dev-local /test/smoke.sh
```

Bumping any version in the Dockerfile means editing `expected-versions.env`
in the same change.
