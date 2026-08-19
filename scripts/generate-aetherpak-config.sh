#!/bin/bash
set -euo pipefail

# Generate aetherpak-apps.yaml from flatpak/manifests/*/
#
# Scans the manifests directory and produces an AetherPak config for all
# packages except the SDK (which is handled by flatpak/aetherpak-sdk.yaml).
#
# Usage:
#   scripts/generate-aetherpak-config.sh          # Write aetherpak-apps.yaml

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFESTS_DIR="$REPO_ROOT/flatpak/manifests"
OUTPUT="$REPO_ROOT/aetherpak-apps.yaml"

generate() {
  cat <<'HEADER'
remote_name: kardbord
defaults:
  remotes:
    flathub: https://dl.flathub.org/repo/flathub.flatpakrepo
    kardbord: https://kardbord.github.io/Boxes/kardbord.flatpakrepo
  flatpaks:
    - remote: flathub
      ref: org.freedesktop.Sdk//25.08
    - remote: kardbord
      ref: io.github.kardbord.Sdk//stable
apps:
HEADER

  for dir in "$MANIFESTS_DIR"/*/; do
    name="$(basename "$dir")"

    # SDK is handled by flatpak/aetherpak-sdk.yaml (Phase 1)
    [[ "$name" == "io.github.kardbord.Sdk" ]] && continue

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

    # Path relative to repo root
    rel_path="${manifest#"$REPO_ROOT/"}"

    cat <<EOF
  - id: $id
    manifest: $rel_path
    arches: [x86_64, aarch64]
    branch: stable
EOF
  done
}

generate >"$OUTPUT"
echo "Generated $OUTPUT"
