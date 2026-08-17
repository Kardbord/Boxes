#!/bin/bash

set -eo pipefail

WD="$(dirname "${BASH_SOURCE[0]}")/../flatpak/manifests"
pushd "${WD}" >/dev/null

if [[ -z "${1}" ]]; then
	echo -e "Expected local package name. Options are:\n $(ls)" >&2
	exit 1
fi

if [[ ! -d "./${1}" ]]; then
	echo -e "You must provide a valid local package name. Options are:\n $(ls)" >&2
	exit 1
fi

pushd "./${1}" >/dev/null

if [[ ! -r "./${1}.yml" ]]; then
	echo "No such manifest: ${1}.yml" >&2
	exit 1
fi

flatpak-builder \
	--disable-rofiles-fuse \
	--force-clean \
	--user \
	--install-deps-from=flathub \
	--repo=local-repo \
	--install \
	build "${1}.yml"
