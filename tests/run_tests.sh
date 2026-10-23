#!/usr/bin/env bash
# All player data goes into a disposable directory; project sources are read-only.
set -euo pipefail

weiyuan_test_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
weiyuan_test_root="$(mktemp -d /tmp/weiyuan-tests.XXXXXX)"
godot_binary="${GODOT_BIN:-godot}"
export XDG_CACHE_HOME="$weiyuan_test_root/cache"
export XDG_CONFIG_HOME="$weiyuan_test_root/config"
export XDG_DATA_HOME="$weiyuan_test_root/data"
export WEIYUAN_TEST_DIR="$weiyuan_test_root/saves"
mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$WEIYUAN_TEST_DIR"
trap 'rm -rf "$weiyuan_test_root"' EXIT
cd "$weiyuan_test_repo"

run_godot_check() {
    local label="$1"
    shift
    local log="$weiyuan_test_root/$label.log" result=0
    timeout 180s "$godot_binary" --headless --path "$weiyuan_test_repo" "$@" >"$log" 2>&1 || result=$?
    cat "$log"
    if [ "$result" -ne 0 ]; then
        return "$result"
    fi
    if grep -Eq '^(SCRIPT ERROR:|ERROR:)' "$log"; then
        printf 'Godot reported an error during %s.\n' "$label" >&2
        return 1
    fi
    if [ "$label" != "import" ] && ! grep -Eq 'TESTS COMPLETE: [1-9][0-9]* passed, 0 failed$' "$log"; then
        printf 'The %s suite did not complete any passing checks.\n' "$label" >&2
        return 1
    fi
}

run_godot_check import --import
run_godot_check run_state --script tests/test_run_state.gd
run_godot_check arena --script tests/test_arena.gd
if [ -f tests/test_world.gd ]; then
    run_godot_check world --script tests/test_world.gd
fi
run_godot_check story --script tests/test_story.gd
run_godot_check ui --script tests/test_ui.gd
printf 'Godot rules, action combat, dialogue, and UI validation all passed.\n'
