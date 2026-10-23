#!/usr/bin/env bash
# Reproduce a single-threaded Godot 4.6.3 Compatibility web build.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_binary="${GODOT_BIN:-godot}"
godot_version=4.6.3
archive_name="Godot_v${godot_version}-stable_export_templates.tpz"
# Pinned from https://github.com/godotengine/godot/releases/download/4.6.3-stable/SHA512-SUMS.txt
archive_sha512=da606b61c10157844f8300172df374472665f95015495cb1a7cd132c40ede404faa96cc1016a4b9662db9909ddea69632c4948b2cd11163438dad4808881fb68
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/jianghu-weiyuan/export"
template_dir="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${godot_version}.stable"
mkdir -p "$cache_dir" "$template_dir" "$repo_root/build/web" "$repo_root/artifacts"
touch "$repo_root/build/.gdignore" "$repo_root/artifacts/.gdignore"

installed_version="$("$godot_binary" --version)"
case "$installed_version" in
    4.6.3.stable.*) ;;
    *) printf 'Godot 4.6.3 is required; found %s\n' "$installed_version" >&2; exit 1 ;;
esac

archive_path="$cache_dir/$archive_name"
# Reuse the already verified official bundle from the previous prototype when present.
previous_archive="${XDG_CACHE_HOME:-$HOME/.cache}/shanhexing/export/$archive_name"
if [ ! -f "$archive_path" ] && [ -f "$previous_archive" ]; then
    archive_path="$previous_archive"
fi
if [ ! -f "$archive_path" ]; then
    printf 'Downloading official Godot templates (1.17 GiB, cached for subsequent builds).\n'
    curl --fail --location --show-error --max-time 300 \
        --output "$archive_path.part" \
        "https://github.com/godotengine/godot/releases/download/${godot_version}-stable/$archive_name"
    printf '%s  %s\n' "$archive_sha512" "$archive_path.part" | sha512sum --check --status
    mv "$archive_path.part" "$archive_path"
fi
printf '%s  %s\n' "$archive_sha512" "$archive_path" | sha512sum --check

# Only install the two required single-threaded templates from the verified bundle.
python3 - "$archive_path" "$template_dir" <<'PY'
from pathlib import Path
import sys, zipfile
archive, destination = Path(sys.argv[1]), Path(sys.argv[2])
with zipfile.ZipFile(archive) as bundle:
    for name in ('version.txt', 'web_nothreads_debug.zip', 'web_nothreads_release.zip'):
        contents = bundle.read('templates/' + name)
        target = destination / name
        if target.exists() and target.read_bytes() != contents:
            raise SystemExit(f'Existing template differs; preserved for inspection: {target}')
        if not target.exists():
            target.write_bytes(contents)
        print('Verified official template:', name)
PY

cd "$repo_root"
"$godot_binary" --headless --path "$repo_root" --import 2>&1 | tee "$cache_dir/import.log"
if grep -Eq '^(SCRIPT ERROR:|ERROR:)' "$cache_dir/import.log"; then
    printf 'Godot import reported an error; inspect %s/import.log\n' "$cache_dir" >&2
    exit 1
fi
"$godot_binary" --headless --path "$repo_root" --export-release Web "$repo_root/build/web/index.html" 2>&1 | tee "$cache_dir/export.log"
if grep -Eq '^(SCRIPT ERROR:|ERROR:)' "$cache_dir/export.log"; then
    printf 'Godot export reported an error; inspect %s/export.log\n' "$cache_dir" >&2
    exit 1
fi

# Ship the font notice alongside the browser game, even though it is not a game resource.
cp "$repo_root/assets/fonts/LICENSE-NOTO.txt" "$repo_root/build/web/LICENSE-NOTO.txt"
mkdir -p "$repo_root/build/web/licenses"
cp "$repo_root/addons/dialogue_manager/LICENSE" "$repo_root/build/web/licenses/DialogueManager-LICENSE.txt"
cp "$repo_root/licenses/Godot-LICENSE.txt" "$repo_root/build/web/licenses/Godot-LICENSE.txt"
cp "$repo_root/licenses/Godot-COPYRIGHT.txt" "$repo_root/build/web/licenses/Godot-COPYRIGHT.txt"
test -s "$repo_root/build/web/index.html"
test -s "$repo_root/build/web/index.wasm"
test -s "$repo_root/build/web/index.pck"
printf '\nWeb build ready: %s/build/web\n' "$repo_root"
printf 'Local play: python3 tools/serve_web.py\n'
