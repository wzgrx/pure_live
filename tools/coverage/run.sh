#!/usr/bin/env bash
# Run every workspace member's tests with coverage (S01.2). Output goes to OUT,
# which must be outside the repository (coverage/ is not ignored by git):
#
#   tools/coverage/run.sh OUT [member...]     default: every member
#   python3 tools/coverage/report.py OUT      the tables
#
# Writes OUT/<name>.lcov and OUT/<name>.log (name = last path segment), and
# OUT/commit.txt. Needs the toolchain on PATH (source ~/tools/purelive-env.sh),
# `flutter pub get` and `tools/ffmpeg_kit/fetch.sh linux` done first, and
# `dart pub global activate coverage 1.15.1` for the pure Dart members.
# Slow (live_core alone takes minutes): do not run it next to the gate or a build.
set -uo pipefail

[[ $# -ge 1 ]] || { echo "usage: tools/coverage/run.sh OUT [member...]" >&2; exit 64; }
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p "$1" || exit 1
out="$(cd "$1" && pwd)"
shift
case "$out/" in
  "$root"/*) echo "run.sh: OUT must be outside the repository" >&2; exit 64 ;;
esac
cd "$root" || exit 1

members=("$@")
if [[ ${#members[@]} -eq 0 ]]; then
  while IFS= read -r member; do members+=("$member"); done < <(
    awk '/^workspace:/{on=1; next} on && /^[^ #]/{exit} on && /^[[:space:]]+-[[:space:]]/{sub(/^[[:space:]]+-[[:space:]]+/, ""); sub(/\/$/, ""); print}' pubspec.yaml
  )
fi

git rev-parse HEAD >"$out/commit.txt"
status=0
for member in "${members[@]}"; do
  name="${member##*/}"
  if [[ ! -d $member/test ]]; then
    echo "skip  $member (no test/)"
    continue
  fi
  start=$SECONDS
  if grep -qE '^[[:space:]]+sdk:[[:space:]]+flutter' "$member/pubspec.yaml"; then
    (cd "$member" && flutter test --coverage --coverage-path="$out/$name.lcov") >"$out/$name.log" 2>&1
    rc=$?
  else
    rm -rf "${out:?}/$name"
    (cd "$member" && dart test --coverage="$out/$name") >"$out/$name.log" 2>&1
    rc=$?
    (cd "$member" && dart pub global run coverage:format_coverage --lcov --in="$out/$name" \
      --out="$out/$name.lcov" --report-on=lib --package=.) >>"$out/$name.log" 2>&1 || rc=1
  fi
  echo "$([[ $rc == 0 ]] && echo 'ok  ' || echo 'FAIL') $member ($((SECONDS - start)) s)"
  [[ $rc == 0 ]] || status=1
done
exit $status
