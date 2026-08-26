# Flatpak — Developer & Maintainer Guide

This document is the operational guide for maintaining the Flatpak packaging
infrastructure in this repository. For a deep-dive into how the pipeline fits
together end-to-end, see [ARCHITECTURE.md](../ARCHITECTURE.md).

User-facing installation instructions are on the [landing page](https://kardbord.github.io/Boxes/).

## Architecture

Most `io.github.kardbord.*` flatpaks are built on `org.freedesktop.Platform`
and `org.freedesktop.Sdk`. The hub app `io.github.kardbord.dev` declares the
`io.github.kardbord.tool` extension point. All tools are delivered as
extensions (`io.github.kardbord.tool.*`) that mount into the hub's sandbox.

```
io.github.kardbord.dev          ← Hub app. Declares extension point.
io.github.kardbord.tool.*       ← Extensions (ripgrep, fd, neovim, etc.)
```

Other apps may also be available, following the `io.github.kardbord.<app>`
naming convention.

### Hub App

`io.github.kardbord.dev` is a minimal app with zero sandbox permissions. It
provides the `activate-kardbord-env` script (sets up PATH for tool extensions)
and the `kardbord-dev` entrypoint (forwards arguments through the env setup).

The hub declares the `io.github.kardbord.tool` extension point:
- Extensions with IDs matching `io.github.kardbord.tool.*` are mounted at
  `/app/lib/kardbord-tools/<name>/`
- `activate-kardbord-env` prepends each extension's `bin/` directory to PATH
- `org.freedesktop.Sdk.Extension.*` extensions are also activated automatically

#### Sandbox Permissions Policy

The hub app has **zero sandbox permissions** — no filesystem access, no network,
no display socket. Users must provide the necessary flags at runtime:

```bash
# Access home directory and network (needed for opencode)
flatpak run --filesystem=home --share=network io.github.kardbord.dev opencode

# Access host filesystem (needed for neovim, ripgrep)
flatpak run --filesystem=host io.github.kardbord.dev nvim

# Access only /tmp (minimal)
flatpak run io.github.kardbord.dev fd
```

Users who prefer a shorter command can create shell aliases for their preferred
flags, e.g. `alias nvim='flatpak run --filesystem=host io.github.kardbord.dev nvim'`.

When adding a new extension, grant only the permissions the tool needs to
function in `finish-args`. Do not add blanket permissions like `--filesystem=host`
unless the tool cannot function without it.

#### Extension Points

The `io.github.kardbord.tool` extension point is defined by the hub app:
- `directory: lib/kardbord-tools`
- `subdirectories: true` — each extension mounts at `lib/kardbord-tools/<name>/`
- `version: stable`
- `add-ld-path: lib` — adds each extension's `lib/` to the linker path

Extensions are installed alongside the hub via `flatpak install kardbord-boxes
io.github.kardbord.tool.<name>`. Once installed, they are automatically mounted
into the hub's sandbox.

### Upstream Tracking

Upstream sources for apps and extensions are tracked by the FEDC check
workflow, which uses `flatpak-external-data-checker` (FEDC) with the
`x-checker-data` annotations in manifests to detect new upstream releases.
FEDC updates the manifests in-place and opens a single PR with all changes
for review before merging. Merging the PR pushes to `main`, which triggers
a rebuild of the affected Flatpak packages. See
[ARCHITECTURE.md](../ARCHITECTURE.md#upstream-tracking) for the full mechanism.

## Adding a New Extension

1. **Create a directory**: `flatpak/manifests/io.github.kardbord.tool.<name>/`

2. **Write the manifest** (`io.github.kardbord.tool.<name>.yml`):
    ```yaml
    id: io.github.kardbord.tool.<name>
    branch: stable
    runtime: io.github.kardbord.dev
    runtime-version: stable
    sdk: org.freedesktop.Sdk//25.08
    build-extension: true
    separate-locales: false

    modules:
      - name: <name>
        buildsystem: simple
        build-commands:
          - install -Dm755 <binary> ${FLATPAK_DEST}/bin/<binary>
        sources:
          - type: archive
            only-arches: [x86_64]
            url: <upstream-x86_64-url>
            sha256: <sha256>
            x-checker-data:
              type: json
              url: https://api.github.com/repos/<owner>/<repo>/releases/latest
              version-query: '.tag_name | sub("^v"; "")'
              url-query: <query>
          - type: archive
            only-arches: [aarch64]
            url: <upstream-aarch64-url>
            sha256: <sha256>
            x-checker-data:
              type: json
              url: https://api.github.com/repos/<owner>/<repo>/releases/latest
              version-query: '.tag_name | sub("^v"; "")'
              url-query: <query>
    ```

3. **Get sha256 checksums**: Fetch from the GitHub API:
   ```
   curl -s https://api.github.com/repos/<owner>/<repo>/releases/latest \
     | jq -r '.assets[] | select(.name | test("musl")) | "\(.name) \(.digest)"'
   ```

4. **Test locally** (the hub app must be installed in the build repo first):
    ```bash
    # Install the hub app into a local repo
    flatpak-builder --force-clean --user --install-deps-from=flathub \
      --repo=repo build-dir \
      flatpak/manifests/io.github.kardbord.dev/io.github.kardbord.dev.yml
    flatpak --user remote-add --no-gpg-verify local-repo repo
    flatpak --user install local-repo io.github.kardbord.dev

    # Build the extension (hub is resolved from local-repo)
    flatpak-builder --force-clean --user --install-deps-from=local-repo \
      --repo=repo build-dir \
      flatpak/manifests/io.github.kardbord.tool.<name>/io.github.kardbord.tool.<name>.yml
    ```

5. **Add x-checker-data to the manifest** (shown above) so the
   FEDC check workflow can detect upstream updates.

6. **Regenerate and commit the apps config**: Run
    `scripts/generate-aetherpak-config.sh` and commit the updated
    `flatpak/aetherpak-apps.yaml` alongside the new manifest.

### Interdependency Model (Staged Hub-First Builds)

Extension builds depend on the hub app (`io.github.kardbord.dev`) being
available in a Flatpak remote at build time. Each extension's
`aetherpak.yaml` entry configures a `remotes` block pointing at the
Boxes OCI repository (`https://kardbord.github.io/Boxes/kardbord-boxes.flatpakrepo`)
and a `flatpaks` dep that installs the hub before building. AetherPak
auto-injects `--install-deps-from=kardbord-boxes` so flatpak-builder
can resolve the hub's extension point during the build.

Each extension is an independent parallel build cell, preserving per-tool
update granularity and FEDC-driven rebuilds. Because AetherPak has no
cross-cell ordering, the CI workflow stages the build explicitly in three
sequential jobs:

1. **publish-hub** — invokes the reusable publish workflow for the hub app
   alone (`app: io.github.kardbord.dev`) with `deploy: false`. The hub is
   built and pushed to OCI, but the site is uploaded as a plain artifact
   (`aetherpak-site-hub`) rather than deployed to Pages.
2. **deploy-hub-site** — downloads the hub site artifact, re-uploads it as
   a Pages artifact under a distinct name (`github-pages-hub`), and deploys
   it to GitHub Pages. This makes the `.flatpakrepo` file and hub index entry
   available on Pages before any extension builds.
3. **publish-apps** — invokes the reusable publish workflow for the full app
   matrix. Extensions resolve the hub via the now-deployed `.flatpakrepo` on
   Pages (`--install-deps-from=kardbord-boxes`). The reusable workflow
   downloads all `aetherpak-record-*` artifacts (including the hub's), builds
   the complete site, and deploys it to Pages under the default artifact name
   (`github-pages`), overwriting the hub-only site from step 2.

Using distinct Pages artifact names (`github-pages-hub` vs `github-pages`)
avoids a collision that would otherwise occur when two jobs in the same
workflow run both attempt to upload an artifact named `github-pages`.

Consequences of this staged design:

- **No manual bootstrap step.** The hub is (re)published on every push, so a
  brand-new repository, a first-ever push, or a hub change all work on the
  first run.
- **Per-push cost.** Because the hub phase forces a build regardless of change
  detection, each push rebuilds and republishes the (very small, zero-permission)
  hub app and produces two sequential Pages deploys; the second, extension-matrix
  deploy is the authoritative index.
- **Hub failure blocks the extension phase.** If the hub-phase build fails, the
  extension phase does not start (nothing is published), consistent with the
  repository-wide all-or-nothing publish policy.
- **Brief incomplete site window.** During the window between the hub deploy
  (step 2) and the extension-matrix deploy (step 3), the site shows only the
  hub app with no extensions. This window is typically minutes at most.

Local extension builds still require the hub to be installed in a local Flatpak
repo before attempting the build — see the build steps earlier in this document.

## Removing a Package

Removal is a two-step process. The index is cumulative (each deploy seeds from
the previously deployed site and only drops entries whose OCI image no longer
exists in GHCR), so deleting the manifest alone is not sufficient.

1. **Delete the manifest directory**, regenerate the apps config, and commit:
   ```bash
   git rm -r flatpak/manifests/io.github.kardbord.<name>/
   scripts/generate-aetherpak-config.sh
   git add flatpak/aetherpak-apps.yaml
   git commit -m "Remove io.github.kardbord.<name>"
   git push
   ```
   The push triggers a rebuild, but the app remains in the index because its
   image still exists in GHCR.

2. **Delete the OCI image tags from GHCR.** Images are tagged
   `<app-id>-<branch>-<arch>` with `.` in the app-id encoded as `_` (Flatpak
   signature constraint). For `io.github.kardbord.<name>` on `stable`, delete:
   - `io_github_kardbord_<name>-stable-x86_64`
   - `io_github_kardbord_<name>-stable-aarch64`

   Via the GitHub web UI (Packages → `boxes` → delete the tagged versions),
   or via the API:
   ```bash
   # List version IDs for the package
   gh api /user/packages/container/boxes/versions --paginate \
     | jq -r '.[] | "\(.id) \(.metadata.container.tags | join(","))"'
   # Delete by version ID
   gh api --method DELETE /user/packages/container/boxes/versions/<version-id>
   ```

3. The **next successful build** reconciles the index: entries whose image is
   definitively missing from GHCR are dropped. Alternatively, trigger the
   weekly `Prune stale Flatpak OCI images` workflow manually with `dry-run`
   first to confirm what will be removed.

Note that the prune workflow only deletes images *unreferenced* by the index,
so it cannot remove an app on its own — the manual GHCR deletion in step 2 is
what definitively removes the app.

## GPG Key Management

The Flatpak repository is GPG-signed. The private key is stored as the GitHub
Actions secret `FLATPAK_GPG_PRIVATE_KEY`. AetherPak handles the signing via its
`signing` input (default: `auto` — sign when a key is set). The public key and
signature lookaside are published alongside the index on Pages.

### Rotating the Key

1. Generate a new key:
   ```bash
   gpg --batch --gen-key <<EOF
   %no-protection
   Key-Type: RSA
   Key-Length: 4096
   Name-Real: Kardbord Boxes CI
   Name-Email: <email>
   Expire-Date: 0
   %commit
   EOF
   ```

2. Export and update the secret:
   ```bash
   gpg --armor --export-secret-keys <KEY_ID>
   # Update FLATPAK_GPG_PRIVATE_KEY in GitHub repo settings
   ```

3. Existing users will need to re-add the remote:
   ```bash
   flatpak remote-delete kardbord-boxes
   flatpak remote-add --user \
     --signature-lookaside=https://kardbord.github.io/Boxes/sigs \
     kardbord-boxes https://kardbord.github.io/Boxes/kardbord-boxes.flatpakrepo
   ```

## CI concurrency, partial failures, and recovery

- **Builds, prunes, and redeploys serialize.** `flatpak-build.yml`,
  `flatpak-prune.yml`, and `redeploy-pages.yml` share the `flatpak-repo`
  concurrency group (no cancellation). Rapid pushes queue rather than cancel
  each other, and a prune can never race an in-flight build.
- **Hub builds are staged before extensions.** `flatpak-build.yml` runs in
  three sequential stages: `publish-hub` (hub-only build, no Pages deploy),
  `deploy-hub-site` (deploys hub site to Pages under `github-pages-hub`),
  and `publish-apps` (full extension matrix, deploys under `github-pages`).
  The `needs` links enforce order, so the hub is always on Pages before any
  extension resolves it. If the hub phase fails, the extension phase is
  skipped.
- **Two Pages deploys per run, distinct artifact names.** The hub site is
  deployed under `github-pages-hub` and the extension-matrix site under
  `github-pages`. Both target the same Pages environment, so the second
  deploy overwrites the first. During the brief window between deploys, the
  site shows only the hub app (no extensions).
- **Two concurrency layers must stay distinct.** Top-level runs share the
  `flatpak-repo` group; the reusable workflow's Pages-deploy job uses
  `flatpak-repo-deploy` (via `concurrency-group`). These names must never be
  equal — a job-level group matching the top-level group makes GitHub detect a
  deadlock and cancel the run ("Canceling since a deadlock was detected for
  concurrency group").
- **Failed app builds block publishing.** All matrix cells run to completion,
  but if any cell fails, nothing from that run is published or deployed — all
  apps keep their last-good index entries and OCI images. Fix the failure and
  push again (or re-run the workflow) to publish.
- **Missed changes after a failed run:** change detection diffs against
  `github.event.before`. A superseded pending run (GitHub keeps only one
  running and one pending run per concurrency group) is not a problem on
  linear history: the surviving newest run diffs against its own
  `github.event.before`, which covers the skipped pushes. A *failed* run is
  the real loss case — later pushes diff only their own ranges. Re-run the
  workflow manually
  (**Actions → Build and publish Flatpak repository → Run workflow**) — a
  manual dispatch forces a full rebuild of everything.
- **Config drift is caught in CI.** The build workflow regenerates
  `flatpak/aetherpak-apps.yaml` during planning and fails fast if it differs
  from the committed copy. Fix: run `scripts/generate-aetherpak-config.sh`
  and commit the result.
- Touching `.github/workflows/flatpak-build.yml` or
  `scripts/generate-aetherpak-config.sh` also triggers the build workflow, and
  touching the workflow file itself forces a full rebuild.
