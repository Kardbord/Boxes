# Architecture

This document explains in detail how the Boxes project works end-to-end: how sources
reach the Open Build Service (OBS), how packages are built across many distributions
and architectures, and the infrastructure decisions that make cross-distribution
packaging work.

## OBS Pipeline Overview

```
GitHub (source of truth)
   │  git push
   ▼
src.opensuse.org (mirror required by scmsync)
   │  scmsync watches the mirror
   ▼
OBS home:Kardbord:Boxes (builds packages)
   │  publish
   ▼
download.opensuse.org (binary packages)
```

1. **GitHub** — This repository (`Kardbord/Boxes`) is the packaging
   source of truth. All packaging files live here.
2. **src.opensuse.org** — The repository is mirrored to `https://src.opensuse.org/Kardbord/Boxes.git`.
   This mirror is required because OBS's `scmsync` hook does not work with GitHub
   directly; it needs an gitea git host to watch.
3. **OBS build** — The OBS project `home:Kardbord:Boxes` is configured with
   `scmsync` pointing at the mirror. Every top-level directory in the repository
   becomes an OBS package, and new commits trigger automatic rebuilds.
4. **Publish** — Completed binaries are published to
   `download.opensuse.org/repositories/home:/Kardbord:/Boxes/<repository>/`,
   ready to be consumed by the installation commands in the [README](./README.md).

### Why `scmsync` and not `_service` download?

`scmsync` is the OBS mechanism that treats an external SCM repository as the
source of truth for a whole project. OBS *reads from* the mirror and never writes
back. This keeps package definitions versioned in git and rebuilds them on every
push. For fetching individual upstream source trees *within* a package, the package's
own `_service` file is used instead (see below).

## OBS Repository Structure

```
Boxes/
├── LICENSE               # MIT license for the packaging configuration
├── README.md             # Portfolio overview + installation instructions
├── ARCHITECTURE.md       # This document
├── _config               # OBS project build configuration (prjconf)
├── _meta                 # Informational copy of the OBS project metadata
├── kardbord-breakout/    # A single package
│   ├── _service          # Describes how to fetch upstream sources
│   ├── kardbord-breakout.spec     # RPM build recipe
│   ├── kardbord-breakout.dsc      # Debian source control file
│   ├── kardbord-breakout.changes  # OBS changelog (RPM)
│   ├── debian.changelog  # Debian changelog
│   ├── debian.control    # Debian binary package definitions
│   ├── debian.copyright  # Debian license/copyright info
│   ├── debian.rules      # Debian build rules (debhelper + cmake)
│   └── ...
└── ...
```

Each package lives in its own top-level directory. The directory name becomes the
OBS package name. Inside, the `_service` file defines where the *upstream application
source* comes from, while the remaining files define how to package it.

## Key Configuration Files

### `_meta` (OBS project metadata)

> **Important:** The `_meta` file in this repository is **purely informational**.
`scmsync` does **not** sync project metadata from the repository. The
authoritative project metadata for `home:Kardbord:Boxes` lives on the OBS
side and must be edited via the [OBS web UI](https://build.opensuse.org/project/show/home:Kardbord:Boxes)
or the `osc` CLI:

```bash
osc meta prj home:Kardbord:Boxes -e
```

The `_meta` defines:

- The `scmsync` URL (the src.opensuse.org mirror).
- Project ownership (`<person>` roles).
- Every `<repository>`: the build target (one per distribution), its architecture
  list, and its build **dependency** `<path>` entries (the repositories OBS may
  read binaries from while building).

Even if the in-repo `_meta` goes stale, the comments document what is configured,
so it is kept as an annotation of record.

### `_config` (project build configuration / prjconf)

The `_config` file **is** synced by `scmsync` and becomes the project's build
configuration (prjconf). Unlike the `_meta`, the build *targets* (repositories,
paths, architectures) are **not** defined here — those live in the OBS-side
`_meta`. The prjconf instead holds project-wide macro and dependency-resolution
overrides. For Boxes, no project-wide settings are currently required; the file
exists as a commented template and a place to add per-repository overrides if
needed later.

### `_service` (within a package)

The `_service` file tells OBS how to prepare the upstream sources for a package.
Boxes uses `obs_scm`:

```xml
<service name="obs_scm">
    <param name="scm">git</param>
    <param name="url">https://github.com/Kardbord/breakout.git</param>
    <param name="revision">@PARENT_TAG@</param>
    <param name="match-tag">v*</param>
    ...
</service>
```

- **`obs_scm` runs on the OBS server**. It clones the upstream git repository, checks
  out the `@PARENT_TAG@` revision (the matching release tag), and stores the
  result as a compact `.obscpio` archive plus metadata.
- The remaining services — `set_version`, `tar`, and `recompress` — run **at
  build time** (`mode="buildtime"`), inside the target's build environment:
  - `set_version` reads the version from the SCM metadata and rewrites `Version:`
    in the `.spec`/`.dsc`.
  - `tar` reconstructs a regular tarball from the `.obscpio` archive.
  - `recompress` compresses it (gzip for Boxes) for `rpmbuild`/`dpkg-buildpackage`.

### RPM `.spec` files

RPM recipes. Boxes specs use `Version: 0` / `Release: 0%{?dist}` as placeholders
— the real version is injected by the `set_version` build-time service. They
use the `%cmake` macro family and a targeted `%{?rhel}` conditional to work across
distributions (see [Cross-Distribution Packaging](#cross-distribution-packaging)).

### Debian files

Each package also ships a `.dsc`, `debian.control`, `debian.rules`, `debian.changelog`,
and `debian.copyright` so the same source produces `.deb` packages via `dpkg-buildpackage`.

## Build Matrix

The OBS project builds every package for the following targets:

| Repository            | Architectures   | Dependency paths (in priority order)                                           |
|-----------------------|-----------------|--------------------------------------------------------------------------------|
| `openSUSE_Tumbleweed` | x86_64, aarch64 | openSUSE:Tools → openSUSE:Tumbleweed                                           |
| `RockyLinux_8`        | x86_64, aarch64 | `home:Kardbord:obs-services` → openSUSE:Tools → Fedora:EPEL:8 → RockyLinux:8   |
| `RockyLinux_9`        | x86_64, aarch64 | `home:Kardbord:obs-services` → openSUSE:Tools → Fedora:EPEL:9 → RockyLinux:9   |
| `RockyLinux_10`       | x86_64, aarch64 | `home:Kardbord:obs-services` → openSUSE:Tools → Fedora:EPEL:10 → RockyLinux:10 |
| `AlmaLinux_8`         | x86_64, aarch64 | `home:Kardbord:obs-services` → openSUSE:Tools → Fedora:EPEL:8 → AlmaLinux:8    |
| `AlmaLinux_9`         | x86_64, aarch64 | openSUSE:Tools → Fedora:EPEL:9 → AlmaLinux:9                                   |
| `AlmaLinux_10`        | x86_64, aarch64 | openSUSE:Tools → Fedora:EPEL:10 → AlmaLinux:10                                 |
| `Ubuntu_26.04`        | x86_64, aarch64 | openSUSE:Tools → Ubuntu:26.04 (standard/universe/update/backports)             |
| `Debian_13`           | x86_64, aarch64 | openSUSE:Tools → Debian:13                                                     |
| `Raspbian_13`         | armv7l          | openSUSE:Tools → Raspbian:13                                                   |

Dependency `<path>` entries are searched top-down; the first repository to satisfy
an install requirement wins. Note that only the RHEL-family repositories include
`home:Kardbord:obs-services`, and only where the architecture support is missing
upstream (see below).

## Cross-Distribution Packaging

Building one package across openSUSE, Rocky/Alma, and Debian/Ubuntu surfaces several
environment differences that the packaging files must accommodate:

- **Doc directory paths** — openSUSE installs package docs to `/usr/share/doc/packages/<name>`
  while RHEL-family distros use `/usr/share/doc/<name>`. The specs therefore use
  the `%{_docdir}` macro (which expands correctly per-distro) and pass `-DCMAKE_INSTALL_DOCDIR=%{_docdir}/%{name}`
  to cmake so the build and file-list agree everywhere.
- **Compiler strictness** — older GCC toolchains on RHEL 8 / Rocky 8 / Alma 8
  enable warnings that newer versions do not, and `-Werror` turns them into build
  failures. The specs conditionally add `-Wno-type-limits` when `%{?rhel} <= 8`
  to suppress a spurious unsigned-vs-zero comparison warning.
- **Package naming** — a package name that exists on one distro may not exist
  (or may be named differently) elsewhere. For example, `obs-service-set_version`
  requires `python3-base` on openSUSE but `python3` on RHEL-family distros.
  This is reconciled with `Substitute:` directives in the `home:Kardbord:obs-services`
  prjconf.
- **`noarch` package availability** — even architecture-independent packages are
  only visible to the OBS solver for a build architecture if the repository that
  provides them actually builds that architecture. See the next section.

## `home:Kardbord:obs-services` — Linked Packages

The Boxes builds use OBS *source services* at build time (`set_version`, `tar`,
`recompress`, and the underlying `obs_scm`). For a build-time service to
run, two things must be true:

1. The corresponding service package (`obs-service-set_version`, `obs-service-tar`,
   `obs-service-recompress`, …) must be installable inside the target's build environment.
2. OBS must be able to *resolve* that package from one of the repository's dependency
   `<path>` entries.

The `openSUSE:Tools` project on OBS is the canonical home of these service packages, but
it does **not** build them for every (distribution, architecture) combination. In
particular:

- `openSUSE:Tools` publishes **x86_64-only** repositories for Rocky Linux (no `aarch64/`
  or `armv7l/` output), so its `noarch` service packages never become visible to
  aarch64 builds.
- OBS excludes an entire repository from the solver for a given architecture when
  that repository has no build output for it — including its `noarch` packages.
  So an aarch64 build for `RockyLinux_8` sees *no* service packages from `openSUSE:Tools/RockyLinux_8`
  at all.

This is why a second OBS project exists: [**`home:Kardbord:obs-services`**](https://build.opensuse.org/project/show/home:Kardbord:obs-services).

### The Solution: linked packages

`home:Kardbord:obs-services` contains OBS **linked packages** for the needed service
tools. A linked package works like this:

- A package in your own project contains a single `_link` file:

  ```xml
  <link project="openSUSE:Tools" package="obs-service-recompress"/>
  ```

- OBS fetches the source from `openSUSE:Tools` and *re-builds* it in your
  project for **your** project's repositories and architectures.
- Because `home:Kardbord:obs-services` defines repositories with `aarch64` enabled
  (e.g. `RockyLinux_8` with `<arch>aarch64</arch>`), OBS now produces aarch64
  build output, and the `noarch` service packages become resolvable for aarch64
  builds.
- The linked packages stay in sync automatically: when `openSUSE:Tools` updates
  a source, OBS detects the change and rebuilds in `home:Kardbord:obs-services`.

Once these packages build, `home:Kardbord:Boxes` lists `home:Kardbord:obs-services`
as the **first** dependency `<path>` for the affected repositories, so the solver
finds the service packages there before falling through to `openSUSE:Tools`.

### `Substitute:` — reconciling package names

`obs-service-set_version` (a pure-Python script) depends on `python3-base` on openSUSE,
but that package name does not exist on RHEL-family distros where it is called `python3`
instead. Rather than patching the linked spec, the `home:Kardbord:obs-services`
prjconf maps the name at the solver level:

```
Substitute: python3-base python3
```

This tells OBS to treat a request for `python3-base` as a request for `python3`,
resolving the dependency on every target without modifying any package source.

### Why tests are disabled

`home:Kardbord:obs-services` disables `%check` for all packages via its prjconf.
These packages are linked copies of already-tested upstream packages from `openSUSE:Tools`;
re-running their test suites in a rebuild-for-architecture context adds build time
and pulls in distribution-specific test infrastructure (e.g. `perl-Test-Harness` on EL8,
which supplies `prove`) that is otherwise only a packaging concern, not a correctness
one. Tests are the upstream's responsibility and have already passed before the package
was published in `openSUSE:Tools`.

### Adding a New Package

1. **Create a directory** in this repository named after the package, e.g. `mypkg/`.
2. **Add the source-service definition** — create `mypkg/_service` with an `obs_scm`
   block pointing at the upstream git repository (following the pattern in `kardbord-breakout/_service`).
3. **Add the build recipes** — create the RPM `.spec` and, if you want `.deb`
   artifacts, the `debian.*` files and a `.dsc`. Follow the conventions noted in
   this document (placeholder `Version: 0`, `%{_docdir}` doc paths, EL8 conditional
   flags, etc.).
4. **Commit and push** to the `main` branch in GitHub. The mirror to src.opensuse.org
   propagates the change, and `scmsync` picks it up.
5. **Verify** on [OBS](https://build.opensuse.org/project/show/home:Kardbord:Boxes)
   that the package builds for the targets you care about; iterate on any distribution-specific
   failures the way `kardbord-breakout` did.

## Flatpak Packaging

In addition to OBS-managed RPM and DEB packages, Boxes hosts a custom Flatpak
repository using [AetherPak](https://github.com/aetherpak/actions). Application
layers are stored as OCI images in GitHub Container Registry (GHCR), and a small
JSON index plus landing page are served from GitHub Pages.

### Flatpak Pipeline Overview

```
GitHub (source of truth)
   │  push to flatpak/**
   ▼
GitHub Actions (flatpak-build.yml)
   │  Phase 1: Build SDK → OCI in GHCR + index on Pages
   │  Phase 2: Build apps/extensions → OCI in GHCR + index on Pages
   ▼
GHCR (OCI images) + Pages (index/static)
   │  flatpak install kardbord-boxes <package>
   ▼
User systems
```

### Two-Phase Build

The SDK (`io.github.kardbord.Sdk`) declares `build-runtime: true`, producing
both `io.github.kardbord.Platform` and `io.github.kardbord.Sdk` runtimes.
All other packages depend on these runtimes at build time. AetherPak builds
packages in a parallel matrix, so the SDK must be built first:

1. **Phase 1** — Build and publish the SDK using `flatpak/aetherpak-sdk.yaml`.
2. **Phase 2** — Generate `aetherpak-apps.yaml` from the manifests directory
   at CI time (via `scripts/generate-aetherpak-config.sh`), compute the build
   matrix, build all apps and extensions in parallel, push OCI images, merge the
   index, and deploy to Pages.

The apps config references the Phase 1 deployment as a custom Flatpak remote so
`flatpak-builder` can resolve `io.github.kardbord.Platform` at build time.

### Auto-Discovery

New packages are auto-discovered from the `flatpak/manifests/` directory. The
`generate-aetherpak-config.sh` script scans the directory, skips the SDK, and
emits an `aetherpak-apps.yaml` config. Adding or removing a package only
requires creating or deleting its manifest directory — no config file to
maintain.

### Custom Runtime

All `io.github.kardbord.*` flatpak apps are built on a custom runtime
(`io.github.kardbord.Platform`) and SDK (`io.github.kardbord.Sdk`), derived
from `org.freedesktop.Platform`/`org.freedesktop.Sdk`. The custom
runtime declares the `io.github.kardbord.tool` extension point.

Any app built on `io.github.kardbord.Platform` automatically inherits this
extension point. Extensions with IDs matching `io.github.kardbord.tool.*` are
mounted into the app sandbox.

Apps that use `base:` to inherit from a Flathub build (e.g. `io.neovim.nvim`)
and switch to the custom runtime will have the extension point injected by the
runtime.

### Flatpak Repository Structure

```
Boxes/
├── .github/workflows/
│   ├── flatpak-build.yml           # Build + deploy workflow
│   └── flatpak-prune.yml           # Weekly OCI image pruning
├── scripts/
│   └── generate-aetherpak-config.sh  # Generates apps config from manifests
├── flatpak/
│   ├── aetherpak-sdk.yaml          # AetherPak config for SDK (committed)
│   ├── README.md                   # Developer/maintainer documentation
│   └── manifests/
│       ├── io.github.kardbord.Sdk/
│       │   └── io.github.kardbord.Sdk.yml
│       ├── io.github.kardbord.neovim/
│       │   ├── io.github.kardbord.neovim.yml
│       │   ├── neovim-first-run.txt
│       │   └── neovim-sdk-update.txt
│       ├── io.github.kardbord.ripgrep/
│       │   ├── io.github.kardbord.ripgrep.yml
│       │   └── ripgrep
│       ├── io.github.kardbord.tool.ripgrep/
│       │   └── io.github.kardbord.tool.ripgrep.yml
│       └── io.github.kardbord.tool.fd/
│           └── io.github.kardbord.tool.fd.yml
├── kardbord-breakout/              # OBS package
├── _manifest                       # Does NOT list flatpak/
└── ...
```

The `flatpak/` directory is intentionally excluded from `_manifest` so that OBS
does not treat it as a package.

### OCI Image Pruning

A weekly scheduled workflow (`flatpak-prune.yml`) runs AetherPak's
`prune-github-container-registry.yml`, which compares the active index against
GHCR container versions and deletes any that are no longer referenced. This
ensures stale images are cleaned up automatically after packages are removed.

### Upstream Tracking

Two mechanisms detect upstream changes independently:

1. **App base dependencies**: Apps that use `base:` to inherit from Flathub
   builds are tracked via GitHub Actions variables. The
   `flatpak-upstream-check.yml` workflow runs daily, queries Flathub for the
   latest stable commit of each base app, and triggers the build workflow if
   upstream has changed. Currently tracks `io.neovim.nvim` via the
   `FLATPAK_NEOVIM_UPSTREAM_COMMIT` variable; additional apps can be added as
   new manifests are introduced.

2. **Extension sources**: The `flatpak-external-data-checker` (FEDC) runs daily,
   using `x-checker-data` annotations in the extension manifests to detect new
   GitHub releases. FEDC auto-commits updated manifests and opens PRs.

### GPG Signing

The Flatpak repository is GPG-signed. The private key is stored as the GitHub
Actions secret `FLATPAK_GPG_PRIVATE_KEY`. AetherPak handles signing via the
`signing` input (default: `auto` — sign when a key is set). The public key and
signature lookaside are published alongside the index on Pages.

### Adding a New Flatpak Extension

1. Create a directory `flatpak/manifests/io.github.kardbord.tool.<name>/`.
2. Write the manifest with `build-extension: true` and `x-checker-data` annotations
   (see [flatpak/README.md](flatpak/README.md) for the template).
3. Test locally with `flatpak-builder`.
4. Commit and push — the `generate-aetherpak-config.sh` script auto-discovers
   the new manifest at CI time.

### Adding a New Flatpak App

1. Create a directory `flatpak/manifests/io.github.kardbord.<name>/`.
2. Write the manifest (`io.github.kardbord.<name>.yml`). If the app exists on
   Flathub, use `base:` to inherit its build and layer your changes on top (see
   the [flatpak/README.md](flatpak/README.md) `base` field documentation). If
   building from source, define `modules` directly.
3. Use `runtime: io.github.kardbord.Platform` and `sdk: io.github.kardbord.Sdk`
   to inherit the `io.github.kardbord.tool` extension point automatically.
4. Add `cleanup-commands: - mkdir -p ${FLATPAK_DEST}/lib/kardbord-tools` to
   create the extension mount point. Without this, bwrap will fail with a
   read-only filesystem error when mounting extensions.
5. If the app uses `base:`, add an upstream tracking variable and extend the
   `flatpak-upstream-check.yml` workflow (see [Upstream Tracking](#upstream-tracking)).
6. Do not grant filesystem access in `finish-args` beyond what the app needs to
   function. See [Sandbox Permissions Policy](flatpak/README.md#sandbox-permissions-policy).
7. Test locally with `flatpak-builder`.
8. Commit and push — the `generate-aetherpak-config.sh` script auto-discovers
   the new manifest at CI time.
