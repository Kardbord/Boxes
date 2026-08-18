#!/bin/bash
set -e

pushd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null

LUA_FILTER="$(mktemp)"
trap 'rm -f "${LUA_FILTER}"' EXIT

cat >"${LUA_FILTER}" <<'EOF'
local base = "https://github.com/Kardbord/Boxes/blob/main/"
local base_tree = "https://github.com/Kardbord/Boxes/tree/main/"

function Link(el)
	if el.target:match("://") or el.target:match("^#") then
		return el
	end
	if el.target:match("/$") then
		el.target = base_tree .. el.target:gsub("^%./", "")
	else
		el.target = base .. el.target:gsub("^%./", "")
	end
	return el
end
EOF

pandoc README.md \
	--template=landing-page.html \
	--lua-filter="${LUA_FILTER}" \
	--metadata title="Kardbord Boxes" \
	--standalone \
	-o "${1:-staging/index.html}"
