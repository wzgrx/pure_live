# S02.4 K90 验证：备份恢复、WebDAV、设备同步、扫码、应用内更新、字体、播放代理、Twitch 和 Kick

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（当时定的档位“应该”、规模“中，真机时间”）
- 类型：验证
- 来源：功能清点里标“没验证”、归给本任务的 8 个功能点（F-BAK-01～06 里的备份目录和设备同步、F-APP-05、F-APP-09、F-NET-02、F-AND-09、F-NET-04，[inventory/FEATURES.md](../../../inventory/FEATURES.md)）；4.0.0 发布说明“已知问题”写明“备份和恢复、WebDAV、设备同步、扫码、应用内更新、字体下载，以及 Twitch 和 Kick 还没在真机上完整走过”（[releases/v4.0.0.md](../../../Y-发布和运营/Y03-发布说明和README/releases/v4.0.0.md)）；2026-10-03 并入原 Q04.1 的播放代理和 Twitch 令牌验证（D-029）；2026-10-07 docs v2 核对后并入海外平台弹幕抽查（D01 的 14 个海外平台）和数据类的补验（日志导出 I01.3、关于和版本 A15.2、云账号说明 A12.3、网络电视和多画面进备份 E06.1）
- 旧编号：F.9d、T15b.4
- 相关：决定 D-019（只点测试包）、D-029；清单 [CHECKLIST.md](../CHECKLIST.md) 第 2 节第 10 条、第 5 节第 1～7、10～13 条；同一次上机可以做 [O04.1](../../../O-Android系统集成/O04-权限/O04.1-Android17本地网络权限/README.md)（第 5 节第 8 条，本地网络权限）和 [K02.1](../../../K-账号和登录/K02-登录状态/K02.1-Cookie和密码加密存储验证/README.md)；第 5 节第 9 条（3.x 数据导入）归 [S04.1](../../S04-覆盖安装验证/S04.1-覆盖安装3.x验证/README.md) 和 J06.1；任务书 [brief.md](brief.md)

## 目标

把“换机、升级、备份、海外平台”这几块在 K90 上逐条走一遍：备份和恢复（含 3.x 的备份）、WebDAV、设备同步和扫码、应用内更新、字体、日志导出、播放代理、Twitch 和 Kick、14 个海外平台的弹幕。通过的功能点在清点里改“完成”、对应的界面任务（A12.3～A12.6、A15.2、A11.2 的字体、D01 海外平台）补上真机结果；有问题的找根因、开任务。做完以后发布说明的“已知问题”可以删掉对应几项。

## 3.x 和现状

| 功能点 | 3.x（`v3.2.11:lib/`，文件:行） | 4.x（`apps/pure_live/lib/`） | 没验证的原因 | CHECKLIST |
|---|---|---|---|---|
| F-BAK-01～03 完整备份、仅关注、备份目录 | `plugins/backup_recovery_service.dart:13`、`:46`；`modules/backup/backup_page.dart:14`（每次备份都让用户选目录） | `features/backup/backup_page.dart`（读 3.x 的 `backupDirectory` `:86`）、`shared/backup/backup_files.dart:73` 的 `defaultBackupFolder`（没选过目录时：能写就用 `/storage/emulated/0/Download/PureLive` `:76`，否则应用自己的外部目录）、`shared/backup/backup_data.dart:196` 的 `RestorePreview` | Android 11 起 `Download/PureLive` 免权限写入没在真机试；恢复 3.x 备份的预览没在真机看 | 5.1 |
| E06.1 网络电视和多画面进备份 | 3.x 的备份不含网络电视列表 | `shared/backup/backup_data.dart`（多画面会话 `:33`）、`shared/backup/backup_iptv.dart`（E06.1 第 5 条） | 只有单元测试 | 5.13 |
| A12.3 云账号停用说明 | 3.x 有云账号登录（`v3.2.11:lib/modules/auth/`） | `features/auth/auth_page.dart`：从备份与恢复进的“云端账号（已停用）”说明页 | 静态页，没在真机点过 | 5.12 |
| F-BAK-04 WebDAV | `modules/web_dav/web_dav_page.dart:12`、`web_dav_controller.dart:50` | `features/web_dav/`（J04.1 加了 Digest 认证 `web_dav_auth.dart:18`、`:127`） | 没连过真实服务器 | 5.2 |
| F-BAK-05、F-BAK-06 设备同步、扫码 | `modules/remote_receiver/remote_sync_service.dart:14`、`:45`；`modules/backup/scan_page.dart:50` | `features/remote_receiver/remote_sync_service.dart`（端口从 39888 起、6 位配对码 `:205`、错 10 次换码 `maxWrongCodes` `:100`、`:317-321`、mDNS `_purelive-sync._tcp`）、`shared/qr_scan.dart` | 要第二台设备 | 5.3 |
| F-APP-05 应用内更新 | `common/widgets/download_apk_dialog.dart:32`、`:148` | `features/version/update_feed.dart:353`（读 `assets/version.json`）、`features/version/update_download.dart:65-73`（先要“安装未知应用”，再选目录、下载、交给系统安装器） | 权限页跳转、系统安装器没在真机走过；**下载的是正式包**，装了会覆盖用户的 3.x | 5.4 |
| A15.2 关于和版本 | `modules/about/`、`modules/version/` | `features/about/`、`features/version/`（下载对话框在 `features/version/update_download.dart`） | 页面没在真机看过 | 5.11 |
| F-APP-09 字体 | `plugins/font_download_manager.dart:12` | `app/fonts.dart:156` 的 `FontLibrary`，字体仓库 `liuchuancong/fonts`（`:73-74`） | 下载和注册后的界面没在真机看 | 5.5 |
| 日志导出（I01.3） | `core/common/log.dart`（本机 HTTP 服务在浏览器里看） | `app/app_log.dart`（`redactSecrets` `:127`）、`features/backup/log_page.dart`（`_share` `:83`） | 记录写“本次不往手机装”，没有归属的真机步骤 | 5.10 |
| F-NET-02 播放代理 | `player/core/playback_proxy_policy.dart:6` | `app/platforms.dart:29-45` 的 `PlaybackProxyPolicy`（读 `enableProxy`、`proxyHost`、`proxyPort`，O03.2 接上） | 要局域网代理 | 5.6 |
| F-AND-09、F-NET-04 原生 HTTP、Twitch 完整性令牌 | `android/.../NativeHttpChannel.kt:16`；`core/utils/twitch/twitch_web_integrity.dart:9` | `platform/native_http.dart`、`platform/twitch_webview_http.dart` | 要代理 | 5.7 |
| 海外平台弹幕（D01.8、D01.9、D01.11、D01.12、D01.15～D01.17、D01.20～D01.24、D01.30、D01.31） | 3.x 的各平台弹幕（其中 PandaTV、BIGO LIVE、SHOWROOM 3.x 没有聊天） | `packages/live_danmaku/lib/src/sites/` 各平台 | 要代理；SHOWROOM、BIGO LIVE、PandaTV 只用录制回放和本地服务器测过 | 2.10 |
| F-AND-04 本地网络权限 | `common/services/local_network_access.dart:10` | `platform/system_access.dart:47`（`isLocalNetworkUrl`）、`:56`（`ensureLocalNetworkFor`） | 归 O04.1；本任务的播放代理、设备同步会顺带触发 | 5.8（O04.1） |

## 方案

不改代码，在 K90 上分六个阶段走（每个阶段能单独上机、单独记结果；登记表现在没有阶段，开工时按这里补）：

| 阶段 | 内容 | CHECKLIST | 要准备的 |
|---|---|---|---|
| 1 | 备份恢复：完整备份、仅关注、恢复 3.x 的备份（看预览）；网络电视和多画面进备份；云账号停用说明页；扫码页的手电筒和相机权限被拒 | 5.1、5.12、5.13 | 一个 3.x 导出的备份文件 |
| 2 | WebDAV：测试连接、上传、浏览、恢复、删除；错误密码和断网的提示 | 5.2 | 一个 WebDAV 账号（用户的坚果云，或电脑上的临时服务） |
| 3 | 设备同步和扫码：互相发现、扫码配对、发送和接收、接收前的预览 | 5.3 | 第二台设备（电脑上的 4.x Windows 测试版或 Android 模拟器） |
| 4 | 应用内更新（到系统安装器为止）、关于和版本、字体、日志导出 | 5.4、5.5、5.10、5.11 | 一个版本号更低的测试包 |
| 5 | 网络：播放代理；和 O04.1 同一次看本地网络权限 | 5.6（5.8 归 O04.1） | 用户开着局域网代理 |
| 6 | 海外平台：Twitch、Kick 播放；14 个海外平台弹幕抽查（PandaTV 连续 35 分钟） | 5.7、2.10 | 用户开着代理 |

- 结果写进本文件夹的 `verify.md`（照 [templates/verify.md](../../../templates/verify.md)）和 CHECKLIST 的“结果”一列；截图在 `verify/`。
- 对应的界面和平台任务补结果：A12.3～A12.6 的“实现和验证”、A15.2、A11.2（字体）、I01.3（日志）、D01 各海外平台、E03.2（Twitch）、E03.16（Kick）、E06.1（备份）——只在它们的“验证”一节加一行“K90（S02.4，日期）：通过 / 有问题”，不改正文。
- 通过的功能点在 [FEATURES.md](../../../inventory/FEATURES.md) 改“完成”并写日期和本任务。

## 发现

| # | 条目 | 现象 | 根因 | 归到 |
|---|---|---|---|---|
| | | | | |

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
| 2026-10-03 | 写任务书（docs v2）；CHECKLIST 5.8 改成在 K90 上验证本地网络权限（K90 是 Android 17）；并入原 Q04.1 的播放代理和 Twitch 令牌（D-029），标题加“播放代理” |
| 2026-10-07 | docs v2 核对：并入海外平台弹幕、日志导出、关于和版本、云账号说明、网络电视进备份；原来顺带的账号登录、剪贴板口令移到 S02.6，划掉应用后继续录移到 H01.4；分成六个阶段 |

## 验证

- 本任务本身就是真机验证；步骤和期望在 [brief.md](brief.md)，结果写进 `verify.md` 和 CHECKLIST。
- 自动测试：无新增。各功能的测试在原任务里（例：`apps/pure_live/test/features/backup/`、`test/features/web_dav/`、`test/features/remote_receiver/remote_sync_test.dart`、`test/features/version/update_dialogs_test.dart`、`packages/live_danmaku/test/` 的各平台用例）。

## 留下的问题

- 和 3.x 设备互相发现（设备同步的 mDNS 兼容）要一台装 3.x 的第二设备；K90 上的 3.x 是用户日常用的，不能拿来测。可以用 S04.1 的模拟器装 3.2.11 当第二台（同一台电脑上，桥接网络才能互相发现）；做不到时写“未验证（缺设备）”，留给 S03.1。
- 发布说明“已知问题”里哪些可以删，由维护者按结果决定（Y03）。
