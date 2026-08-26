# Kardbord's Boxes

A collection of custom build specifications for upstream FOSS projects as well
as any projects of my own that I wish to distribute. Builds are handled by the
SUSE Open Build Service (OBS) or GitHub Actions, and binaries are hosted via the
OBS or GitHub Pages. Software built from upstream sources retains its original
license.

## Links

- [GitHub Repository](https://github.com/Kardbord/Boxes)
- [OBS Project](https://build.opensuse.org/project/show/home:Kardbord:Boxes)
- [OBS Mirror](https://src.opensuse.org/Kardbord/Boxes)
- [Homepage (GitHub Pages)](https://kardbord.github.io/Boxes)
- [OCI Index](https://kardbord.github.io/Boxes/index/static)
- [ARCHITECTURE.md](./ARCHITECTURE.md) — how the pipeline works end-to-end
- [docs/OBS-MAINTENANCE.md](./docs/OBS-MAINTENANCE.md) — OBS packaging guide
- [docs/FLATPAK-MAINTENANCE.md](./docs/FLATPAK-MAINTENANCE.md) — Flatpak packaging guide

## Distro Packages

`.rpm` and `.deb` packages are published to
[download.opensuse.org](https://download.opensuse.org/repositories/home:/Kardbord:/Boxes/)
by the Open Build Service and can be added to your system's package manager.
Select the repository that matches your distribution, then install the desired
package by name.

**RPM-based distributions (openSUSE, Rocky Linux, AlmaLinux):**

```bash
REPO_URL="https://download.opensuse.org/repositories/home:/Kardbord:/Boxes/[REPOSITORY]/home:Kardbord:Boxes.repo"

# openSUSE (zypper)
sudo zypper addrepo --refresh "$REPO_URL"

# Rocky Linux / AlmaLinux (dnf)
sudo dnf config-manager --add-repo "$REPO_URL"

# refresh and install a package
sudo zypper refresh   # or: sudo dnf makecache
sudo zypper install [PACKAGE]   # or: sudo dnf install [PACKAGE]
```

**Debian-based distributions (Ubuntu, Debian, Raspbian):**

```bash
REPO_URL="https://download.opensuse.org/repositories/home:/Kardbord:/Boxes/[REPOSITORY]"

# import the repository signing key
curl -fsSL "$REPO_URL/Release.key" | gpg --dearmor \
  | sudo tee /usr/share/keyrings/home_Kardbord_Boxes.gpg > /dev/null

# add the OBS repository for your distribution
echo "deb [signed-by=/usr/share/keyrings/home_Kardbord_Boxes.gpg] $REPO_URL/ ./" \
  | sudo tee /etc/apt/sources.list.d/home:Kardbord:Boxes.list

# refresh and install a package
sudo apt update
sudo apt install [PACKAGE]
```

Replace `[REPOSITORY]` with your distribution's repository name
(e.g. `openSUSE_Tumbleweed`, `RockyLinux_9`, `AlmaLinux_8`, `Debian_13`,
`Ubuntu_26.04`, `Raspbian_13`) and `[PACKAGE]` with a package name.

## Flatpak Repository

Flatpak apps and extensions are hosted as OCI images on GHCR, with the index
and landing page served from [kardbord.github.io/Boxes](https://kardbord.github.io/Boxes).
Extensions (`io.github.kardbord.tool.*`) mount automatically into the
hub app (`io.github.kardbord.dev`).

**Quick start:**

```bash
# Add the remote
flatpak remote-add --if-not-exists --user kardbord-boxes \
  oci+https://kardbord.github.io/Boxes

# Install the hub and a tool extension
flatpak install kardbord-boxes io.github.kardbord.dev
flatpak install kardbord-boxes io.github.kardbord.tool.neovim

# Run neovim with host filesystem access
flatpak run --filesystem=host io.github.kardbord.dev nvim
```

Add or remove `--filesystem=` flags as needed for each app. For language
toolchains (Go, Rust, Java, etc.), install SDK extensions directly from Flathub.

See [docs/FLATPAK-MAINTENANCE.md](./docs/FLATPAK-MAINTENANCE.md) for the
developer and maintainer guide.

## How It Works

<details>
<summary><b>OBS Builds</b></summary>

This repository is the source of truth for the packaging of the projects above.

1. **Source** — Each package directory contains a `_service` file describing where
   the upstream sources come from, plus the packaging files (RPM `.spec`, Debian
   `debian.*`, etc.) needed to build it.
2. **Mirror** — The repository is mirrored to
   [src.opensuse.org](https://src.opensuse.org/Kardbord/Boxes). The Open Build
   Service's `scmsync` integration requires a gitea git host, so it cannot
   consume GitHub directly.
3. **Build** — The OBS project
   [`home:Kardbord:Boxes`](https://build.opensuse.org/project/show/home:Kardbord:Boxes)
   watches the mirror and builds every package for the distribution/architecture
   matrix in the README. New commits trigger rebuilds automatically.
4. **Publish** — Completed binaries are published to
   [download.opensuse.org](https://download.opensuse.org/repositories/home:/Kardbord:/Boxes/),
   from which they can be installed by the commands above.

#### Keeping Upstream Current

Tracked OBS packages stay up to date through the FEDC check workflow, which
scans the `_manifest`-listed packages for upstream releases, updates their
sources, and opens a single pull request. On merge the push to `main` is what
`scmsync`/`obs_scm` pick up to re-fetch upstream and queue a rebuild. See
[docs/OBS-MAINTENANCE.md](./docs/OBS-MAINTENANCE.md) for the maintenance
runbook.

</details>

<details>

<summary><b>Flatpak Builds (AetherPak)</b></summary>

Flatpak packages are built and published using
[AetherPak](https://github.com/aetherpak/actions), which stores application
layers as OCI images in GitHub Container Registry (GHCR) and serves a small
JSON index from GitHub Pages.

1. **Build** — The hub app (`io.github.kardbord.dev`) is built and
   published first, followed by parallel builds of all extensions driven
   by the committed `flatpak/aetherpak-apps.yaml` config.
2. **Publish** — Each package is pushed to GHCR as a signed OCI image. The index
   (`index/static`) is merged and reconciled against the registry, then deployed
   to GitHub Pages along with a landing page and `.flatpakref` files.
3. **Prune** — A scheduled workflow removes stale OCI images from GHCR that are
   no longer referenced in the active index.

Packages are discovered from the `flatpak/manifests/` directory by
`scripts/generate-aetherpak-config.sh`, which emits the committed
`flatpak/aetherpak-apps.yaml` config. Adding or removing a package requires
creating or deleting its manifest directory, re-running the script, and
committing the updated config. See
[docs/FLATPAK-MAINTENANCE.md](./docs/FLATPAK-MAINTENANCE.md) for the guide.

</details>

## Supported Platforms

<details>

<summary><b>Distribution / Architecture matrix</b></summary>

Packages are built for the following distribution and architecture combinations:

| Distribution           | Architectures   |
|------------------------|-----------------|
| openSUSE Tumbleweed    | x86_64, aarch64 |
| Rocky Linux 8 / 9 / 10 | x86_64, aarch64 |
| AlmaLinux 8 / 9 / 10   | x86_64, aarch64 |
| Ubuntu 26.04           | x86_64, aarch64 |
| Debian 13              | x86_64, aarch64 |
| Raspbian 13            | armv7l          |
| Flatpak                | x86_64, aarch64 |

</details>

## Available Packages

<details>

<summary><b>Packages in this repository</b></summary>

The authoritative inventory is discoverable in the repository (`kardbord-breakout/`
for OBS, `flatpak/manifests/` for Flatpak), via the OBS project, or via the
package repositories. Commonly installed packages:

| Package                                                   | Description                                                       | Build Status |
|-----------------------------------------------------------|-------------------------------------------------------------------|--------------|
| [kardbord-breakout](./kardbord-breakout/)                | A terminal-based clone of the classic brick-breaking arcade game. | [![OBS](https://build.opensuse.org/projects/home:Kardbord:Boxes/packages/kardbord-breakout/badge.svg)](https://build.opensuse.org/package/show/home:Kardbord:Boxes/kardbord-breakout) |
| [io.github.kardbord.dev](./flatpak/)                      | Hub app providing the `io.github.kardbord.tool` extension point.  | [![Flatpak Build](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml/badge.svg)](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml) |
| [io.github.kardbord.tool.actionlint](./flatpak/)          | actionlint extension for the hub app.                             | [![Flatpak Build](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml/badge.svg)](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml) |
| [io.github.kardbord.tool.clipboard](./flatpak/)           | clipboard (cb) extension for the hub app.                         | [![Flatpak Build](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml/badge.svg)](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml) |
| [io.github.kardbord.tool.fd](./flatpak/)                  | fd extension for the hub app.                                     | [![Flatpak Build](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml/badge.svg)](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml) |
| [io.github.kardbord.tool.fzf](./flatpak/)                 | fzf extension for the hub app.                                    | [![Flatpak Build](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml/badge.svg)](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml) |
| [io.github.kardbord.tool.git](./flatpak/)                 | git extension for the hub app.                                    | [![Flatpak Build](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml/badge.svg)](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml) |
| [io.github.kardbord.tool.lua](./flatpak/)                 | Lua language extension for the hub app.                           | [![Flatpak Build](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml/badge.svg)](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml) |
| [io.github.kardbord.tool.neovim](./flatpak/)              | Neovim extension for the hub app.                                 | [![Flatpak Build](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml/badge.svg)](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml) |
| [io.github.kardbord.tool.opencode](./flatpak/)            | opencode extension for the hub app.                               | [![Flatpak Build](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml/badge.svg)](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml) |
| [io.github.kardbord.tool.ripgrep](./flatpak/)             | ripgrep extension for the hub app.                                | [![Flatpak Build](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml/badge.svg)](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml) |
| [io.github.kardbord.tool.ruby4](./flatpak/)               | Ruby 4.0 extension for the hub app.                               | [![Flatpak Build](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml/badge.svg)](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml) |
| [io.github.kardbord.tool.sk](./flatpak/)                  | sk (skim) extension for the hub app.                              | [![Flatpak Build](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml/badge.svg)](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml) |
| [io.github.kardbord.tool.treesitter-cli](./flatpak/)      | treesitter-cli extension for the hub app.                         | [![Flatpak Build](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml/badge.svg)](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml) |
| [io.github.kardbord.tool.uv](./flatpak/)                  | uv extension for the hub app.                                     | [![Flatpak Build](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml/badge.svg)](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml) |
| [io.github.kardbord.tool.viu](./flatpak/)                 | viu image viewer extension for the hub app.                       | [![Flatpak Build](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml/badge.svg)](https://github.com/Kardbord/Boxes/actions/workflows/flatpak-build.yml) |

</details>

## License

The packaging configuration in this repository is provided under the MIT License;
see [LICENSE](./LICENSE). Software built from upstream sources retains its original
license.