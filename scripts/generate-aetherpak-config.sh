#!/bin/bash
set -euo pipefail

# Generate flatpak/aetherpak-apps.yaml from flatpak/manifests/*/
#
# Scans the manifests directory and produces an AetherPak config for all
# packages. The config is committed to the repository — adding or removing
# a package requires creating or deleting its manifest directory, re-running
# the script, and committing the updated config.
#
# Usage:
#   scripts/generate-aetherpak-config.sh   # Write flatpak/aetherpak-apps.yaml

# Pin the locale to C so glob ordering of the manifests directory (and thus
# the emitted app order) is byte-order deterministic regardless of the host
# locale. Without this, LC_COLLATE=en_US.* interleaves case (sk < Sdk < tool)
# while CI's C.UTF-8 collates uppercase first, producing a spurious diff in
# the workflow's config-sync guard. LC_ALL is used (not LC_COLLATE) because
# an inherited LC_ALL would otherwise take precedence.
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFESTS_DIR="$REPO_ROOT/flatpak/manifests"
OUTPUT="$REPO_ROOT/flatpak/aetherpak-apps.yaml"

generate() {
  cat <<'HEADER'
remote_name: kardbord-boxes
defaults:
  remotes:
    flathub: https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpaks:
    - remote: flathub
      ref: org.freedesktop.Sdk//25.08
apps:
HEADER

  for dir in "$MANIFESTS_DIR"/*/; do
    name="$(basename "$dir")"

    # Find the manifest file (matches directory name)
    manifest="$dir${name}.yml"
    [[ -f "$manifest" ]] || manifest="$dir${name}.yaml"
    if [[ ! -f "$manifest" ]]; then
      echo "warning: no manifest found in $dir" >&2
      continue
    fi

    # Extract app id from manifest
    id="$(grep -m1 '^id:' "$manifest" | sed 's/^id:[[:space:]]*//')"
    if [[ -z "$id" ]]; then
      echo "warning: no id found in $manifest" >&2
      continue
    fi

    # Detect build-extension manifests (extensions of the hub app)
    is_extension=false
    grep -q '^build-extension:[[:space:]]*true' "$manifest" 2>/dev/null && is_extension=true

    # Path relative to repo root
    rel_path="${manifest#"$REPO_ROOT/"}"

    if [[ "$is_extension" == "true" ]]; then
      cat <<EOF
  - id: $id
    manifest: $rel_path
    arches: [x86_64, aarch64]
    branch: stable
    remotes:
      kardbord-boxes:
        url: https://kardbord.github.io/Boxes/kardbord-boxes.flatpakrepo
    flatpaks:
      - remote: kardbord-boxes
        ref: io.github.kardbord.dev//stable
EOF
    else
      cat <<EOF
  - id: $id
    manifest: $rel_path
    arches: [x86_64, aarch64]
    branch: stable
EOF
    fi
  done
}

generate >"$OUTPUT"
echo "Generated $OUTPUT"