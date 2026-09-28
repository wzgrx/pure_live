#!/usr/bin/env bash
# Runs the pure-Dart packages' tests with the wall clock moved forward, to find
# tests that break once a recorded expiry passes. Linux/WSL only.
# Usage: tools/timeshift/run.sh [days...]   (default: 30 365 1825)
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
[[ -f ~/tools/purelive-env.sh ]] && source ~/tools/purelive-env.sh >/dev/null 2>&1
# Tests never need the network; a proxy from the environment makes some of
# them hang once the wall clock is shifted.
unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy ALL_PROXY all_proxy
lib="${TMPDIR:-/tmp}/pure_live-timeshift.so"
cc -shared -fPIC -O2 -o "$lib" tools/timeshift/shift.c -ldl || exit 1
days=("$@"); [[ ${#days[@]} -eq 0 ]] && days=(30 365 1825)
status=0
for day in "${days[@]}"; do
  for package in packages/live_net packages/live_core packages/live_danmaku; do
    [[ -d $package/test ]] || continue
    if (cd "$package" && SHIFT_SECONDS=$((day * 86400)) LD_PRELOAD="$lib" dart test >/dev/null 2>&1); then
      echo "timeshift: ok   +${day}d $package"
    else
      echo "timeshift: FAIL +${day}d $package (rerun: cd $package && SHIFT_SECONDS=$((day * 86400)) LD_PRELOAD=$lib dart test)"
      status=1
    fi
  done
done
exit $status
