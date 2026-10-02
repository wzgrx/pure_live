# T08c.1 录制设置

- 日期：2026-10-02
- 设计：[docs/T08/T08c/T08c.1/README.md](README.md)（第 1 版，用户已确认；V1～V4 都按建议 A：“缓存”改叫“录制文件”、最大任务数行内加减、切片按整分钟、“打开文件夹”在目录行右边）
- 改动的目录：`apps/pure_live/lib/features/record_settings/`、`apps/pure_live/lib/shared/record/record_actions.dart`（“改上限”的跳转）、`features/live_play/record/record_panel.dart` 和 `features/recorder/recorder_page.dart`（各改一行，见“设计范围外的改动”）、`packages/live_ui`（只做添加）、翻译文件、门禁基线、文档
- 没有改原生部分，没有构建 APK，没有往手机安装

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 全部设置项、默认值、范围、五组和顺序、行的样子、三个单选对话框、缓存上限对话框、清空确认、转圈；3.x 设置照旧 | ✅ | 21 行一项不少，存储键一个没改（`Settings.record*`）；行用 T09a.2 的设置行（`SettingsLinkRow`/`SwitchRow`/`SliderRow`/`CounterRow`）；选目录、清空、计算大小时行尾转圈 |
| c2 | 组标题 13 号主色；说明次要色；卡片低表面容器色、分隔线看得见 | ✅ | T09a.2 的 `SettingsGroup` |
| c3 | 说明和路径完整换行 | ✅ | `live_ui` 设置行加了 `subtitleMaxLines`（只做添加，默认仍是 2 行），这一页的说明和路径传 `null` |
| c4 | 依赖开关的项变灰不消失（含重连间隔时间） | ✅ | 总大小上限、最大重试次数、重连间隔时间、检测间隔时间、启用指数退避、最大检测间隔；不能用时 38% 透明、不响应 |
| c5 | 中文单位、GB | ✅ | “15 秒”“5 分钟”“5.5 分钟”“1 小时”“5 次”；大小“3.5 GB”（GB、MB 一位小数） |
| c6 | 值在右边，标题下写意思 | ✅ | 读写超时“15 秒”+“响应迅速 (推荐，适合稳定网络)”，缓冲队列“2048”+“原画推荐 (1080P)”，文字取自 v3 对话框 |
| c7 | 改名（V1） | ✅ | 录制文件、限制录制文件总大小（超过上限时自动删除最早的录像）、总大小上限、已占用、录制文件总大小上限 (MB)、开播检测、录制文件已清空。用新键，旧键（`cache_management` 等）没动 |
| c8 | 清空确认写删多少、不能恢复，“清空”错误色 | ✅ | “清空录制文件目录？”“将删除 3.5 GB 录像，不能恢复……”，按钮“取消”“清空”（错误色实心） |
| c9 | 最大同时录制任务数行内加减；从“改上限”进来滚到并高亮（V2） | ✅ | 1～10，到头按钮变灰，点一下就存。录制面板和录制中心的“改上限”带参数 `recordSettingsMaxTasks` 打开本页：滚到这一行、主色边框和 8% 主色底高亮 2 秒 |
| c10 | “打开文件夹”挪到目录行右边（V4） | ✅ | 文件夹图标按钮，悬停说明“打开文件夹”；组标题行不再有按钮 |
| c11 | 切片时长按整分钟（V3） | ✅ | 滑块 1～60 分钟、59 档；3.x 存的 330 秒显示“5.5 分钟”，拖动后才变整分钟。最大检测间隔同样按分钟（5～60） |
| c12 | 宽屏内容最宽 720 | ✅ | `live_ui` 新加的 `SettingsPageList`（最宽 720 居中）；高度 <480 时顶栏 48 高（同 T09a.2） |
| c13 | 单选对话框当前项“主色 + 勾”，说明 14 号 | ✅ | 不再用单选圈；当前项主色文字、8% 主色底、右边勾 |
| c14 | 选目录失败的提示 | ✅ | “这个文件夹不能写入（不存在、有非法字符或没有存储权限），请换一个”（新键，原来的 `path_or_permission_error` 别处还在用，没改） |

拿不准的第 3 条（目录行）：有系统文件夹选择器时（应用里 Android、Windows、Linux 都有，T13c.1），点目录行直接打开选择器（照 v3）；没有选择器时（测试、以后没有选择器的平台）仍是 v4 的输入路径对话框（有“使用默认目录”）。iOS 的做法交给 T19a.1（设计如此）。

## 设计范围外的改动（需要主控知道）

- `features/live_play/record/record_panel.dart:287`、`features/recorder/recorder_page.dart:206`：“改上限”从 `AppNavigator.toNamed(RoutePath.kRecordSettings)` 改成 `openRecordLimit()`（`shared/record/record_actions.dart`，带参数打开），各一行。c9 要求从这里进来时高亮，只能在调用处带参数。

## v3 文件 → v4 文件

| v3 | v4 |
|---|---|
| `recorder/pages/record_settings/record_settings_page.dart`（页面、单选和输入对话框、清空确认） | `features/record_settings/record_settings_page.dart`（页面、滑块行）、`record_settings_dialogs.dart`（单选对话框、上限对话框、清空确认、无选择器时的目录对话框）、`record_settings_texts.dart`（单位、大小、意思） |
| `common/widgets/widget_extensions.dart` 的行 | `packages/live_ui` 的设置行（T09a.2） |

## 新设置项

无。

## 门禁（`ui_baseline.json`）

- `record_settings` 直接写的颜色和图标 **28 → 0**（基线里删掉这一行）；新图标都进 `AppIcons`（`recordQuality` 等 21 个，照 v3 的字形）。
- 跨功能引用删掉 `record_settings -> recorder/recorder_texts.dart`（单位和大小的文字改在本目录）。

## 测试

- 新增 `apps/pure_live/test/features/record_settings/record_settings_page_test.dart` 12 个：文字（单位、大小、意思）；竖屏五组和 21 行的顺序、图标、值在右边和意思、依赖项变灰、说明不截断、“打开文件夹”在目录行右边；3.x 的值（5.5 分钟、5、30 秒）和打开开关后恢复可用；行内加减（1～10、到头变灰）；“改上限”滚到并高亮 2 秒；单选对话框（没有单选圈、勾、说明 14 号、选了就存并关）；上限对话框（变灰时不开、说明、校验）；清空确认（大小、错误色按钮、取消、完成提示）；系统选择器直接选目录和不能写入的提示；没有选择器时的对话框；横屏一栏最宽 720、顶栏 48；宽屏 720 居中、标题居中。
- `recorder_page_test.dart` 删掉 2 个和新设计冲突的测试（“the folder dialog saves the folder from the system picker”“the settings page shows imported values and saves changes”：断言了目录对话框、“10m”“30s”和最大任务数对话框），由上面的新测试代替。
- `live_ui`：设置行 `subtitleMaxLines`、页面框架、菜单的红色项各 1 个；图标对照表加了 T08c.1、T09 的图标。
- 全部测试数见 [T09e.1.md](../../../T09/T09e/T09e.1/record.md) 末尾（四个任务一起跑）。
