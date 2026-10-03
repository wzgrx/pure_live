# A04.1 尺寸和字号适配：高度分档、分屏、折叠屏、字号上限、触控区域：任务书

> 原任务单（旧编号 P06，2026-10-02）的全部要求都保留在下面，按任务书模板 v2 重排；“现状”一节是 2026-10-03 读代码写的。登记表：暂停，阶段 0/3（高度分档 → 字号上限 → 触控区域），`next`“先看旧工作区里的改动能否直接用，再补测试”。

## 背景

- 来源：调研报告 [V03.2](../../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md) 第 3 节的 D1、D3、D4（第 0 节第 9 条“8 个文件用整屏尺寸判断高度紧凑，代码里没有高度分档的定义；分屏、小窗、折叠屏铰链都没处理”，第 11 条“应用字号乘系统字号，最坏能叠到大约 4 倍”）。另有两处留给本任务的：A02.1“状态页按窗口判断：A04.1 做高度分档时复查”、A02.3“折叠屏铰链没有避让”。
- 现象：
  - 竖屏分屏（K90 上约 400×420 dp）时，设置、工具箱、版本、关于、标签、屏蔽各页按**整个屏幕**的高度判断“矮”，标题栏被压成 48 高；以后加的高度判断没有统一定义，各写 480。
  - 系统设置里把字体调到最大（约 2 倍），再把应用的“文字大小”调到 200%，文字放大到约 4 倍，很多页面截断、溢出；3.x 最多 2 倍。
  - 折叠屏半开时内容压在铰链上。
  - 几处按钮用了 `VisualDensity.compact`，点击区域可能只有 40 dp；没有任何触控区域的测试。
- 为什么现在做：第二档；规范 [specs/UI.md](../../../specs/UI.md) 第 5.1 节（高度分档、只读约束）、第 5.3 节（字体 1.3、1.5 倍不截断）、第 5.4 节（48×48）现在只在文档里。
- 规模：中；分组：组件；依赖：A02.1（待真机，已合并）；能否和别的任务同时做：组件组最后一个（会改很多页面）；**不要和 A01.2 第 3 阶段并行**（都改 `settings_page_frame.dart`、`settings_tiles.dart` 和几个设置页）。
- 出设计：不用（照调研报告和本任务书；改变外观或手感的地方在记录里写清前后对比）。
- 已经做过的：`WindowWidthClass`、`GridColumns`（`packages/live_ui/lib/src/theme/grid_columns.dart`，A09.1 时做的宽度分档和网格列数）；直播间的 `roomCompactMaxHeight`（`features/live_play/logic/room_layout.dart:62`）；状态页横排（A02.1）；控制层 1.3 倍上限（`features/live_play/player/player_view.dart:746-747`）。暂停前登记的工作区 `worktree-agent-a39fe9339ffb138a9`（“做了大半，未提交”）在这个仓库里查不到。

## 目标和验收

1. `live_ui` 有高度分档（紧凑 <480、中等 480–899、展开 ≥900）和“横屏手机”（高度紧凑且宽 > 高）的定义，从 `live_ui.dart` 导出，有单元测试。
2. `apps/pure_live/lib` 和 `packages/live_ui/lib` 里不再用 `MediaQuery.sizeOf(context).height < 480` 判断布局（`grep -rn "sizeOf(context).height <"` 为 0）；改成按约束（`LayoutBuilder` 或调用处传入的尺寸）判断。状态页按窗口判断是 A02.1 有意保留的，只换成常量并留注释。
3. 竖屏分屏（400×420，紧凑 / 紧凑）不当成横屏手机：直播间、多画面不进横屏布局，设置类页面按自己的高度决定标题栏。
4. 折叠屏：读 `MediaQuery.displayFeatures`，铰链不压住内容（至少首页网格、设置两栏、对话框和面板）。
5. 总体文字缩放（系统字号 × 应用“文字大小”）每个字号最多 2 倍；画面控制层的 1.3 倍保留；“文字大小”设置的键名和 0.5～2 的范围不变（D-018）。
6. 报告第 3.3 节 D1 列出的尺寸 × 字号组合都不溢出：360×400、400×420、400×869、821×400、673×841、841×673、1280×800、1500×1000，每个尺寸配 1.3 / 1.5 / 2.0 倍字号。
7. 主要页面触控区域达标：`expect(tester, meetsGuideline(androidTapTargetGuideline))` 通过；不达标的扩到 48 dp（视觉不变）。
8. 门禁通过；`live_ui`、`apps/pure_live` 全部测试通过。

## 现状（读代码得出，写文件:行）

- 宽度分档：`packages/live_ui/lib/src/theme/grid_columns.dart:5`（`WindowWidthClass`，<600 / 600–839 / 840–1199 / 1200–1599 / ≥1600）、`:38`（`GridColumns`：`count`、`roomMinWidth` 160/180/200、`areaMinWidth` 110/130/150、`rooms` 2–8、`areas` 3–10）；没有高度分档。
- 读整屏高度的 9 处（都是矮时标题栏 48、否则 56）：`packages/live_ui/lib/src/widgets/settings_page_frame.dart:21`（`:40`）；`apps/pure_live/lib/features/settings/settings_tiles.dart:652`（`:660`）；`features/settings/settings_page.dart:172`（两栏左边标题区 `:183`）；`features/toolbox/toolbox_page.dart:153`；`features/shield/shield_page.dart:30`；`features/version/version_page.dart:156`；`features/version/release_history_view.dart:75`；`features/about/about_page.dart:75`；`features/tags/tags_page.dart:182`。
- 已按约束、但各写 480 的：`features/multiview/multiview_page.dart:437-442`（`_arrangementOf(constraints.biggest)`，`:452`）；`features/settings/playback_tiles.dart:627`（`constraints.maxHeight < 480 && maxWidth >= 560` 放侧边）；`features/recorder/recorder_page.dart:315`（`maxWidth >= 840 && maxHeight >= 480`）；`features/live_play/logic/room_layout.dart:62`（`roomCompactMaxHeight`）、`:67`（`height < 480 && width > height && width >= 600` → 横屏布局），由 `live_play_page.dart:1087-1092` 按 `LayoutBuilder` 传入；`packages/live_ui/lib/src/widgets/status_view.dart:39`（`statusSideBySideHeight`）、`:236`（按窗口）。
- 读整屏宽度的（本任务可以顺手改成约束，不强求）：`features/popular/popular_page.dart:157`、`features/search/search_scope.dart:82`（`side: width >= 600`）、`features/live_play/layout/room_panel.dart:89`、`packages/live_ui/lib/src/widgets/adaptive_panel.dart:29`（面板在右侧还是底部）；`shared/rooms/room_grid.dart:43`、`:457`、`:460`、`:517`，`features/areas/*`、`favorite/favorite_page.dart:406`（网格的 `windowWidth`，规范 5.3 的最小卡宽按窗口分档，属于有意的）。应用里（除电视）`MediaQuery.sizeOf(context)` 共 26 处、`LayoutBuilder(` 72 处。
- 折叠屏：`apps/pure_live/lib`、`packages/live_ui/lib` 里没有 `displayFeatures`、`DisplayFeatureSubScreen`；小菜单 `packages/live_ui/lib/src/widgets/anchored_menu.dart` 自己排位置（`_AnchoredMenuLayout`，`:152`），没有铰链避让。
- 文字缩放：`apps/pure_live/lib/app/app.dart:177`（读 `Settings.textScaleFactor`）、`:242-247`（`MediaQuery(... textScaler: AppTextScaler(MediaQuery.textScalerOf(context), textScale))`）；`AppTextScaler`（`packages/live_ui/lib/src/theme/text_styles.dart:175`）`scale(s) = system.scale(s) × factor`，没有上限；设置项 `packages/live_store/lib/src/settings/settings.dart:200`（`textScaleFactor`，默认 1、0.5～2），设置界面 `features/settings/appearance_pages.dart:356-364`（滑块 0.5～2，步长 0.05）；控制层 `features/live_play/player/player_view.dart:746-747`（`withClampedTextScaling(maxScaleFactor: 1.3)`）。依赖字号的现成判断：`settings_row.dart:21`（`settingsRowLargeText` 1.5 倍以上值换到标题下）、`shared/rooms/room_prompt.dart:62`。
- 触控区域：测试里没有 `meetsGuideline`（`apps/pure_live/test`、`packages/live_ui/test` 0 处）。`VisualDensity.compact`：`shared/links/supported_platforms.dart:63`、`features/search/search_widgets.dart:194`、`:633`、`features/search/search_view.dart:613`、`:633`、`features/live_play/switch_room/room_switch_panel.dart:516`、`features/settings/font_manager_page.dart:392`、`features/backup/log_page.dart:216`；`MaterialTapTargetSize.shrinkWrap`：`room_switch_panel.dart:515`。直播间详情把手 `features/live_play/layout/room_details.dart:119`（20 高）归 A03.3。
- 现成的测试写法：`apps/pure_live/test/desktop_window_test.dart:459`（360×400 尺寸下打开对话框）、`:619`（最小窗口 360×400）；`apps/pure_live/test/features/live_play/live_play_layouts_test.dart`（各布局、字号）。

## 3.x 基线

- 宽度：`lib/common/base/base_page_view.dart:57`（宽 >680 且不是手机系统才用电脑翻页）；网格 640 / 960 / 1280 固定断点（`lib/modules/area_rooms/area_rooms_page.dart:52`、`lib/modules/areas/areas_grid_view.dart:263`、`lib/modules/favorite/room_grid_view.dart:38-40`），读整屏的 `Get.width`（规范 5.1 说这是要修的问题）。
- 高度：没有统一分档；直播间各自判断（`lib/modules/live_play/widgets/content_first_panel_layout.dart:25` 宽 <720 或高 <520；`video_controller_panel.dart:2131` 横屏且高 <620；`iptv_schedule_dialog.dart:49` 高 ≤600 或字大于 1.5 倍）。
- 文字缩放：`lib/main.dart:140`（读 `textScaleFactor`）、`:184`（`TextScaler.linear(currentFactor)` 替换系统字号）；范围 `lib/common/services/settings/font_settings_controller.dart:16-18`（默认 1、0.5～2），所以 3.x 总倍数最多 2，但系统字号调大在应用里没用。4.x 改成“系统 × 应用”是 A11.2 的确认改动（U.6b C-5），要保留，只加上限。
- 触控：`lib/common/widgets/count_button.dart` 两块 48×48；回到顶部 40（`lib/common/base/base_page_view_extension.dart:64-99`）。
- 要保留：网格列数和宽度分档（已照规范）；“文字大小”的键名、范围和“乘系统字号”的做法；直播间横屏、竖屏的判断结果（`room_layout.dart` 的数值）；各页面默认尺寸下的样子不变。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 8 节合并审查、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 5 节（5.1 判定、5.3 动态适配规则、5.4 输入方式）、第 8.2 节。
3. 本文件夹的 `README.md`；调研报告 `docs/V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md` 第 3 节；[A04 子分类页](../README.md)的代码地图和已知问题。
4. `packages/live_ui/lib/src/theme/grid_columns.dart`、`text_styles.dart`、`packages/live_ui/lib/src/widgets/settings_page_frame.dart`、`status_view.dart`；`apps/pure_live/lib/app/app.dart`；`apps/pure_live/lib/features/live_play/logic/room_layout.dart`。
5. 可以借鉴的旧实现（之前从零写的版本，只借思路）：`git show v4-archive:packages/live_ui/lib/src/window_class.dart`（`HeightClass`、`WindowLayout.isShortLandscape`）、`git show v4-archive:packages/live_ui/lib/src/text_scale.dart`（`CombinedTextScaler`：`min(system.scale(s) × factor, 2s)`）；对应提交 `c48cceb5d`、`a43618912`（2026-09-28）。

## 范围

- 可以改：`packages/live_ui/lib/`（`theme/grid_columns.dart` 或新文件、`theme/text_styles.dart`、`widgets/settings_page_frame.dart`、`widgets/status_view.dart` 的常量、`widgets/adaptive_panel.dart`、`widgets/app_dialog.dart`、`widgets/anchored_menu.dart` 的铰链避让）、`packages/live_ui/test/`；`apps/pure_live/lib/app/app.dart`；“现状”列出的 9 个页面文件和 `multiview_page.dart`、`playback_tiles.dart`、`recorder_page.dart`（只换判断方式和常量）；主要页面（只为触控区域扩点击区）；`apps/pure_live/test/`；本文件夹的 `record.md`。
- 不能改：`apps/pure_live/lib/features/live_play/` 除 `logic/room_layout.dart` 的常量引用以外的文件（直播间组同时只交给一个执行者；详情把手归 A03.3）；`apps/pure_live/lib/tv/`（电视不按宽度分档，规范 5.1 第 1 条）；宽度分档和网格列数的数值；“文字大小”设置的键名、默认值、范围（D-018）；页面在默认尺寸和默认字号下的样子；版本号、`assets/version.json`、`assets/releases.json`。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 高度分档 | c1（D1）：`live_ui` 加 `WindowHeightClass` 和横屏手机判断（常量 480、900）；9 处整屏判断改成按约束（标题栏可以用 `LayoutBuilder` 包住 `Scaffold`，或由页面把 `constraints` 传给 `settingsPageAppBar`）；`roomCompactMaxHeight`、`statusSideBySideHeight`、`multiview_page.dart:439`、`playback_tiles.dart:627`、`recorder_page.dart:315` 的 480 引用常量；分屏 400×420 的测试；折叠屏 `displayFeatures`：首页网格、设置两栏、`AppDialog`、`showAdaptivePanel`、小菜单避开铰链（`DisplayFeatureSubScreen` 或照它的算法） | `grid_columns.dart`（或新 `window_class.dart`）、`live_ui.dart`、上面列的页面、`app_dialog.dart`、`adaptive_panel.dart`、`anchored_menu.dart` | 验收 1～4；`grep` 为 0；新测试过 |
| 2 字号上限 | c2（D3）：`AppTextScaler.scale` 改成 `min(system.scale(s) × factor, 2s)`，`textScaleFactor` 同样封顶；控制层 1.3 不动 | `text_styles.dart`、`app/app.dart`（如需） | 验收 5；单元测试过；8 个尺寸 × 3 个倍数的布局测试不溢出（验收 6） |
| 3 触控区域 | c3（D4）：主要页面加 `meetsGuideline(androidTapTargetGuideline)`；不达标的扩点击区（`MaterialTapTargetSize.padded`、外包 48 的 `SizedBox` 或 `ConstrainedBox`），视觉不变；`VisualDensity.compact` 9 处逐个确认 | 主要页面、`apps/pure_live/test/` | 验收 7 |

每个阶段都要能单独合并（门禁通过、不留半截功能）。

## 测试

- 阶段 1：`packages/live_ui/test/` 加高度分档的单元测试（479 / 480 / 899 / 900 的边界；821×400 是横屏手机、400×420 不是）；`apps/pure_live/test/` 加：400×420 下直播间不是 `RoomPageLayout.landscape`、多画面不是横屏排法；设置页在 `LayoutBuilder` 给的高度 <480 时标题栏 48；折叠屏用 `MediaQueryData(displayFeatures: [DisplayFeature(bounds: …, type: DisplayFeatureType.hinge, state: DisplayFeatureState.postureHalfOpened)])` 测首页、设置两栏、对话框不跨铰链。
- 阶段 2：`AppTextScaler(TextScaler.linear(2), 2).scale(14) == 28`；`AppTextScaler(TextScaler.linear(1.3), 1).scale(14)` 等于系统值（不受上限影响）；非线性系统缩放（自写一个 `TextScaler` 子类）在上限内保持曲线。
- 布局测试：上面 8 个尺寸 × 1.3 / 1.5 / 2.0 倍，至少首页、热门、关注、设置总览和外观、录制中心、直播间竖屏、多画面；`tester.view.physicalSize` + `devicePixelRatio`，断言 `tester.takeException()` 为空（没有 `RenderFlex overflowed`）；测完 `addTearDown(tester.view.reset)`。
- 阶段 3：每个主要页面一条 `expect(tester, meetsGuideline(androidTapTargetGuideline))`（竖屏和宽屏各一次）。
- 定时器至少 1 秒；不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. `adb shell wm size 720x1600`、`adb shell wm density 320`，打开首页、热门、设置、直播间；再 `wm density 540` 看一遍；测完 `adb shell wm size reset`、`adb shell wm density reset` | 各页面不溢出、不截断，网格列数合理 |
| 2. 系统设置把字体调到最大，应用设置 → 外观 → 文字大小 200%；看首页、设置、录制中心、直播间（竖屏和横屏全屏）；测完把两处都设回去（或 `adb shell settings put system font_scale 1.0`） | 文字最多是默认的 2 倍，所有页面不截断；画面上的控制层文字不随着变到 2 倍（最多 1.3 倍） |
| 3. 分屏打开应用（上下分屏，本应用一半） | 竖屏布局正常，直播间不变成横屏全屏样子；设置页标题栏正常 |
| 4. 横屏拿手机看设置、工具箱、版本、关于 | 标题栏是矮的（48），和改之前一样 |
| 5. 首页、设置里点各个小按钮（搜索页的平台筛选、日志页的按钮、切换直播间的列表开关） | 好点，不用对准 |

## 风险和注意

- `settings_page_frame.dart`、`settings_tiles.dart` 是 A01.2（暂停中的第 3 阶段）也要改的文件；同一组同时只开一个开发。
- `roomCompactMaxHeight` 在 `features/live_play/`：只改成引用常量，数值和判断不能变（`room_swipe_test.dart`、`live_play_layouts_test.dart` 有用例）；直播间组同时有别的任务在做时先协调。
- 文字上限会让“系统字体最大 + 应用 200%”的用户看到的字比现在小，这是有意的（3.x 最多也是 2 倍），写进记录。
- `textScaleFactor` getter 已弃用但接口要求实现；封顶时用和 `scale` 一致的线性估计。
- `displayFeatures` 在模拟器和 K90 上都是空的，只能靠测试；有折叠屏时再真机看。
- 状态页的窗口判断不要改成 `LayoutBuilder`（`SliverFillRemaining` 里会报错，A02.1 全量测试曾因此失败 30 多条）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 接手前：维护者本机 `git worktree list` 看 `worktree-agent-a39fe9339ffb138a9` 还在不在、有没有改动；有就先对照本任务书看能不能用，没有就从最新 master 开始。
- 分支 `ai/A04.1` 或本机工作区；提交信息以 `[A04.1]` 开头（英文）；不推 master。
- 提交前：`packages/live_ui`、`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`；根目录 `python3 tools/gate/check_ui_structure.py`、`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（哪个阶段、哪些页面改完了）、更新登记表的 `done`、`next`、`branch`；交给别的 AI 时 `git push origin <分支>:wip/A04.1`。

## 报告（中文，简洁）

每条验收做到没有；高度分档的名字和常量；改成按约束的页面数；折叠屏怎么避让；文字上限前后的最大倍数；布局测试的尺寸 × 倍数组合数和失败过的页面；触控区域不达标、改了的控件；测试数量；改了哪些文件；要在真机上看的；需要维护者决定的；可能冲突的文件（尤其和 A01.2、A03.3）。
