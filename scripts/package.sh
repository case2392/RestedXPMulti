#!/usr/bin/env bash
# Build the CurseForge zips for every addon in this repo.
#
# CurseForge wants one folder per addon at the top of the zip, named the
# same as the .toc inside it, and nothing else. Party Sync's files live in
# the repo root (RestedXPMulti.toc beside Core.lua ...), so zipping the
# checkout as-is gives a zip full of other addons and no RestedXPMulti
# folder, which CurseForge rejects. This puts each addon in its folder.
#
#   scripts/package.sh            # every addon -> dist/<Folder>-<version>.zip
#   scripts/package.sh RestedXPMulti ForeverClassicUI
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dist="$root/dist"
mkdir -p "$dist"

version_of() {  # the toc's ## Version line
    sed -n 's/^## Version: *//p' "$1" | tr -d '\r' | head -1
}

build() {
    local folder="$1"; shift
    local toc="$1"; shift
    local version; version="$(version_of "$toc")"
    local stage; stage="$(mktemp -d)"
    mkdir -p "$stage/$folder"
    for f in "$@"; do cp "$f" "$stage/$folder/"; done
    local zip="$dist/$folder-$version.zip"
    rm -f "$zip"
    (cd "$stage" && zip -q -r -X "$zip" "$folder")
    rm -rf "$stage"
    echo "$zip"
    unzip -l "$zip" | awk 'NR>3 && $4 != "" {print "    " $4}' | grep -v '/$'
}

selected=("$@")
wanted() {
    [ ${#selected[@]} -eq 0 ] && return 0
    local s; for s in "${selected[@]}"; do [ "$s" = "$1" ] && return 0; done
    return 1
}

cd "$root"
wanted RestedXPMulti && build RestedXPMulti RestedXPMulti.toc \
    RestedXPMulti.toc Core.lua Sync.lua Duo.lua UI.lua LICENSE
for addon in ForeverClassicUI AdventurePlates RXPProfessions RIPBozo; do
    if wanted "$addon" && [ -f "$addon/$addon.toc" ]; then
        # everything in the folder except art sources and screenshots
        files=()
        while IFS= read -r f; do files+=("$f"); done < <(
            find "$addon" -maxdepth 1 -type f \( -name '*.lua' -o -name '*.toc' -o -name '*.xml' -o -name '*.tga' -o -name '*.blp' -o -name '*.md' \) | sort)
        build "$addon" "$addon/$addon.toc" "${files[@]}"
    fi
done
