# cxx-cmake-container

Build-environment images for the cxx-cmake templates:
[cxx-cmake-library](https://github.com/SherlockInSpace/cxx-cmake-library),
[cxx-cmake-app](https://github.com/SherlockInSpace/cxx-cmake-app) and the
Yocto layer [meta-cxx-cmake](https://github.com/SherlockInSpace/meta-cxx-cmake).
One Dockerfile builds two stages for linux/amd64 and linux/arm64, and every
release publishes both to GHCR.

Built on Ubuntu 26.04 LTS packages. Not affiliated with or endorsed by
Canonical.

## Stages

| Stage | Image | Use |
|---|---|---|
| `ci` | `ghcr.io/sherlockinspace/cxx-cmake-container/ci` | CI jobs. Runs as root, because GitHub Actions job containers need it. |
| `dev` | `ghcr.io/sherlockinspace/cxx-cmake-container/dev` | Working in a shell. `ci` plus a `dev` user with sudo and zsh, starting in `/work`. |

Both have GCC, Clang, CMake, Ninja, ccache, OpenSSL, GoogleTest, Google
Benchmark, spdlog, the Tracy client library and `tracy-capture`, clang-tidy,
clang-format, Doxygen with doxygen-awesome-css, gcovr, and pytest and ruff
for the app template's Python tests.
`/etc/cxx-cmake-container/versions.txt` lists the base image digest, the
snapshot ID and every installed package.

## Using the image

Mount the directory that holds your checkouts at `/work` and keep the
compiler cache in a named volume:

```sh
docker run --rm -it \
  -v "$PWD:/work" \
  -v cxx-cmake-ccache:/home/dev/.cache/ccache \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  ghcr.io/sherlockinspace/cxx-cmake-container/dev:0.1
```

With `HOST_UID` and `HOST_GID` set, the entrypoint moves the `dev` account to
your ids before starting the shell, so files written under `/work` are yours.

For CI, or anything that has to build the same way next year, use the full
version and the digest from the release notes:

```yaml
container: ghcr.io/sherlockinspace/cxx-cmake-container/ci:0.1.0@sha256:<digest>
```

## Versions

The image follows Yocto Wrynose 6.0.2, so code that builds here builds against
the same tool versions under BitBake. The match is in version numbers only.
Ubuntu's GCC turns on PIE, `_FORTIFY_SOURCE=3`, `-fcf-protection` and
`-fstack-clash-protection` by default and Yocto's GCC does not, so a build here
says nothing about how the Yocto toolchain behaves.

| Component | Wrynose 6.0.2 | Image | Match |
|---|---|---|---|
| GCC | 15.3.0 | `gcc-15` 15.2.0-16ubuntu1 | patch release behind |
| binutils | 2.46.1 | `binutils` 2.46-3ubuntu2 | patch release behind |
| glibc | 2.43 | `libc6` 2.43-2ubuntu2.7 | same |
| CMake | 4.3.1 | Kitware release tarball 4.3.1 | same |
| Ninja | 1.13.2 | `ninja-build` 1.13.2-1 | same |
| LLVM/Clang | 22.1.2 | `clang-22` 1:22.1.2-1ubuntu1 | same |
| OpenSSL | 3.5.7 | `libssl-dev` 3.5.5-1ubuntu3.7 | patch release behind |
| GoogleTest | 1.17.0 | `libgtest-dev` 1.17.0-1build1 | same |
| Google Benchmark | 1.9.5 | `libbenchmark-dev` 1.9.1-1build1 | patch release behind |
| spdlog | 1.17.0 | upstream release 1.17.0 with its bundled fmt 12.1, built in the image | same |
| Tracy | not in Wrynose | upstream release 0.15.0, built in the image | |

Ubuntu 26.04 has CMake 4.2, so CMake comes from Kitware's tarball, checked
against its published SHA-256. `clang`, `clang-tidy` and `clang-format` point
at LLVM 22; Ubuntu's unversioned packages would install LLVM 21.

## Tags

A release is tagged `X.Y.Z` and `X.Y`, and from 1.0 on also `X`. There is no
`latest`. An image named `latest` changes compiler whenever a release happens,
without anyone who uses it deciding to move, and a template's CI should change
toolchain only in a commit that says so.

From 1.0 the version means:

- major: a new toolchain baseline, such as a new Yocto release or GCC major
- minor: a tool added, or the next Wrynose point release followed
- patch: a rebuild or fix that changes no tool version

Before 1.0 a breaking change bumps the minor and everything else the patch.

## Reproducibility

To get the same image again, pull it by digest. To build the same image again,
the Dockerfile fixes its two inputs: the base image by its index digest in the
`FROM` line, and the apt packages by a snapshot ID (`UBUNTU_SNAPSHOT`) on
snapshot.ubuntu.com. Downloads from outside apt, CMake, doxygen-awesome-css,
the Tracy and spdlog sources and the ruff wheel, are checked against SHA-256
sums in the Dockerfile. The
exception is `tracy-capture`: Tracy's own CMake fetches capstone, zstd and
PPQSort by the git tags it names, so a rebuild trusts those tags.

### The snapshot service

Every build downloads its packages from snapshot.ubuntu.com. The service is
run by Canonical and there is no mirror; falling back to the live archive
would quietly give up the fixed package set. It goes down for minutes at a
time. apt retries each download with backoff and the Dockerfile's `apt-retry`
repeats a failed step a few times, so short outages pass. A longer one fails
the build with a message naming the service; re-run the job when it's back.
`--build-arg UBUNTU_SNAPSHOT=` builds from the live archive for a local
experiment.

## Building and testing locally

```sh
docker build --target ci -t cxx-cmake-container:ci-local .
docker build --target dev -t cxx-cmake-container:dev-local .
```

`test/smoke.sh` checks a built image against `test/expected-versions.env`.
Each tool has to report the version listed there and `versions.txt` has to
name the same base digest and snapshot ID. Then a small C++23 project that
finds OpenSSL and GoogleTest is configured with Ninja, built with g++ and
clang++ and run. It works in both stages:

```sh
docker run --rm -v "$PWD/test:/test:ro" cxx-cmake-container:ci-local /test/smoke.sh
docker run --rm -v "$PWD/test:/test:ro" -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) \
  cxx-cmake-container:dev-local /test/smoke.sh
```

## Bumping versions

Every bump edits `test/expected-versions.env` in the same commit, and the
table above when a row changes.

- **Snapshot.** Set `UBUNTU_SNAPSHOT` to a newer ID (`YYYYMMDDTHHMMSSZ`). The
  package set comes from the snapshot, so this is the real package bump.
  Build, run the smoke test and copy what it reports.
- **Base digest.** Dependabot opens a pull request that changes the `FROM`
  line. It stays red until the same digest is copied into `UBUNTU_DIGEST` in
  the Dockerfile and into `expected-versions.env`. The snapshot has to be no
  older than the base image (`org.opencontainers.image.created` in its
  config): a newer base already has packages the older snapshot cannot match,
  and apt will not downgrade them.
- **CMake.** Change `CMAKE_VERSION` and both SHA-256 sums, taken from
  `cmake-<version>-SHA-256.txt` on Kitware's release page.
- **spdlog.** Change `SPDLOG_VERSION` and the SHA-256 of its tag's tarball.
- **ruff.** Change `RUFF_VERSION` and, for both architectures, the wheel URL
  and SHA-256 from <https://pypi.org/project/ruff/#files>.
- **Wrynose point release.** Compare its versions with the table, move the
  snapshot forward until Ubuntu's packages match as closely as they can,
  update the table and commit it as `feat(docker)`.

## Licence

The scripts and Dockerfile in this repository are MIT, and that is what the
images' `org.opencontainers.image.licenses` label says. The software inside
the images keeps its own licences; each package's terms are in
`/usr/share/doc/<package>/copyright`.

[CONTRIBUTING.md](CONTRIBUTING.md) covers changes and releases.
