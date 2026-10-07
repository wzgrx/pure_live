# A10 录制界面

录制中心、录制设置、录制按钮和各处的录制状态图形。

一句话：录制在用户眼前的样子：录制中心页面、录制设置页面，以及直播间顶栏、画面角标、录制面板状态卡、录制通知里那一组表示“没在录 / 等开播 / 准备中 / 录制中 / 重连中 / 合成中 / 失败”的图形。

## 范围

- 包括：
  - 录制中心（A10.1）：五个带数量的筛选、任务卡片（卡片头 + 状态卡的紧凑尺寸）、更多菜单（进入直播间、开播自动录、删除任务）、删除确认、空状态、开播检测关着时的提示、按宽度分列。
  - 录制设置（A10.2）：五组 21 行设置、单选对话框、上限对话框、清空确认、目录选择和不能写入的提示、从“改上限”进来时滚到并高亮。
  - 录制状态图形（A10.3）：`RecordGlyph` 七种状态、画面角标 `RecordingBadge`、顶栏录制按钮的状态和提示文字、状态卡卡片头、Android 通知小图标的形状。
- 不包括（归哪里）：
  - 录制本身（FFmpeg、分段、合并、重连、自动录的轮询）在 [H 录制](../../H-录制/README.md)：录制核心 H01、录制中心的逻辑 H02、设置和存储 H03、自动录 H04、通知的文字和按钮 H05。
  - 直播间里的录制面板（A07.6）的布局在 [A07](../A07-直播间界面/README.md)；这里只管它的状态卡（和录制中心是同一个组件 `RecordStatusCard`）和图形。
  - 通知栏的整体外观（标题、正文、按钮）在 [A14.1](../A14-系统界面/A14.1-系统界面/README.md)；首页导航的“录制中心”入口在 [A06](../A06-首页和全局/README.md)。
  - 电视：pure_live_TV 没有录制，电视界面不做（A17 各任务写明“不适用”）。

## 现状：做到哪、怎么工作的

- **用户看得到的**：
  - 录制中心：手机是底部导航第四个标签（左上角菜单），宽屏从导航栏按钮或直播间面板进（左上角返回）。顶部一行五个筛选“全部 / 进行中 / 等待开播 / 已保存 / 失败”带数量；卡片按状态排（录制中 → 重连中 → 整理文件 → 准备中 → 排队中 → 等待开播 → 失败 → 已保存 → 没在录制），同状态新的在前；列数 = ⌊(宽 + 12) ÷ 412⌋，1～4 列（393 一列、852 两列、1280 三列、1920 四列）。
  - 录制设置：内容最宽 720；“缓存”改叫“录制文件”；依赖开关的项变灰不消失；最大同时录制任务数行内加减 1～10；切片按整分钟；目录行右边“打开文件夹”。
  - 状态图形：没在录是和旁边图标同色的圆环加圆点（没有红色）；录制中是红色实心圆加白色圆角方块、外圈呼吸；等待开播圆环右下角小钟；准备中、合成中中性色环形进度；重连中琥珀色虚线圆环；失败圆环右下角错误色“!”。画面角标只在录制中（红底）、重连中、合成中（深色底）出现；横屏全屏顶栏录制中时按钮右边带 `mm:ss`。
- **内部怎么工作**：
  - 任务来自 `packages/live_record` 的录制器（`AppRecording`，`apps/pure_live/lib/app/recording.dart:369`）。每个任务的 `task.status` 和名额经 `recordCardState`（`shared/record/record_state.dart:39`）变成九种卡片状态 `RecordCardState`（:7）；图形用 `recordGlyphState`（`shared/record/record_look.dart:12`）从卡片状态映射，画面角标用 `recordBadgeState`（:39）只认 running / reconnecting / processing。顶栏按钮、角标、状态卡、录制中心都走这两个函数，不再用 `RecordStatus.isActive` 二分。
  - 录制中心的筛选、计数、列数是纯 Dart（`features/recorder/logic/recorder_view.dart`），数量变化只重建筛选行。按钮动作（开播自动录、打开开播检测、再录一次、播放、查看原因、改上限）在 `shared/record/record_actions.dart`，直播间面板和录制中心调用同一份。
  - 录制设置读写 `live_store` 的 `Settings.record*`，存储键和 3.x 一样（`RecordSettingsStore`，`app/recording.dart:212`）。
- **完成度**：A10.1、A10.2 完成（2026-10-01、10-02 合并）；A10.3 代码已合并（2026-10-02），待真机。3.x 的功能一项不少（停止、启动、立即检测、重试、重新录制、取消、删除、打开文件夹、设置都有对应按钮），改动见各任务 README 的“改动”表。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/features/recorder/recorder_page.dart` | 录制中心页面 `RecorderPage`（:94）：顶栏（首页标签里是菜单，其余返回）、筛选行 `_FilterBar`（:369）、任务网格 `_TaskGrid`（:490，按行懒加载、行内顶对齐）、开播检测提示 `_PollingOffBanner`（:582）、从通知定位到任务的高亮 `RecorderTaskHighlight`（:605）；打开录制文件夹 `openRecordFolder`（:55） |
| `apps/pure_live/lib/features/recorder/recorder_task_card.dart` | 一张任务卡片 `RecorderTaskCard`（:90）：卡片头 `_Head`（:309，封面 96×54，宽屏 160×90、主播名、标题、“平台 · 人数”、“⏱ 自动录”胶囊 :399）、更多菜单（:74）、删除确认 |
| `apps/pure_live/lib/features/recorder/logic/recorder_view.dart` | 五个筛选 `RecorderFilter`（:7）、可见任务和排序（:48）、数量（:63）、列数 `recorderColumns`（:93，最小卡宽 400、间距 12） |
| `apps/pure_live/lib/features/recorder/recorder_texts.dart` | 筛选名、阶段、失败原因、受限原因、提示文字；大小和秒数（录制设置也用） |
| `apps/pure_live/lib/features/record_settings/record_settings_page.dart` | 录制设置页 `RecordSettingsPage`（:29）：五组 21 行、滑块行 `_SliderSetting`（:576）、“改上限”高亮 2 秒（:21） |
| `apps/pure_live/lib/features/record_settings/record_settings_dialogs.dart` | 单选对话框 `showRecordRadioDialog`（:34，当前项主色加勾）、上限对话框 `RecordIntegerDialog`（:79）、清空确认 `confirmRecordClear`（:218）、没有系统选择器时的目录对话框（:231） |
| `apps/pure_live/lib/features/record_settings/record_settings_texts.dart` | 中文单位（秒、分钟、小时、次）、GB / MB、读写超时和缓冲队列的意思 |
| `apps/pure_live/lib/shared/record/record_state.dart` | 九种卡片状态和判断（:7、:39）、名额（:57）、开播自动录是否开着（:70）、清晰度、分段、时钟文字、排序表 `recordCardOrder`（:145） |
| `apps/pure_live/lib/shared/record/record_status_card.dart` | 状态卡 `RecordStatusCard`（:164）：直播间面板的完整尺寸和录制中心的紧凑尺寸（计时 24 号、按钮 40 高），每种状态的按钮 |
| `apps/pure_live/lib/shared/record/record_look.dart` | 卡片状态 → 七种图形（:12）、按钮提示文字（:25）、角标状态和文字（:39、:47）、合并进度 |
| `apps/pure_live/lib/shared/record/record_actions.dart` | “改上限”（:22，带参数 `max-tasks` 打开设置）、打开开播检测（:27）、开播自动录（:38）、再录一次（:69）、播放（:76）、查看原因（:81） |
| `apps/pure_live/lib/shared/record/saved_file.dart` | 后台检查录像文件是否还在（“播放”按钮只在文件在时出现） |
| `apps/pure_live/lib/features/live_play/buttons/record_button.dart` | 直播间顶栏和全屏顶栏的录制按钮（:23）：按状态画图形、提示文字；横屏全屏录制中带时间 `_RecordTime`（:178） |
| `apps/pure_live/lib/features/live_play/player/recording_badge.dart` | 画面上的录制角标 `RoomRecordingBadge`（:18）：录制中、重连中、合成中；控制栏隐藏时紧凑形 |
| `packages/live_ui/lib/src/widgets/record_glyph.dart` | 七种状态 `RecordGlyphState`（:10）、图形 `RecordGlyph`（:41，呼吸和转圈，减少动态效果时不动）、画法 `RecordGlyphPainter`（:154）、角标 `RecordingBadge`（:328） |
| `apps/pure_live/lib/app/recording_notice.dart` | 前台录制通知的标题和正文（按状态写：准备录制 / 正在录制 / 正在重连 / 正在整理录像，属于 H05） |
| `apps/pure_live/android/app/src/main/res/drawable/ic_stat_recording.xml`、`ic_stat_record_stopped.xml` | 录制通知小图标（实心圆挖出方块）、“录制已停止”提醒小图标（圆环开口加“!”） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/recorder/recorder_centre_test.dart` | 顶栏、筛选和数量、九种状态卡、更多菜单（点 ⋮、长按、右键）、删除、开播检测提示、横屏两列、宽屏三列、九张卡片头的图形 |
| `apps/pure_live/test/features/recorder/recorder_page_test.dart`、`recording_wiring_test.dart` | 七种状态在顶栏的图形、红色、提示、合成进度、横屏带时间；卡片状态到图形和角标的映射；录制器接线 |
| `apps/pure_live/test/features/record_settings/record_settings_page_test.dart` | 21 行的顺序和图标、依赖项变灰、3.x 的值、行内加减、“改上限”高亮、三种对话框、清空确认、选目录、横屏和宽屏 720 |
| `packages/live_ui/test/design_system_test.dart` | 图形七种状态的颜色（只有录制中有红色）、画面上的色调、呼吸和转圈（减少动态效果时不动）、角标三种状态 |
| `apps/pure_live/test/platform/system_surfaces_test.dart` | 通知小图标资源、通知按状态写的标题 |

## 3.x 基线

- 录制中心：`git show v3.2.11:lib/recorder/pages/recorder/recorder_page.dart`（842 行）：顶栏 `:35-53`（标题居中，左边宽 ≤680 时是菜单，右边打开文件夹、设置）、状态块 `:579-711`；九个筛选 `lib/recorder/widgets/recorder_bounded_scroll.dart`；排序 `lib/recorder/models/recorder_task_ordering.dart`；入口：手机底部导航第四个标签 `lib/modules/home/mobile_view.dart:56-63`，宽屏导航栏上方按钮 `tablet_view.dart:138-146`。
- 录制设置：`lib/recorder/pages/record_settings/record_settings_page.dart`（622 行，页面、单选和输入对话框、清空确认）；设置行 `lib/common/widgets/widget_extensions.dart`。
- 录制按钮：`lib/modules/live_play/widgets/button/record_action_button.dart:40-104`、`record_action_content.dart`：48×48 圆角 12 的按钮，没有任务时是中性色 `Remix.record_circle_line`，有任务 `checkbox_circle_fill` 主色，录制中 `record_circle_fill` 红色。v3 的未录本来就没有红色，4.0.0 的红点是 A07.1 改动 13 加的（A10.3 修掉）。
- 要保留的操作：卡片长按或右键打开菜单（[specs/UI.md](../../specs/UI.md) 附录 A 第 14 条）；点卡片进直播间；3.x 的录制设置键名和含义不变（D-018）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 录制状态图形还没在真机上看（呼吸、减少动态效果、通知小图标） | A10.3 | 动画节奏和颜色只在测试和效果图里看过 | [A10.3](A10.3-录制按钮和状态图标/verify.md) 待真机 |
| 录制的清晰度标签曾写请求的“原画”，实际是平台给的“超清”（S02.2 发现） | `packages/live_record`（`RecordStreamResolver.servedQuality`） | 面板、通知、录制中心写的清晰度不对 | 已在 [H01.3](../../H-录制/H01-录制核心/H01.3-合并进度/record.md) 修好，真机复看归 [S02.5](../../S-质量和验证/S02-真机验证/README.md) |
| 主播下播后无限快速重试、一个 0 字节分段让整段合并失败 | 录制核心 | 录制中心里任务一直在“重连中”或合并失败 | [H01.5](../../H-录制/H01-录制核心/README.md) |
| iOS 的“打开文件夹”和目录行没有设计落地 | 录制中心顶栏、录制设置目录行 | iOS 没有文件夹的概念 | [A18.1](../A18-苹果平台界面/A18.1-iOS和iPadOS差异设计/README.md) |
| 跨功能引用：`recorder -> home/home_menu.dart`、`menu_button.dart`（首页菜单）、`live_play -> recorder/recorder_texts.dart` | `tools/gate/ui_baseline.json` | 门禁基线里还有 3 条 | 首页菜单挪到 `shared/`、录制文字挪到 `shared/record/` 时去掉 |
| 只录一个直播间时，点前台录制通知不会定位到那条任务 | `app/recording_notice.dart` | 少一步定位 | [H05.2](../../H-录制/H05-录制通知/README.md) |

## 相关决定和规范

- D-003（A10.1 的 U1～U3、A10.2 的 V1～V4、A10.3 的 X1～X3 按建议 A；A10.3 的 X4 由维护者补做）、D-018（录制设置键名不变，A10.2 一个键没改，新文字用新键）。
- [specs/UI.md](../../specs/UI.md) 第 5.3 节（只读父组件宽度；录制中心按页面宽度分列，A10.1 偏差 1）、第 5.4 节（点击区域至少 48：筛选格高 48）、第 7 节（更多菜单是贴着按钮的小菜单，删除是对话框）、第 8.1 节（语义色 `LiveSemanticColors.recording`、`warning`）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/recorder test/features/record_settings test/platform/system_surfaces_test.dart`；`cd packages/live_ui && flutter test test/design_system_test.dart`。缺：深色主题下录制中心的布局测试（只在开发时本机渲染看过）；录制中心 1.3 倍字号。
- 真机：[S02 的 CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 3 节（录制）。S02.2 看过录制面板、通知、录制中心的“已保存”卡片（通过）；S02.3 看过录一场 5 分钟以上的合并（通过）。A10.3 的图形按 [verify.md](A10.3-录制按钮和状态图标/verify.md) 看。

## 路线

1. A10.3 在 K90 上按 verify.md 看完，登记为完成（第一件事，不需要写代码）。
2. 录制核心的修复（H01.5 下播重试和空分段、H01 的清晰度标签）合并后，回看录制中心卡片的“重连中”“失败”“已保存”是否显示正确。
3. 新的录制界面需求（例如按房间设置录制清晰度的入口）先进 [V01](../../V-需求和反馈/V01-新功能提议/README.md) 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：`features/recorder/`、`record_settings/`、`shared/record/`
- 进度：`███████████████████░` 97%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A10.1 | 录制中心 | 界面 | 完成 | 2026-10-01 | 83b1de999 | [设计或说明](A10.1-录制中心/README.md)、[记录](A10.1-录制中心/record.md)、[评审页](A10.1-录制中心/page/01-说明.jpg) |
| A10.2 | 录制设置 | 界面 | 完成 | 2026-10-02 | 965d41956 | [设计或说明](A10.2-录制设置/README.md)、[记录](A10.2-录制设置/record.md)、[评审页](A10.2-录制设置/page/01-说明.jpg) |
| A10.3 | 录制按钮和录制状态图标重新设计：没在录单色圆环、在录红底白方块 | 界面 | 待真机 | 2026-10-02 | 2e6c6f5ab | [设计或说明](A10.3-录制按钮和状态图标/README.md)、[任务书](A10.3-录制按钮和状态图标/brief.md)、[记录](A10.3-录制按钮和状态图标/record.md)、[真机验证](A10.3-录制按钮和状态图标/verify.md)、[评审页](A10.3-录制按钮和状态图标/page/01-说明.jpg) |

<!-- docs:生成结束 -->
