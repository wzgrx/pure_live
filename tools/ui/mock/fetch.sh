#!/usr/bin/env bash
# Puts what the mockups need into tools/ui/mock/.cache/ (git-ignored):
#   fonts/  Material Icons (and Round) and Geist from fonts.txt, checked
#           against their SHA-256; remix.ttf linked from the remixicon
#           package in the pub cache (run `flutter pub get` once first).
#   img/    sample pictures from images.txt (picsum.photos).
# Downloads land in $PURE_LIVE_UI_MOCK_CACHE, else
# ${XDG_CACHE_HOME:-~/.cache}/pure_live/ui_mock, once; later runs only link.
# Downloads honour HTTPS_PROXY. The Chinese font is the system's
# "Noto Sans CJK SC" (Debian/Ubuntu: fonts-noto-cjk).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
cache="${PURE_LIVE_UI_MOCK_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/pure_live/ui_mock}"
mkdir -p "$cache/fonts" "$cache/img" "$here/.cache"
ln -sfn "$cache/fonts" "$here/.cache/fonts"
ln -sfn "$cache/img" "$here/.cache/img"

sha() { sha256sum "$1" | cut -d' ' -f1; }

while IFS=$'\t' read -r name hash url; do
  [[ -z $name || $name == \#* ]] && continue
  file="$cache/fonts/$name"
  if [[ ! -f $file || $(sha "$file") != "$hash" ]]; then
    echo "ui mock: downloading $name"
    curl -fsSL --retry 3 -o "$file.part" "$url"
    if [[ $(sha "$file.part") != "$hash" ]]; then
      rm -f "$file.part"
      echo "ui mock: $name does not match its SHA-256" >&2
      exit 1
    fi
    mv "$file.part" "$file"
  fi
done < "$here/fonts.txt"

remix="$(python3 - "$root" <<'PY'
import json, sys, urllib.parse, os
cfg = os.path.join(sys.argv[1], '.dart_tool', 'package_config.json')
try:
    pkgs = json.load(open(cfg))['packages']
except OSError:
    sys.exit(0)
for p in pkgs:
    if p['name'] == 'remixicon':
        print(os.path.join(urllib.parse.urlparse(p['rootUri']).path, 'fonts', 'remix.ttf'))
PY
)"
if [[ -n $remix && -f $remix ]]; then
  ln -sfn "$remix" "$cache/fonts/remix.ttf"
else
  echo "ui mock: remixicon not found in the pub cache; run 'flutter pub get' in the repository first" >&2
  exit 1
fi

while IFS=$'\t' read -r id w h _; do
  [[ -z $id || $id == \#* ]] && continue
  file="$cache/img/$id.jpg"
  if [[ ! -s $file ]]; then
    echo "ui mock: downloading picture $id"
    curl -fsSL --retry 3 -o "$file.part" "https://picsum.photos/id/$id/$w/$h.jpg"
    mv "$file.part" "$file"
  fi
done < "$here/images.txt"

fc-list | grep 'Noto Sans CJK SC' >/dev/null || echo "ui mock: install the Noto Sans CJK SC font (fonts-noto-cjk) for Chinese text" >&2
echo "ui mock: ready ($cache)"
