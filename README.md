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

## Releases

The version is the image version and the commit subjects on `main` decide it.
`.github/workflows/release.yml` runs release-please on every push. It keeps one
rolling pull request that adds the `feat`, `fix`, `build` and `revert` commits
since the last release to `CHANGELOG.md` and sets the next version. Until 1.0
a breaking change (`!`) bumps the minor and everything else the patch. From
1.0 on `!` bumps the major, `feat` the minor and the rest the patch. The first
release is 0.1.0 (`initial-version` in `release-please-config.json`). Merging
the pull request tags `vX.Y.Z`, creates the GitHub Release, and publishes the
images.

### Publishing

The same workflow then builds `ci` and `dev` natively on amd64 and arm64,
pushes each by digest with an SBOM and provenance attestation, and puts the two
digests of each stage under one multi-arch index tagged `X.Y.Z` and `X.Y` (and
`X` from 1.0 on; never `latest`). It checks both platforms are in each index and
adds the two index digests to the release notes, since consumers pin by digest.

If publishing fails after the release exists, run the workflow by hand
(Actions > release > Run workflow) with the version, for example `0.1.0`. It
builds that tag again and refuses if `ci:<version>` already exists: re-running
only repairs a failed publish, and anything else is a new patch release.

GHCR creates both packages private on the first publish. Make each public once,
under Packages > `cxx-cmake-container/ci` (and `/dev`) > Package settings >
Change visibility, and check that the package shows this repository under
"Repository source"; after that `docker pull` works without logging in.

`docs`, `ci`, `chore`, `test` and `refactor` commits stay out of the changelog
and on their own do not open a release pull request.

### One-time setup

The workflow needs a fine-grained personal access token in the
`RELEASE_PLEASE_TOKEN` secret and fails at its first step without one. GitHub
runs no workflows on pull requests or tags created with a workflow's own
`GITHUB_TOKEN`, so with the default token the release pull request would never
pass the gate and the tag would never publish anything.

Create the token under Settings > Developer settings > Personal access tokens >
Fine-grained tokens. Repository access: this repository only. Permissions:
Contents read and write, Pull requests read and write, and Issues read and
write (release-please labels the pull request). Then:

```sh
gh secret set RELEASE_PLEASE_TOKEN -R SherlockInSpace/cxx-cmake-container
```

Fine-grained tokens expire, so a 401 from the release-please step means setting
a new one the same way.
