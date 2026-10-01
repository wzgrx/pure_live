# U.3d 全局弹窗

- 日期：2026-10-01
- 设计：[docs/ui/compare/U.3d/README.md](../compare/U.3d/README.md)（第 1 版，用户已确认；Z1、Z2 按建议 A）
- 范围：新版本、选择下载目录、下载安装包（全部状态）、口令导入，以及下载流程里的提示条。
- 改动的目录：`apps/pure_live/lib/features/version/`、`apps/pure_live/lib/shared/rooms/room_prompt.dart`（新）、`packages/live_store`（只加两个设置）、`packages/live_ui`（只做添加）、翻译文件、门禁基线、文档。没有改原生部分（安装权限用已有的 `SystemAccess`），没有构建 APK。

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 四个都是居中对话框；内容、按钮文字和顺序（取消在左、主要按钮在右）；安装权限、下载目录的检查顺序；“立即安装”“打开文件夹”“重新打开”；同一时间只有一个下载 | ✅ | Android 的 APK 在下载**之前**先查“安装未知应用”权限（3.x 如此；v4 原来只在安装时查，现在两处都查），再查下载目录，再开下载对话框 |
| c2 | 标题“发现新版本 v…”，下面一行“当前 v…”和“本软件开源免费”链接（打开项目主页，不关对话框） | ✅ | |
| c3 | “下载并安装”直接在应用里下载本机的安装包，挑最快的下载源，失败换下一个；“其他下载方式”进版本页 | ✅ | v4 原来就能下载；按钮“查看详情”改为“其他下载方式”，放到按钮行最左。本机没有安装包时主要按钮是“更新”（进版本页），没有“其他下载方式” |
| c4 | “不再提醒这个版本” | ✅ | 新设置 `skippedUpdateVersion`；勾上马上保存，这个版本启动时不再提示，更新的版本照常提示；“关于”页（版本页）手动检查不受影响 |
| c5 | 字号统一 14；日志前加“更新内容”；对话框宽时“不再提醒”放在按钮行左边，横屏手机能看全日志 | ✅ | 对话框宽 ≥480 时同一行；日志区单独滚动，按钮行固定；按钮字号由 `DialogButtonsTheme` 统一为 14（主题的按钮是 13，和 3.x 一样） |
| c6 | 选择下载目录加“取消”；点外面、返回键、Esc 都等于取消，提示“未选择下载目录，已取消下载” | ✅ | 什么时候问照 3.x：选过的目录不存在或不能写，或者从没回答过而默认目录还不存在。回答记在新设置 `downloadDirectoryDecisionMade`（3.x 的键名，3.x 的数据会被接上） |
| c7 | 下载完成后有“关闭”；标题跟着状态变；返回键、Esc 等于对话框里的取消或关闭 | ✅ | “正在下载 v…”“v… 已下载”“下载没有完成”；对话框点外面不关（3.x），所以 Esc 由对话框自己接（`DialogKeys`） |
| c8 | 下载失败留在对话框里：原因、“重试”“在浏览器中下载”“关闭”；保留已下载的部分 | ✅ | v4 原来就有续传；进度条变灰 |
| c9 | 去掉打开下载对话框时的“正在下载…”提示条 | ✅ | v4 原来就没有；测试固定 |
| c10 | 所有尺寸同一个排法（图标在左、按钮一行），字体放大 1.5 倍以上才上下排；状态行 14 号 | ✅ | 按钮放不下一行时右边的按钮换到第二行（不溢出） |
| c11 | 口令导入：标题“打开分享的直播间”，下一行“从剪贴板识别到分享口令”；主播名后面写平台中文名和房间号；去掉框中框，圆角 24 | ✅（触发在 M12.5） | `shared/rooms/room_prompt.dart`：`showRoomPrompt` 排在应用提示队列里（U.3c c7），最宽 400；窄于 350 或字体放大 1.6 倍时头像在上（照 v3） |
| 各客户端 | 回车等于主要按钮，Esc 等于取消或关闭；焦点框只在用键盘时显示 | ✅ | `live_ui` 新增 `DialogKeys`：对话框打开时拿焦点，回车按主要按钮（某个按钮有焦点时按那个按钮）；四个对话框都用 |

**下载对话框的状态**（`UpdateDownloadDialog`）：

| 状态 | 标题 | 状态行 | 按钮 |
|---|---|---|---|
| 准备中 | 正在下载 v… | 准备中...，进度“…” | 取消 |
| 下载中 | 正在下载 v… | 18.6 MB / 62.4 MB，百分比 | 取消 |
| 大小未知 | 正在下载 v… | 已下载: 18 MB，进度“…” | 取消 |
| 下载完成 | v… 已下载 | 下载完成，100% | 关闭 ｜ 打开文件夹、立即安装 |
| 正在打开 | v… 已下载 | 下载完成，正在打开文件... | 灰的“正在打开” |
| 下载失败 | 下载没有完成 | （红）下载中断，已下载的部分会保留，重试时接着下载 | 关闭 ｜ 在浏览器中下载、重试 |
| 打开失败 | v… 已下载 | （红）文件已下载，但打开失败。 | 关闭 ｜ 重新打开 |
| 打开文件夹失败 | v… 已下载 | 系统里没有可以打开该文件夹的应用，文件位置：… | 关闭 ｜ 打开文件夹、立即安装 |

进度只刷新状态行和进度框（`ValueListenableBuilder`），不整个对话框重建。

偏差和原因：

1. **“打开文件夹”所有平台都有**（v3 如此；v4 原来只在电脑上有）。Android 的默认目录在 `Android/data` 下，系统文件管理器打不开，会走“打开文件夹失败”并写出文件位置（设计图里就是这个状态）。
2. **选的目录没有写入权限时只提示**：v3 在 Android 上还会打开应用设置页；v4 的 `SystemAccess` 没有打开应用设置的方法，没加原生代码，只提示“所选下载目录需要存储权限……”。
3. **版本页的下载也带版本号**：`version_page.dart` 把版本号传给下载对话框，标题才能写“正在下载 v…”（没有版本号时写文件名）。
4. **口令导入的触发不在主线**：读剪贴板、解码口令、“只问一次”的逻辑在暂停的 M12.5 分支。这次只做了对话框和排队。M12.5 的 `room_prompt.dart` 同名，多一个“不再识别”按钮（`RoomPromptChoice.stopDetecting`），确认的设计里没有，合并时要决定（见报告）。
5. **苹果平台、电视**：iOS、macOS 的更新方式在 U.17；电视的更新提示样式在 U.15b（电视首页调用的是同一个 `checkForUpdateOnStartup`，现在也排队、也只在首页弹）。

## v3 文件 → v4 文件

| v3 | v4 |
|---|---|
| `modules/about/widgets/version_dialog.dart` | `features/version/update_prompt.dart`（`NewVersionDialog`、`checkForUpdateOnStartup`） |
| `plugins/update.dart` | `features/version/update_download.dart`（`showUpdateDownload`、`ensureDownloadDirectory`） |
| `common/widgets/download_directory_dialog.dart` | `features/version/download_directory_dialog.dart` |
| `common/widgets/download_apk_dialog.dart` | `features/version/update_download.dart`（`UpdateDownloadDialog`） |
| `common/widgets/share_command_import_dialog.dart` | `shared/rooms/room_prompt.dart` |

## 新设置（只做添加，`live_store`）

| 键 | 类型 | 默认 | 范围 | 说明 |
|---|---|---|---|---|
| `skippedUpdateVersion` | 文字 | 空 | 本机（不进备份） | “不再提醒这个版本”记下的版本 |
| `downloadDirectoryDecisionMade` | 开关 | 关 | 本机（不进备份） | 3.x 同名键：回答过下载目录的提问 |

## 新增的文字

中英各 10 条：`update_new_version_title`、`update_log_title`、`update_skip_version`、`update_other_ways`、`update_downloading_title`、`update_downloaded_title`、`update_download_incomplete`、`update_opening`、`room_prompt_title`、`room_prompt_from_clipboard`。

## `live_ui` 的添加

`DialogButtonsTheme`（对话框里的按钮 14 号）、`DialogKeys`（回车和 Esc）；`AppIcons.downloadDone`、`downloadFailed`、`install`、`retry`。

## 门禁

`version` 直接写的颜色和图标 **15 → 11**（剩下的都在版本页和更新日志，属于 U.12b）。没有新增跨功能引用。

## 测试

- `test/features/version/update_dialogs_test.dart`（新）9 个：新版本的标题、当前版本、链接不关对话框、更新内容、按钮顺序、字号 14、“其他下载方式”；宽屏时“不再提醒”和按钮同一行、没有安装包时是“更新”、回车和 Esc；“不再提醒”只管这个版本；横屏手机日志单独滚动、按钮不动；另一个页面在上面时不弹、回来才弹；下载中、完成、打开失败的标题、状态行、按钮顺序和图标，返回键关掉、文件留着；大小未知和下载失败；下载中返回键和 Esc 都是取消（点外面不关）；下载目录的提问、按钮顺序、取消 / Esc / 点外面都提示取消、选默认目录后记住并开始下载。
- `test/shared/app_prompts_test.dart`（新）口令导入 3 个：标题、来源、平台中文名和房间号、头像在左、按钮顺序和字号、圆角跟主题、进入 / Esc / 回车；字体放大时头像在上；横屏最宽 400。
- `live_ui`：`test/dialog_support_test.dart` 1 个（按钮 14 号、回车、Esc、有焦点的按钮保留自己的回车）。
- 原有的 `version_page_test.dart` 没有改，照旧通过。
- `live_store` 32 个、`live_ui` 48 个、`apps/pure_live` 306 个全部通过；三个包 `analyze` 无问题；`check_ui_structure.py` 通过。
