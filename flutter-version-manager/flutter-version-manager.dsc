Format: 3.0 (quilt)
# debtransform wiring for the multi-tarball prebuilt layout. Do not put
# ":" characters in these comments: dsc paragraphs are colon-parsed.
# DEBTRANSFORM-TAR names the orig tarball (required: with three per-arch
# tarballs the auto-discovery would fail with "Too many files looking like
# a usable source tarball"). DEBTRANSFORM-FILES attaches the other assets
# into the source tree at debian/<name> (debtransform maps "debian.<name>"
# to "debian/<name>"); they are what debian.rules consumes. Filename
# references here are version-free, so version bumps do not touch this
# file beyond the Version: line that set_version rewrites.
DEBTRANSFORM-TAR: fvm-linux-x64.tar.gz
DEBTRANSFORM-FILES: debian.fvm-linux-x64.tar.gz debian.fvm-linux-arm64.tar.gz debian.fvm-linux-arm.tar.gz
Source: flutter-version-manager
Binary: flutter-version-manager
Architecture: amd64 arm64 armhf
Version: 4.3.2-1
Standards-Version: 4.6.2
Build-Depends: debhelper-compat (= 13)
Homepage: https://fvm.app
Package-List:
 flutter-version-manager deb utils optional arch=amd64,arm64,armhf
