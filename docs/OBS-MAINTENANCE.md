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
4. **Register the package** in the top-level `_manifest` file.
5. **Commit and push** to the `main` branch in GitHub. The mirror to
   src.opensuse.org propagates the change, and `scmsync` picks it up.
6. **Verify** on [OBS](https://build.opensuse.org/project/show/home:Kardbord:Boxes)
   that the package builds for the targets you care about; iterate on any
   distribution-specific failures the way `kardbord-breakout` did.

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