# U.11a 备份与恢复

- 日期：2026-10-02
- 设计：[docs/ui/compare/U.11a/README.md](../compare/U.11a/README.md)（第 1 版，用户已确认；Q1～Q3 都按建议 A：日志管理移到设置、手机点“同步TV数据”直接扫码、目录中的备份全部列出）
- 一并处理的跨任务待同步：U.10c → U.11a（“云端账号（已停用）”一行跳 `RoutePath.kMine`，U.10c X1 A）；U.11a → U.6e（日志管理移到设置，见下）
- 改动的目录：`apps/pure_live/lib/features/backup/`、`apps/pure_live/lib/shared/backup/`（新，从 backup 搬来）、`apps/pure_live/lib/shared/qr_scan.dart`、`apps/pure_live/lib/platform/plugins.dart`、`apps/pure_live/lib/routes/`（加 `kLogs`）、`features/settings/settings_catalog.dart`（日志一行改用路由，两行）、`packages/live_ui`（只做添加）、翻译文件、门禁基线、文档
- 没有改原生部分，没有构建 APK，没有往手机安装

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 入口、组的顺序、行的图标标题和顺序、一次只做一件事、提示文字 | ✅ | 入口不变（首页 ≡ 菜单、设置“数据”）；先“云端和其他设备”，后本地；创建备份 → 恢复备份 → 仅导出关注列表 → 仅导入关注列表，图标回到 v3（`file_download_line` / `file_upload_line`） |
| c2 | 组名“云端和其他设备”，去掉 Firebase，“同步TV数据”各客户端都有 | ✅ | WebDAV、设备同步、同步TV数据（`qr_code_line`，v3）；前面加 U.10c 的“云端账号（已停用）”（`cloud_off_line`，“改用 WebDAV 或设备同步；点这里看怎么迁移旧的云端配置”，跳 `RoutePath.kMine`） |
| c3 | 目录中的备份：点一下预览后恢复，⋮ 恢复全部 / 仅恢复关注 / 删除 | ✅ | 组名“目录中的备份 · N”；每行“时间 · 大小 · 完整备份 / 仅关注列表”；⋮、右键、长按打开同一个小菜单（`showAppMenu`，删除红色、前面一条线，仅关注的文件没有“恢复全部设置”）；电脑上悬停说明“点一下预览后恢复；右键或 ⋮ 有更多操作”；删除先确认（红色“删除”） |
| c4 | 恢复前预览 | ✅ | v4 已有的预览，搬到 `shared/backup/`（WebDAV、设备同步共用） |
| c5 | 直接存到备份目录；默认目录、改回默认、电脑打开目录；组名“备份目录” | ✅ | 没设过时行名“备份目录（默认）”；“打开备份目录”只在 Windows、Linux、macOS |
| c6 | 提示条写文件名 | ✅ | “已备份到 purelive_….txt”，列表同时多一条 |
| c7 | 进行中其他备份操作变灰 | ✅ | 正在做的那行转圈，其他备份行（含同步TV数据、备份文件、备份目录）变灰；云端账号、WebDAV、设备同步照常能进 |
| c8 | 扫码页：手动输入地址；成功“完成 / 再扫一次”；失败写原因；图标颜色跟主题 | ✅ | 见下“扫码页” |
| c9 | 日志管理移到设置（Q1） | ✅（有偏差） | 见下“日志管理” |
| c10 | 行样式同 U.2f，副标题对比度够 | ✅（有偏差） | 用 U.6a 的统一设置行（主控任务书要求所有设置页用这套）：副标题 `onSurfaceVariant`、卡片圆角 16；标题是 15 号 600（设计图写“15 号常规”，统一行组件是 600） |
| c11 | 内容最宽 720 | ✅ | `SettingsPageList` |

## 扫码页（`shared/qr_scan.dart`，U.11c 用同一个）

- 顶栏“扫描二维码”，右边手电筒（关 / 开 / 不可用三种图标）、切换相机；图标用顶栏的前景色（修 B8 的灰、黄写死）。
- 画面上四角取景框，下面“扫描电视端显示的服务器二维码”和“手动输入地址”。
- 扫到地址：正在同步（转圈、“正在发送到电视 192.168.1.100:8888”）→ 同步成功（“关注、历史、屏蔽词和弹幕设置已发送到电视”，“完成”回到备份页、“再扫一次”）或同步失败（原因“同步失败，请确认电视端已打开同步页并在同一局域网”，“重试”重发到同一台、“输入地址”）；扫到的不是地址也进失败（写“设备地址无效”，“重试”重新扫）。
- 相机不可用：“相机当前不可用”“请检查相机权限后重试，或者直接输入电视端同步页显示的地址。”，“重试”“输入地址”。
- 相机是接口 `QrCamera`（应用里是 mobile_scanner，测试用假相机）；原来的 `QrScan.scan` 换成 `QrScan.camera`（`plugins.dart` 跟着改）。显示结果时释放相机，回到扫码再打开。
- 手机（有相机）点“同步TV数据”直接进扫码页（Q2 A，照 v3）；电脑和没有相机时弹输入地址对话框（v4 已有，地址不对时框下面写“设备地址无效”）。

## 日志管理（Q1，和 U.6e 协调，主控决定入口）

- 日志页从 `features/settings/log_page.dart` 搬到 `features/backup/log_page.dart`（`git mv`，主控任务书要求放在 U.11a 的目录），样式换成统一设置行和 `AppIcons`，功能不变（写入文件、最低级别、本次的日志、复制、分享、打开目录、清空）。
- 新路由 `RoutePath.kLogs`（`/logs`，`app_router.dart` 注册；`home_test` 的路由表断言加了这一项）。
- **设置里的入口**：为了这个分支能编译，`settings_catalog.dart` 的“日志管理”一行从 `page: (_) => const LogPage()` 改成 `route: RoutePath.kLogs`，并删掉对 `settings/log_page.dart` 的引用（两行，别的没动）。U.6e 同时在改设置；合并时如果冲突，以 U.6e 的位置为准，只要入口用 `route: RoutePath.kLogs`（设置不能直接引用 backup 目录的文件，门禁不允许新增跨功能引用）。`plugins.dart` 的 `logSharerProvider` 引用跟着改。

## 设计范围外的改动（需要主控知道）

- `shared/backup/`：`backup_data.dart`、`backup_preview_dialog.dart`、`backup_files.dart`（文件名、列表、默认目录、大小和时间文字）从 `features/backup/` 搬来，设备同步要用恢复预览（U.11c S1），功能目录之间不能互相引用。应用内的文件浏览对话框留在 `features/backup/file_browser.dart`。`backup_data.dart` 仍引用 `features/search/search_history.dart`（搜索记录进备份，原来就有），现在是 `shared → features/search`，门禁不查 shared。
- `features/settings/settings_catalog.dart` 两行（见上）。
- `routes/route_path.dart`、`routes/app_router.dart`：加 `kLogs`。

## v3 文件 → v4 文件

| v3 | v4 |
|---|---|
| `modules/backup/backup_page.dart` | `features/backup/backup_page.dart`（页面、文件行和菜单） |
| `modules/backup/scan_page.dart` | `shared/qr_scan.dart`（扫码页、状态、相机接口）、`features/backup/tv_sync.dart`（`TvSyncScanPage`、输入地址对话框、发送） |
| `plugins/backup_recovery_service.dart` | `packages/live_store` 的 `BackupService`（不变）、`shared/backup/backup_data.dart`、`backup_files.dart`、`backup_preview_dialog.dart` |
| 备份页的日志管理（`:257-313`） | `features/backup/log_page.dart`（设置 → 日志管理，`RoutePath.kLogs`） |

## 新设置项

无。

## 门禁（`ui_baseline.json`）

- `backup` 直接写的颜色和图标 **22 → 0**（日志页搬进来后也是 0）；`settings` **126 → 119**（日志页搬走的 7 个）。
- 跨功能引用删掉 `backup -> search/search_history.dart`（随 `backup_data.dart` 搬到 shared）。
- 新图标进 `AppIcons`：`syncTv`、`backupCreate`、`backupRestore`、`backupFile`、`backupFollows`、`backupEmpty`、`backupFolder`、`backupOpenFolder`、扫码页的 `torchOff/On/Unavailable`、`switchCamera`、`typeAddress`、`scanQr`、`cameraUnavailable`、`syncDone`、`syncFailed`，日志页的 `logFile`、`logLevel`、`exportFile`、`clearLog`，预览的 `bullet`。

## 测试

- `apps/pure_live/test/features/backup/backup_page_test.dart`：7 → 18 个（数据 4 个不变；页面 3 个保留并按新结构改了找列表的方式；新增 11 个）：四组和九行的顺序、图标、文字，没有 Firebase 和日志组；创建后列出并写文件名；恢复预览期间其他备份操作变灰、WebDAV 和设备同步不变；⋮、右键、长按同一个菜单，仅关注文件少一项，删除红色带线、先确认；读不了目录时说明并重试；选目录和改回默认；不是备份的文件；手机进扫码页、电脑弹输入地址（地址无效写在框下）；横屏 720 居中和 48 顶栏；宽屏 720 和“打开备份目录”。扫码页 4 个：顶栏手电筒在切换相机左边、图标随状态变、不写死颜色、提示和“手动输入地址”；发送中 → 成功（完成 / 再扫一次，完成回去）；失败（原因、重试重发、输入地址）；相机不可用（重试、输入地址）。
- `test/shared/fake_qr_camera.dart`：测试用的假相机（备份、设备同步、插件测试共用）。
- `test/plugins_test.dart`：电视地址对话框的扫码按钮改用假相机（`QrScan.scan` 换成了 `QrScan.camera`）。
- 全部测试见 [U.11c.md](U.11c.md) 末尾。
