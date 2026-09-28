#!/usr/bin/env bash
# Claude Code PostToolUse hook: format an edited Dart file of a workspace member
# (packages/, apps/, tools/).
path="$(python3 -c 'import json, sys; print(json.load(sys.stdin).get("tool_input", {}).get("file_path", ""))' 2>/dev/null)"
[[ $path == *.dart ]] || exit 0
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
relative="${path#"$root"/}"
case "$relative" in
  packages/*|apps/*|tools/*) ;;
  *) exit 0 ;;
esac
if ! command -v dart >/dev/null 2>&1 && [[ -f "$HOME/tools/purelive-env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/tools/purelive-env.sh" >/dev/null 2>&1
fi
command -v dart >/dev/null 2>&1 || exit 0
dart format "$path" >/dev/null 2>&1 || true
