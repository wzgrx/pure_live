#!/usr/bin/env bash
# Quality gate (docs/PLAN.md §3): format, dependency direction, analyze, tests.
#
#   tools/gate/gate.sh           workspace members changed against origin/master, plus uncommitted work
#   tools/gate/gate.sh --all     every member and the gate's own tests; required before every push
#   tools/gate/gate.sh --hook    Claude Code Stop hook: silent when no member changed, exit 2 on failure
#
# One heavy task at a time: a second caller waits for the lock.
set -uo pipefail

mode=changed
case "${1:-}" in
  --all) mode=all ;;
  --hook) mode=hook ;;
  '') ;;
  *) echo "usage: tools/gate/gate.sh [--all|--hook]" >&2; exit 64 ;;
esac

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root" || exit 1

if [[ $mode == hook ]]; then
  input="$(cat || true)"
  # A second Stop after a blocked one: report, but do not loop forever.
  if grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' <<<"$input"; then
    hook_retry=1
  fi
fi

if ! command -v dart >/dev/null 2>&1 && [[ -f "$HOME/tools/purelive-env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/tools/purelive-env.sh" >/dev/null 2>&1
fi
if ! command -v dart >/dev/null 2>&1; then
  [[ $mode == hook ]] && exit 0
  echo "gate: dart is not on PATH" >&2
  exit 1
fi

members=()
while IFS= read -r member; do members+=("$member"); done < <(
  awk '/^workspace:/{on=1; next} on && /^[^ #]/{exit} on && /^[[:space:]]+-[[:space:]]/{sub(/^[[:space:]]+-[[:space:]]+/, ""); sub(/\/$/, ""); print}' pubspec.yaml
)

selected=()
if [[ $mode == all ]]; then
  selected=("${members[@]}")
else
  base=HEAD
  git rev-parse -q --verify origin/master >/dev/null && base="$(git merge-base HEAD origin/master)"
  changed="$( { git diff --name-only "$base"; git ls-files --others --exclude-standard; } | sort -u)"
  if grep -qxE 'pubspec\.(yaml|lock)|toolchain\.env|tools/gate/gate\.sh|tools/gate/check_deps\.py' <<<"$changed"; then
    selected=("${members[@]}")
  else
    for member in "${members[@]}"; do
      grep -q "^$member/" <<<"$changed" && selected+=("$member")
    done
  fi
  if [[ ${#selected[@]} -eq 0 ]]; then
    [[ $mode == hook ]] || echo "gate: no workspace member changed"
    exit 0
  fi
fi

if command -v flock >/dev/null 2>&1; then
  exec 9>"${TMPDIR:-/tmp}/pure_live-gate.lock"
  flock -w 3600 9 || { echo "gate: timed out waiting for another gate" >&2; exit 1; }
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
failures=()

step() {
  local name="$1"; shift
  if "$@" >"$log" 2>&1; then
    echo "gate: ok   $name"
  else
    echo "gate: FAIL $name" >&2
    tail -n 60 "$log" >&2
    failures+=("$name")
  fi
}

in_dir() { (cd "$1" && shift && "$@"); }

# A merge or pull that changed the lock leaves package_config.json stale:
# analyze would then miss new packages while `flutter test` resolves them.
config=.dart_tool/package_config.json
stale=0
[[ -f $config ]] || stale=1
for spec in pubspec.lock pubspec.yaml "${members[@]/%//pubspec.yaml}"; do
  [[ -f $spec && $spec -nt $config ]] && stale=1
done
if [[ $stale == 1 ]]; then
  if command -v flutter >/dev/null 2>&1; then
    step "dependencies" flutter pub get
  else
    step "dependencies" dart pub get
  fi
fi

# The recorder's FFmpeg bundles: the app's build hook (flutter test builds
# the Linux one) reads them from .ffmpeg_kit/ (M8.1); cached outside the
# repository, downloaded only when missing.
if [[ " ${selected[*]} " == *" apps/pure_live "* ]]; then
  step "ffmpeg bundles" tools/ffmpeg_kit/fetch.sh linux
fi

step "dependency direction" python3 tools/gate/check_deps.py
step "fixture privacy" python3 tools/gate/check_fixtures.py
for member in "${selected[@]}"; do
  step "$member format" dart format --output=none --set-exit-if-changed "$member"
  step "$member analyze" in_dir "$member" dart analyze --fatal-infos
  if [[ -d $member/test ]]; then
    if grep -qE '^[[:space:]]+sdk:[[:space:]]+flutter' "$member/pubspec.yaml"; then
      step "$member test" in_dir "$member" flutter test
    else
      step "$member test" in_dir "$member" dart test
    fi
  fi
done

if [[ $mode == all ]]; then
  step "gate tests" python3 -m unittest discover -s tools/gate/tests
fi

if [[ ${#failures[@]} -gt 0 ]]; then
  echo "gate: ${#failures[@]} failed: ${failures[*]}" >&2
  if [[ $mode == hook ]]; then
    [[ -n ${hook_retry:-} ]] && exit 0
    exit 2
  fi
  exit 1
fi
[[ $mode == hook ]] || echo "gate: passed ($mode, ${#selected[@]} members)"
