Name:           breakout
Version:        0
Release:        0%{?dist}
Summary:        A terminal-based clone of the classic brick-breaking arcade game.
License:        MIT
URL:            https://github.com/Kardbord/breakout
Source0:        %{name}-%{version}.tar.xz
Patch0:         breakout-cmake-min-3.26.patch
BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  git
BuildRequires:  glibc-devel
BuildRequires:  make

%description
A terminal-based clone of the classic brick-breaking arcade game.
Built with C++17 and the FTXUI UI library. Not affiliated with
Atari in any way.

%prep
%autosetup -p1

%build
%cmake -DCMAKE_SKIP_RPATH:BOOL=ON -DCMAKE_BUILD_TYPE=Release
%cmake_build

%install
install -D -m0755 %{_vpath_builddir}/breakout %{buildroot}%{_bindir}/breakout

%files
%{_bindir}/breakout

%changelog
