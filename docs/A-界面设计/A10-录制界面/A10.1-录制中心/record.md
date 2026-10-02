# A10.1 录制中心

- 日期：2026-10-01
- 设计：[docs/A-界面设计/A10-录制界面/A10.1-录制中心/README.md](README.md)（第 1 版，用户已确认；选择 U1～U3 都按 A：筛选一行五个带数量、删除放进卡片右上角的更多菜单、已保存卡片是播放 / 打开文件夹 / 再录一次）
- 范围：录制中心页面和它的入口。录制设置页（A10.2）由别的任务做，这里只用路由跳过去。
- 改动的目录：`apps/pure_live/lib/features/recorder/`、`apps/pure_live/lib/shared/record/`（新，A07.6 状态卡和录制逻辑搬过来两边共用）、`apps/pure_live/lib/features/live_play/`（只改引用）、`packages/live_ui`（只加图标）、翻译文件、门禁基线、文档。`packages/live_record` 不用改（A07.6 加的单次覆盖、开播自动录、`lastOutputPath`、`lastLiveCheckAt` 够用）。
- 没有改原生部分，所以没有构建 APK；没有往手机安装。“播放”用应用已有的 `AppNavigator.openFile`，“打开文件夹”用已有的 `openRecordFolder`（Android 走 `RecordFolderOpener`，桌面交给系统文件管理器），只是多了一个“打开哪个文件夹”的参数。

## 状态卡：从直播间搬到共用的地方（EXTRA 第 2 条）

| 要求 | 做到 | 说明 |
|---|---|---|
| 找到 A07.6 在 `features/live_play` 里做的状态卡，提到共用的地方 | ✅ | `features/live_play/record/record_panel.dart` 里的 `_StatusCard` 和它用的计时、转圈、红点、数字块、三种按钮，搬到 `shared/record/record_status_card.dart`（`RecordStatusCard`）；九种状态的判断等纯逻辑 `features/live_play/logic/record_state.dart` 整个搬到 `shared/record/record_state.dart`（git 记为改名） |
| 只做移动和参数化，不改它在直播间里的样子 | ✅ | 参数：`compact`（录制中心的紧凑尺寸）、`onCentre` / `onFolder`（已保存卡片第二个按钮是“在录制中心查看”还是“打开文件夹”）、失败原因的文字由调用方给（录制中心要带上本次会话的受限原因）。直播间不传 `compact`，样子、文字、按钮键名都和原来一样；A07.6 的 20 个弹窗测试不改一行断言全部通过 |
| 直播间那边的引用跟着改 | ✅ | `record_panel.dart` 用 `RecordStatusCard`；`record_button.dart`、`room_header.dart` 引 `shared/record/record_state.dart`；和录制无关的弹幕帧率函数 `resolvedDanmakuFps` 从原文件挪到 `live_play/logic/danmaku_fps.dart` |
| 两边同一种做法 | ✅ | “开播自动录”的开关逻辑、打开开播检测（带提示）、“再录一次”、“播放”、“查看原因”对话框也搬到 `shared/record/record_actions.dart`，面板和录制中心调用同一份 |

紧凑尺寸和面板的差别（设计 c2 写的三处，加上效果图里的尺寸）：计时 24 号（面板 36 号，`displaySmall`）；按钮 40 高、一行排开（面板 48 高，已保存时“播放 / 在录制中心查看”一行、“再录一次”单独一行）；“没在录制”不写说明句，“等待开播”写检查间隔和上次检查时间（开播检测关着时黄字）而不是面板的说明句；“正在整理文件”去掉面板里的“可以关掉这里，不影响整理”；卡片圆角 12、内边距 12（面板 16）；录像有缺失时在数字下面加 3.x 的黄色提示（面板不加，保持原样）。

## 逐条对照（设计 README 的 c1～c11）

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 入口：手机底部导航“录制中心”标签、宽屏导航栏的录制按钮、直播间面板“录制中心 ›”“在录制中心查看” | ✅ | 入口都已在（`home_page.dart`、`home_views.dart`、A07.6 面板），这次没改；页面路由不变（`RoutePath.kRecordPage`） |
| c1 | 顶栏：标题居中；左边底部导航标签里是菜单，其他是返回；右边打开文件夹、录制设置 | ✅ | 图标照 v3（`Remix.folder_video_line`、`Remix.settings_5_line`，22 号），改走 `AppIcons.recordFolder` / `recordSettings`；左上角按页面是否在首页标签里决定，不再读整屏宽度（修 P11，见下“偏差 1”） |
| c1 | 点卡片进直播间；按状态排序，同状态新的在前 | ✅ | 排序按卡片状态：录制中 → 重连中 → 整理文件 → 准备中 → 排队中 → 等待开播 → 失败 → 已保存 → 没在录制（`recordCardOrder`），同状态按会话开始时间新的在前（3.x `RecorderTaskOrdering`）；所有筛选都用这个顺序（“进行中”含五种状态，也按状态分开） |
| c1 | v3 筛选按钮的样子；3.x 的任务和设置照旧 | ✅ | 等分格、圆角 11、间距 3、外边距 10 / 6、选中主色容器底；没有新设置项，任务 JSON 不变 |
| c2 | 状态块 = A07.6 状态卡（同一个组件，紧凑尺寸） | ✅ | 见上一节；九种状态的图标、颜色、名字、数字、按钮和面板一致 |
| c3 | 卡片头：封面 96×54、主播名、标题、平台中文名和图标、人数；“自动录”标签；右上角“更多” | ✅ | 封面按显示尺寸的两倍解码；宽屏封面 160×90（效果图 `v4-wide`）；人数“热度 84.7万”用共用的 `audienceLabel` + `readableAudience`，没有人数时只写平台；“⏱ 自动录”跟着 `autoRecordOn`（和直播间顶栏、面板开关同一个判断）；封面上不再压状态字（P2） |
| c4 | 删除进“更多”菜单（进入直播间、开播自动录、删除任务）；长按 / 右键卡片也打开；对话框写清后果；统一叫“删除任务” | ✅ | 小菜单贴着“⋮”在下方弹出（和直播间右上角菜单同一种做法：`PopupMenuButton`、圆角 8、图标 20），长按、右键都打开同一个菜单；“开播自动录”行带开关，点整行切换（和面板同一个逻辑）；“删除任务”红色、前面一条分隔线。对话框标题“删除“晚风”的录制任务？”，正文照设计，按钮“取消”“删除”（错误色实心）；确认后照 v3 先停止（有分段就合并），再从列表删掉 |
| c5 | 已保存：播放、打开文件夹、再录一次（U3 A） | ✅ | 三个按钮一行；“播放”用系统默认程序打开 `lastOutputPath`，文件不在时不显示（面板的规则）；“打开文件夹”打开这次录像所在的文件夹（`lastOutputPath` 的目录，没有就用最后一次尝试的目录，再没有就是录制根目录）；“再录一次”同面板：新的一次录到下播为止，除非开着“开播自动录” |
| c6 | 筛选一行五个带数量：全部、进行中、等待开播、已保存、失败；“没在录制”只在全部里（U1 A） | ✅ | 按卡片状态分（排队但有空位的显示“准备中”，算进行中；停止且录到东西的算已保存）；数量 0 也显示；数量变化只重建筛选行（`ListenableSelector`） |
| c7 | 空状态两种 | ✅ | 一个任务都没有：“暂无录制任务”+ 怎么添加（翻译里已有的 `recorder_empty_hint`）；某个筛选为空：“没有“失败”的任务”。用 `live_ui` 的 `AppStatusView`（统一的状态组件，见“偏差 3”） |
| c8 | 开播检测关着且有等待开播的任务：列表顶上黄色提示和“打开”；开着时等待开播的卡片写“每 30 秒检查一次是否开播 · 上次检查 21:35” | ✅ | 提示只在当前列表里有等待开播的任务时出现（全部、等待开播）；“打开”直接打开“启用开播检测”，提示“已打开开播检测（每 N 秒检查一次）”，和面板同一个函数；多列时提示占满一整行 |
| c9 | 失败的“查看原因”看全文（同面板的对话框） | ✅ | 同一个对话框（`showRecordFailureReason`），可选中复制 |
| c10 | 手机竖屏一列；横屏和宽屏按可用宽度分列（最小卡宽 400）；只读父组件宽度 | ✅ | `LayoutBuilder` 取页面自己的宽高：列数 = ⌊(宽 + 12) ÷ 412⌋，1～4 列（393 宽 1 列、852 宽 2 列、1280 宽 3 列、1920 宽 4 列）；一行里卡片顶对齐，行高取最高的一张（效果图 `v4-wide`）；按行懒加载 |
| c11 | 去掉开始时间、“1.0x”、满格细条、线路名 | ✅ | 录制中看计时，已保存显示完成时间；线路名在失败原因里 |

v3 的问题：P1～P11 都按上表修了。P4 里点名的“排队中的‘启动’点了没反应”（v3 `recorder_controller.dart:745-748`：任务已在队列里直接返回）——v4 录制器的 `startTask` 对排队中的任务同样直接返回，所以照设计把这个按钮去掉：排队卡片只有“取消”“改上限”，名额没满的排队任务显示成“准备中”（只有“取消”），整理文件时没有按钮；测试固定排队卡片里没有“启动”。

和 v3 对照（功能一项不少）：停止 → 停止录制；启动 → 开始录制 / 再录一次；立即检测 → 现在就录（v3 的“立即检测”和“启动”都是 `forceStartTask`；v4 原来另加的“只检测不录”按钮不在设计里，去掉）；重试 → 重试；重新录制 → 再录一次；排队中的取消 → 取消；删除 → 更多菜单的删除任务；打开文件夹、设置 → 顶栏不变；九个筛选 → 五个；录像有缺失的提示 → 保留（紧凑卡片里）；最近失败 → 状态卡里的失败原因 + 查看原因。

### 各客户端

| 客户端 | 做法 |
|---|---|
| 手机竖屏 | 底部导航标签：左上角菜单，一列 |
| 手机横屏（852×393） | 两列，封面 96×54，筛选拉满宽度；高度紧凑，不算宽屏 |
| 宽屏（平板、Windows、Linux、macOS、iPad；宽 ≥840 且高 ≥480） | 从导航栏或直播间进入，左上角返回；2～4 列；封面 160×90；筛选行最宽 660、靠左；鼠标悬停卡片高亮（`InkWell`），右键 = 更多菜单；回车打开有焦点的卡片 |
| 电视 | 不适用（pure_live_TV 没有录制） |
| iOS | “打开文件夹”的做法交给 A18.1（设计如此），这次没改 |

### 偏差和原因

1. **左上角菜单只看是不是首页标签**：v3 和 v4 原来是“在首页标签里且整屏宽 ≤680”。首页只在手机布局里放“录制中心”标签（宽屏布局把它换成导航栏按钮，`home_menu.dart`），所以只看 `inHome` 结果一样，又不读整屏宽度（P11）。顺带去掉了 `recorder -> home/home_menu.dart` 这条跨功能引用。
2. **筛选格高 48**：效果图里是 44；保留 v3 的 48，满足“点击区域至少 48”（计划书 5.4）。字照效果图 13 号，选中 600、未选中 400（计划书 8.2 只用这两种字重），数字 12 号等宽、80% 透明度。
3. **空状态的圆**：效果图是 72 的灰圆、34 的图标；用了 `live_ui` 的 `AppStatusView`（86 的圆、42 的图标、弹出动画），守“统一用 live_ui 的状态组件”。图标照 v3（`video_collection_outlined`），颜色用次要文字色。
4. **紧凑按钮的内边距 8**：Material 按钮默认左右各 24，三个按钮一行时“打开文件夹”“再录一次”会被截断；只在紧凑尺寸改，面板不变。按钮的可点区域仍按平台规则补到 48（手机上）。
5. **等待开播的提示**：列表顶上的黄色提示在“全部”和“等待开播”里都出现（设计图画在“等待开播”下，改动表写“列表顶上”）；卡片里那行黄字照效果图同时保留。

## 新设置项

无。

## 门禁（`ui_baseline.json`）

- `recorder` 直接写的颜色和图标：**36 → 0**（v3 的九种状态色、`Icons.*`、`Remix.*` 全部换成 `live_ui` 的颜色角色、`LiveSemanticColors` 和 `AppIcons`）；基线里删掉 `recorder` 一行。`live_play` 仍是 9（这次只搬走、没加）。
- 跨功能引用：删掉 `recorder -> home/home_menu.dart`；没有新增（录制中心和直播间都只引 `shared/record/`）。
- `features/recorder/logic/recorder_view.dart`（筛选、排序、数量、列数）是纯 Dart，不引 material。
- `recorder_texts.dart` 去掉只给 v3 卡片用的九个筛选表、九种状态名和状态色、`recordPlatformName`、`recordDurationText`、`recordTimeText`；`recordBitrateText` 搬到 `shared/record/record_state.dart`（状态卡用）。录制设置页用的 `recordSizeText`、`recordSecondsText` 和失败、提示文字的函数都还在，录制设置页（A10.2）不用改。

## 新增

- `AppIcons`（只加）：`recordFolder`、`recordSettings`、`recordEmpty`、`recordUnavailable`、`more`、`enterRoom`、`delete`，`live_ui` 的图标对照测试一并加上。
- 翻译中英各 7 条：`record_card_processing_desc`、`recorder_delete_body`、`recorder_delete_task`、`recorder_delete_title`、`recorder_filter_active`、`recorder_filter_saved`、`recorder_polling_off`。其余文字用已有的（面板的 `record_panel_*`、`room_open`、`more`、`delete`、`recorder_empty_*`、`recorder_open_folder` 等）。

## v3 文件 → v4 文件

| v3（`lib/recorder/`） | v4 |
|---|---|
| `pages/recorder/recorder_page.dart`（页面、顶栏、列表、空状态、`_remove` 对话框） | `features/recorder/recorder_page.dart`（页面、筛选行、列表、提示、空状态）、`features/recorder/recorder_task_card.dart`（卡片头、更多菜单、删除对话框） |
| `pages/recorder/recorder_page.dart` 的状态块（`:579-711`） | `shared/record/record_status_card.dart`（A07.6 状态卡，紧凑尺寸） |
| `widgets/recorder_bounded_scroll.dart`（九个筛选） | `features/recorder/recorder_page.dart` 的 `_FilterBar`；`features/recorder/logic/recorder_view.dart` |
| `models/recorder_task_ordering.dart`、`record_status.dart:17-38` | `features/recorder/logic/recorder_view.dart`（`recorderVisible`）、`shared/record/record_state.dart`（`recordCardOrder`） |
| `pages/recorder/recorder_controller.dart` 的 `forceStartTask`、`stopTask`、`unRecorder` | `packages/live_record`（不变）；`shared/record/record_actions.dart` |

## 测试

- 新增 `apps/pure_live/test/features/recorder/recorder_centre_test.dart` 14 个：
  - 顶栏：首页标签里左上角菜单、标题居中、右边先文件夹后设置（图标、提示文字）；从别处进来是返回。
  - 没有任务：说明怎么添加，五个筛选都是 0。
  - 手机竖屏：五个筛选一行、顺序和数量（全部 9、进行中 5、等待开播 1、已保存 1、失败 1）、高 48；九张卡一列、按确认的顺序；封面 96×54。
  - 每张卡：卡片头（主播名、自动录、标题、“哔哩哔哩 · 热度 84.7万”、“⋮”在右上）；九种状态各自的状态卡、文字和按钮；计时 24 号、按钮 40 高；没有“1.0x”、细条、线路；排队中只有“取消”“改上限”、没有“启动”（P4）；已保存三个按钮一行和录像有缺失的提示；没在录制没有说明句。
  - 已保存：播放打开文件、打开文件夹打开这次录像的文件夹；查看原因的对话框。
  - 筛选：进行中、已保存、失败只显示自己的任务，“没在录制”只在全部；空筛选写“没有“失败”的任务”。
  - 开播检测关着：列表顶上的提示（只在有等待开播任务的列表里）、“打开”后提示消失，卡片写“每 30 秒检查一次是否开播 · 上次检查 21:35”。
  - 更多菜单：点“⋮”、长按、右键打开同一个菜单（附录 A 第 14 条），三项的顺序、图标、分隔线；开播自动录打开后已保存的任务回到等待开播、开播检测打开；再关掉时只在等待的任务被删除（同面板、3.x 的取消监控）。
  - 删除任务：对话框的标题和正文、取消不删、确认后删掉并更新数量。
  - 手机横屏两列、小封面、返回；宽屏 1280×800 三列、左右各 24、大封面、筛选不超过 660。
  - 逻辑：筛选、排序、数量、列数（1 / 2 / 3 / 4 列，最多 4 列）。
- `live_ui`：45 个（图标对照表加了 7 个图标）。
- `live_play_popups_test.dart`：只改了两行引用（逻辑文件搬家），20 个全部通过，断言没改。
- 全部测试：`apps/pure_live` 291 个通过（A10.1 前 278 个：删 1 个、加 14 个）；`flutter analyze`（`apps/pure_live`、`packages/live_ui`）无问题；`check_ui_structure.py` 通过。
- 另外在本机用真字体（Noto Sans CJK、Material Icons、Remix）把竖屏、九种状态（深浅两套）、横屏、宽屏、菜单、删除对话框、空状态渲染成图片对照效果图看过一遍（临时测试，没有提交）。

### 和新设计冲突、照实改了的原有断言

| 测试 | 原断言 | 改为 | 原因 |
|---|---|---|---|
| `recorder_page_test` “lists the tasks by status with counts…” | v3 的九个筛选（`recorder-status-7`）、空状态不显示数量、卡片上的“重试”“重新录制”、红色“删除”和“取消监控”对话框 | 删掉，由 `recorder_centre_test` 的筛选、状态卡、更多菜单和删除测试代替 | 筛选改成五个（U1 A）、删除进更多菜单（U2 A）、按钮改成面板的叫法（c2） |

## 提交

分了几次提交：状态卡搬到共用（直播间引用跟着改）、录制中心页面和图标与翻译、测试、文档。中间的提交单独构建不一定通过，只验证了最终状态。
