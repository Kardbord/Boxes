Name:           breakout
Version:        0
Release:        0%{?dist}
Summary:        A terminal-based clone of the classic brick-breaking arcade game.
License:        MIT
URL:            https://github.com/Kardbord/breakout
Source0:        %{name}-%{version}.tar.gz

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
%cmake -DCMAKE_INSTALL_DOCDIR=%{_docdir}/%{name}
%cmake_build

%install
%cmake_install

%files
%license LICENSE
%{_bindir}/breakout
%dir %{_docdir}/%{name}
%{_docdir}/%{name}/LICENSE

%changelog
