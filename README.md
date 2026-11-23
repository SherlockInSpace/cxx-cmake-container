# cxx-cmake-container

Versioned build-environment images for the cxx-cmake template family. Images
will be published to GHCR under semver tags (never `latest`), in two stages —
`ci` and `dev` — for amd64 and arm64.

**Status:** under construction; scope and progress are tracked in the issues.

Sibling repos:

- [cxx-cmake](https://github.com/SherlockInSpace/cxx-cmake)
- [cxx-cmake-app](https://github.com/SherlockInSpace/cxx-cmake-app)
- [meta-cxx-cmake](https://github.com/SherlockInSpace/meta-cxx-cmake)

## The snapshot service

Every image build downloads its packages from snapshot.ubuntu.com, so we get the
same package versions on every rebuild. The service is run by Canonical, and the
build depends on it: there is no mirror, and falling back to the live archive
would silently give up reproducibility. It goes down for minutes at a time. apt retries each download with backoff and the Dockerfile's `apt-retry`
repeats a failed step a few times, so short outages pass. A longer one fails the
build with a message naming the service; re-run the job when it's back.
`--build-arg UBUNTU_SNAPSHOT=` builds from the live archive for a local
experiment.

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
in the same change. Dependabot opens the pull request for the `ubuntu:26.04`
digest and for the actions in `.github/workflows`. Dependabot's digest pull
request stays red until the new digest is copied into `UBUNTU_DIGEST` and
`expected-versions.env`. The package set comes from the apt snapshot, so the
real bump is editing `UBUNTU_SNAPSHOT` by hand.
