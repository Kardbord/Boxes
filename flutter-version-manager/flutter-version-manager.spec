Name:           flutter-version-manager
Version:        0
Release:        0%{?dist}
Summary:        FVM (Flutter Version Management) — a version manager for the Flutter SDK
License:        MIT
URL:            https://fvm.app
# Source names are version-free (renamed by the _service download_url
# blocks) so version bumps only touch .upstream.yml/_service and the
# Version: tag that set_version rewrites. The "debian."-prefixed names
# are what debtransform attaches into the Debian source tree; the same
# files are consumed here for the RPM side.
Source0:        fvm-linux-x64.tar.gz
Source1:        debian.fvm-linux-arm64.tar.gz
Source2:        debian.fvm-linux-arm.tar.gz
Source3:        debian.fvm-LICENSE
ExclusiveArch:  x86_64 aarch64

%description
FVM helps you manage multiple Flutter SDK versions per project, caching
installed SDKs and switching between them per workspace. This package
installs the official prebuilt FVM command-line tool as /usr/bin/fvm.
FVM is a third-party tool and is not affiliated with Google or the
Flutter project.

%prep
# The upstream release archives (built by cli_pkg) contain a top-level
# `fvm/` directory; extract the archive matching the build architecture.
# The x64 asset is a single self-contained Dart AOT binary (fvm/fvm);
# the aarch64 asset is the snapshot layout (fvm/fvm wrapper next to
# fvm/src/{dart,fvm.snapshot}). The shipped license is the separately
# downloaded upstream LICENSE (Source3), not the tarball's combined
# dependency license text.
cp %{SOURCE3} fvm-LICENSE
%ifarch x86_64
tar -xf %{SOURCE0}
%endif
%ifarch aarch64
tar -xf %{SOURCE1}
%endif

%build
# Prebuilt Dart artifacts; nothing to build.

%install
# Snapshot-layout assets (wrapper + src/) must be installed as a tree:
# the wrapper resolves its own real path via readlink -f, so a symlink
# from /usr/bin/fvm into the tree works. Single-binary assets go straight
# to /usr/bin/fvm. Detected via the snapshot file so it adapts if
# upstream changes an asset's layout.
if [ -f fvm/src/fvm.snapshot ]; then
  install -d -m 755 %{buildroot}%{_libdir}/flutter-version-manager
  cp -a fvm/. %{buildroot}%{_libdir}/flutter-version-manager/
  ln -s %{_libdir}/flutter-version-manager/fvm %{buildroot}%{_bindir}/fvm
else
  install -Dpm0755 fvm/fvm %{buildroot}%{_bindir}/fvm
fi

%files
%license fvm-LICENSE
%{_bindir}/fvm
%ifarch aarch64
%{_libdir}/flutter-version-manager/
%endif

%changelog
