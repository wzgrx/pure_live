# shellcheck shell=bash
# Guarded adb helpers for checking Pure Live test builds on a phone (Z04.1).
#
#   source tools/device/pl-adb.sh
#   export PL_DEVICE=<serial or ip:port>      # or D=...; no default
#   pl_check_others; pl_front; pl_tapl '设置'; pl_shot 01
#
# Rules (docs: tools/device/README.md):
# - Every input (tap, long press, key, text, swipe, tap by label) and every read
#   of the screen (screenshot, UI tree) first checks that the focused window
#   belongs to $PL_APP; otherwise it prints "ABORT: foreground is <package>"
#   and sends nothing.
# - $PL_APP defaults to the test build com.mystyle.purelive.v4dev. The user's
#   own install com.mystyle.purelive is refused by every function.
#
# Settings are read on every call, so `PL_APP=... pl_front` and later exports
# take effect without sourcing again:
#   PL_DEVICE   adb serial (falls back to $D); required
#   PL_APP      package under test (default com.mystyle.purelive.v4dev)
#   PL_SHOTS    screenshot directory (default ./verify)
#   PL_BACK_XY  "x y" of the app bar back arrow used by pl_home (default "80 228",
#               the K90 in portrait)
#   PL_FRONT_WAIT  seconds pl_front waits after starting the app (default 2)

PL_PROTECTED_APP=com.mystyle.purelive
PL_ACTIVITY=com.mystyle.purelive.MainActivity
PL_DEVICE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_pl_app() { printf '%s' "${PL_APP:-com.mystyle.purelive.v4dev}"; }
_pl_dev() { printf '%s' "${PL_DEVICE:-${D:-}}"; }

# Refuses to work on the user's own install or without a device.
_pl_guard() {
  if [ "$(_pl_app)" = "$PL_PROTECTED_APP" ]; then
    echo "REFUSED: PL_APP is $PL_PROTECTED_APP (the user's own install); use the test build" >&2
    return 1
  fi
  if [ -z "$(_pl_dev)" ]; then
    echo "REFUSED: set PL_DEVICE (or D) to the adb serial, for example ip:5555" >&2
    return 1
  fi
}

_pl_adb() { adb -s "$(_pl_dev)" "$@"; }

# pl_env: print the settings in use.
pl_env() {
  echo "PL_DEVICE=$(_pl_dev) PL_APP=$(_pl_app) PL_SHOTS=${PL_SHOTS:-./verify}"
}

# pl_fg: the package of the focused window (empty when it is not an app window).
pl_fg() {
  _pl_guard || return 1
  _pl_adb shell "dumpsys window | grep -m1 mCurrentFocus" 2>/dev/null |
    grep -o 'u0 [^ /}]*' | head -n1 | cut -d' ' -f2
}

# pl_need: succeed only when $PL_APP is in the foreground.
pl_need() {
  _pl_guard || return 1
  local f
  f="$(pl_fg)"
  if [ "$f" != "$(_pl_app)" ]; then
    echo "ABORT: foreground is ${f:-unknown}"
    return 1
  fi
}

# pl_front: start the test build's activity (never by pressing BACK), then check.
pl_front() {
  _pl_guard || return 1
  _pl_adb shell am start -n "$(_pl_app)/$PL_ACTIVITY" >/dev/null 2>&1
  sleep "${PL_FRONT_WAIT:-2}"
  pl_need && echo "front: $(_pl_app)"
}

# pl_tap X Y
pl_tap() {
  [ $# -eq 2 ] || { echo "usage: pl_tap X Y" >&2; return 2; }
  pl_need || return 1
  _pl_adb shell input tap "$1" "$2"
}

# pl_hold X Y [MS]: long press (default 900 ms).
pl_hold() {
  [ $# -ge 2 ] || { echo "usage: pl_hold X Y [MS]" >&2; return 2; }
  pl_need || return 1
  _pl_adb shell input swipe "$1" "$2" "$1" "$2" "${3:-900}"
}

# pl_key CODE: a key event (number or KEYCODE_* name).
pl_key() {
  [ $# -eq 1 ] || { echo "usage: pl_key CODE" >&2; return 2; }
  pl_need || return 1
  _pl_adb shell input keyevent "$1"
}

# pl_text TEXT: ASCII letters, digits, spaces and . _ @ : / + = - only;
# `input text` cannot type Chinese.
pl_text() {
  [ $# -eq 1 ] || { echo "usage: pl_text TEXT" >&2; return 2; }
  if ! [[ $1 =~ ^[A-Za-z0-9\ ._@:/+=-]*$ ]]; then
    echo "REFUSED: pl_text takes ASCII letters, digits, spaces and . _ @ : / + = - only" >&2
    return 2
  fi
  pl_need || return 1
  _pl_adb shell input text "${1// /%s}"
}

# pl_swipe X1 Y1 X2 Y2 [MS]
pl_swipe() {
  [ $# -ge 4 ] || { echo "usage: pl_swipe X1 Y1 X2 Y2 [MS]" >&2; return 2; }
  pl_need || return 1
  _pl_adb shell input swipe "$@"
}

_pl_capture() {
  local name="$1" width="$2" dir png
  pl_need || return 1
  dir="${PL_SHOTS:-./verify}"
  mkdir -p "$dir" || return 1
  png="$dir/$name.png"
  _pl_adb exec-out screencap -p >"$png" || { rm -f "$png"; return 1; }
  python3 "$PL_DEVICE_DIR/resize.py" shrink "$png" "$dir/$name.jpg" "$width"
}

# pl_shot NAME: portrait screenshot, saved as $PL_SHOTS/NAME.jpg, 540 wide.
pl_shot() {
  [ $# -eq 1 ] || { echo "usage: pl_shot NAME" >&2; return 2; }
  _pl_capture "$1" 540
}

# pl_shotl NAME: landscape screenshot, 1080 wide.
pl_shotl() {
  [ $# -eq 1 ] || { echo "usage: pl_shotl NAME" >&2; return 2; }
  _pl_capture "$1" 1080
}

# pl_row OUT IMG...: images side by side, each 540 wide, as $PL_SHOTS/OUT.jpg.
pl_row() {
  [ $# -ge 2 ] || { echo "usage: pl_row OUT IMG..." >&2; return 2; }
  local out="$1"
  shift
  mkdir -p "${PL_SHOTS:-./verify}" || return 1
  python3 "$PL_DEVICE_DIR/resize.py" row "${PL_SHOTS:-./verify}/$out.jpg" 540 "$@"
}

# pl_ui [REGEX]: labels on screen as `text="..." [x1,y1][x2,y2]` (or content-desc).
# Dumping the UI tree in landscape freezes rotation; see pl_rotation_reset.
pl_ui() {
  pl_need || return 1
  local f="/data/local/tmp/pl_ui_$$.xml" rot
  _pl_adb shell uiautomator dump "$f" >/dev/null 2>&1
  _pl_adb exec-out cat "$f" |
    grep -oE '(content-desc|text)="[^"]+"[^>]*bounds="[^"]+"' |
    sed -E 's/" .*bounds=/" /' | grep -E "${1:-.}"
  _pl_adb shell rm -f "$f" >/dev/null 2>&1
  rot="$(_pl_adb shell settings get system user_rotation 2>/dev/null | tr -d '\r')"
  if [ -n "$rot" ] && [ "$rot" != 0 ]; then
    echo "NOTE: user_rotation is $rot; run pl_rotation_reset when the landscape checks are done" >&2
  fi
  return 0
}

# pl_tapl REGEX: tap the centre of the first label matching REGEX.
pl_tapl() {
  [ $# -eq 1 ] || { echo "usage: pl_tapl REGEX" >&2; return 2; }
  local line x1 y1 x2 y2
  line="$(pl_ui "$1" | head -n1)"
  case "$line" in ABORT:*) echo "$line"; return 1 ;; esac
  read -r x1 y1 x2 y2 < <(grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]' <<<"$line" |
    grep -oE '[0-9]+' | tr '\n' ' ')
  [ -n "${y2:-}" ] || { echo "NOTFOUND: $1"; return 1; }
  pl_tap $(((x1 + x2) / 2)) $(((y1 + y2) / 2))
}

# pl_ctl LABEL [VX VY]: tap a player control by its label; when it is not on
# screen, first tap the picture at (VX, VY) (default 600 450) to show the controls.
pl_ctl() {
  [ $# -ge 1 ] || { echo "usage: pl_ctl LABEL [VX VY]" >&2; return 2; }
  if ! pl_ui "content-desc=\"$1\"" | grep -q 'content-desc'; then
    pl_tap "${2:-600}" "${3:-450}" || return 1
    sleep 0.4
  fi
  pl_tapl "content-desc=\"$1\""
}

# pl_home: back to the bottom navigation by tapping the app bar back arrow
# ($PL_BACK_XY) up to six times; never presses BACK, which can leave the app.
pl_home() {
  pl_front >/dev/null || { echo "ABORT: could not bring $(_pl_app) to the front"; return 1; }
  local i x y
  read -r x y <<<"${PL_BACK_XY:-80 228}"
  for i in 1 2 3 4 5 6; do
    pl_ui '第 1 个标签，共 4 个' | grep -q '关注' && return 0
    pl_tap "$x" "$y" || return 1
    sleep 1.5
  done
  echo "NOTFOUND: bottom navigation after $i taps"
  return 1
}

# pl_rotation: print user_rotation (0 portrait); pl_rotation_reset: set it back to 0.
pl_rotation() {
  _pl_guard || return 1
  _pl_adb shell settings get system user_rotation
}
pl_rotation_reset() {
  _pl_guard || return 1
  _pl_adb shell settings put system user_rotation 0
}

# pl_net off|on: cut or restore the network of $PL_APP only (adb over Wi-Fi keeps
# working). Only new connections are blocked: a stream that is already open
# keeps playing.
pl_net() {
  _pl_guard || return 1
  case "${1:-}" in
    off)
      _pl_adb shell cmd connectivity set-chain3-enabled true &&
        _pl_adb shell cmd connectivity set-package-networking-enabled false "$(_pl_app)"
      ;;
    on) _pl_adb shell cmd connectivity set-package-networking-enabled true "$(_pl_app)" ;;
    *) echo "usage: pl_net off|on" >&2; return 2 ;;
  esac
}

_pl_aapt() {
  local tool last=""
  for tool in aapt2 aapt; do
    command -v "$tool" >/dev/null 2>&1 && { command -v "$tool"; return 0; }
  done
  for tool in "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"/build-tools/*/aapt2; do
    [ -x "$tool" ] && last="$tool"
  done
  [ -n "$last" ] && { echo "$last"; return 0; }
  return 1
}

# pl_install APK: install (replace) an APK whose package is a .v4dev test build.
pl_install() {
  [ $# -eq 1 ] || { echo "usage: pl_install APK" >&2; return 2; }
  _pl_guard || return 1
  [ -f "$1" ] || { echo "REFUSED: no such file: $1" >&2; return 1; }
  local aapt pkg
  aapt="$(_pl_aapt)" || { echo "REFUSED: aapt2 or aapt not found (Android build-tools)" >&2; return 1; }
  pkg="$("$aapt" dump badging "$1" 2>/dev/null | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -n1)"
  case "$pkg" in
    *.v4dev) ;;
    *) echo "REFUSED: $1 is package '${pkg:-unknown}', not a .v4dev test build" >&2; return 1 ;;
  esac
  _pl_adb install -r "$1"
}

# pl_check_others: recent adb sessions from other clients (another automation
# may be driving the phone at the same time).
pl_check_others() {
  _pl_guard || return 1
  _pl_adb logcat -d 2>/dev/null | grep "adbd service requested" | tail -n "${1:-20}"
  return 0
}
