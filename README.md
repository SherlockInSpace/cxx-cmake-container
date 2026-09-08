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

## Releases

The version is the image version and the commit subjects on `main` decide it.
`.github/workflows/release.yml` runs release-please on every push. It keeps one
rolling pull request that adds the `feat`, `fix`, `build` and `revert` commits
since the last release to `CHANGELOG.md` and sets the next version. Until 1.0
a breaking change (`!`) bumps the minor and everything else the patch. From
1.0 on `!` bumps the major, `feat` the minor and the rest the patch. The first
release is 0.1.0 (`initial-version` in `release-please-config.json`). Merging
the pull request tags `vX.Y.Z` and creates the GitHub Release. A later workflow
publishes the images from that release.

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
