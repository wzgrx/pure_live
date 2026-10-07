# S02.4 K90 验证：备份恢复、WebDAV、设备同步、扫码、应用内更新、字体、Twitch 和 Kick：任务书

## 背景

- 来源：功能清点（[inventory/FEATURES.md](../../../inventory/FEATURES.md)）里这些功能点标着“没验证”；4.0.0 发布说明的“已知问题”对用户写明“多画面、网络电视、投屏、账号登录、备份和恢复、WebDAV、设备同步、扫码、应用内更新、字体下载，以及 Twitch 和 Kick……还没在真机上完整走过，遇到问题请反馈”。
- 现象：没有已知的坏现象；风险在于这些功能只在组件测试和电脑上跑过（例如备份默认写 `/storage/emulated/0/Download/PureLive`，Android 11 起的分区存储下没在真机试过）。
- 为什么是第二档：不影响天天用的看直播，但都是“换机、升级、备份”这类一出问题就丢数据或装不上的功能；做完后发布说明的“已知问题”可以删掉对应几项。
- 已经做过的：S02.2、S02.3 走了 CHECKLIST 第 1～4 节的一部分（结果已填进 [CHECKLIST.md](../CHECKLIST.md)）；J04.1 给 WebDAV 加了 Digest 认证；Y01.1 第 4 条加了 Android 17 本地网络权限的申请。

## 目标和验收

1. [CHECKLIST.md](../CHECKLIST.md) 第 5 节第 1～8 条每条都有结果（通过 / 有问题 / 未验证并写原因），写进“结果”一列，带日期和“S02.4”。
2. 顺带的 4 条（下面阶段 5）有结果：哔哩哔哩扫码登录和重开后仍登录（4.6）、网页登录（4.7）、3.x 分享口令（4.11 的口令部分）、划掉应用后继续录（3.3）。
3. 每个问题都有现象、截图或日志、根因线索和去向（已有任务或建议的新任务）。
4. 本文件夹写 `record.md`：设备、构建（提交号、debug 或 profile）、逐条结果；README 的“发现”表和“结果”一节补上。
5. 用户的 3.x（`com.mystyle.purelive`）和它的数据始终没被碰过；应用内更新那条**停在系统安装器界面并取消**，不安装。

## 现状（读代码得出）

- 备份：`apps/pure_live/lib/shared/backup/backup_files.dart:70-91` 选默认目录（能写时 `/storage/emulated/0/Download/PureLive`，否则应用自己的外部目录）；`features/backup/backup_page.dart:86` 读 3.x 的 `backupDirectory`；恢复前预览 `shared/backup/backup_data.dart` 的 `RestorePreview`（`:196`）。
- WebDAV：`features/web_dav/`（`web_dav_client.dart`、`web_dav_auth.dart` 的 Basic 和 Digest）。
- 设备同步：`features/remote_receiver/remote_sync_service.dart`（HTTP 服务端口 39888，6 位配对码 `:205`、错的配对码次数 `:317-321`），mDNS 发现 `mdns_peers.dart`（`_purelive-sync._tcp`，兼容 3.x 的广播），扫码 `shared/qr_scan.dart`。
- 应用内更新：`features/version/update_feed.dart:353` 从 GitHub 读 `assets/version.json`（现在是 4.0.0、构建号 5001）；`features/version/update_download.dart:65-73` 先要“安装未知应用”权限、选下载目录、下载、交给系统安装器。**下载的是正式包 `com.mystyle.purelive`**，和用户的 3.x 同包名、同签名，装下去就会覆盖用户的 3.x。
- 字体：`app/fonts.dart` 的 `FontLibrary`（`:156`），字体仓库 `liuchuancong/fonts`（`:73-74`）。
- 播放代理：`app/platforms.dart:29-45` 读 `enableProxy`、`proxyHost`、`proxyPort`（3.x 的键）。
- 本地网络权限：`platform/system_access.dart:47`（`isLocalNetworkUrl`）、`:56`（`ensureLocalNetworkFor`）；投屏搜索前、局域网播放地址打开前申请；被拒的提示文字见 Y01.1 记录第 4 条。
- Twitch、Kick：`platform/native_http.dart`（系统 TLS），`platform/twitch_webview_http.dart`（无界面浏览器取完整性令牌）。

## 3.x 基线

- 各功能点的 3.x 位置见本文件夹 [README.md](README.md) 的“3.x 和现状”表（例如备份 `v3.2.11:lib/plugins/backup_recovery_service.dart:13`，扫码 `modules/backup/scan_page.dart:50`）。
- 要保留的行为：3.x 导出的备份能在 4.x 恢复（发布说明对用户的承诺）；设备同步和 3.x 设备能互相发现（mDNS 名字 `PureLive-<id 后 6 位>`）；应用内更新的流程照 3.x（先权限、再下载、再交给系统安装器）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 10 节真机验证、第 14 节规则）。
2. 本子分类的 [README.md](../README.md)（一次上机怎么做、CHECKLIST 怎么用）和 [CHECKLIST.md](../CHECKLIST.md) 第 5 节。
3. 本文件夹的 [README.md](README.md)；[J04.1 记录](../../../J-设置和数据/J04-WebDAV/J04.1-WebDAVDigest认证/record.md)；[Y01.1 记录](../../../Y-发布和运营/Y01-版本签名和发布/Y01.1-4.0.0发布前修复/record.md) 第 4 条（本地网络权限）。

## 范围

- 可以改：本文件夹的 `README.md`（发现、结果）、`record.md`、`verify/` 截图；[CHECKLIST.md](../CHECKLIST.md) 的“结果”一列。
- 不能改：任何代码；其他组的文档（问题写进报告，由维护者开任务）；版本号、`assets/version.json`、`assets/releases.json`；手机上的 `com.mystyle.purelive`（用户的 3.x）和它的数据；Windows 上 `D:\Soft\PureLive`、`D:\Soft\pure_live`。
- 不能做：在系统安装器里点“安装”（会用正式包覆盖用户的 3.x）；把真实的 WebDAV 账号、Cookie、配对码写进仓库或截图（截图前遮掉）。

## 方案和阶段

| 阶段 | 做什么（CHECKLIST 第 5 节的条目） | 需要准备 | 怎么算做完 |
|---|---|---|---|
| 1 | 备份恢复：5.1 创建完整备份、仅关注备份；恢复一个 3.x 导出的备份（先看预览再确认） | 一个 3.x 导出的备份文件（向用户要，或用 `packages/live_store/test/` 造的样本格式手写一个最小的）；推到 `/sdcard/Download/` | 5.1 有结果；文件确实在 `Download/PureLive`（`adb shell ls /sdcard/Download/PureLive`） |
| 2 | WebDAV：5.2 测试连接、上传、浏览、恢复、删除 | 一个 WebDAV 账号（坚果云等，用户提供；或在电脑上起一个临时服务，例如 `rclone serve webdav` 带 Basic 认证） | 5.2 有结果；Basic 和 Digest 至少一种真实通过 |
| 3 | 设备同步和扫码：5.3 两台设备互相发现、扫码配对、发送和接收（看预览） | 第二台设备：优先电脑上的 4.x Windows 测试版（工作目录里构建，不碰 `D:\Soft`）或 Android 模拟器；装 3.x 的第二设备只在用户提供时做 | 5.3 有结果；缺设备的部分写“未验证（缺设备）” |
| 4 | 应用内更新和字体：5.4、5.5；网络：5.6 播放代理、5.7 Twitch 和 Kick、5.8 本地网络权限 | 5.4 要一个版本号更低的测试包（`flutter build apk --debug --build-name=3.9.0 --build-number=1`）；5.6、5.7 要用户开着局域网代理 | 5.4～5.8 有结果；5.4 停在系统安装器并取消 |
| 5 | 顺带：4.6 哔哩哔哩扫码登录、杀掉重开仍登录；4.7 网页登录；4.11 复制一个 3.x 分享口令后切回应用；3.3 录制中划掉应用 | 一个哔哩哔哩账号（用户扫码）；一条 3.x 生成的口令（用户提供） | 四条有结果 |

每个阶段单独记录，可以分几次上机；5.9（3.x 数据导入）不在本任务，见 S04.1、J06.1。

## 测试

- 本任务不写自动测试。发现的问题由去向任务先写改之前会失败的测试再修。

## 真机验证（维护者在 K90 上做）

准备：WSL 里 `source ~/tools/purelive-env.sh`，`cd apps/pure_live`，`flutter build apk --profile --target-platform android-arm64`，`adb -s 192.168.1.2:5555 install -r build/app/outputs/flutter-apk/app-profile.apk`；`export PL_APP=com.mystyle.purelive.v4dev; source ~/tools/pl-adb.sh`；先 `adb -s 192.168.1.2:5555 logcat -d | grep "adbd service requested"`。

| 步骤 | 期望 |
|---|---|
| 1. 设置 → 数据 → 备份与恢复 → 创建完整备份 | 提示保存成功；`/sdcard/Download/PureLive/` 下有新文件；没有弹“所有文件访问” |
| 2. 同页“仅关注”备份 | 另一个文件，只含关注和关注的分区 |
| 3. 恢复 → 选 3.x 导出的备份 | 先出预览（关注、分区、历史、分组、屏蔽词、设置各有几条、哪些会改）；确认后关注页、设置变过来；不确认就什么都不变 |
| 4. 设置 → 数据 → 备份与恢复 → WebDAV → 新建配置 → 测试连接 | 成功提示；错误密码时提示认证失败而不是一直转圈 |
| 5. WebDAV 上传一个备份、浏览目录、下拉刷新、恢复、删除 | 都成功；下拉时文件列表不消失（A03.1） |
| 6. 第二台设备打开设备同步；K90 在 设置 → 数据 → 备份与恢复 → 设备同步 | 两边互相出现在列表；只经 mDNS 发现的 3.x 设备标“3.x 版本的设备” |
| 7. K90 扫第二台设备的二维码；发送 | 第二台出现确认；配对码对上后才能收；接收方先看到预览 |
| 8. 第二台向 K90 发送 | K90 先看到预览，确认后数据过去 |
| 9. 装版本号 3.9.0 的测试包，版本页“下载并安装” | 先要“安装未知应用”权限（没有时引导到系统页）；下载有进度、能取消和继续；完成后系统安装器出现——**点取消，不安装** |
| 10. 设置 → 外观 → 字体 → 下载一个字体并设为应用字体；杀掉重开 | 下载有进度；字体立即生效；重开后还在 |
| 11. 设置播放代理指向局域网代理，进一个海外直播间；关掉代理再进 | 开时能播；关时直连（海外平台通常失败并温和提示） |
| 12. （有代理时）进 Twitch、Kick 直播间各一个 | 能播；Twitch 不报完整性令牌错误 |
| 13. `adb shell getprop ro.build.version.sdk` 确认 37；系统设置里关掉本应用的“本地网络”权限；打开投屏、播放局域网地址的网络电视频道 | 弹系统的本地网络权限请求；拒绝时提示“未获得「本地网络」权限……”；允许后能搜到设备、能播 |
| 14. 账号 → 哔哩哔哩扫码登录；杀掉应用重开 | 显示用户名；重开后仍登录（Keystore 解密正常） |
| 15. 哔哩哔哩网页登录（短信） | 登录完成回到账号页显示用户名 |
| 16. 复制一条 3.x 生成的分享口令，切回应用 | 约 1 秒后弹“进入直播间”；同一口令只弹一次 |
| 17. 录制中，在最近任务里清除本应用（长按卡片找“清除”，或 `adb shell am kill com.mystyle.purelive.v4dev` 对照） | 记下现象：录制是否继续、回来后录制中心的状态（HyperOS 可能结束进程，发布说明已写） |

## 风险和注意

- **应用内更新会下载正式包**：同包名、同签名，装了就把用户的 3.x 覆盖成 4.x。只验证到系统安装器出现为止，点取消；下载的 APK 用完删掉（`adb shell rm` 下载目录里的文件）。
- 装 3.9.0 的测试包会覆盖平时的 `.v4dev` 测试包（同包名），测完重新装平时的包；测试包的数据会保留。
- 恢复备份会改测试包里的关注和设置：先用第 1 步的完整备份留底，测完恢复回去。
- WebDAV、哔哩哔哩账号、配对码都是真实凭据：截图前遮掉，不写进记录。
- 局域网代理和 Twitch、Kick 只在用户开着代理时做；不在 K90 上改系统代理。
- 设备同步时测试包要监听端口：手机和第二设备在同一个 Wi-Fi；Android 17 上同样会要本地网络权限（和第 13 步相关）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 本机工作区；只提交文档：提交信息以 `[S02.4]` 开头（英文），例如 `[S02.4] device checks: backup, WebDAV, sync, update, fonts`；不推 master。
- 提交前：`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：已经看完的阶段写进 `record.md`（每条结果），CHECKLIST 填上已有结果，提交；在 `record.md` 末尾写“停在哪”（下一个阶段、缺什么准备），维护者更新登记表的 `next`。

## 报告（中文，简洁）

每条（5.1～5.8 和顺带的 4 条）的结果；发现的问题（现象、根因线索、截图位置、建议去向）；缺设备或缺账号没做的；需要维护者决定的（例如发布说明“已知问题”删哪几项）。
