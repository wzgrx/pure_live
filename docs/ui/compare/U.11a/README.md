# U.11a 备份与恢复：设计（第 1 版）

- 状态：已确认（2026-10-01，用户已同意全部设计：“后续全部通过”；“需要你选的”按建议）。原状态：待确认（第 1 版，2026-10-01）
- 范围：备份与恢复页（列表、进行中、空、出错）、恢复预览对话框、备份文件菜单、同步电视的扫码页和输入地址对话框、提示条
- 对应：[TASKS.md](../../TASKS.md)、[INVENTORY.md](../../INVENTORY.md#u11a)、[TASK_FILES.md](../../TASK_FILES.md#u11a)
- 评审页：claude.ai 私有页面（待发布）；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)（公用部分 [src/skit.py](src/skit.py)）
- 图片：v3 按 `v3.2.11` 代码还原（文字取自 `assets/translations/zh.json`）；相机画面是示意图片；路径、地址、文件名都是示例

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| U.11a-01 | 备份与恢复页 | 首页左上角 ≡ 菜单“备份与恢复”（`common/widgets/menu_button.dart:51-55`，宽屏侧边栏同一个菜单）；v4 另在设置“数据”里 | 竖屏、横屏、宽屏 | 默认；某个操作进行中（行尾转圈）；备份目录未设置；日志开关更新中 / 失败（v3） |
| — | 系统目录 / 文件选择器 | 创建备份、恢复备份、备份目录 | 各系统自带 | v3 每次都弹；新设计只在“恢复备份”“备份目录”弹 |
| 新 | 目录中的备份 | 本页一组（v4 已有） | 同上 | 有文件、加载中、空、读不了目录 |
| 新 | 恢复预览对话框（`backup_preview_dialog.dart`，v4 已有） | 点备份文件、恢复备份 | 同上 | 有变化、无变化、有跳过的项 |
| 新 | 备份文件菜单 | 备份文件的 ⋮ / 右键 | 同上 | 完整备份三项；仅关注的文件没有“恢复全部设置” |
| U.11a-02 | 扫码页（`ScanCodePage`） | “同步TV数据”（v3 只在 Android、iOS） | 竖屏 | 扫码中、正在同步、成功、失败、相机不可用；手电筒开 / 关 / 不可用 |
| 新 | 输入电视地址对话框（`tv_sync.dart`，v4 已有） | 电脑上的“同步TV数据”、扫码页“手动输入地址” | 竖屏、宽屏 | 空、地址无效 |
| — | 提示条（9 处） | 创建 / 导出 / 恢复 / 导入的成功和失败、请先授予读写文件权限、备份目录未更改、同步成功 / 失败、日志目录相关 | 全部 | 新设计：创建成功写文件名 |

## v3 的样子

文件在 `lib/modules/backup/` 下（另注的除外）。

- **顶栏**：返回；标题居中“备份与恢复”（20 号 600，`common/style/theme.dart:115-121`）。
- **列表**（`backup_page.dart:83-316`）：内边距 16/12；组标题 12 号粗体、主色 65%（`common/widgets/widget_extensions.dart:21-36`）；卡片 `surfaceContainerHighest` 15%、圆角 20（`:101-111`）；行 `buildTile`：左图标 22 主色，标题 15/600，副标题 12 号 `hintColor` 75%，右 `Icons.chevron_right_rounded` 20（`:154-233`）。内容最宽 960 居中（`:8-18`）。
  1. **云端备份**：Firebase 账号行（`Remix.account_circle_line`，连接中 / 失败 / 登录 / 我的四种文字，`:88-148`）→ WebDav（`Remix.cloud_line`，“备份到WebDav服务器”）→ 设备同步（`Remix.qr_scan_2_line`，“通过局域网在设备之间同步配置”）→ 同步TV数据（`Remix.qr_code_line`，“将数据远程同步到TV”，只在 Android、iOS，`:163-170`）。
  2. **本地备份**：创建备份（`Remix.file_download_line`，“可用于恢复当前数据”）→ 恢复备份（`Remix.file_upload_line`，“从备份文件中恢复”）→ 仅导出关注列表（`file_download_line`）→ 仅导入关注列表（`file_upload_line`），后两个副标题都是“仅含关注的房间和分区，不影响其他设置”（`:174-237`）。
  3. **备份设置**：备份目录（`Remix.folder_open_line`，副标题是路径或“请先设置备份目录”，`:239-255`）。
  4. **日志管理**：启用本地日志（`Remix.file_text_line` + 开关，更新中“正在更新本地日志状态…”）→ 在浏览器中查看日志（`Remix.global_line`，副标题是地址，右边 `Remix.arrow_right_s_line`；日志开着才有）→ 打开日志目录（`Remix.folder_open_line`，“查看并管理日志文件”）（`:257-313`）。
- **进行中**：一次只做一件事，正在做的行尾 20 的转圈，其他行 `onTap` 为空（`:28-51`）。
- **创建 / 导出**（`plugins/backup_recovery_service.dart:14-73`）：先要存储权限；每次弹系统目录选择器（起始在备份目录）；文件名 `purelive_<日期>.txt`、`purelive_favorites_<日期>_<uuid>.txt`；第一次成功后记住目录。
- **恢复 / 导入**（`:75-108`）：系统文件选择器（只看 .txt），选完立刻覆盖，提示“恢复备份成功 / 失败”。
- **扫码页**（`scan_page.dart:130-264`）：顶栏“扫描二维码”，右边手电筒（`Icons.flash_off` 灰 / `flash_on` 黄 / `flash_auto` / `no_flash` 灰）、切换相机（`Icons.camera_rear` / `camera_front`）；相机画面底部黑 72% 圆角 12 的提示“扫描电视端显示的服务器二维码”；扫到合法地址就发送（`:266-295`）：正在同步（转圈 + “正在同步”16 粗）→ 成功（`Icons.check_circle_outline` 44 绿 + “同步成功”+ “重试”按钮）或失败（`Icons.error_outline` 红 + “同步失败”+ “重试”）；相机出错：黑底 `Icons.no_photography_outlined` 44 + “相机当前不可用，请检查相机权限后重试。”+ “重试”。
- **按宽度分支**：只有行在窄于 360 或字体大于 1.5 倍时把右侧控件放到下面（`widget_extensions.dart:235-257`）。没有快捷键。

## v3 的问题

| 编号 | 问题 | 位置 |
|---|---|---|
| B1 | 恢复选完文件直接覆盖，没有确认和预览（WebDAV 页却会确认） | `backup_recovery_service.dart:75-91`、`web_dav/web_dav_page.dart:194-204` |
| B2 | 看不到已有的备份，每次恢复都要在系统选择器里找 | `backup_page.dart:239-255`、`backup_recovery_service.dart:77-83` |
| B3 | 每次创建都弹目录选择器，“备份目录”只是起始位置 | `backup_recovery_service.dart:22-37`、`:53-70` |
| B4 | 成功提示不说文件名和位置 | `backup_recovery_service.dart:38`、`:71` |
| B5 | 进行中其他行点了没反应但样子不变 | `backup_page.dart:181-247` |
| B6 | 电脑上不能同步电视 | `backup_page.dart:163-170` |
| B7 | 扫码成功页按钮也叫“重试”；失败不说原因；相机不可用没有别的路 | `scan_page.dart:208-227`、`:245-262` |
| B8 | 手电筒灰、黄写死，黄色在浅色顶栏上看不见 | `scan_page.dart:147-152` |
| B9 | “云端备份”里是 Firebase 和局域网同步，组名不对 | `backup_page.dart:87-171` |
| B10 | 日志管理和备份无关 | `backup_page.dart:257-313` |
| B11 | 副标题 45% 黑，约 3.3:1 | `widget_extensions.dart:203` |

## v4 现在的偏差（`apps/pure_live/lib/features/backup/`）

M12 已经做了：去掉 Firebase 行；组的顺序改成本地备份在前、云端在后，仅导出关注列表挪到恢复备份前面，图标换成 `heart_add_line`、`heart_pulse_line`、`tv_2_line`；加“目录中的备份”、恢复预览、默认目录、改回默认目录、打开备份目录；“同步TV数据”在所有平台都先弹输入地址对话框（框里有扫码按钮）；日志管理移到设置。新设计保留其中修 v3 问题的部分，组和行的顺序、图标回到 v3。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 对比、各状态、扫码页、三处待选 | 待评审 |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [对比：竖屏](page/02-对比-竖屏.jpg)
- [创建和恢复](page/03-创建和恢复.jpg)
- [同步TV数据](page/04-同步TV数据.jpg)
- [横屏和宽屏](page/05-横屏和宽屏.jpg)
- [v3 的问题](page/06-v3-的问题.jpg)
- [改了什么](page/07-改了什么.jpg)
- [每个按钮是干什么的、怎么用](page/08-每个按钮是干什么的-怎么用.jpg)
- [各客户端](page/09-各客户端.jpg)
- [需要你选的](page/10-需要你选的.jpg)
- [性能要点](page/11-性能要点.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-backup.jpg](v3-backup.jpg)、[v4-backup.jpg](v4-backup.jpg) | 竖屏第一屏 |
| [v3-backup-full.jpg](v3-backup-full.jpg)、[v4-backup-full.jpg](v4-backup-full.jpg)、[v4-backup-full-n.jpg](v4-backup-full-n.jpg) | 完整内容 / 按钮编号 |
| [v3-backup-states.jpg](v3-backup-states.jpg)、[v4-backup-states.jpg](v4-backup-states.jpg) | 进行中、完成、系统选择器 / 进行中、完成、空、出错 |
| [v4-restore.jpg](v4-restore.jpg) | 备份文件菜单、恢复预览、恢复完成 |
| [v3-scan.jpg](v3-scan.jpg)、[v4-scan.jpg](v4-scan.jpg)、[v4-scanner-n.jpg](v4-scanner-n.jpg) | 扫码页五种状态 / 编号 |
| [v4-tv-dialog.jpg](v4-tv-dialog.jpg) | 输入电视地址对话框、地址无效 |
| [v3-backup-land.jpg](v3-backup-land.jpg)、[v4-backup-land.jpg](v4-backup-land.jpg) | 手机横屏 852×393 |
| [v3-backup-wide.jpg](v3-backup-wide.jpg)、[v4-backup-wide.jpg](v4-backup-wide.jpg)、[v4-backup-wide-n.jpg](v4-backup-wide-n.jpg) | 宽屏 1280×800 |

## 改动（待确认）

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 保留 | 入口、组的顺序、行的图标标题和顺序、一次只做一件事、提示文字 | — |
| c2 | 修改 | 组名“云端和其他设备”，去掉 Firebase，“同步TV数据”各客户端都有 | B6、B9 |
| c3 | 增强 | “目录中的备份”：点一下预览后恢复，⋮ 恢复全部 / 仅恢复关注 / 删除（v4 已有） | B2 |
| c4 | 增强 | 恢复前预览会改变什么（v4 已有） | B1 |
| c5 | 修改 | 直接存到备份目录；默认目录、改回默认、电脑打开目录（v4 已有） | B3 |
| c6 | 修改 | 提示条写文件名（v4 已有） | B4 |
| c7 | 修改 | 进行中其他备份操作变灰 | B5 |
| c8 | 修改 | 扫码页：手动输入地址；成功“完成 / 再扫一次”；失败写原因；图标颜色跟主题 | B7、B8 |
| c9 | 修改 | 日志管理移到设置（Q1） | B10 |
| c10 | 修改 | 行样式同 U.2f 组件，副标题对比度够 | B11 |
| c11 | 修改 | 内容最宽 720（计划书 5.3） | — |

新加的文字（v4 已有键）：`backup_create_subtitle`、`backup_restore_subtitle`、`backup_files_title`、`backup_files_empty`、`backup_files_error`、`backup_files_hint`、`backup_folder_default`、`backup_folder_reset`、`backup_open_folder`、`backup_created`、`backup_preview_*`、`backup_tv_hint`、`backup_tv_failed`。新键：“云端和其他设备”“手动输入地址”“输入地址”“完成”“再扫一次”“正在发送到电视 {address}”“关注、历史、屏蔽词和弹幕设置已发送到电视”“请检查相机权限后重试，或者直接输入电视端同步页显示的地址。”

## 按钮的作用和用法

| 编号 | 控件 | 怎么用 |
|---|---|---|
| 1 | WebDAV | 进 WebDAV 页（U.11b） |
| 2 | 设备同步 | 进设备同步页（U.11c） |
| 3 | 同步TV数据 | 手机打开扫码页，电脑打开输入地址对话框（Q2） |
| 4 | 创建备份 | 存到备份目录，提示文件名 |
| 5 | 恢复备份 | 选文件，预览后恢复 |
| 6 | 仅导出关注列表 | 只存关注 |
| 7 | 仅导入关注列表 | 只恢复关注，先预览 |
| 8 | 备份文件 | 点一下预览后恢复 |
| 9 | ⋮ / 右键 | 恢复全部设置、仅恢复关注列表、删除 |
| 10 | 备份目录 | 换目录 |
| 11 | 改回默认目录 | 设过才有 |
| 12 | 打开备份目录 | 电脑 |
| 13 | 手动输入地址 | 扫码页 |
| 14 | 返回 | 回到上一页 |
| 15 | 手电筒 | 开关闪光灯 |
| 16 | 切换相机 | 前后摄像头 |

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 竖屏如图；横屏同一列表，最宽 720 居中；“同步TV数据”打开扫码页 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 同一页；悬停说明、右键等于 ⋮；电脑多“打开备份目录”，“同步TV数据”打开输入地址对话框 |
| 电视 | U.15i：pure_live_TV 有云端备份（设备同步）、本地备份（创建备份、手机扫码导入 / 导出）、备份管理；内容和顺序对齐这里 |
| 苹果平台差异 | iOS 滑动返回、没有“打开备份目录”；macOS 在访达里打开 |

## 待选（A 是建议）

- Q1 日志管理：A 移到“设置 → 日志管理”（v4 已有）；B 留在这一页最后。
- Q2 点“同步TV数据”：A 手机直接扫码（照 v3），扫码页可手动输入，电脑输入地址；B 都先弹输入地址对话框（v4 现在）。
- Q3 目录中的备份：A 全部列出；B 最近 5 个加“全部 N 个”。

## 拿不准的地方

1. v3 的提示条是 `SmartDialog.showToast` 的默认样子（黑色半透明圆角），图里按这个画，没有真机截图核对。
2. v3 `hintColor` 按 Material 3 默认（黑 60%）推算，副标题是黑 45%。
3. 新设计创建备份的副标题“不含账号 Cookie 和 WebDAV 密码”是 v4 的备份内容；v3 的完整备份是否含账号要以 `BackupController.exportAllSettings` 为准，开发时核对。
4. 扫码页成功后的“完成”是回到备份与恢复页；v3 没有这一步（按钮叫“重试”，其实是重新扫码）。

## 需要改工具的地方

- 无。
