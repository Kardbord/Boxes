#!/bin/bash

set -eo pipefail

WD="$(dirname "${BASH_SOURCE[0]}")/../flatpak/manifests"
pushd "${WD}" >/dev/null

is_local_install() {
	flatpak info "${1}" &>/dev/null
	return $?
}

for dir in * io.github.kardbord.Platform; do
	is_local_install "${dir}" && flatpak --user uninstall "${dir}" || true
done
