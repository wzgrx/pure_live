#!/usr/bin/env bash
# Puts the recorder's FFmpeg bundles (bundles.txt) where the ffmpeg_kit
# build hook reads them: downloaded once into a cache outside the repository,
# checked against their SHA-256, and linked into <repo>/.ffmpeg_kit/.
#
#   tools/ffmpeg_kit/fetch.sh            # every bundle
#   tools/ffmpeg_kit/fetch.sh android    # only the names containing "android"/"aar"
#
# Cache: $PURE_LIVE_FFMPEG_KIT_CACHE, else ${XDG_CACHE_HOME:-~/.cache}/pure_live/ffmpeg_kit.
# Downloads honour HTTPS_PROXY. Without network a filled cache is enough; CI
# (empty cache) downloads every time, as before.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cache="${PURE_LIVE_FFMPEG_KIT_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/pure_live/ffmpeg_kit}"
target="$root/.ffmpeg_kit"
filter="${1:-}"
mkdir -p "$cache" "$target"

sha() { sha256sum "$1" | cut -d' ' -f1; }

while IFS=$'\t' read -r name hash url; do
  [[ -z $name || $name == \#* ]] && continue
  case "$filter" in
    '') ;;
    android) [[ $name == *.aar ]] || continue ;;
    *) [[ $name == *"$filter"* ]] || continue ;;
  esac
  file="$cache/$name"
  if [[ ! -f $file || $(sha "$file") != "$hash" ]]; then
    echo "ffmpeg_kit: downloading $name"
    curl -fL --retry 3 --progress-bar -o "$file.part" "$url"
    if [[ $(sha "$file.part") != "$hash" ]]; then
      rm -f "$file.part"
      echo "ffmpeg_kit: $name does not match its SHA-256" >&2
      exit 1
    fi
    mv "$file.part" "$file"
  fi
  ln -sfn "$file" "$target/$name"
  echo "ffmpeg_kit: $name ready"
done < "$root/tools/ffmpeg_kit/bundles.txt"
