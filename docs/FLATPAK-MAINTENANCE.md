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
- `no-autodownload: true` — extensions are not auto-installed with the hub
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
   runtime: org.freedesktop.Platform
   runtime-version: '25.08'
   sdk: org.freedesktop.Sdk
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
             url-query: '.assets[] | select(.name | test("x86_64-unknown-linux-musl\\.tar\\.gz$")) | .browser_download_url'
         - type: archive
           only-arches: [aarch64]
           url: <upstream-aarch64-url>
           sha256: <sha256>
           x-checker-data:
             type: json
             url: https://api.github.com/repos/<owner>/<repo>/releases/latest
             version-query: '.tag_name | sub("^v"; "")'
             url-query: '.assets[] | select(.name | test("aarch64-unknown-linux-musl\\.tar\\.gz$")) | .browser_download_url'
   ```

3. **Get sha256 checksums**: Fetch from the GitHub API:
   ```
   curl -s https://api.github.com/repos/<owner>/<repo>/releases/latest \
     | jq -r '.assets[] | select(.name | test("musl")) | "\(.name) \(.digest)"'
   ```

4. **Test locally**:
   ```bash
   flatpak-builder --force-clean --user --install-deps-from=flathub \
     --repo=test-repo build-dir \
     flatpak/manifests/io.github.kardbord.tool.<name>/io.github.kardbord.tool.<name>.yml
   ```

5. **Add x-checker-data to the manifest** (shown above) so the
   FEDC check workflow can detect upstream updates.

6. **Regenerate and commit the apps config**: Run
   `scripts/generate-aetherpak-config.sh` and commit the updated
   `flatpak/aetherpak-apps.yaml` alongside the new manifest.

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

## Local Development

### Prerequisites

```bash
sudo apt install flatpak flatpak-builder   # Debian-family
# or
sudo dnf install flatpak flatpak-builder   # RedHat-family
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install flathub org.freedesktop.Sdk//25.08
flatpak install flathub org.freedesktop.Platform//25.08
```

### Building the Hub App

```bash
flatpak-builder --force-clean --user --install-deps-from=flathub \
  --repo=repo build-dir \
  flatpak/manifests/io.github.kardbord.dev/io.github.kardbord.dev.yml
```

### Building an Extension

```bash
flatpak-builder --force-clean --user --install-deps-from=flathub \
  --repo=repo build-dir \
  flatpak/manifests/io.github.kardbord.tool.ripgrep/io.github.kardbord.tool.ripgrep.yml
```

### Testing Locally

```bash
flatpak --user remote-add --no-gpg-verify local-repo repo
flatpak --user install local-repo io.github.kardbord.dev
flatpak --user install local-repo io.github.kardbord.tool.ripgrep
flatpak run --command=sh io.github.kardbord.dev -c "which rg"
```

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
