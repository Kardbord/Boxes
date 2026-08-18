#!/bin/bash

set -eo pipefail

MANIFESTS_ROOT="$(readlink -e "$(dirname "${BASH_SOURCE[0]}")/../flatpak/manifests")"

WD=$(mktemp -d)
pushd "${WD}" >/dev/null

if [[ -z "${1}" ]]; then
	echo -e "Expected local package name. Options are:\n$(ls "${MANIFESTS_ROOT}")" >&2
	exit 1
fi

MANIFEST_DIR="${MANIFESTS_ROOT}/${1}"
if [[ ! -d "${MANIFEST_DIR}" ]]; then
	echo -e "You must provide a valid local package name. Options are:\n$(ls "${MANIFESTS_ROOT}")" >&2
	exit 1
fi

MANIFEST="${MANIFEST_DIR}/${1}.yml"
if [[ ! -r "${MANIFEST}" ]]; then
	echo "No such manifest: ${MANIFEST}" >&2
	exit 1
fi

flatpak-builder \
	--disable-rofiles-fuse \
	--force-clean \
	--user \
	--install-deps-from=flathub \
	--repo=local-repo \
	--delete-build-dirs \
	--install \
	"flatpak-build_${1}" "${MANIFEST}"

popd >/dev/null
rm -rf "${WD}"
