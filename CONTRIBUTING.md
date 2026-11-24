# Contributing

This file describes how changes land in this repository and how releases are
made. [README.md](README.md) is the manual for using the images.

## From issue to merge

1. **Start from an issue.** Every change has one. Its title is a Conventional
   Commit subject (`build(docker): ...`, `ci: ...`) and its body ends in a
   "Done when" list.
2. **Branch** as `issue/<number>-<short-slug>` from `main`.
3. **Commit** in Conventional Commit style. The subject is the issue title, the
   body says what changed and why, and the issue goes in the body:
   `Closes #N` when the commit finishes it, `Refs #N` when it does not. Every
   commit builds and passes the smoke test on its own, because pull requests
   are rebase-merged and each commit lands as it was reviewed.
4. **Keep pull requests small**: one issue, one to a few commits. Say in the
   description what you verified and how, and what you could not.
5. **CI is the gate.** A pull request merges when `build (amd64)`,
   `build (arm64)`, `yocto (amd64)`, `yocto (arm64)` and `conventional commit
   messages` are green.

The commit type decides the next release, so choose it for what the change
means to someone using the image:

- `feat(docker)`: a tool added, or the next Wrynose point release followed
- `fix(docker)`, `build(docker)`: anything else that changes the image, such
  as a newer snapshot
- `!` after the type: a new toolchain baseline
- `ci`, `docs`, `chore`, `test`, `refactor`: no release

## Definition of done

Run these from the repository root before asking for review. CI runs the same
steps on amd64 and arm64.

```sh
docker build --target ci -t cxx-cmake-container:ci-local .
docker build --target dev -t cxx-cmake-container:dev-local .
docker build --target yocto -t cxx-cmake-container:yocto-local .
docker run --rm -v "$PWD/test:/test:ro" cxx-cmake-container:ci-local /test/smoke.sh
docker run --rm -v "$PWD/test:/test:ro" -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) \
  cxx-cmake-container:dev-local /test/smoke.sh
docker run --rm -v "$PWD/test:/test:ro" cxx-cmake-container:yocto-local /test/smoke-yocto.sh
```

## Dockerfile

- apt installs go through `apt-retry` and resolve against the snapshot. CI
  never falls back to the live archive; when snapshot.ubuntu.com is down, wait
  and re-run.
- Anything downloaded outside apt has a version `ARG` and a SHA-256 checked in
  the same `RUN`. The one exception is what Tracy's CMake fetches by git tag
  while building `tracy-capture`; don't add another.
- A version change edits `test/expected-versions.env` in the same commit, and
  the README's version table when a row changes.
- `ci` stays root. People-facing setup goes in `dev`.
- Comments say why. Most steps need none; a file header is at most six lines.
- `REUSE.toml` gives every file its licence, so new files need no SPDX header.

## Releases

`.github/workflows/release.yml` runs release-please on every push to `main`.
It keeps one rolling pull request that adds the `feat`, `fix`, `build` and
`revert` commits since the last release to `CHANGELOG.md` and sets the next
version. Merging that pull request tags `vX.Y.Z`, creates the GitHub Release
and publishes the images. The first release is 0.1.0 (`initial-version` in
`release-please-config.json`).

Publishing builds `ci`, `dev` and `yocto` natively on amd64 and arm64, pushes
each by digest with an SBOM and provenance attestation, and puts the two
digests of each stage under one multi-arch index tagged as the README
describes. It checks that both platforms are in each index and adds the index
digests to the release notes.

If publishing fails after the release exists, run the workflow by hand
(Actions > release > Run workflow) with the version, for example `0.1.0`. It
builds that tag again and refuses if `ci:<version>` already exists: re-running
only repairs a failed publish, and anything else is a new patch release.

GHCR creates each package private on its first publish. Make each public
once, under Packages > `cxx-cmake-container/ci` (and `/dev`, `/yocto`) >
Package settings > Change visibility, and check that the package shows this
repository under "Repository source"; after that `docker pull` works without
logging in.

### Release token

The workflow needs a fine-grained personal access token in the
`RELEASE_PLEASE_TOKEN` secret and fails at its first step without one. GitHub
runs no workflows on pull requests or tags created with a workflow's own
`GITHUB_TOKEN`, so with the default token the release pull request would never
pass the gate.

Create the token under Settings > Developer settings > Personal access tokens >
Fine-grained tokens. Repository access: this repository only. Permissions:
Contents read and write, Pull requests read and write, and Issues read and
write (release-please labels the pull request). Then:

```sh
gh secret set RELEASE_PLEASE_TOKEN -R SherlockInSpace/cxx-cmake-container
```

Fine-grained tokens expire, so a 401 from the release-please step means setting
a new one the same way.
