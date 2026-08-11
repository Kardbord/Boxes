# KardbordBox OBS project meta

The current authoritative project meta for `home:Kardbord:KardbordBox` on
build.opensuse.org, with comments. This file is informational only — it is
**not** consumed by scmsync. The project meta must be applied on the OBS
side (see below), because scmsync does not sync project meta from the
repository.

Note: XML comments may be stripped by OBS when the meta is normalized on
save, so the comments here are annotations, not a guarantee of what you
see when you read the meta back.

## Apply

```
osc meta prj --edit home:Kardbord:KardbordBox
```

or via the WebUI (project → Advanced → meta), keeping the existing
`<scmsync>`.

## Meta

```xml
<project name="home:Kardbord:KardbordBox">
  <title>KardbordBox</title>
  <description>A collection of custom build specifications for upstream FOSS projects as well as any projects of my own that I wish to distribute. Builds are handled by the SUSE Open Build Service (OBS) or GitHub Actions, and binaries are hosted via the OBS or github pages. Software built from upstream sources retains its original license.
  </description>

  <!-- scmsync: pull the full project from GitHub. Every top-level directory
       in the repo becomes a package; the top-level _config becomes the
       project's build config (prjconf). OBS reads FROM GitHub, never writes. -->
  <scmsync>https://github.com/Kardbord/KardbordBox.git</scmsync>

  <!-- Ownership of THIS project (home:Kardbord:KardbordBox) and all its
       auto-created packages. maintainer = can administer; bugowner = owns
       bug/bounce target. Not needed in _config (prjconf has no roles). -->
  <person userid="Kardbord" role="maintainer"/>
  <person userid="Kardbord" role="bugowner"/>

  <!-- Each <repository> = one build target + one publish directory.
       Binary output lands in download.opensuse.org/repositories/home:/Kardbord:/KardbordBox/<name>/ -->

  <!-- Tumbleweed (x86_64). Path is the build DEPENDENCY: binaries read from
       openSUSE:Factory's 'snapshot' repo; nothing is written back. -->
  <repository name="openSUSE_Tumbleweed">
    <path project="openSUSE:Factory" repository="snapshot"/>
    <arch>x86_64</arch>
  </repository>

  <!-- Tumbleweed for ARM: the snapshot repo only mirrors x86_64/i586, so
       aarch64 comes from the separate openSUSE:Factory:ARM project. -->
  <repository name="openSUSE_Tumbleweed_ARM">
    <path project="openSUSE:Factory:ARM" repository="standard"/>
    <arch>aarch64</arch>
  </repository>

  <!-- RHEL rebuilds. Rocky 8/9/10 and Alma 8/9/10 are near-identical
       toolchains; kept for full version-lineage coverage.
       arch x86_64 + aarch64 covers Intel/AMD and ARM hardware. -->
  <repository name="RockyLinux_8">
    <path project="RockyLinux:8" repository="standard"/>
    <arch>x86_64</arch>
    <arch>aarch64</arch>
  </repository>
  <repository name="RockyLinux_9">
    <path project="RockyLinux:9" repository="standard"/>
    <arch>x86_64</arch>
    <arch>aarch64</arch>
  </repository>
  <repository name="RockyLinux_10">
    <path project="RockyLinux:10" repository="standard"/>
    <arch>x86_64</arch>
    <arch>aarch64</arch>
  </repository>

  <repository name="AlmaLinux_8">
    <path project="AlmaLinux:8" repository="standard"/>
    <arch>x86_64</arch>
    <arch>aarch64</arch>
  </repository>
  <repository name="AlmaLinux_9">
    <path project="AlmaLinux:9" repository="standard"/>
    <arch>x86_64</arch>
    <arch>aarch64</arch>
  </repository>
  <repository name="AlmaLinux_10">
    <path project="AlmaLinux:10" repository="standard"/>
    <arch>x86_64</arch>
    <arch>aarch64</arch>
  </repository>

  <!-- Ubuntu 26.04 LTS. Multiple <path> entries = layered dependency repos,
       searched top-down. 'standard' carries base/main packages, 'universe'
       the community archive, then update + backports streams. -->
  <repository name="Ubuntu_26.04">
    <path project="Ubuntu:26.04" repository="standard"/>
    <path project="Ubuntu:26.04" repository="universe"/>
    <path project="Ubuntu:26.04" repository="update"/>
    <path project="Ubuntu:26.04" repository="universe-update"/>
    <path project="Ubuntu:26.04" repository="backports"/>
    <path project="Ubuntu:26.04" repository="universe-backports"/>
    <arch>x86_64</arch>
    <arch>aarch64</arch>
  </repository>

  <!-- Debian 13 (trixie). aarch64 also covers 64-bit Raspberry Pi OS,
       which is plain Debian. -->
  <repository name="Debian_13">
    <path project="Debian:13" repository="standard"/>
    <arch>x86_64</arch>
    <arch>aarch64</arch>
  </repository>

  <!-- Raspbian 13 = 32-bit Pi OS (armv7l); armv7l only, matching that repo. -->
  <repository name="Raspbian_13">
    <path project="Raspbian:13" repository="standard"/>
    <arch>armv7l</arch>
  </repository>
</project>
```