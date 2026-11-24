# AGENTS.md

Instructions for coding agents working in this repository. People should read
[CONTRIBUTING.md](CONTRIBUTING.md); this is the short form of the same rules.

## Build and test

| Task | Command |
|---|---|
| Build `ci` | `docker build --target ci -t cxx-cmake-container:ci-local .` |
| Build `dev` | `docker build --target dev -t cxx-cmake-container:dev-local .` |
| Smoke test `ci` | `docker run --rm -v "$PWD/test:/test:ro" cxx-cmake-container:ci-local /test/smoke.sh` |
| Smoke test `dev` | `docker run --rm -v "$PWD/test:/test:ro" -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) cxx-cmake-container:dev-local /test/smoke.sh` |
| Build `yocto` | `docker build --target yocto -t cxx-cmake-container:yocto-local .` |
| Smoke test `yocto` | `docker run --rm -v "$PWD/test:/test:ro" cxx-cmake-container:yocto-local /test/smoke-yocto.sh` |

A change is done when every stage builds and its smoke test passes. CI
repeats this on amd64 and arm64; say in the pull request which architecture
you checked locally.

## Rules

- Never build CI images from the live archive or drop `UBUNTU_SNAPSHOT`. If
  snapshot.ubuntu.com fails, the fix is to re-run later.
- A download outside apt gets a version `ARG` and a SHA-256 check. Tracy's
  own tag fetches for `tracy-capture` are the only exception; add no others.
- A version change edits `test/expected-versions.env`, and the README's
  version table if a row changes, in the same commit.
- `UBUNTU_DIGEST` and the `FROM` digest are always the same value.
- Never tag `latest`, and never publish over an existing version.
- Commits are Conventional Commits with the issue in the body (`Closes #N` or
  `Refs #N`); each commit must build and pass on its own. The type decides the
  release (see CONTRIBUTING.md).
