#!/usr/bin/env bash
# Builds the Linux release and packs it as 3.x did (X02.1):
#   PureLive-<version>-<build>-linux-x64.tar.gz
# holding PureLive-<version>-<build>-linux-x64/ with the bundle, a desktop
# entry, the icon and a short README. Run from the repository root after
# `source ~/tools/purelive-env.sh`; the tarball lands in $1 (default build/release).
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${1:-$root/build/release}"
version=$(sed -n 's/^version: \([0-9.]*\)+\([0-9]*\)$/\1/p' "$root/apps/pure_live/pubspec.yaml")
build=$(sed -n 's/^version: \([0-9.]*\)+\([0-9]*\)$/\2/p' "$root/apps/pure_live/pubspec.yaml")
name="PureLive-$version-$build-linux-x64"
bash "$root/tools/ffmpeg_kit/fetch.sh" linux >/dev/null
(cd "$root/apps/pure_live" && flutter build linux --release)
# Each build rewrites analysis_options.yaml's excludes; keep the committed one.
git -C "$root" checkout -- apps/pure_live/analysis_options.yaml 2>/dev/null || true
stage="$(mktemp -d)/$name"
mkdir -p "$stage" "$out"
cp -a "$root/apps/pure_live/build/linux/x64/release/bundle/." "$stage/"
cp "$root/apps/pure_live/assets/icons/icon.png" "$stage/purelive.png"
cat > "$stage/purelive.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=纯粹直播
Name[en]=PureLive
Comment=多平台直播聚合
Exec=sh -c '"$(dirname "$(readlink -f "%k")")/pure_live"'
Icon=purelive
Terminal=false
Categories=AudioVideo;Video;Player;
DESKTOP
cat > "$stage/README.txt" <<'README'
纯粹直播 Linux 版（x86_64）

运行：解压后执行 ./pure_live 。数据保存在 ~/.local/share/com.mystyle.purelive/ 。
加到应用菜单：把 purelive.desktop 里的 Exec 改成 pure_live 的完整路径，
再复制到 ~/.local/share/applications/ ，图标 purelive.png 复制到
~/.local/share/icons/ 。
需要：GTK 3、OpenGL（一般桌面都已自带）。Linux 版没有应用内网页登录，
账号可以在手机或 Windows 上登录后用“设备同步”带过来。
README
tar -C "$(dirname "$stage")" -czf "$out/$name.tar.gz" "$name"
echo "$out/$name.tar.gz"
