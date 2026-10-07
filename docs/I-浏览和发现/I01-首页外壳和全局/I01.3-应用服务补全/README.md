# I01.3 应用服务补全

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（应用服务，含 Android 原生一个插件）
- 来源：O03.1 记录“没做，留给 Y01”的应用内更新和 bonsoir；J01.1 记录“留给后续”和“只存设置”的核对；I08.1 版本页、设备同步的“留给后续”
- 旧编号：M12.4、T07a.3
- 相关：I01.1、I01.2；O03.1（插件和桌面外壳）；J01.1（设置注册表）；I08.1（版本页、设备同步页）；之后的 A15.2、A06.3（新版本对话框和应用内下载的界面）、A12.6（设备同步界面）、J05（设备同步逻辑）、Y02（更新通道）；提交 `0e4ecb34e`；记录 [record.md](record.md)

## 目标

把 3.x 有、4.x 还只存了设置没生效的几项应用级服务补上：下载字体、应用内下载并安装更新、和 3.x 设备互相发现（mDNS）、显示模式信息、日志（应用内查看、写文件、脱敏）、Android 17 本地网络权限、刷新缩略图和下载目录；并逐项核对 J01.1 列出的“只存未生效”的设置还剩哪些。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在（文件:行） | 结果 |
|---|---|---|---|
| 字体下载 | `lib/plugins/font_download_manager.dart`、`font_settings_controller.dart`；文件在 `<数据目录>/DOWNLOADS/fonts` | `apps/pure_live/lib/app/fonts.dart`：`FontLibrary`（`:156`），清单 `assets/fonts/fonts-manifest.json`（57 个），镜像竞速、`.pending` 原子替换、3.x 选过的字体从 3.x 目录复制 | 一致，文件放 `<数据目录>/fonts` |
| 应用内更新 | `common/widgets/download_apk_dialog.dart`、`plugins/update.dart`：每次从头下 | `lib/app/downloads.dart`：`FileDownloader`（`:98`，`.part` 续传、换源接着下）；界面 `features/version/update_download.dart` | 断点续传；之后界面由 A15.2、A06.3 重做 |
| 设备发现（mDNS） | `modules/remote_receiver/remote_sync_service.dart` 的 bonsoir | `features/remote_receiver/mdns_peers.dart`（`_purelive-sync._tcp`，TXT 同 3.x） | 能发现 3.x 设备，标“3.x 版本的设备” |
| 显示模式 | `common/services/display_mode_service.dart`，只显示 | `lib/platform/display_mode.dart`、设置的“界面刷新率”“Windows 动态刷新率”两行 | 一致，多显示“可用”的刷新率 |
| 日志 | `core/common/log.dart`、`log_controller.dart`：本机 HTTP 服务在浏览器里看 | `lib/app/app_log.dart`：`AppLog`（`:144`，2000 条）、`redactSecrets`（`:127`）；设置 → 数据与备份 → 日志管理（`features/settings/log_page.dart`） | 应用内看、导出 / 分享，写入前脱敏 |
| 本地网络权限（Android 17） | `common/services/local_network_access.dart` | `android/.../SystemAccessPlugin.kt`、`lib/platform/system_access.dart` 的 `LocalNetworkGuard`（`:67`） | 有代理指向局域网时申请一次 |
| 刷新缩略图、下载目录 | `cache_controller.dart` 的 `refreshImageCache()`；下载前弹“选择下载目录” | `features/settings/data_tools.dart`：`CoverRefreshTimer`（`:87`）、`RefreshCoversTile`（`:285`）、`DownloadDirectoryTile`（`:334`） | 不再弹选择框，默认目录可在缓存页改 |

## 结果

- 做了什么（详见 [record.md](record.md)“每项的做法”）：上表 7 项；协调者追加的字体清单和 WebDAV 帮助截图搬进应用资源、Windows 标题栏拖动时显示尺寸、启动页时标题栏渐变。
- 核对“只存设置”（record.md 第二张表）：定时刷新关注（I04.1）、定时刷新封面（O03.1）、分页控件（I02.1、I03.1）、关闭窗口行为（O03.1）已生效；Windows 窗口大小立即应用、开机启动状态本任务做了；“退出时销毁播放器”、后台播放、录制等归直播间和录制任务。
- 新设置 3 个（`live_store`）：`downloadDirectoryPath`（`cache`，本机路径、不进备份，3.x 同名键导入）、`enableLocalLog`（默认关）、`logLevel`（默认 `info`）。
- 原生：新文件 `SystemAccessPlugin.kt`（`canInstallPackages`、`openInstallSettings`、`localNetworkGranted`、`requestLocalNetwork`）；Windows 没改 C++。
- 有意差异 4 条：日志在应用内看、不开本机 HTTP 服务；下载前不弹目录选择；字体放 `<数据目录>/fonts`；刷新率多显示“可用”。
- 翻译键：中英文各加 30 个（`settings_log_*` 18 个、`update_*` 6 个……）。
- 提交 `0e4ecb34e`（2026-10-01）。
- 测试：新增 `test/services_test.dart` 11 个（现在 13 个）、`version_page_test.dart` 1 个；`live_store` 迁移测试 1 个；应用全量 217 个。

## 验证

- 自动测试：`apps/pure_live/test/services_test.dart`（脱敏、日志、下载续传和换源、字体清单和下载注册、显示模式、本地网络权限只问一次、mDNS 发现 3.x 设备）、`test/features/version/` 的应用内下载用例、`test/platform/display_mode_test.dart`。
- 真机：当时“本次不往手机装”（record.md“没验证的部分”列了 Android 8 项、Windows 9 项）。之后：应用内下载和安装由 A15.2、S02.5 的清单看；字体、应用内更新、本地网络权限、设备同步列在 [S02.4](../../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md)（未开始）；设置里刷新率那一行的显示在 R02.2 的真机步骤里（`R02-刷新率/R02.2-刷新率策略修正/record.md` 第 73 行起）。日志导出没有归属的真机步骤。

## 留下的问题

- Windows 部分全部没构建、没运行（安装包、`explorer /select`、窗口大小、启动项、标题栏、显示器信息、`bonsoir_windows`）→ X01（D-004）。
- 3.x ↔ 4.x 设备互相发现和配对同步没在真机上测 → S02.4 第 3 阶段（要第二台设备）；设备同步的逻辑归 J05。
- 下载镜像的真实可用性、各镜像对 `Range` 的支持没联网测（测试用本地假服务器）→ Y02 发布时看。
- 弹幕字体：本任务能下载、选择、启动时注册；弹幕层用 `danmakuFontFamilyName` 当字体是 D05.1 的事（`shared/danmaku/danmaku_settings.dart` 已读它）。
- 日志导出的真机步骤没有归属：建议并入 S02.4（写进本单元报告）。
