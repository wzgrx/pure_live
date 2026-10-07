# S02.4 K90 验证：备份恢复、WebDAV、设备同步、扫码、应用内更新、字体、播放代理、Twitch 和 Kick：任务书

## 背景

- 来源：功能清点（[inventory/FEATURES.md](../../../inventory/FEATURES.md)）里归给本任务的 8 个“没验证”功能点；4.0.0 发布说明“已知问题”对用户写明“多画面、网络电视、投屏、账号登录、备份和恢复、WebDAV、设备同步、扫码、应用内更新、字体下载，以及 Twitch 和 Kick……还没在真机上完整走过，遇到问题请反馈”；D-029 把原 Q04.1 的播放代理（F-NET-02）和 Twitch 令牌（F-NET-04）并进来；2026-10-07 docs v2 核对时，各组发现的“登记完成但没有真机结果”里**海外平台和数据类**的部分也并进来（见子分类说明“已知问题”第 1 行）：14 个海外平台的弹幕（D01）、日志导出（I01.3）、关于和版本（A15.2）、云账号停用说明（A12.3）、网络电视和多画面进备份（E06.1 第 5 条）。
- 现象：没有已知的坏现象；风险在于这些功能只在组件测试和电脑上跑过。例：备份默认写 `/storage/emulated/0/Download/PureLive`，Android 11 起的分区存储下没在真机试过；SHOWROOM、BIGO LIVE、PandaTV 的弹幕连真实服务器都没接过；应用内更新的“安装未知应用”权限页跳转没走过。
- 为什么是第二档：不影响天天用的看直播，但都是“换机、升级、备份”这类一出问题就丢数据或装不上的功能，以及要代理才能用的海外平台；做完后发布说明的“已知问题”可以删掉对应几项。决定 D-019（只点测试包，不碰 3.x 和正式包）。
- 已经做过的：S02.2、S02.3 走了 CHECKLIST 第 1～4 节的一部分；J04.1 给 WebDAV 加了 Digest 认证；Y01.1 第 4 条加了 Android 17 本地网络权限的申请；O03.2 接上了播放代理。

## 目标和验收

1. [CHECKLIST.md](../CHECKLIST.md) 里“由谁验证”写着 S02.4 的 13 条（第 2 节第 10 条，第 5 节第 1～7、10～13 条）每条都有结果（通过 / 有问题 / 没验证并写原因），写进“结果”一列，带日期和“S02.4”。
2. 本文件夹写 `verify.md`（照 `docs/templates/verify.md`）：设备、构建（提交号、debug 或 profile）、下面“真机验证”表每一步的结果；截图在 `verify/`（宽不超过 1080、单张不超过 300 KB，凭据打码）。
3. 每个问题都有现象、截图或日志、根因线索（文件:行）和去向（已有任务或建议的新任务）；README 的“发现”表补上。
4. 通过的功能点在 `docs/inventory/FEATURES.md` 改“完成”，备注“K90（S02.4，日期）”，统计表同步；对应任务（A12.3～A12.6、A15.2、A11.2 字体、I01.3、E03.2、E03.16、E06.1、D01 的 14 个海外平台）的“验证”一节各加一行结果。
5. 用户的 3.x（`com.mystyle.purelive`）和它的数据始终没被碰过；应用内更新那一步**停在系统安装器并取消**，不安装；测试包恢复成测试前的关注和设置（第 1 步的完整备份留底）。

## 现状（读代码得出，写文件:行）

路径相对 `apps/pure_live/lib/`。

- 备份：`shared/backup/backup_files.dart:73` 的 `defaultBackupFolder`：Android 上候选先是 `/storage/emulated/0/Download/PureLive`（`:76`），再是应用外部目录下的 `backup`、应用支持目录下的 `backup`，取第一个 `isWritableFolder` 的；`features/backup/backup_page.dart:86` 先读 3.x 的设置 `backupDirectory`（用户选过就用它，`:213` 保存）；恢复前预览 `shared/backup/backup_data.dart:196` 的 `RestorePreview`；多画面会话（`:33` 起，`{"multiview": {"session": …}}`）和网络电视列表（`shared/backup/backup_iptv.dart`）是 E06.1 第 5 条加的。
- 云账号停用说明：`features/auth/auth_page.dart`（从备份与恢复页进）。
- WebDAV：`features/web_dav/`（`web_dav_client.dart`；`web_dav_auth.dart:18` Basic、`:127` Digest）。
- 设备同步：`features/remote_receiver/remote_sync_service.dart`：HTTP 服务从 39888 起找空闲端口（`:66`）、6 位配对码（`:205`）、错的配对码 10 次后换码（`maxWrongCodes` `:100`、`:317-321`）；广播和发现走 UDP 39889 和 mDNS `_purelive-sync._tcp`（`:73`，兼容 3.x 的 TXT）；手动地址的提示 `192.168.1.100:39888`（`remote_receiver_page.dart:611`）；扫码 `shared/qr_scan.dart`。
- 应用内更新：`features/version/update_feed.dart:353` 从 GitHub（含镜像）读 `assets/version.json`（现在是 4.0.0、构建号 5001）；`features/version/update_download.dart:65-73`：Android 先要“安装未知应用”，没有可用的下载目录时让用户选，再下载（进度、取消、继续），最后交给系统安装器。**下载的是正式包 `com.mystyle.purelive`**，和用户的 3.x 同包名、同签名，装下去就会覆盖用户的 3.x。
- 字体：`app/fonts.dart:156` 的 `FontLibrary`，字体仓库 `liuchuancong/fonts`（`:73-74`）；设置 → 外观 →“字体和字号”组 →“字体”（`features/settings/settings_catalog.dart:441-446`）。
- 日志：`app/app_log.dart`（`AppLog` 内存 2000 条，`redactSecrets` `:127` 在写入前去掉 Cookie 和令牌）；设置 → 数据 → 日志管理（`features/backup/log_page.dart`：`_share` `:83` 先导出到临时目录再走系统分享，分享不了时复制到剪贴板并提示 `settings_log_copied_instead`；`_openFolder` `:95`；`_clear` `:109`）。
- 播放代理：设置 → 通用和网络 → 自定义网络代理 →“播放器内核代理”组 →“启用播放代理”（`settings_catalog.dart:1473-1480`）；规则 `app/platforms.dart:29-45` 的 `PlaybackProxyPolicy`（读 3.x 的键 `enableProxy`、`proxyHost`、`proxyPort`，关掉时视频流直连，即使开着应用层代理）。
- Twitch、Kick：`platform/native_http.dart`（Android 系统 TLS）、`platform/twitch_webview_http.dart`（无界面浏览器取完整性令牌）。
- 海外平台弹幕：`packages/live_danmaku/lib/src/sites/` 各平台；PandaTV 令牌 30 分钟到期前 60 秒悄悄换连接（D01.22 README），所以要连续看 35 分钟才能看到换连接。
- 本地网络权限：`platform/system_access.dart:47`（`isLocalNetworkUrl`）、`:56`（`ensureLocalNetworkFor`）；归 [O04.1](../../../O-Android系统集成/O04-权限/O04.1-Android17本地网络权限/README.md)，本任务的播放代理（局域网地址）和设备同步会触发它。

## 3.x 基线

- 各功能点的 3.x 位置见本文件夹 [README.md](README.md) 的“3.x 和现状”表（例：备份 `v3.2.11:lib/plugins/backup_recovery_service.dart:13`，扫码 `lib/modules/backup/scan_page.dart:50`，应用内更新 `lib/common/widgets/download_apk_dialog.dart:32`）。
- 要保留的行为：3.x 导出的备份能在 4.x 恢复（发布说明对用户的承诺）；设备同步和 3.x 设备能互相发现（mDNS 名字 `PureLive-<id 后 6 位>`）；应用内更新的流程照 3.x（先权限、再下载、再交给系统安装器）；播放代理和应用层代理分开（3.x `playback_proxy_policy.dart:6`）。
- 和 3.x 不同、不算问题的：3.x 每次备份都让用户选目录，4.x 没选过时用 `Download/PureLive`；3.x 的日志在浏览器里看，4.x 在应用里看和导出。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 10 节真机验证、第 14 节规则）。
2. 本子分类的 [README.md](../README.md)（一次上机怎么做：构建、安装、`pl-adb.sh`、只断测试包的网、截图、日志）和 [CHECKLIST.md](../CHECKLIST.md) 第 2 节第 10 条、第 5 节。
3. 本文件夹的 [README.md](README.md)；[J04.1 记录](../../../J-设置和数据/J04-WebDAV/J04.1-WebDAVDigest认证/record.md)；[Y01.1 记录](../../../Y-发布和运营/Y01-版本签名和发布/Y01.1-4.0.0发布前修复/record.md) 第 4 条（本地网络权限）；A12.4～A12.6、A15.2 README 的“实现和验证”（各页面要看的细节）；`docs/D-弹幕/D01-平台弹幕协议/D01.22-PandaTV弹幕/README.md`（令牌换连接）。

## 范围

- 可以改：本文件夹的 `README.md`（发现、结果）、`verify.md`、`verify/`；[CHECKLIST.md](../CHECKLIST.md) 的“结果”一列；`docs/inventory/FEATURES.md` 里本任务这些功能点的状态和统计；上面验收第 4 条列的任务 README 的“验证”一节（只加结果行）。
- 不能改：任何代码和测试；其他文档的正文（问题写进报告，由维护者开任务）；版本号、`assets/version.json`、`assets/releases.json`；手机上的 `com.mystyle.purelive`（用户的 3.x）和它的数据；Windows 上 `D:\Soft\PureLive`、`D:\Soft\pure_live`。
- 不能做：在系统安装器里点“安装”（会用正式包覆盖用户的 3.x）；把真实的 WebDAV 账号、Cookie、配对码写进仓库或截图（截图前遮掉）；在 K90 上改系统代理；关 Wi-Fi（adb 会断）。

## 方案和阶段

| 阶段 | 做什么（CHECKLIST 条目） | 需要准备 | 怎么算做完 |
|---|---|---|---|
| 1 | 备份恢复：完整备份、仅关注备份、恢复 3.x 导出的备份（先看预览再确认）；网络电视和多画面进备份（5.13）；云账号停用说明（5.12）；扫码页的手电筒和相机权限被拒的说明 | 一个 3.x 导出的备份文件（向用户要，或在 S04.1 的模拟器里用 3.2.11 导出一个）；推到 `/sdcard/Download/` | 5.1、5.12、5.13 有结果；文件确实在 `Download/PureLive`（`adb shell ls -l /sdcard/Download/PureLive`） |
| 2 | WebDAV（5.2）：添加服务器、测试连接、上传、浏览、下拉刷新、点文件看预览后恢复、删除；错误密码、断网时的提示 | 一个 WebDAV 账号（用户的坚果云；或电脑上 `rclone serve webdav --addr :8080 --user t --pass t <临时目录>` 起一个带 Basic 认证的临时服务，同一 Wi-Fi） | 5.2 有结果；Basic 和 Digest 至少一种真实通过；坚果云的错误是否都落到四类原因里记下来 |
| 3 | 设备同步和扫码（5.3）：两台设备互相发现、扫码配对、发送和接收（看预览）、错的配对码 | 第二台设备：优先 S04.1 的 Android 模拟器（装测试包；桥接网络）或电脑上的 4.x Windows 测试版（工作目录里构建，不碰 `D:\Soft`）；装 3.x 的第二设备（模拟器装 3.2.11）用来看 3.x 兼容 | 5.3 有结果；缺设备的部分写“没验证（缺设备）” |
| 4 | 应用内更新（5.4，到系统安装器为止）、关于和版本（5.11）、字体（5.5）、日志导出（5.10） | 5.4 要一个版本号更低的测试包：`flutter build apk --debug --build-name=3.9.0 --build-number=1` | 5.4、5.5、5.10、5.11 有结果；5.4 停在系统安装器并取消，下载的 APK 删掉 |
| 5 | 播放代理（5.6）；同一次上机做 O04.1 的本地网络权限（5.8，结果写 O04.1） | 用户开着局域网代理（地址、端口由用户给） | 5.6 有结果 |
| 6 | 海外平台：Twitch、Kick 播放（5.7）；14 个海外平台弹幕抽查（2.10），PandaTV 连续 35 分钟 | 用户开着代理；各平台各找一个在播的直播间（没有在播的写“跳过”） | 5.7、2.10 有结果；每个平台一行（第一条聊天出现的秒数、2 分钟里有没有断开） |

每个阶段单独记录，可以分几次上机；5.9（3.x 数据导入）不在本任务，见 S04.1、J06.1。

## 测试

- 本任务不写自动测试。发现的问题由去向任务先写改之前会失败的测试再修。
- 构建：WSL 里 `source ~/tools/purelive-env.sh`，根目录 `bash tools/ffmpeg_kit/fetch.sh`、`flutter pub get`，`cd apps/pure_live && flutter build apk --profile --target-platform android-arm64`；在 `verify.md` 写下提交号。

## 真机验证（维护者在 K90 上做）

准备：`adb -s 192.168.1.2:5555 install -r build/app/outputs/flutter-apk/app-profile.apk`；`export PL_APP=com.mystyle.purelive.v4dev; source ~/tools/pl-adb.sh`；先 `adb -s 192.168.1.2:5555 logcat -d | grep "adbd service requested"`；“只断测试包的网”的命令见子分类说明第 5 步。

| 步骤 | 期望 |
|---|---|
| 1. 设置 → 数据 → 备份与恢复 → 创建完整备份 | 提示保存成功；`/sdcard/Download/PureLive/` 下有新文件；没有弹“所有文件访问” |
| 2. 同页“仅关注”备份 | 另一个文件，只含关注和关注的分区 |
| 3. 恢复 → 选 3.x 导出的备份 | 先出预览（关注、分区、历史、分组、屏蔽词、设置各有几条、哪些会改）；确认后关注页、设置变过来；不确认就什么都不变 |
| 4. 网络电视里删一个播放列表、多画面关掉“恢复上次”；恢复第 1 步的备份 | 预览里列出网络电视；恢复后播放列表和“恢复上次”回来（E06.1） |
| 5. 备份与恢复 →“云端账号（已停用）” | 说明页，四行（备份、WebDAV、设备同步、账号）都能进对应页面（A12.3） |
| 6. 备份与恢复 → 扫码；系统弹相机权限时先拒绝，再允许；打开手电筒 | 拒绝时页面说明为什么要相机、有“去设置”；允许后能扫；手电筒能开关 |
| 7. 备份与恢复 → WebDAV → 添加新配置 → 测试连接；再把密码改错测一次 | 正确时“连接成功”；错误密码时提示认证失败而不是一直转圈 |
| 8. WebDAV 上传一个备份、浏览目录、下拉刷新、点文件看预览后恢复、删除；只断测试包的网再下拉 | 都成功；下拉时文件列表不消失（A03.1）；断网时提示网络问题、列表留着 |
| 9. 第二台设备打开设备同步；K90 在 备份与恢复 → 设备同步 | 两边互相出现在列表；只经 mDNS 发现的 3.x 设备标“3.x 版本的设备”；第一次时 K90 弹系统“本地网络”权限（结果记给 O04.1） |
| 10. K90 扫第二台设备的二维码；发送 | 第二台出现确认；配对码对上后才能收；接收方先看到预览，确认后才写入 |
| 11. 第二台向 K90 发送；故意输错配对码几次 | K90 先看到预览，确认后数据过去；错的配对码被拒，错满 10 次后配对码换新 |
| 12. 装版本号 3.9.0 的测试包，首页更多 → 关于 → 在线更新 →“下载并安装” | 先要“安装未知应用”权限（没有时引导到系统页，回来后接着走）；下载有进度、能取消和继续；完成后系统安装器出现——**点取消，不安装**；然后 `adb shell rm` 掉下载的 APK，重新装平时的测试包 |
| 13. 关于页、在线更新、版本历史（竖屏点一行，横屏再看） | 顶栏只有返回、Logo 不弹跳；状态卡、“本机”标在 ARM64、下载源能收起和展开；版本历史竖屏点一行出详情、✕ 关，横屏左右分栏（A15.2） |
| 14. 设置 → 外观 → 字体和字号 → 字体 → 下载一个字体并设为应用字体；杀掉重开 | 下载有进度；字体立即生效；重开后还在 |
| 15. 设置 → 数据 → 日志管理：打开“启用本地日志”，进一个直播间再回来；“导出/分享”选一个能收文件的应用；“打开日志目录”；“清除日志” | 列表里有本次运行的日志；导出出现系统分享面板（分享不了时提示“无法分享文件，日志已复制到剪贴板”）；导出的文件里搜 `SESSDATA`、`access_token`、`Cookie:` 都找不到；清除前确认，清除后“本次运行还没有日志” |
| 16. 设置 → 通用和网络 → 自定义网络代理 →“启用播放代理”填局域网代理；进一个海外直播间；关掉再进 | 开时能播（代理那边能看到视频流请求）；关时直连（海外平台通常失败并温和提示）；局域网地址第一次用时弹本地网络权限（记给 O04.1） |
| 17. （有代理时）进 Twitch、Kick 直播间各一个 | 能播；Twitch 不报完整性令牌错误；Kick 的 API 走系统 TLS 能取到流 |
| 18. （有代理时）SOOP、Twitch、Kick、YouTube、CHZZK、niconico、TwitCasting、Picarto、SHOWROOM、BIGO LIVE、FC2、Steam、17LIVE 各进一个在播的直播间，开着聊天列表看 2 分钟 | 聊天区“开始连接弹幕服务器”“弹幕服务器连接正常”；有人发言时出现聊天；2 分钟不断开、不反复重连；记下第一条聊天出现的秒数 |
| 19. （有代理时）PandaTV 一个在播的直播间，开着聊天列表连续看 35 分钟 | 聊天一直在来；30 分钟左右换连接时界面不出现“正在重连”；结束时记下总条数 |
| 20. 测完：恢复第 1 步的完整备份；删掉临时的 WebDAV 配置、设备同步记录；关掉播放代理、本地日志 | 测试包回到测试前的关注和设置 |

## 风险和注意

- **应用内更新会下载正式包**：同包名、同签名，装了就把用户的 3.x 覆盖成 4.x。只验证到系统安装器出现为止，点取消；下载的 APK 用完删掉。
- 装 3.9.0 的测试包会覆盖平时的 `.v4dev` 测试包（同包名），测完重新装平时的包；测试包的数据会保留。
- 恢复备份会改测试包里的关注和设置：先用第 1 步的完整备份留底，测完恢复回去。
- WebDAV、哔哩哔哩账号、配对码、代理地址都是真实凭据：截图前遮掉，不写进记录。
- 局域网代理、Twitch、Kick、海外弹幕只在用户开着代理时做；不在 K90 上改系统代理。
- 设备同步时测试包要监听端口：手机和第二设备在同一个 Wi-Fi；Android 模拟器默认是 NAT 网络，互相发现要桥接（或手动输地址 `adb forward` 不行，要真实局域网地址），做不到就写“没验证（缺设备）”。
- PandaTV 35 分钟期间不要让手机灭屏（屏幕常亮开着）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 本机工作区；只提交文档：提交信息以 `[S02.4]` 开头（英文），例如 `[S02.4] device checks stage 1: backup and restore`；不推 master。
- 提交前：`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：已经看完的阶段写进 `verify.md`（每条结果），CHECKLIST 填上已有结果，提交；在 `verify.md` 末尾写“停在哪”（下一个阶段、缺什么准备），更新登记表的 `done`、`next`（六个阶段 2026-10-07 已登记）。

## 报告（中文，简洁）

每个阶段每条的结果（CHECKLIST 13 条和上表 20 步）；发现的问题（现象、根因线索、截图位置、建议去向）；缺设备、缺账号、缺代理没做的；FEATURES 改了哪几项；需要维护者决定的（例如发布说明“已知问题”删哪几项）。
