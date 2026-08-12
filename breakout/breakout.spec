Name:           breakout
Version:        0
Release:        0
Summary:        A Breakout game that runs in the terminal
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
A cheap imitation of the classic Breakout game that runs in the terminal.
Built with C++17 and the FTXUI UI library. Not affiliated with Atari in
any way.

%prep
%setup -q
%patch0 -p1

%build
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build

%install
install -D -m0755 build/breakout %{buildroot}%{_bindir}/breakout

%files
%{_bindir}/breakout

%changelog
