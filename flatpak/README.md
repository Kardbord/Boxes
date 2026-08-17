# Flatpak — Developer & Maintainer Guide

This directory contains the Flatpak packaging infrastructure for the Boxes project.
User-facing installation instructions are on the [landing page](https://kardbord.github.io/Boxes/).

## Architecture

### Runtime Hierarchy

```
org.freedesktop.Platform / org.freedesktop.Sdk (upstream)
  └── io.github.kardbord.Platform / io.github.kardbord.Sdk (custom)
        └── io.github.kardbord.neovim, ... (apps)
```

All `io.github.kardbord.*` apps use the custom runtime, which provides the
`io.github.kardbord.tool` extension point.

### Extension Points

The custom runtime (`io.github.kardbord.Sdk`) declares the
`io.github.kardbord.tool` extension point. Any app built on
`io.github.kardbord.Platform` inherits it automatically — apps do not need to
declare it themselves.

Extensions with IDs matching `io.github.kardbord.tool.*` are automatically
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

Two mechanisms detect upstream changes:

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

5. **Add x-checker-data to the manifest** (shown above) so FEDC can auto-update it.

6. **Commit and push**: The `flatpak-build.yml` workflow auto-discovers the new
   manifest and builds it.

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

6. **Commit and push**: The `flatpak-build.yml` workflow auto-discovers the new
   manifest and builds it.

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

The Flatpak repo is GPG-signed. The private key is stored as the GitHub Actions
secret `FLATPAK_GPG_PRIVATE_KEY`. The public key is embedded in
`kardbord.flatpakrepo`.

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

3. Update the public key in `kardbord.flatpakrepo`:
   ```bash
   gpg --export <KEY_ID> | base64 --wrap=0
   ```

4. Existing users will need to re-add the remote:
   ```bash
   flatpak remote-delete kardbord
   flatpak remote-add --if-not-exists kardbord https://kardbord.github.io/Boxes/kardbord.flatpakrepo
   ```

## Troubleshooting

### Extension not found in app

Verify the extension is installed and the ID matches:
```bash
flatpak list --app --extensions | grep kardbord
flatpak info io.github.kardbord.tool.ripgrep
```

### Tool not on PATH inside app

Apps that use `base: io.neovim.nvim` get `ide-flatpak-wrapper`, which adds
`/app/tools/*/bin` to PATH. For other apps, verify the app's entrypoint does
the same. Check the mount:
```bash
flatpak run --command=sh io.github.kardbord.neovim -c "ls /app/tools/"
```

### FEDC not detecting updates

Check that `x-checker-data` annotations are correct in the manifest. The
`url-query` must be a valid jq expression matching the GitHub Releases API
response structure.
