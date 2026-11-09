# OBS — Developer & Maintainer Guide

This document is the operational guide for maintaining the Open Build Service
(OBS) packaging infrastructure in this repository. For a deep-dive into how the
pipeline fits together end-to-end (scmsync internals, the build matrix, the
`home:Kardbord:obs-services` linked packages), see [ARCHITECTURE.md](../ARCHITECTURE.md).

User-facing installation instructions are in the [README](../README.md).

## Package Layout

Each package lives in its own top-level directory. The directory name becomes
the OBS package name. Minimal `kardbord-breakout/` structure:

```
kardbord-breakout/
├── _service              # Describes how to fetch upstream sources
├── .upstream.yml         # Upstream tracking manifest for FEDC
├── kardbord-breakout.spec     # RPM build recipe
├── kardbord-breakout.dsc      # Debian source control file
├── debian.changelog
├── debian.control
├── debian.copyright
├── debian.rules
└── ...
```

Adding a package requires creating its directory and registering it in the
top-level `_manifest` file so the OBS SCM bridge treats it as a package.

## Adding a New Package

1. **Create a directory** in this repository named after the package, e.g. `mypkg/`.
2. **Add the source-service definition** — create `mypkg/_service` with an `obs_scm`
   block pointing at the upstream git repository (following the pattern in
   `kardbord-breakout/_service`).
3. **Add the build recipes** — create the RPM `.spec` and, if you want `.deb`
   artifacts, the `debian.*` files and a `.dsc`. Follow the packaging
   conventions (placeholder `Version: 0`, `%{_docdir}` doc paths, EL8
   conditional flags, etc.) described in [ARCHITECTURE.md](../ARCHITECTURE.md#cross-distribution-packaging).
   For prebuilt upstream binaries, see [Prebuilt-Binary Packages](#prebuilt-binary-packages).
4. **Add upstream tracking (optional but recommended)** — create `mypkg/.upstream.yml`
   with `x-checker-data` annotations so the FEDC workflow can detect and propose
   upstream updates automatically.
5. **Register the package** in the top-level `_manifest` file.
6. **Commit and push** to the `main` branch in GitHub. The mirror to
   src.opensuse.org propagates the change, and `scmsync` picks it up.
7. **Verify** on [OBS](https://build.opensuse.org/project/show/home:Kardbord:Boxes)
   that the package builds for the targets you care about; iterate on any
   distribution-specific failures the way `kardbord-breakout` did.

### Prebuilt-Binary Packages

Some packages (e.g. `flutter-version-manager`) ship prebuilt upstream release
binaries instead of building from source. They use a different source and
update flow:

#### Layout

```
mypkg/
├── .upstream.yml   # FEDC tracking manifest: pinned archive URLs + sha256s
├── _service.in     # human-authored OBS service template (placeholders)
├── _service        # generated from _service.in by the sync script
├── mypkg.spec      # RPM build recipe
├── mypkg.rpmlintrc # rpmlint exceptions (e.g. Dart AOT RUNPATH on openSUSE)
└── debian.*        # Debian build recipes
```

#### How it works

- `_service` chains `download_url` (server-side; renames assets to
  version-free names via the `filename` param) → `verify_file` (sha256
  checks, before any build) → buildtime `set_version` (explicit `version`
  param; rewrites `Version:` in the `.spec`, `.dsc`, and
  `debian.changelog`).
- `.upstream.yml` is a dummy flatpak manifest with `x-checker-data`; FEDC
  rewrites each archive source's `url` and `sha256` on new releases.
- `scripts/sync-obs-services.sh` renders `_service` from `_service.in`
  (`{{UPSTREAM_VERSION}}` / `{{SHA256:<filename>}}` placeholders,
  consistency-checked), and the FEDC workflow runs it so its weekly PR
  updates both. Merging that PR is the entire update flow.

#### Gotchas

- `verify_file` `file` params must use the `_service:download_url:<file>`
  prefix: bs_service renames each service's outputs between server-side
  runs. Local service runs (`osc service run`) do not prefix; verify
  locally with manual sha256 checks or trigger the real server-side run
  with `osc service remoterun`.
- Deb builds see only the transformed source package (orig tarball +
  debian overlay), not the staged sources:
  - `DEBTRANSFORM-TAR: <tarball>` in the `.dsc` names the orig tarball
    (auto-discovery fails with multiple per-arch tarballs).
  - Other payload files are named `debian.<name>` in the sources and
    listed space-separated in `DEBTRANSFORM-FILES`; they land in the
    source tree under their verbatim names. Non-tarball `debian.*` files
    attach automatically as `debian/<name>` and are not listed. Every
    `DEBTRANSFORM-FILES` entry must exist as a package source file —
    attach failures are silent.
  - Don't trust the unpacked orig tree (dpkg may strip or alter the
    top-level directory); extract payloads into a scratch dir and locate
    attachments by name (`find . -name '*<file>'`).
  - dsc comments must not contain `:`.
- Filenames referenced by the `.dsc`, `.spec`, and `debian.rules` must be
  version-free, so a version bump only touches `.upstream.yml`, `_service`,
  and the `Version:` tags `set_version` rewrites.
- Prebuilt binaries trip rpmlint (e.g. Dart AOT `RUNPATH=$ORIGIN/`); ship
  `<specname>.rpmlintrc` with `setBadness(...)`/`addFilter(...)`.
- Check upstream's per-arch asset layouts before writing install recipes.
  cli_pkg (FVM) ships single binaries for some platforms and
  wrapper + `src/{dart,<name>.snapshot}` bundles for others. Wrapper
  assets install as a tree under `/usr/lib` (or `%{_libdir}`) with a
  `/usr/bin` symlink (the wrapper resolves its own real path via
  `readlink -f`); single binaries install directly. Detect the layout by
  content (e.g. presence of `fvm/src/<name>.snapshot`), not by arch.

#### Adding a prebuilt-binary package

1. Create the package dir with a `.spec` (+ `debian.*`) that extracts the
   payload per architecture (see the gotchas above).
2. Add `.upstream.yml` with one `type: archive` source per asset (`url`,
   `sha256`, `x-checker-data` — copy the matching Flatpak manifest's
   recipe if one exists).
3. Add a `_service.in` template (see `flutter-version-manager/_service.in`)
   and run `scripts/sync-obs-services.sh <pkg>` to generate `_service`.
4. Register in `_manifest`, commit, and push.

Trade-off: checksums come from GitHub release metadata over TLS; if upstream
re-uploads an asset, builds fail (by design) until the next FEDC run refreshes
the URLs and checksums.

## Rebuilding and Re-running Services

Because the whole project is managed by `scmsync`, new package builds are
normally triggered by pushing to this repository: the mirror propagates the
change and `obs_scm` re-fetches the upstream sources automatically.

Sometimes you want to trigger a build without a git change:

| Goal                                  | Command                                        | Notes                                                                 |
|---------------------------------------|------------------------------------------------|-----------------------------------------------------------------------|
| Rebuild with the current sources      | `osc rebuild <Project> <Package>`              | Use `--all` for all packages; useful for retrying failed builds. Does **not** re-fetch upstream. |
| Re-run `_service` (re-fetch upstream) | `osc token <TOKEN> --trigger <Project> <Package>` | Re-fetches the upstream sources and queues a rebuild.                 |

## How Upstream Stays Current

Tracked packages stay up to date through the FEDC check workflow:

1. FEDC scans every manifest with `x-checker-data` annotations — the Flatpak
   manifests under `flatpak/manifests/` **and** the `_manifest`-listed OBS
   packages (each ships an `.upstream.yml` manifest in its directory).
2. When a new upstream release is found, FEDC rewrites the manifest sources in
   place and opens (or updates) a single pull request for review.
3. Merging that PR pushes to `main`, which is what `scmsync`/`obs_scm` pick up
   to re-fetch the upstream sources and queue a rebuild.

See [ARCHITECTURE.md](../ARCHITECTURE.md#upstream-tracking) for the full
mechanism.
