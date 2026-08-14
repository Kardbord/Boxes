Name:           kardbord-breakout
Version:        0
Release:        0%{?dist}
Summary:        A terminal-based clone of the classic brick-breaking arcade game.
License:        MIT
URL:            https://github.com/Kardbord/breakout
Source0:        breakout-%{version}.tar.gz

BuildRequires:  cmake >= 3.26
BuildRequires:  gcc-c++
BuildRequires:  make

%description
A terminal-based clone of the classic brick-breaking arcade game.
Built with C++17 and the FTXUI UI library. Not affiliated with
Atari in any way.

%prep
%autosetup

%build
%if 0%{?rhel} && 0%{?rhel} <= 8
%cmake -DCMAKE_INSTALL_DOCDIR=%{_docdir}/kardbord-breakout -DCMAKE_CXX_FLAGS="-Wno-type-limits"
%else
%cmake -DCMAKE_INSTALL_DOCDIR=%{_docdir}/kardbord-breakout
%endif
%cmake_build

%install
%cmake_install

%files
%license LICENSE
%{_bindir}/kb-breakout
%dir %{_docdir}/kardbord-breakout
%{_docdir}/kardbord-breakout/LICENSE

%changelog
