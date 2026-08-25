# Flatpak — Developer & Maintainer Guide

This document is the operational guide for maintaining the Flatpak packaging
infrastructure in this repository. For a deep-dive into how the pipeline fits
together end-to-end, see [ARCHITECTURE.md](../ARCHITECTURE.md).

User-facing installation instructions are on the [landing page](https://kardbord.github.io/Boxes/).

## Architecture

This guide intentionally omits the full runtime/extension-point walkthrough
(the custom `io.github.kardbord.Platform`/`io.github.kardbord.Sdk` runtimes and
the `io.github.kardbord.tool` extension point are documented in
[ARCHITECTURE.md](../ARCHITECTURE.md#custom-runtime)). In short:

- All `io.github.kardbord.*` apps run on the custom runtime, which provides the
  `io.github.kardbord.tool` extension point.
- Extensions with IDs matching `io.github.kardbord.tool.*` are automatically
  mounted into the app sandbox.

### Sandbox Permissions Policy

All `io.github.kardbord.*` apps use a minimal sandbox. Only the host access an
app needs to function is granted — nothing more. This means some apps ship with
no host filesystem access by default.

Users must pass explicit filesystem arguments at runtime:

```bash
# Access only the user's home directory
flatpak run --filesystem=home io.github.kardbord.ripgrep <args>

# Access the entire host filesystem
flatpak run --filesystem=host io.github.kardbord.ripgrep <args>
```

When adding a new app, grant only the permissions the app needs to function in
`finish-args`. Do not add blanket permissions like `--filesystem=host` unless
the app cannot function without it.

### The `base` Field

Apps can use `base:` to inherit the entire build output of a Flathub app. For
example, `io.github.kardbord.neovim` uses `base: io.neovim.nvim`:

- All upstream modules (binaries, libraries, wrappers, etc.) are inherited
- The custom manifest only needs to specify the app ID, `finish-args`, and `add-extensions`
- `finish-args` must be re-specified in full (they replace, not merge from base)
- `base-version: stable` resolves dynamically to the latest Flathub stable commit at build time

### Upstream Tracking

Upstream sources for extensions are tracked by the FEDC check workflow, which
uses `flatpak-external-data-checker` (FEDC) with the `x-checker-data`
annotations in manifests to detect new upstream releases. FEDC updates the
manifests in-place and opens a single PR with all changes for review before
merging. Merging the PR pushes to `main`, which triggers a rebuild of the
affected Flatpak packages. See
[ARCHITECTURE.md](../ARCHITECTURE.md#upstream-tracking) for the full mechanism.

## Adding a New Extension

1. **Create a directory**: `flatpak/manifests/io.github.kardbord.tool.<name>/`

2. **Write the manifest** (`io.github.kardbord.tool.<name>.yml`):
   ```yaml
   id: io.github.kardbord.tool.<name>
   branch: stable
   runtime: io.github.kardbord.Platform
   runtime-version: 'stable'
   sdk: io.github.kardbord.Sdk
   build-extension: true
   separate-locales: false

   modules:
     - name: <name>
       buildsystem: simple
       build-commands:
         - install -Dm755 <binary> /app/tools/<name>/bin/<binary>
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
   `flatpak/aetherpak-apps.yaml` alongside the new manifest. The config must
   stay complete (SDK/Platform included) — AetherPak's reconcile prunes index
   entries for apps not listed in the config.

## Adding a New App

1. **Create a directory**: `flatpak/manifests/io.github.kardbord.<name>/`

2. **Write the manifest** (`io.github.kardbord.<name>.yml`):
   ```yaml
   id: io.github.kardbord.<name>
   branch: stable
   runtime: io.github.kardbord.Platform
   runtime-version: 'stable'
   sdk: io.github.kardbord.Sdk
   command: <name>

   modules:
     - name: <name>
       buildsystem: simple
       build-commands:
         - install -Dm755 <wrapper-script> ${FLATPAK_DEST}/bin/<name>
       sources:
         - type: file
           path: <wrapper-script>

   cleanup-commands:
     - mkdir -p ${FLATPAK_DEST}/lib/kardbord-tools
     - mkdir -p ${FLATPAK_DEST}/lib/sdk
   ```

   The `cleanup-commands` entry is required for **all** apps on this runtime,
   whether or not they actively use tool extensions. It creates the parent
   directory for the `io.github.kardbord.tool` extension mount point. Without
   it, bwrap will fail with a read-only filesystem error when mounting any
   extension — including ones installed separately by the user.

   If the app **requires** a specific tool extension to function (i.e. it will
   not work without it), add an explicit `add-extensions` override to force
   auto-download of that extension:
   ```yaml
   add-extensions:
     io.github.kardbord.tool.<name>:
       directory: lib/kardbord-tools/<name>
       version: stable
   ```

   If the extension is optional (the app works without it), omit the
   `add-extensions` override. The extension point is inherited from the runtime,
   so optional extensions installed by the user will still be mounted
   automatically. The `cleanup-commands` entry ensures the mount point exists in
   either case.

3. **Create the wrapper script** (if the app uses tool extensions): Use
   `activate-kardbord-env` to set up PATH for tool extensions, then exec the
   real command:
   ```sh
   #!/bin/sh
   exec activate-kardbord-env <command> "$@"
   ```

   If the app does not use any tool extensions, set `command` directly to the
   app's binary — no wrapper script is needed. The `cleanup-commands` entry is
   still required in either case.

4. **Follow the [Sandbox Permissions Policy](#sandbox-permissions-policy)**:
   grant only the host access the app needs in `finish-args`.

5. **Test locally**:
   ```bash
   flatpak-builder --force-clean --user --install-deps-from=flathub \
     --repo=test-repo build-dir \
     flatpak/manifests/io.github.kardbord.<name>/io.github.kardbord.<name>.yml
   ```

6. **Regenerate and commit the apps config**: Run
   `scripts/generate-aetherpak-config.sh` and commit the updated
   `flatpak/aetherpak-apps.yaml` alongside the new manifest. The config must
   stay complete (SDK/Platform included) — AetherPak's reconcile prunes index
   entries for apps not listed in the config.

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

### Building the Custom Runtime

Before building apps or extensions, build and install the custom runtime:

```bash
flatpak-builder --force-clean --user --install-deps-from=flathub \
  --repo=repo build-dir \
  flatpak/manifests/io.github.kardbord.Sdk/io.github.kardbord.Sdk.yml
```

### Building an Extension

```bash
flatpak-builder --force-clean --user --install-deps-from=flathub \
  --repo=repo build-dir \
  flatpak/manifests/io.github.kardbord.tool.ripgrep/io.github.kardbord.tool.ripgrep.yml
```

### Building the Neovim App

```bash
flatpak-builder --force-clean --user --install-deps-from=flathub \
  --repo=repo build-dir \
  flatpak/manifests/io.github.kardbord.neovim/io.github.kardbord.neovim.yml
```

### Testing Locally

```bash
flatpak --user remote-add --no-gpg-verify local-repo repo
flatpak --user install local-repo io.github.kardbord.neovim
flatpak run --command=sh io.github.kardbord.neovim -c "which rg"
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

## Troubleshooting

### CI concurrency, partial failures, and recovery

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

### Extension not found in app

Verify the extension is installed and the ID matches:
```bash
flatpak list --app --extensions | grep kardbord
flatpak info io.github.kardbord.tool.ripgrep
```

### Tool not on PATH inside the app

Apps that use `base:` (e.g. `io.neovim.nvim`) get a wrapper that adds
`/app/tools/*/bin` to PATH. For other apps, verify the app's entrypoint does
the same. Check the mount:
```bash
flatpak run --command=sh io.github.kardbord.neovim -c "ls /app/tools/"
```

### FEDC not detecting updates

Check that the `x-checker-data` annotations are correct in the manifest. The
`url-query` must be a valid jq expression matching the GitHub Releases API
response structure.