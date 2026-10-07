# S02.4 K90 验证：备份恢复、WebDAV、设备同步、扫码、应用内更新、字体、Twitch 和 Kick

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（当时定的档位“应该”、规模“中，真机时间”）
- 类型：验证
- 来源：功能清点里标“没验证”的功能点；4.0.0 发布说明“已知问题”写明“备份和恢复、WebDAV、设备同步、扫码、应用内更新、字体下载，以及 Twitch 和 Kick 还没在真机上完整走过”（[releases/v4.0.0.md](../../../Y-发布和运营/Y03-发布说明和README/releases/v4.0.0.md)）
- 旧编号：F.9d、T15b.4
- 相关：功能点 F-BAK-01～06、F-APP-05、F-APP-09、F-NET-02、F-AND-04、F-AND-09、F-NET-04（[inventory/FEATURES.md](../../../inventory/FEATURES.md)）；清单 [CHECKLIST.md](../CHECKLIST.md) 第 5 节；顺带 S02.3 留下的账号登录、剪贴板口令、划掉应用后继续录；可以和 [O02.1](../../../O-Android系统集成/O02-画中画/README.md)、[K02.1](../../../K-账号和登录/K02-登录状态/README.md) 同一次上机。第 5 节第 9 条（3.x 数据导入）归 [S04.1](../../S04-覆盖安装验证/S04.1-覆盖安装3.x验证/README.md) 和 J06.1
- 涉及代码：不改代码（发现问题归到对应任务）；评审页：不需要；任务书 [brief.md](brief.md)

## 怎么做

1. 照 [CHECKLIST.md](../CHECKLIST.md) 第 5 节第 1～8 条逐条做（先确认前台应用，不碰 3.x），具体步骤、顺序和准备见 [brief.md](brief.md)。
2. 结果写进清单每条的“结果”一列：通过（日期，S02.4）/ 有问题（现象，归到哪个任务）；逐条记录写进本文件夹的 `record.md`。
3. 有问题的截图、抓开发版的 `adb logcat`，在下表记下，先找根因再归任务。

## 发现

| # | 条目 | 现象 | 根因 | 归到 |
|---|---|---|---|---|
| | | | | |

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
| 2026-10-03 | 写任务书（docs v2）；CHECKLIST 5.8 改成在 K90 上验证本地网络权限（K90 是 Android 17） |

## 3.x 和现状

| 功能点 | 3.x（文件:行） | 4.x（文件） | 没验证的原因 |
|---|---|---|---|
| F-BAK-01～03 完整备份、仅关注、备份目录 | `plugins/backup_recovery_service.dart:13`、`:46`；`modules/backup/backup_page.dart:14` | `features/backup/backup_page.dart`、`shared/backup/backup_files.dart`（默认 `Download/PureLive`，`:70-91`）、`shared/backup/backup_data.dart` | Android 11 起 `Download/PureLive` 免权限写入没在真机试；恢复 3.x 备份的预览没在真机看 |
| F-BAK-04 WebDAV | `modules/web_dav/web_dav_page.dart:12`、`web_dav_controller.dart:50` | `features/web_dav/`（J04.1 加了 Digest 认证） | 没连过真实服务器 |
| F-BAK-05、F-BAK-06 设备同步、扫码 | `modules/remote_receiver/remote_sync_service.dart:14`、`:45`；`modules/backup/scan_page.dart:50` | `features/remote_receiver/`、`shared/qr_scan.dart` | 要第二台设备 |
| F-APP-05 应用内更新 | `common/widgets/download_apk_dialog.dart:32`、`:148` | `app/downloads.dart`、`features/version/update_download.dart` | 权限页跳转、系统安装器没在真机走过 |
| F-APP-09 字体 | `plugins/font_download_manager.dart:12` | `app/fonts.dart`（`FontLibrary`） | 下载和注册后的界面没在真机看 |
| F-NET-02 播放代理 | `player/core/playback_proxy_policy.dart:6` | `app/platforms.dart:29-45`（O03.2 接上） | 要局域网代理 |
| F-AND-04 本地网络权限 | `common/services/local_network_access.dart:10` | `platform/system_access.dart:47-60`（Y01.1 第 4 条） | 当时误以为 K90 不是 Android 17 |
| F-AND-09、F-NET-04 原生 HTTP、Twitch 完整性令牌 | `android/.../NativeHttpChannel.kt:16`；`core/utils/twitch/twitch_web_integrity.dart:9` | `platform/native_http.dart`、`platform/twitch_webview_http.dart` | 要代理 |

## 方案

- 分五个阶段上机（详见 [brief.md](brief.md)）：1 备份恢复（5.1）；2 WebDAV（5.2）；3 设备同步和扫码（5.3，要第二台设备）；4 应用内更新、字体、播放代理、Twitch 和 Kick、本地网络权限（5.4～5.8）；5 顺带 S02.3 留下的账号登录、3.x 分享口令、划掉应用后继续录。
- 应用内更新只验证到系统安装器出现为止：下载的是正式包 `com.mystyle.purelive`，装了会覆盖用户的 3.x。
- 做完后在这里写“结果”：每条结果、发现的问题和去向、提交。

## 验证

- 本任务本身就是真机验证；步骤和期望在 [brief.md](brief.md)，结果写进 `record.md` 和 CHECKLIST 第 5 节。

## 留下的问题

- 和 3.x 设备互相发现（设备同步的 mDNS 兼容）要一台装 3.x 的第二设备；K90 上的 3.x 是用户日常用的，不能拿来测。没有时在结果里写“未验证（缺设备）”，留给 S03.1。
