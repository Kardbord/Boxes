#!/bin/bash
# Render OBS _service files for prebuilt-binary packages.
#
# For every package listed in the top-level _manifest that has both a FEDC
# tracking manifest (.upstream.yml with `type: archive` sources) and an OBS
# service template (_service.in), this script:
#
#   1. Derives the pinned upstream version from the archive source URLs
#      (https://.../releases/download/<version>/<file>); all archive
#      sources must agree on the version.
#   2. Builds a filename -> sha256 map from the same sources.
#   3. Renders _service.in with every {{UPSTREAM_VERSION}} replaced by the
#      version and every {{SHA256:<filename>}} replaced by the matching
#      checksum.
#   4. Writes the result as _service only when it differs from the current
#      file, so the script is idempotent.
#
# The FEDC workflow runs this script after rewriting .upstream.yml so the
# upstream-update PR keeps the _service files in sync automatically.
#
# Packages without a .upstream.yml/_service.in pair (e.g. source-built
# packages like kardbord-breakout that use obs_scm) are skipped.
#
# Usage:
#   scripts/sync-obs-services.sh           # sync all eligible packages
#   scripts/sync-obs-services.sh mypkg     # sync a single package
#
# Requires: bash >= 4, yq (mikefarah v4).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO_ROOT/_manifest"

info() { printf 'sync-obs-services: %s\n' "$*"; }
die() {
  printf 'sync-obs-services: ERROR: %s\n' "$*" >&2
  exit 1
}

packages=()
if [ "$#" -gt 0 ]; then
  packages=("$@")
else
  while IFS= read -r pkg; do
    [ -n "$pkg" ] && packages+=("$pkg")
  done < <(yq -r '.packages[]' "$MANIFEST")
fi

if [ "${#packages[@]}" -eq 0 ]; then
  die "no packages found in _manifest"
fi

synced=0
skipped=0
for pkg in "${packages[@]}"; do
  dir="$REPO_ROOT/$pkg"
  upstream="$dir/.upstream.yml"
  template="$dir/_service.in"
  service="$dir/_service"

  if [ ! -f "$upstream" ] || [ ! -f "$template" ]; then
    info "skipping $pkg: no .upstream.yml/_service.in pair (not a prebuilt-binary package)"
    skipped=$((skipped + 1))
    continue
  fi

  # Build the filename -> sha256 map and the agreed-on version.
  declare -A checksums=()
  version=""
  while IFS=$'\t' read -r url sha; do
    [ -n "$url" ] || continue
    file="${url##*/}"
    if [ -z "$sha" ] || [ "$sha" = "null" ]; then
      die "$pkg: archive source $file has no sha256 in .upstream.yml"
    fi
    if [ -n "${checksums[$file]+x}" ]; then
      die "$pkg: duplicate archive source for $file"
    fi
    checksums["$file"]="$sha"

    if [[ ! "$url" =~ /releases/download/([^/]+)/ ]]; then
      die "$pkg: cannot derive the version from URL $url (expected the /releases/download/<version>/... shape)"
    fi
    v="${BASH_REMATCH[1]}"
    if [ -z "$version" ]; then
      version="$v"
    elif [ "$version" != "$v" ]; then
      die "$pkg: mismatched versions across archive sources ($version vs $v)"
    fi
  done < <(yq -r '.modules[].sources[] | select(.type == "archive") | [.url, .sha256] | @tsv' "$upstream")

  if [ "${#checksums[@]}" -eq 0 ]; then
    die "$pkg: no type: archive sources found in .upstream.yml"
  fi

  # Pass 1: substitute the version.
  rendered="$(<"$template")"
  rendered="${rendered//"{{UPSTREAM_VERSION}}"/$version}"

  # Pass 2: substitute checksum placeholders (their keys embed the version,
  # so they are only resolvable after pass 1).
  while [[ "$rendered" == *'{{SHA256:'* ]]; do
    key="${rendered#*'{{SHA256:'}"
    key="${key%%'}}'*}"
    placeholder="{{SHA256:$key}}"
    if [ -z "${checksums[$key]+x}" ]; then
      die "$pkg: no archive source in .upstream.yml matches checksum placeholder $placeholder"
    fi
    rendered="${rendered//"$placeholder"/${checksums[$key]}}"
  done

  # Guard against unresolved placeholders (e.g. typos in the template).
  if [[ "$rendered" == *'{{UPSTREAM_VERSION}}'* || "$rendered" == *'{{SHA256:'* ]]; then
    die "$pkg: unresolved placeholders in rendered _service"
  fi

  # Every tracked archive source must still be referenced by the template;
  # otherwise a renamed upstream asset could silently drop verification.
  for file in "${!checksums[@]}"; do
    if [[ "$rendered" != *"$file"* ]]; then
      die "$pkg: archive source $file is not referenced by _service.in"
    fi
  done

  if [ -f "$service" ] && [ "$(<"$service")" = "$rendered" ]; then
    info "$pkg: _service is up to date ($version)"
  else
    printf '%s\n' "$rendered" >"$service"
    info "$pkg: updated _service for $version"
  fi
  synced=$((synced + 1))
  unset checksums
done

info "done: $synced synced, $skipped skipped"
