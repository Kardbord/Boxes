# Boxes

A collection of custom build specifications for upstream FOSS projects as well
as any projects of my own that I wish to distribute. Builds are handled by the
SUSE Open Build Service (OBS) or GitHub Actions, and binaries are hosted via the
OBS or GitHub Pages. Software built from upstream sources retains its original
license.

## Available Packages

| Package               | Description                                                       | Build Status                                                                                                                                                        |
|-----------------------|-------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [breakout](breakout/) | A terminal-based clone of the classic brick-breaking arcade game. | [![OBS](https://build.opensuse.org/projects/home:Kardbord:Boxes/packages/breakout/badge.svg)](https://build.opensuse.org/package/show/home:Kardbord:Boxes/breakout) |

## Supported Platforms

Packages are built for the following distribution and architecture combinations:

| Distribution           | Architectures   |
|------------------------|-----------------|
| openSUSE Tumbleweed    | x86_64, aarch64 |
| Rocky Linux 8 / 9 / 10 | x86_64, aarch64 |
| AlmaLinux 8 / 9 / 10   | x86_64, aarch64 |
| Ubuntu 26.04           | x86_64, aarch64 |
| Debian 13              | x86_64, aarch64 |
| Raspbian 13            | armv7l          |

## Installation

Packages are published to [download.opensuse.org](https://download.opensuse.org/repositories/home:/Kardbord:/Boxes/)
by the Open Build Service and can be added to your system's package manager.
Select the repository that matches your distribution, then install the desired package
by name.

**RPM-based distributions (openSUSE, Rocky Linux, AlmaLinux):**

```bash
REPO_URL="https://download.opensuse.org/repositories/home:/Kardbord:/Boxes/<REPOSITORY>/home:Kardbord:Boxes.repo"

# openSUSE (zypper)
sudo zypper addrepo --refresh "$REPO_URL"

# Rocky Linux / AlmaLinux (dnf)
sudo dnf config-manager --add-repo "$REPO_URL"

# refresh and install a package
sudo zypper refresh   # or: sudo dnf makecache
sudo zypper install <PACKAGE>   # or: sudo dnf install <PACKAGE>
```

**Debian-based distributions (Ubuntu, Debian, Raspbian):**

```bash
REPO_URL="https://download.opensuse.org/repositories/home:/Kardbord:/Boxes/<REPOSITORY>"

# import the repository signing key
curl -fsSL "$REPO_URL/Release.key" | gpg --dearmor \
  | sudo tee /usr/share/keyrings/home_Kardbord_Boxes.gpg > /dev/null

# add the OBS repository for your distribution
echo "deb [signed-by=/usr/share/keyrings/home_Kardbord_Boxes.gpg] $REPO_URL/ ./" \
  | sudo tee /etc/apt/sources.list.d/home:Kardbord:Boxes.list

# refresh and install a package
sudo apt update
sudo apt install <PACKAGE>
```

Replace `<REPOSITORY>` with your distribution's repository name (e.g. `openSUSE_Tumbleweed`,
`RockyLinux_9`, `AlmaLinux_8`, `Debian_13`, `Ubuntu_26.04`, `Raspbian_13`) and `<PACKAGE>`
with a package name from the table above.

<details>
<summary><b>How It Works</b></summary>

This repository is the source of truth for the packaging of the projects listed
above.

1. **Source** — Each package directory contains a `_service` file describing where
   the upstream sources come from, plus the packaging files (RPM `.spec`, Debian
   `debian.*`, etc.) needed to build it.
2. **Mirror** — The repository is mirrored to [src.opensuse.org](https://src.opensuse.org/Kardbord/Boxes).
    The Open Build Service's `scmsync` integration requires a gitea git host,
    so it cannot consume GitHub directly.
3. **Build** — The OBS project [`home:Kardbord:Boxes`](https://build.opensuse.org/project/show/home:Kardbord:Boxes)
   watches the mirror and builds every package for the distribution/architecture
   matrix above. New commits trigger rebuilds automatically.
4. **Publish** — Completed binaries are published to
   [download.opensuse.org](https://download.opensuse.org/repositories/home:/Kardbord:/Boxes/),
   from which they can be installed by the commands above.

See [ARCHITECTURE.md](ARCHITECTURE.md) for a detailed deep-dive into the pipeline,
configuration files, and the cross-distribution packaging infrastructure.

</details>

## License

The packaging configuration in this repository is provided under the MIT License;
see [LICENSE](./LICENSE). Software built from upstream sources retains its original
license.
