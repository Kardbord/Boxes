Format: 3.0 (quilt)
# debtransform wiring for the multi-tarball prebuilt layout. Do not use
# colons in these comments - dsc paragraphs are colon-parsed and a colon
# in a comment line would be re-emitted into the published dsc as a
# bogus tag. DEBTRANSFORM-TAR names the orig tarball (with three per-arch
# tarballs the auto-discovery would fail with a "Too many files" error);
# the amd64 rules install the binary straight from its extracted fvm/
# directory. DEBTRANSFORM-FILES attaches the arm64/arm tarballs into the
# source tree for the armhf/arm64 rules. Filenames are version-free so
# version bumps do not touch this file beyond the Version line that
# set_version rewrites. Note that every DEBTRANSFORM-FILES entry must
# exist as a package source file (a download_url filename param), and
# debtransform does not check the attach exit status, so a missing file
# fails silently - the armhf/arm64 builds would then die later in rules.
DEBTRANSFORM-TAR: fvm-linux-x64.tar.gz
DEBTRANSFORM-FILES: debian.fvm-linux-arm64.tar.gz debian.fvm-linux-arm.tar.gz
Source: flutter-version-manager
Binary: flutter-version-manager
Architecture: amd64 arm64 armhf
Version: 4.3.2-1
Standards-Version: 4.6.2
Build-Depends: debhelper-compat (= 13)
Homepage: https://fvm.app
Package-List:
 flutter-version-manager deb utils optional arch=amd64,arm64,armhf
