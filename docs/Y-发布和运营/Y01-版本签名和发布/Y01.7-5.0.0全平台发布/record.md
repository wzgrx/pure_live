# Y01.7 记录

## 2026-10-15

| 阶段 | 结果 |
|---|---|
| 1 版本号和发布说明 | `5.0.0+5100`；`releases/v5.0.0.md`；README 改成新仓库和全部平台 |
| 2 各平台构建和检查 | 提交 `2bab69f63`（旧仓库 master）。Android：`flutter build apk --release --split-per-abi`，包名 `com.mystyle.purelive`、versionCode 7100/6100/9100、versionName 5.0.0、证书 SHA-256 `1e832295…`（和 3.x 同一把）、四个图标都在、14 个 `.so` 全部 16 KB 对齐。Linux：`tools/release/package_linux.sh`，解开后有 README.txt、purelive.desktop、purelive.png，WSL 里启动 20 秒不退出。Windows：Windows 电脑上 `pack-win5.ps1 origin/master`（`tools/release/package_windows.ps1`），便携版解压后启动，版本 5.0.0+5100、首页正常；安装版没有在这台电脑上运行（装着用户的 3.x，同一个 AppId 会装到它的目录上）。安装包和 `SHA256SUMS.txt` 在 `~/ref/release/v5.0.0-5100/`，哈希写在发布说明 |
| 3 K90 和 Windows 快速测试 | 同一批代码的 v4dev 测试包（5.0.0/5100）：录像在应用里播放（第一次因为中文路径打不开，修了：给 mpv 用 file:// 地址、本地文件不走中继；上一段/下一段改成按直播间文件夹列）、倍速；HyperOS 上“在快手打开”这次系统弹出自己的确认框，跳转正常、我们的提示是被拦截时的兜底；电视模式：使用须知、收起的导航栏、返回键退出确认（第一次返回直接退出了应用：go_router 的根路由把 Android 的返回直接结束了，改成电视首页接住原生返回通道），返回键取消、从推上去的页面返回都对 |
| 4 新仓库、标签、发布页 | `gh repo create wzgrx/PureLive --public`；`git commit-tree master^{tree}`（旧仓库 `2f3a023a7` 的同一棵树）推成新仓库 master 的第一个提交 `914dbaeac`；附注标签 `v5.0.0`；发布页“纯粹直播 v5.0.0”，六个包和 `SHA256SUMS.txt`，GitHub 记的 SHA-256 和本机逐个一致 |
| 5 更新文件 | `assets/version.json`：顶层和 android、windows、linux 都是 5.0.0、5100、500005100，下载地址指向新仓库发布页（3.x 的 Windows、Linux 也会收到提示；macOS、iOS 还是 3.2.10）；`assets/releases.json` 最前面加 5.0.0（文件地址都在新仓库）；旧仓库和新仓库的 master 一起改 |

