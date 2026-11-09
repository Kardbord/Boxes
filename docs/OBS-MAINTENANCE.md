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
   If the package ships prebuilt upstream binaries instead of building from
   source, see [Prebuilt-Binary Packages](#prebuilt-binary-packages) below —
   it uses a `_service.in` template and a `download_url`-based `_service`
   instead of `obs_scm`.
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

Some packages (e.g. `flutter-version-manager`) ship **prebuilt upstream
release binaries** rather than building from source — the upstream project
compiles them (e.g. a Dart AOT CLI) and there is no viable from-source build
across the OBS target matrix. These packages follow a different source and
update flow:

#### Layout

```
mypkg/
├── .upstream.yml   # FEDC tracking manifest: pinned archive URLs + sha256s
├── _service.in     # human-authored OBS service template (placeholders)
├── _service        # generated from _service.in by the sync script
├── mypkg.spec      # RPM build recipe (unpacks the right tarball per arch)
├── mypkg.rpmlintrc # rpmlint exceptions (e.g. Dart AOT RUNPATH on openSUSE)
└── debian.*        # Debian build recipes
```

#### How it works

- The `_service` file uses **`download_url`** (no `mode` attribute, so it
  runs server-side when `scmsync` picks up a push — same trigger path as
  `obs_scm`, and no build-environment service dependencies) to fetch pinned
  upstream release assets, followed by **`verify_file`** blocks that check
  each asset's sha256 **before anything is built**, and a buildtime
  **`set_version`** service with an explicit `version` parameter that
  rewrites `Version:` in the `.spec`, `.dsc`, and `debian.changelog`.
- **`verify_file` must reference the service-prefixed filename**:
  `_service:download_url:<file>`. Between server-side service runs, the
  OBS service daemon (`bs_service`) renames each service's output with
  `_service:<service-name>:` — so when `verify_file` executes, the plain
  filenames do not exist in the working directory and verification would
  fail with `sha256sum: ...: No such file or directory`. This is the
  standard idiom for chained `download_url` + `verify_file` packages.
  Note the asymmetry: `osc service localrun` runs services *without*
  prefixing, so local service runs fail at the `verify_file` step. Verify
  locally by either checking sums manually against `.upstream.yml` or by
  triggering the real server-side run: `osc service remoterun`.
- `.upstream.yml` is a dummy flatpak manifest with `x-checker-data` JSON
  annotations (same recipe as the Flatpak manifests). FEDC rewrites the
  archive `url` **and `sha256`** fields in place when upstream publishes a
  new release.
- `scripts/sync-obs-services.sh` renders `_service` from `_service.in`:
  it derives the version from the `/releases/download/<version>/` URLs,
  asserts all archive sources agree on it, substitutes the
  `{{UPSTREAM_VERSION}}` and `{{SHA256:<filename>}}` placeholders, refuses
  to leave unresolved placeholders or unreferenced archive sources, and
  writes `_service` only when it changed.
- The FEDC workflow runs the sync script right after its check loop, so the
  weekly upstream-update PR contains both the rewritten `.upstream.yml` and
  the regenerated `_service` files. Merging the PR is all that's needed:
  the push triggers `scmsync`, the server-side services re-download and
  re-verify the assets, and OBS rebuilds every target.
- **Deb builds only see the transformed source package — attach extra
  files with `DEBTRANSFORM-TAR`/`DEBTRANSFORM-FILES`.** Unlike RPM builds
  (which stage all source files into the build root), the deb build tree
  contains only the unpacked source package: the orig tarball plus the
  debian overlay. Consequences:
  - The deb transformer (`debtransform`) auto-discovers the upstream
source tarball and refuses when more than one file looks like a
candidate ("Too many files looking like a usable source tarball") —
the normal case for per-arch prebuilt binaries. Set
`DEBTRANSFORM-TAR: <tarball>` in the `.dsc` to name the orig tarball.
  - Anything else the `debian/rules` needs (the other per-arch tarballs,
    a license file, …) must be named `debian.<name>` in the package
    sources and listed in `DEBTRANSFORM-FILES` (space-separated).
    `debian.fvm-LICENSE`-style non-tarball attachments are added
    automatically by debtransform's generic `debian.` loop and don't need
    to be listed. **Where the attachments land inside the source tree has
    differed between debtransform versions** (remapped to
    `debian/<name>` or verbatim at the top level as `debian.<name>` —
    observable via dpkg's include-binaries notes in the build log), so
    have `debian/rules` locate them by name (e.g. `find . -name
    'fvm-linux-arm64.tar.gz' -o -name 'debian.fvm-linux-arm64.tar.gz'`)
    rather than hard-coding a path. The payload copies carry identical
    bytes, so either location is equivalent.
  - Use **version-free** download filenames (via the `download_url`
`filename` param) for everything referenced by the `.dsc`, `.spec`,
and `debian.rules`, so a version bump only touches `.upstream.yml`,
`_service`, and the `Version:` tags that `set_version` rewrites.
  - dsc comments must not contain `:` characters: debtransform colon-parses
the first dsc paragraph, and a comment line with a colon would be
re-emitted into the published dsc as a bogus tag.
  (debtransform strips the `DEBTRANSFORM-*` tags from the published dsc,
  and `set_version` only rewrites `Version:`, so the wiring survives
  builds.)
- **Silence rpmlint for prebuilt binaries with `<pkg>.rpmlintrc`.**
  Prebuilt upstream binaries routinely trip openSUSE rpmlint checks (e.g.
  Dart AOT executables from `dart compile exe` embed `RUNPATH=$ORIGIN/`,
  which is flagged as `binary-or-shlib-defines-rpath` with badness 10000
  and aborts the Tumbleweed build). Ship a `<specname>.rpmlintrc` in the
  package directory with `setBadness(...)`/`addFilter(...)` entries and a
  comment explaining why the finding is expected, so the binary stays
  bit-identical to upstream (see
  `flutter-version-manager/flutter-version-manager.rpmlintrc`).

#### Adding a prebuilt-binary package

1. Create the package directory with a `.spec` (and `debian.*` files) that
   unpacks the downloaded tarball per architecture and installs the binary.
2. Add a `.upstream.yml` with one `type: archive` source per asset, each
   with `url`, `sha256`, and `x-checker-data` (copy the recipe from the
   matching Flatpak manifest if one exists).
3. Write a `_service.in` template using `download_url` + `verify_file` +
   `set_version`, with `{{UPSTREAM_VERSION}}` / `{{SHA256:<filename>}}`
   placeholders (see `flutter-version-manager/_service.in`). Reference
   `_service:download_url:<file>` in the `verify_file` `file` params —
   see the prefixed-filename note under "How it works" above.
4. Run `scripts/sync-obs-services.sh <pkg>` to generate `_service`.
5. Register the package in `_manifest` (this also makes the FEDC workflow
   pick up its `.upstream.yml`), commit, and push.

Trade-off: the checksums come from GitHub release metadata over TLS; if
upstream re-uploads a release asset, builds fail (by design) until FEDC
refreshes the URLs and checksums in the next weekly run.

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
