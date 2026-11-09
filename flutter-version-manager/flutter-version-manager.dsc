Format: 3.0 (quilt)
# Names the upstream tarball debtransform must use as the orig tarball.
# Required because this package ships three per-arch tarballs, which
# would otherwise fail debtransform's auto-discovery with "Too many files
# looking like a usable source tarball". The tarballs not named here stay
# in the package sources and are staged into the build root unchanged,
# where debian.rules picks them per architecture.
DEBTRANSFORM-TAR: fvm-4.3.2-linux-x64.tar.gz
Source: flutter-version-manager
Binary: flutter-version-manager
Architecture: amd64 arm64 armhf
Version: 4.3.2-1
Standards-Version: 4.6.2
Build-Depends: debhelper-compat (= 13)
Homepage: https://fvm.app
Package-List:
 flutter-version-manager deb utils optional arch=amd64,arm64,armhf
