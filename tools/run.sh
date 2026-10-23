#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
if [[ "$project_dir" == /workspace/* && -d /workspace/.godot-environment ]]; then
  export XDG_CACHE_HOME=/workspace/.godot-environment/cache
  export XDG_CONFIG_HOME=/workspace/.godot-environment/config
  export XDG_DATA_HOME=/workspace/.godot-environment/data
  mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
fi
exec "${GODOT_BIN:-godot}" --path "$project_dir" "$@"
