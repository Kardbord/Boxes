Name:           flutter-version-manager
Version:        0
Release:        0%{?dist}
Summary:        FVM (Flutter Version Management) — a version manager for the Flutter SDK
License:        MIT
URL:            https://fvm.app
Source0:        fvm-%{version}-linux-x64.tar.gz
Source1:        fvm-%{version}-linux-arm64.tar.gz
Source2:        fvm-%{version}-linux-arm.tar.gz
Source3:        fvm-LICENSE
ExclusiveArch:  x86_64 aarch64

%description
FVM helps you manage multiple Flutter SDK versions per project, caching
installed SDKs and switching between them per workspace. This package
installs the official prebuilt FVM command-line tool as /usr/bin/fvm.
FVM is a third-party tool and is not affiliated with Google or the
Flutter project.

%prep
# The upstream release archives (built by cli_pkg) contain a top-level
# `fvm/` directory holding the prebuilt binary; extract the archive
# matching the build architecture. The shipped license is the separately
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
# Prebuilt Dart AOT binary; nothing to build.

%install
install -Dpm0755 fvm/fvm %{buildroot}%{_bindir}/fvm

%files
%license fvm-LICENSE
%{_bindir}/fvm

%changelog
