# A10 录制界面

录制在用户眼前的样子：录制中心页面、录制设置页面，以及直播间顶栏、画面角标、录制面板状态卡、录制中心卡片、Android 录制通知里那一组表示“没在录 / 等待开播 / 准备中 / 录制中 / 重连中 / 合成中 / 失败”的图形。

## 范围

- 包括：
  - 录制中心（A10.1）：`features/recorder/` 的页面 `RecorderPage`、顶栏（菜单或返回、打开文件夹、录制设置）、五个带数量的筛选、任务卡片（卡片头 + 状态卡的紧凑尺寸）、更多菜单（进入直播间、开播自动录、删除任务）、删除确认、两种空状态、开播检测关着时的提示、按宽度分列、从“录制已停止”提醒进来时滚到并高亮那条任务。
  - 录制设置（A10.2）：`features/record_settings/` 的五组 21 行设置、单选对话框、总大小上限对话框、清空确认、选目录和“不能写入”的提示、目录对话框（没有系统选择器时）、从“改上限”进来时滚到并高亮。
  - 录制状态图形（A10.3）：`packages/live_ui` 的 `RecordGlyph`（七种状态）和 `RecordingBadge`（三种角标）、`shared/record/record_look.dart` 的状态映射、直播间顶栏和全屏顶栏的录制按钮 `RecordButton`、画面角标 `RoomRecordingBadge`、状态卡卡片头、Android 录制通知的两个小图标。
  - 录制中心和直播间录制面板共用的界面块：`shared/record/` 的状态卡 `RecordStatusCard`、九种卡片状态、按钮动作（A10.1 从 A07.6 搬过来的）。
- 不包括（归哪里）：
  - 录制本身（FFmpeg、分段、合并、重连、受限判断）→ [H01 录制核心](../../H-录制/H01-录制核心/README.md)；录制中心的接线和录制器的任务列表 → [H02](../../H-录制/H02-录制中心/README.md)；设置的存储、迁移、生效 → [H03](../../H-录制/H03-录制设置和存储/README.md)；开播自动录的轮询和排队 → [H04](../../H-录制/H04-自动录制和排队/README.md)；通知的文字、按钮、前台服务 → [H05](../../H-录制/H05-录制通知/README.md)。A10 只管这些东西长什么样、怎么点、各状态怎么说。
  - 直播间里的录制面板（`features/live_play/record/record_panel.dart`，604 行）的布局、位置、清晰度和分段选项 → [A07.6](../A07-直播间界面/A07.6-直播间弹窗/README.md)；这里只管它里面的状态卡（和录制中心是同一个 `RecordStatusCard`）和图形。录制按钮在顶栏的位置 → A07.1、A07.4。
  - 通知栏的整体外观（标题、正文、按钮的排法）→ [A14.1](../A14-系统界面/A14.1-系统界面/README.md)；首页导航的“录制中心”入口和首页标签顶栏的搜索、更多 → [A06](../A06-首页和全局/README.md)；设置行组件 `SettingsGroup`、`SettingsCounterRow` 等 → A02.1、A11.1。
  - 电视：pure_live_TV 没有录制，电视界面不做（A17 各任务写明“不适用”）；电视卡片 `tv/widgets/tv_room_card.dart` 不显示录制状态。
  - iOS、macOS 的“打开文件夹”和目录行 → [A18.1](../A18-苹果平台界面/A18.1-iOS和iPadOS差异设计/README.md)、A18.2。

## 现状：做到哪、怎么工作的

- 用户看得到的（A10.1、A10.2 登记为完成，A10.3 待真机）：
  - **录制中心**：手机是底部导航的“录制中心”标签（左上角菜单，右边还有首页各标签共有的搜索、更多），宽屏是左侧导航栏里的一项（A06.2 把 3.x 导航栏上方盖住整个窗口的按钮改成了导航项，`home_menu.dart:48-50`），顶栏左边不放按钮；从直播间录制面板的“录制中心 ›”“在录制中心查看”进来是返回（`record_panel.dart:76`、`:346`）；标题居中（`centredPageTitle`）。顶部一行五个筛选“全部 / 进行中 / 等待开播 / 已保存 / 失败”带数量，格高 48，宽屏最宽 660 靠左（`recorder_page.dart:369-423`）。卡片按状态排：录制中 → 重连中 → 整理文件 → 准备中 → 排队中 → 等待开播 → 失败 → 已保存 → 没在录制（`recordCardOrder`，`shared/record/record_state.dart:145`），同状态新的在前（`recorder_view.dart:48-58`）。列数 = ⌊(可用宽 + 12) ÷ 412⌋，1～4 列，可用宽是页面宽减两边留白（手机 16、宽屏 24），即 393 宽一列、852 两列、1280 三列、1920 四列（`recorderColumns` `recorder_view.dart:93`）。每张卡：卡片头（封面 96×54，宽屏 160×90；主播名、“⏱ 自动录”胶囊、标题、“平台 · 热度 84.7万”、右上角“⋮”）+ 状态卡的紧凑尺寸（计时 24 号、按钮 40 高一行）。“⋮”、长按、右键打开同一个小菜单：进入直播间、开播自动录（带开关）、删除任务（红色，前面一条分隔线），删除先弹确认。没有任务时“暂无录制任务”+ 怎么添加；某个筛选为空时“没有“失败”的任务”。开播检测关着且当前列表有等待开播的任务时，列表顶上黄色提示 +“打开”。没有 FFmpeg 的构建整页是“录制不可用”。
  - **录制设置**：顶栏“录制设置”；五组 21 行（基本 3、录制文件 5、性能与画质 5、断线重连 3、开播检测 5），内容最宽 720 居中（`SettingsPageList`）；依赖开关的项变灰不消失（总大小上限、最大重试次数、重连间隔、检测间隔、指数退避、最大检测间隔）；值在右边、标题下写意思（读写超时“15 秒 · 响应迅速”、缓冲队列“2048 · 原画推荐”）；中文单位、大小用 GB / MB 一位小数；“缓存”改叫“录制文件”，“挂机轮询检测”改叫“开播检测”；最大同时录制任务数行内减、加（1～10）；切片 1～60 整分钟；目录行右边“打开文件夹”；清空确认写删多少、不能恢复，“清空”错误色。从录制面板或录制中心的“改上限”进来时滚到“最大同时录制任务数”并主色边框高亮 2 秒。
  - **状态图形**：没在录是和旁边图标同色的圆环 + 中心圆点（没有红色）；等待开播（也用于名额满的排队中）圆环右下角小钟；准备中中性色 1/4 段弧转圈；录制中红色实心圆 + 白色圆角方块，外圈光晕 2.4 秒一呼一吸；重连中琥珀色 8 段虚线圆环；合成中中性色进度弧（没有进度时同准备中）；失败圆环右下角错误色“!”。减少动态效果时呼吸和转圈都停住（光晕常亮 30%）。画面角标只在录制中（红底“录制中 12:34”）、重连中、合成中（黑 60% 底“重连中 12:34”“合成中 45%”）出现；横屏全屏顶栏录制中时按钮右边带 `mm:ss`，这时控制栏下面不再重复“录制中”角标（网络电视例外：它的全屏顶栏没有录制按钮，角标照常显示）。录制通知小图标是实心圆挖出方块，“录制已停止”提醒是圆环开口加“!”。
- 内部怎么工作：
  - 任务来自 `packages/live_record` 的 `Recorder`，应用里由 `AppRecording`（`apps/pure_live/lib/app/recording.dart:369`，`recordingProvider`）持有；设置是 `RecordSettingsStore`（`:212`），读写 `live_store` 的 `Settings.record*`，存储键和 3.x 一样（D-018）。
  - 每个任务的 `task.status` 加上名额（`recordSlotsInUse` `record_state.dart:57`、`maxTaskCount`）经 `recordCardState`（`record_state.dart:39`）变成九种卡片状态 `RecordCardState`（`:7`）：排队中有空位时算“准备中”，停止但录到东西的算“已保存”。图形用 `recordGlyphState`（`shared/record/record_look.dart:12`）从卡片状态映射，按钮提示 `recordButtonLabel`（`:25`），画面角标 `recordBadgeState`（`:39`）只认 running / reconnecting / processing，合并进度 `recordJoinProgress`（`:55`）。顶栏按钮、角标、状态卡、录制中心都走这几个函数，不再用 `RecordStatus.isActive` 二分（A10.3 的根因）。
  - 录制中心：`RecorderPage` 听录制器的 `changes`，筛选、计数、排序、列数是纯 Dart（`features/recorder/logic/recorder_view.dart`，不引 material）；数量变化只重建筛选行（`ListenableSelector<RecorderCounts>` `recorder_page.dart:388`），每张卡自己听 `changes`。按钮动作（开播自动录、打开开播检测、再录一次、播放、查看原因、改上限）在 `shared/record/record_actions.dart`，直播间面板和录制中心调同一份。“播放”按钮先在后台问文件还在不在（`SavedFileCheck`，`shared/record/saved_file.dart:12`），不在就不显示。
  - 录制设置：`RecordSettingsPage` 读 `recording.settings`，改一项就写回（滑块在拖完时存）；“改上限”是带参数 `recordSettingsMaxTasks`（`'max-tasks'`，`record_actions.dart:18`）打开 `RoutePath.kRecordSettings`。
  - 通知：`app/recording_notice.dart` 按状态写标题（准备录制 / 正在录制 / 正在重连 / 正在整理录像，H05.1），原生 `RecorderForegroundService.kt` 设小图标（`:331` 录制中、`:135` 录制已停止）。
- 完成度（和 3.x 对照）：
  - 一致的：入口（手机底部导航标签；宽屏 3.x 是导航栏上方的按钮，现在是导航项，A06.2 的改动）、顶栏的打开文件夹和设置、点卡片进直播间、按状态排序、长按和右键菜单；录制设置 21 行的全部项、默认值、范围、存储键；3.x 卡片上的每个动作都有对应按钮（停止 → 停止录制；启动、重新录制 → 开始录制 / 再录一次；立即检测 → 现在就录；重试；排队中的取消；删除 → 更多菜单的删除任务）。
  - 确认过的改动：A10.1 c1～c11（U1～U3 按建议 A）、A10.2 c1～c14（V1～V4 按建议 A）、A10.3 c1～c11（X1～X3 按建议 A，X4 由维护者在 H05.1 补做）；都按 D-003 定。
  - 还缺：A10.3 的真机验证；A10.1、A10.2 登记为完成，但筛选、更多菜单、删除、录制设置各对话框没有逐项的 K90 记录（见“已知问题”）；深色主题和 1.3 倍字号下的录制中心没有自动测试。

## 代码地图

录制中心和录制设置（`apps/pure_live/lib/features/`）：

| 文件 | 职责 | 设计 |
|---|---|---|
| `recorder/recorder_page.dart`（637 行） | `androidDocumentFolderUri`（`:38`）、打开录制文件夹 `openRecordFolder`（`:55`，Android 公共目录交给文件管理器）、`recordTaskFolder`（`:77`，这次录像所在的文件夹）、页面 `RecorderPage`（`:94`，路由 `RoutePath.kRecordPage`；手机首页标签里左上角是菜单、宽屏导航项里不放按钮、从别处进来是返回 `:276-284`、顶栏两个按钮 `:287-299`、没有 FFmpeg 时 `:305`、按宽度分列 `:311-335`）、`recorderTaskOf`（`:110`，从提醒进来时的任务编号）、筛选行 `_FilterBar`（`:369`）和 `_FilterChip`（`:425`）、任务网格 `_TaskGrid`（`:490`，按行懒加载、行内顶对齐、空状态 `:532-540`）、开播检测提示 `_PollingOffBanner`（`:582`）、高亮 `RecorderTaskHighlight`（`:605`） | A10.1、A08.5 |
| `recorder/recorder_task_card.dart`（426） | 卡片的动作表 `RecorderCardActions`（`:15`）、更多菜单项 `_CardMenu`（`:74`）、`RecorderTaskCard`（`:90`，删除确认 `:201`、长按和右键 `:259-260`、状态卡紧凑尺寸 `:268`）、卡片头 `_Head`（`:309`，封面 96×54 / 160×90 `:321`）、“⏱ 自动录”胶囊 `_AutoPill`（`:399`） | A10.1 c3、c4 |
| `recorder/logic/recorder_view.dart`（94） | 五个筛选 `RecorderFilter`（`:7`）、每个任务的卡片状态 `recorderStates`（`:41`）、可见任务和排序 `recorderVisible`（`:48`）、数量 `recorderCounts`（`:63`）、列数 `recorderColumns`（`:93`，最小卡宽 400 `:84`、间距 12 `:87`） | A10.1 c6、c10 |
| `recorder/recorder_texts.dart`（143） | 筛选名（`:8`）、阶段（`:17`）、FFmpeg 失败原因（`:34`）、受限原因（`:49`）、取流失败（`:56`）、录制提示 `recordNoticeText`（`:93`，直播间录制按钮也用）；`recordSizeText`（`:123`）、`recordSecondsText`（`:135`）现在没有调用者 | A10.1、H02.1 |
| `record_settings/record_settings_page.dart`（626） | 高亮时长 `recordLimitHighlight` 2 秒（`:21`）、`RecordSettingsPage`（`:29`，“改上限”进来 `:81`、滚到并高亮 `_showLimit` `:87-98`、五组从 `:273`、`:314`、`:375`、`:448`、`:484` 起，目录行和“打开文件夹” `:316-332`、最大同时录制任务数 `_maxTasks` `:542`）、滑块行 `_SliderSetting`（`:576`，拖完才存） | A10.2 |
| `record_settings/record_settings_dialogs.dart`（347） | 系统目录选择器的注入点 `recordDirectoryPickerProvider`（`:13`）、`RecordOption`（`:16`）、单选对话框 `showRecordRadioDialog`（`:34`，当前项主色加勾）、整数对话框 `RecordIntegerDialog`（`:79`，总大小上限）、清空确认 `confirmRecordClear`（`:218`）、没有系统选择器时的目录对话框 `RecordDirectoryDialog`（`:231`） | A10.2 c8、c13、c14 |
| `record_settings/record_settings_texts.dart`（60） | 中文时长和单位（`:12`、`:20`、`:23`）、GB / MB（`:26`）、清晰度名（`:38`）、读写超时和缓冲队列的意思（`:48`、`:55`） | A10.2 c5、c6 |

共用（`apps/pure_live/lib/shared/record/`）：

| 文件 | 职责 | 设计 |
|---|---|---|
| `record_state.dart`（169） | 九种卡片状态 `RecordCardState`（`:7`）和判断 `recordCardState`（`:39`）、占用的名额（`:57`）、`recordBusy`（`:65`）、开播自动录是否开着 `autoRecordOn`（`:70`）、房间的任务（`:77`）、清晰度选项和默认（`:82`、`:94`）、合并百分比、分段号和段数、时钟和大小文字、排序表 `recordCardOrder`（`:145`）、码率（`:158`） | A07.6、A10.1 |
| `record_status_card.dart`（701） | 状态卡要显示的事实 `recordCardFacts`（`:39`）、颜色档 `_Tone`（`:88`，红 = 录制中、黄 = 排队和重连、绿 = 已保存、错误色 = 失败 `:106-109`）、`RecordStatusCard`（`:164`，`compact` 是录制中心的尺寸 `:228`；卡片头图形 `:265`；九种状态的正文和按钮 `:267-517`；合成进度 `:410-437`；录像有缺失的提示 `:519`） | A07.6、A10.1 c2、A10.3 c9、H01.3 |
| `record_look.dart`（58） | 卡片状态 → 七种图形 `recordGlyphState`（`:12`）、按钮提示 `recordButtonLabel`（`:25`）、角标状态 `recordBadgeState`（`:39`）和文字（`:47`）、合并进度 `recordJoinProgress`（`:55`） | A10.3 c2、c7 |
| `record_actions.dart`（90） | “改上限”的参数 `recordSettingsMaxTasks`（`:18`）和 `openRecordLimit`（`:22`）、打开开播检测 `enableRecordPolling`（`:27`）、开播自动录 `setAutoRecord`（`:38`）、再录一次（`:69`）、播放（`:76`）、查看原因（`:81`） | A10.1、A10.2 c9 |
| `saved_file.dart`（58） | `SavedFileCheck`（`:12`）：后台检查录像文件是否还在（“播放”只在文件在时出现，A07.11 / B09 c6） | A07.11 |

图形和别处的接线：

| 文件 | 职责 | 设计 |
|---|---|---|
| `packages/live_ui/lib/src/widgets/record_glyph.dart`（400） | `RecordGlyphState` 七种（`:10`）、`RecordGlyph`（`:41`，呼吸 2.4 秒 `:64`、转圈 1.2 秒 `:67`、减少动态效果时不动 `:80`）、画法 `RecordGlyphPainter`（`:154`，各状态 `:235-298`，右下角挖空用 `saveLayer` + `BlendMode.clear` `:240-244`）、`formatRecordingTime`（`:314`）、角标 `RecordingBadge`（`:328`） | A10.3 c1～c7 |
| `packages/live_ui/lib/src/theme/live_colors.dart` | `LiveSemanticColors.recording`（`:173`，`#D92D20`）、`onRecording`（`:176`）、`recordingHalo`（`:180`，静止时 30%）、`OnVideoColors.onError`（`:104`，画面上的“!”） | A10.3 |
| `apps/pure_live/lib/features/live_play/buttons/record_button.dart`（217） | 直播间顶栏和全屏顶栏的录制按钮 `RecordButton`（`:23`）：按卡片状态画图形和提示（`:93-110`）；等待开播且开着开播自动录时是“自动录”胶囊（`:111-139`）；横屏全屏录制中带时间（`:140-165`，`_RecordTime` `:178` 每秒只重画这段字） | A10.3 c3、c8 |
| `apps/pure_live/lib/features/live_play/player/recording_badge.dart`（102） | 画面上的录制角标 `RoomRecordingBadge`（`:18`）：录制中、重连中、合成中；`showsRecording` 关掉录制中（横屏全屏）；控制栏隐藏和小窗时紧凑形 | A10.3 c7、c8 |
| `apps/pure_live/lib/features/live_play/player/player_controls.dart`、`player_view.dart`、`layout/room_header.dart`、`mini/mini_player.dart` | 放按钮和角标的地方：竖屏顶栏 `room_header.dart:106`；横屏全屏顶栏带时间 `player_controls.dart:294`、`:372`；竖屏全屏第一行 `:310`；竖屏画面标题前的角标 `_RecordingMark` `:447-458`；控制栏隐藏时左上角紧凑角标 `player_view.dart:724`、全屏控制栏下面的角标 `:734-736`；小窗 `mini_player.dart:229` | A07 各任务；A10.3 c8 |
| `apps/pure_live/lib/app/recording_notice.dart`（174） | 前台录制通知的标题和正文（`recordNotificationContent` `:22`，单个直播间按状态 `_oneTitleKey` `:59`）、“录制已停止”提醒（`:76`）、`RecordingNotices`（`:94`） | H05.1、A14.1 |
| `apps/pure_live/android/app/src/main/res/drawable/ic_stat_recording.xml`、`ic_stat_record_stopped.xml` | 录制通知小图标（实心圆挖出圆角方块）、“录制已停止”提醒小图标（圆环开口加“!”）；`RecorderForegroundService.kt:331`、`:135` 使用 | A10.3 c10、H05.1 |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/recorder/recorder_centre_test.dart`（23 个用例声明） | A10.1：首页标签里的顶栏和从别处进来的返回；没有任务；五个筛选一行、数量、高 48；九种状态的卡片头和紧凑状态卡；A10.3 九张卡片头的图形；已保存的播放、打开文件夹、查看原因；“播放”在后台问磁盘；筛选和空筛选；开播检测提示；更多菜单的三种打开方式和开播自动录；删除确认；手机横屏两列、宽屏 1280 三列；筛选、排序、列数的逻辑；3.x 默认目录的录像搬一次；A08.5 从提醒进来滚到并高亮（5 个） |
| `.../recorder/recorder_page_test.dart`（5） | 录制设置值从 meta 和 3.x 搬进存储一次；Android 文件夹地址；A10.3 顶栏七种状态的图形、红色、提示、合成进度、横屏带时间和角标；九种卡片状态到图形和角标的映射；没有 FFmpeg 时“录制不可用” |
| `.../recorder/recording_wiring_test.dart`（3） | 受限房间的说明、画质受限的说法、录制器接线（H02.1） |
| `apps/pure_live/test/features/record_settings/record_settings_page_test.dart`（12） | A10.2：文字和单位；21 行的顺序、图标、值和意思；3.x 存的值和依赖项变灰；行内加减；“改上限”高亮 2 秒；单选对话框；总大小上限对话框；清空确认；系统选择器和不能写入；没有选择器时的目录对话框；横屏和宽屏最宽 720 |
| `packages/live_ui/test/design_system_test.dart`（11，其中录制 4 个） | A10.3：只有录制中有红色、其余用图标色；画面上的深色色调；呼吸和转圈、减少动态效果时都不动；角标三种状态；录制提示的对比度 4.5:1 |
| `apps/pure_live/test/platform/system_surfaces_test.dart`（12，其中录制 5 个） | 录制通知按状态写标题（X4）、“录制已停止”提醒的文字、通知小图标资源和发行包不被资源压缩删掉 |

## 3.x 基线

文件都在 `git show v3.2.11:lib/` 下（本机副本 `~/ref/v3ref/lib/`，已核对和标签一致）：

- 录制中心：`recorder/pages/recorder/recorder_page.dart`（842 行）：顶栏 `:35-52`（标题居中；`Get.width <= 680` 且不能返回时左边是菜单 `:29`、`:38`；右边打开文件夹 `Remix.folder_video_line`、设置 `Remix.settings_5_line`，都是 22 号）；每张卡的状态块、计时、细条、“1.0x”在 `:579-711`。九个筛选 `recorder/widgets/recorder_bounded_scroll.dart`（161 行）；排序 `recorder/models/recorder_task_ordering.dart`（25 行）；动作 `recorder/pages/recorder/recorder_controller.dart`（1763 行）。入口：手机底部导航 `modules/home/mobile_view.dart:56-63`（`Remix.download_2_line`“录制中心”），宽屏导航栏上方按钮 `modules/home/tablet_view.dart:138-146`。
- 录制设置：`recorder/pages/record_settings/record_settings_page.dart`（622 行，页面、单选和输入对话框、清空确认）、`record_settings_controller.dart`（348 行）、默认值 `recorder/consts/recorder_config.dart`（297 行）；设置行 `common/widgets/widget_extensions.dart`（455 行，宽屏最宽 960 `:8`）。
- 录制按钮：`modules/live_play/widgets/button/record_action_button.dart:39-94`：48×48、圆角 12 的实心按钮；没有任务是中性色 `Remix.record_circle_line`、底 `surfaceContainerHighest`，有任务 `Remix.checkbox_circle_fill` 主色，running / reconnecting / preparing 是 `Remix.record_circle_fill` 红色（`Colors.redAccent`，`_isTaskRunning` `:96-104`）；点了是五个动作的对话框（`_handlePressed` `:106` 起）。图标和字在 `record_action_content.dart`（51 行）。v3 的未录本来没有红色，4.0.0 的红点是 A07.1 改动 13 加的（A10.3 修掉）。
- 要保留的操作：卡片长按或右键打开菜单（[specs/UI.md](../../specs/UI.md) 附录 A 第 14 条）；点卡片进直播间；3.x 的录制设置键名和含义不变（D-018）；录制设置的全部项、范围和默认值。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 录制状态图形还没在真机上看（呼吸节奏、减少动态效果、深色、通知小图标） | A10.3 | 动画节奏和颜色只在测试和效果图里看过 | [A10.3](A10.3-录制按钮和状态图标/verify.md) 待真机；同一轮看 H05.1 |
| A10.1、A10.2 登记为“完成”，K90 上只看过“已保存”卡片和合并（S02.2、S02.3）；筛选、更多菜单、删除、开播检测提示、录制设置的对话框、选目录、清空、“改上限”高亮没有记录 | 各任务 `record.md`；[S02.2 记录](../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md) | 不符合 PROCESS 3.2“完成必须有真机结果” | 写进本单元报告；建议并入 [S03.1](../../S-质量和验证/S03-统一验证/README.md) 或 S02.6 补看 |
| `recordSizeText`、`recordSecondsText` 没有调用者（A10.2 把录制设置的单位挪到 `record_settings_texts.dart` 后留下的） | `features/recorder/recorder_texts.dart:123`、`:135` | 死代码，不影响用户 | 影响小，没有任务管；以后整理录制文字时删掉 |
| 跨功能引用：`recorder -> home/home_menu.dart`、`recorder -> home/menu_button.dart`（首页标签顶栏的菜单和搜索、更多，`recorder_page.dart:14-15`）、`live_play -> recorder/recorder_texts.dart`（`record_button.dart:11`、`record_panel.dart:12` 用录制提示文字） | `tools/gate/ui_baseline.json` | 门禁基线里还有 3 条（A10.1 去掉过 `home_menu`，合并时和首页外壳 U.3a 的 `showsHomeBarButtons` 一起又回来了） | 首页菜单挪到 `shared/`（A06）、录制提示文字挪到 `shared/record/` 时去掉；没有专门任务 |
| 主播下播后无限快速重试、一个 0 字节分段让整段合并失败 | 录制核心 | 录制中心里任务一直在“重连中”或合并失败 | [H01.5](../../H-录制/H01-录制核心/H01.5-主播下播后不再无限快速重试/README.md)（未开始） |
| 录制中心卡片“整理文件”有合并进度，通知里没有 | `app/recording_notice.dart` | 合并时只能进应用看进度 | [H05.3](../../H-录制/H05-录制通知/H05.3-录制通知显示合并进度/README.md) |
| 只录一个直播间时，点前台录制通知不会定位到那条任务（“录制已停止”提醒会） | `app/recording_notice.dart`、`RecorderForegroundService.kt` | 少一步定位 | [H05.2](../../H-录制/H05-录制通知/H05.2-只录一个直播间时点前台录制/README.md) |
| “优先录制原画轨道”和“默认录制清晰度”同时设置时谁优先，说明照 v3 保留，没在代码里确认 | 录制设置第三组；`packages/live_record` | 说明可能和实际不符 | H03（A10.2 记录“拿不准的地方”第 1 条） |
| iOS 的“打开文件夹”和目录行没有设计落地 | 录制中心顶栏、录制设置目录行 | iOS 没有“打开某个文件夹” | [A18.1](../A18-苹果平台界面/A18.1-iOS和iPadOS差异设计/README.md) |
| 录制设置页、录制中心在电脑上按 Esc 不返回（没有 `EscapeBack`） | `record_settings_page.dart`、`recorder_page.dart` | 规范 5.4 的 Esc 返回链不全 | A05.1 |
| 已解决：录制的清晰度标签曾写请求的“原画”，实际是平台给的“超清”（S02.2 发现） | `packages/live_record/lib/src/resolver.dart:334`（`servedQuality`） | — | [H01.3](../../H-录制/H01-录制核心/H01.3-合并进度/record.md) 已修；真机复看归 S02.5 |

## 相关决定和规范

- D-003：A10.1 的 U1～U3、A10.2 的 V1～V4、A10.3 的 X1～X3 由维护者按建议 A 定；A10.3 的 X4（通知按状态写字、“录制已停止”新图标）超出范围，维护者在 H05.1 补做（`79ecb5d2b`）。
- D-018：3.x 的录制设置键名和含义不变（A10.2 一个键没改；改名的文字用新翻译键，旧键 `cache_management` 等留着）。
- D-011：标题位置照 3.x 实际运行的样子，录制中心标题居中（`centredPageTitle`）；录制设置照 3.x 靠左（宽屏测试断言“标题在开头”）。
- D-019：真机验证只点测试包，不碰 3.x 和正式包的录像。
- D-024：翻译键这次不清理（A10.1、A10.2 不再用的旧键留着）。
- [specs/UI.md](../../specs/UI.md)：第 3 节（同一件事一种做法：直播间面板和录制中心是同一张状态卡、同一组图形）；第 5.3 节（只读父组件宽度：录制中心按页面宽度分列，A10.1 偏差 1）；第 5.4 节（点击区域至少 48：筛选格高 48，紧凑按钮的点击区补到 48）；第 7 节（更多菜单是贴着按钮的小菜单，删除、清空是对话框）；第 8.1 节（语义色 `LiveSemanticColors.recording`、`warning`；红色只给录制中）；第 9 节（动效：减少动态效果时不呼吸、不转圈）；附录 A 第 14 条。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/recorder test/features/record_settings test/platform/system_surfaces_test.dart`；`cd packages/live_ui && flutter test test/design_system_test.dart`（上表）。覆盖了每个确认的改动。缺：深色主题下录制中心和录制设置的布局测试（只在开发时本机渲染看过）；1.3 倍字号下的卡片头和筛选行；没有截图对照。
- 真机：[S02 的 CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 3 节（录制）第 1 条（通过：S02.2 录 75 秒、S02.3 录 5 分 39 秒两段合成一个 MP4，录制中心显示“已保存”卡片的时长、大小、播放、打开文件夹、再录一次）、第 4 条（断网重连，没看）、第 5 条（等开播，没看）、第 6 条（换目录和打开文件夹，没看）。A10.3 的图形按 [verify.md](A10.3-录制按钮和状态图标/verify.md) 看。

## 路线

1. A10.3 在 K90 上按 [verify.md](A10.3-录制按钮和状态图标/verify.md) 看完（不需要写代码），通过后登记为完成；同一轮把 H05.1（通知标题、“录制已停止”图标）一起看。
2. 同一轮或 S03.1 时补看 A10.1、A10.2 没有记录的部分（CHECKLIST 第 3 节第 4～6 条，加上筛选、更多菜单、删除、“改上限”高亮），给两个任务补上真机结果。
3. 录制核心的修复 H01.5（下播重试和空分段）合并后，回看录制中心卡片的“重连中”“失败”“已保存”是否显示正确；H05.2、H05.3 做完后看通知定位和合并进度。
4. 以后：iOS 和 macOS 的打开文件夹（A18.1、A18.2）；跨功能引用的三条（首页菜单、录制提示文字挪到 `shared/`）。新的录制界面需求（例如按房间设置录制清晰度的入口）先进 [V01](../../V-需求和反馈/V01-新功能提议/README.md) 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：`features/recorder/`、`record_settings/`、`shared/record/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A10.1 | 录制中心 | 界面 | 完成 | 2026-10-01 | 83b1de999 | [设计或说明](A10.1-录制中心/README.md)、[记录](A10.1-录制中心/record.md)、[评审页](A10.1-录制中心/page/01-说明.jpg) |
| A10.2 | 录制设置 | 界面 | 完成 | 2026-10-02 | 965d41956 | [设计或说明](A10.2-录制设置/README.md)、[记录](A10.2-录制设置/record.md)、[评审页](A10.2-录制设置/page/01-说明.jpg) |
| A10.3 | 录制按钮和录制状态图标重新设计：没在录单色圆环、在录红底白方块 | 界面 | 完成 | 2026-10-08 | 2e6c6f5ab | [设计或说明](A10.3-录制按钮和状态图标/README.md)、[任务书](A10.3-录制按钮和状态图标/brief.md)、[记录](A10.3-录制按钮和状态图标/record.md)、[真机验证](A10.3-录制按钮和状态图标/verify.md)、[评审页](A10.3-录制按钮和状态图标/page/01-说明.jpg) |

<!-- docs:生成结束 -->
