# A04 尺寸和适配

页面怎么适应不同的窗口和字号：宽度和高度分档、网格列数、横屏手机和分屏、折叠屏、桌面最小窗口、内容最大宽度、文字缩放的上限、触控区域。原则是只看自己拿到的空间（父组件的约束），不看整块屏幕（[specs/UI.md](../../specs/UI.md) 第 5.1 节）。

## 范围

- 包括：
  - 分档和列数的定义：`packages/live_ui/lib/src/theme/grid_columns.dart`；以后的高度分档也放这里（A04.1）。
  - 组件里和尺寸有关的常量和判断：状态页横排（`status_view.dart`）、设置行换行（`settings_row.dart`）、阅读列宽（`settings_tiles.dart`）、设置类标题栏高度（`settings_page_frame.dart`）、面板位置（`adaptive_panel.dart`）、对话框和提示条宽度（`app_dialog.dart`、`app_toast.dart`）、卡片高度跟随字号（`room_card_appearance.dart`、`live_room_card.dart`）。
  - 文字缩放：`AppTextScaler`（`packages/live_ui/lib/src/theme/text_styles.dart`）、应用根部的 `MediaQuery`（`apps/pure_live/lib/app/app.dart`）、画面控制层的 1.3 倍上限。
  - 各页面里的尺寸判断（读整屏高度的 9 处、首页导航、设置两栏、电脑翻页、直播间布局、多画面排法、录制中心宽屏），以及触控区域。
- 不包括（归哪里）：
  - 每个页面在各尺寸下的设计（图、按钮位置）→ 各界面任务（A06～A16）；电视不按宽度分档（规范 5.1 第 1 条）→ A17。
  - 读屏、焦点、对比度 → [A05](../A05-无障碍/README.md)（A05.1 管全应用的触控检查清单，A04.1 管主要页面的自动检查和尺寸）；字号角色本身 → [A01](../A01-设计系统/README.md)。
  - 图片解码尺寸和图片缓存上限 → R03、R01.1（`apps/pure_live/lib/app/bootstrap.dart:36-39` 已按内存设了上限）；切房间预览按展示方式解码 → A03.3。

## 现状：做到哪、怎么工作的

- 用户看得到的：
  - 宽度：紧凑 <600 用底部导航，≥600 用侧边导航（`apps/pure_live/lib/features/home/home_menu.dart:42`、`:45`，首页按约束判断 `home_page.dart:148`）；房间网格列数按网格自己的宽度算（`clamp(⌊(内容 + 间隙) ÷ (最小卡宽 + 间隙)⌋, 2, 8)`，最小卡宽 160 / 180 / 200），393 宽的手机 2 列和 3.x 一样，拖窗口时只在跨过一档时变；分区网格 3～10 列。设置 ≥840 两栏（左栏 360，`features/settings/settings_page.dart:19`、`:22`）；直播间 ≥840 画面加右侧聊天栏（`features/live_play/logic/room_layout.dart:59`）；面板和提示条 ≥600 在右侧和居中；阅读型内容最宽 720。电脑翻页栏照 3.x 在宽 >680 且不是手机系统时出现（`apps/pure_live/lib/shared/rooms/paging.dart:18`）。
  - 高度：没有统一的分档。直播间按约束判断“横屏手机”（高 <480 且宽 > 高且宽 ≥600 → 横屏布局，`room_layout.dart:62`、`:66-70`），多画面、录制中心、播放设置也按约束各写 480；设置类页面、工具箱、版本、关于、标签、屏蔽 9 处按**整屏**高度判断，矮时标题栏 48 高；状态页按窗口判断横排（A02.1 有意的）。
  - 分屏、折叠屏：没有专门处理；竖屏分屏（约 400×420）时整屏高度判断的页面标题栏变矮；没有读 `displayFeatures`，内容可能压在铰链上。
  - 文字：系统字号 × 应用“文字大小”（0.5～2），没有上限，最坏约 4 倍；画面控制层最多 1.3 倍（`features/live_play/player/player_view.dart:746-747`）；设置行字大于 1.5 倍时值换到标题下（`packages/live_ui/lib/src/widgets/settings_row.dart:21`），网格卡片的高度跟着字号算（`room_card_appearance.dart:314` 起，A01.1 P10）。
  - 桌面：最小窗口 360×400（`apps/pure_live/lib/app/desktop/desktop_window.dart:261`），落到紧凑布局。
  - 触控：A02.1 把回到顶部、计数、头像、横幅的 ✕、面板的 ✕ 做到 48；还有 `VisualDensity.compact` 8 处、`shrinkWrap` 1 处可能不到 48；没有自动检查。
- 内部怎么工作：宽度分档是一个枚举 `WindowWidthClass.of(width)`，网格用 `GridColumns.rooms(width: 约束宽, windowWidth: 窗口宽)`——列数看约束，最小卡宽看窗口分档（规范 5.3）。高度、横屏手机、两栏、侧边导航的分界各在自己的文件里写常量（600、840、480、680），没有集中。文字缩放在应用根部 `MediaQuery(textScaler: AppTextScaler(系统, 文字大小))`（`app/app.dart:242-247`）一次决定，下面的组件只读 `MediaQuery.textScalerOf`。
- 完成度：宽度分档、网格列数、内容最宽 720、桌面最小窗口已按规范做完（A09.1、A02.1、A16.1）；高度分档、分屏、折叠屏、字号上限、触控检查都在 [A04.1](A04.1-尺寸和字号适配/README.md)（暂停，阶段 0/3）。和 3.x 比：3.x 用 680 一个分界、640 / 960 / 1280 固定列数断点、读整屏 `Get.width`，这些已经修掉；3.x 应用倍数替换系统字号所以最多 2 倍，4.x 乘系统字号（A11.2 C-5）后少了这个上限。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_ui/lib/src/theme/grid_columns.dart` | `WindowWidthClass`（`:5`，<600 / 600–839 / 840–1199 / 1200–1599 / ≥1600，`of` `:22`）；`GridColumns`（`:38`）：`count`（`:42`，按网格自己的宽度和内边距）、`roomMinWidth`（`:58`，160 / 180 / 200）、`areaMinWidth`（`:66`，110 / 130 / 150）、`rooms`（`:73`，2–8）、`areas`（`:78`，3–10）、`itemWidth`（`:82`） |
| `packages/live_ui/lib/src/theme/text_styles.dart` | `AppTextScaler`（`:175`）：系统缩放 × 应用倍数，保留系统的非线性曲线，没有上限 |
| `packages/live_ui/lib/src/widgets/status_view.dart` | `statusSideBySideHeight` 480（`:39`）；按窗口判断横排（`:236`）；转圈大小按场合 24 / 28 / 32 |
| `packages/live_ui/lib/src/widgets/settings_page_frame.dart` | `settingsPageAppBar` 读整屏高度 <480（`:21`）→ 标题栏 48（`:40`）；`SettingsPageList` 一列最宽 720 |
| `packages/live_ui/lib/src/widgets/settings_tiles.dart` | `readableContentMaxWidth` 720（`:12`）、`ReadableContent`（`:16`） |
| `packages/live_ui/lib/src/widgets/settings_row.dart` | `settingsRowNarrowWidth` 360（`:18`）、`settingsRowLargeText` 1.5（`:21`）：窄或字大时值换到标题下 |
| `packages/live_ui/lib/src/widgets/adaptive_panel.dart` | `sidePanelWidth` 360（`:9`）、`sidePanelBreakpoint` 600（`:14`）；默认按整屏宽度选底部或右侧（`:29`） |
| `packages/live_ui/lib/src/widgets/app_dialog.dart` | 对话框宽：屏宽减 32、最宽 400 / 560、离边 16（`:18-24`）；字大于 1.5 倍时按钮竖排 |
| `packages/live_ui/lib/src/widgets/app_toast.dart` | `appToastMaxWidth` 560（`:11`）、`appToastWidth`（`:119`） |
| `packages/live_ui/lib/src/widgets/anchored_menu.dart` | 小菜单离屏幕边和安全区 8（`:18`），最大高度是所选一侧的空间（`:178`）；没有铰链避让 |
| `packages/live_ui/lib/src/widgets/room_card_appearance.dart`、`live_room_card.dart` | `RoomCardLayoutMetrics`（`:314`，网格卡片高度按字号和文字缩放算）；`LiveRoomCardMetrics`（`live_room_card.dart:177`）；封面解码宽 240–720（`live_room_card.dart:246`） |
| `apps/pure_live/lib/app/app.dart` | `:177` 读 `textScaleFactor`；`:242-247` 根部 `MediaQuery(textScaler: AppTextScaler(...))` |
| `apps/pure_live/lib/features/home/home_menu.dart`、`home_page.dart` | `homeTabletBreakpoint` 600（`home_menu.dart:42`）、`isHomeRailWidth`（`:45`）；首页按约束切换（`home_page.dart:148`） |
| `apps/pure_live/lib/features/settings/settings_page.dart` | `settingsTwoPaneBreakpoint` 840（`:19`）、`settingsOverviewWidth` 360（`:22`）；两栏时左栏标题区读整屏高度（`:172`、`:183`） |
| `apps/pure_live/lib/features/settings/settings_tiles.dart` | `settingsAppBar` 读整屏高度（`:652`、`:660`） |
| `apps/pure_live/lib/features/toolbox/toolbox_page.dart:153`、`shield/shield_page.dart:30`、`version/version_page.dart:156`、`version/release_history_view.dart:75`、`about/about_page.dart:75`、`tags/tags_page.dart:182` | 读整屏高度 <480 时标题栏 48（A04.1 改成按约束） |
| `apps/pure_live/lib/features/live_play/logic/room_layout.dart` | `roomWideMinWidth` 840（`:59`）、`roomCompactMaxHeight` 480（`:62`）、`roomPageLayout`（`:66-70`，按 `LayoutBuilder` 传入的宽高，`live_play_page.dart:1087-1092`） |
| `apps/pure_live/lib/features/live_play/player/player_view.dart` | `:746-747` 控制层 `withClampedTextScaling(maxScaleFactor: 1.3)` |
| `apps/pure_live/lib/features/multiview/multiview_page.dart` | `_arrangementOf`（`:437-442`，按约束：矮且宽 → 横屏，≥840 → 宽屏，`:452`） |
| `apps/pure_live/lib/features/recorder/recorder_page.dart:315`、`settings/playback_tiles.dart:627` | 按约束的宽屏判断（≥840 且高 ≥480；矮且宽 ≥560 放侧边） |
| `apps/pure_live/lib/shared/rooms/paging.dart` | `usesDesktopPages`（`:18`，宽 >680 且不是手机系统）、`pageSizesOf`（`:22-23`，宽 >960 时电脑每页默认 20 条、否则 12，照 3.x `PageSettingsController`） |
| `apps/pure_live/lib/features/popular/popular_page.dart:157`、`search/search_scope.dart:82`、`live_play/layout/room_panel.dart:89` | 面板放右侧还是底部，读整屏宽度 ≥600 |
| `apps/pure_live/lib/features/search/web_search_view.dart:284-285` | 网页搜索的识别条按宽度放（<600 底部、≥1200 宽版） |
| `apps/pure_live/lib/shared/rooms/room_prompt.dart:62` | 宽 <350 或字大时按钮竖排 |
| `apps/pure_live/lib/app/desktop/desktop_window.dart` | `DesktopShell.minimumSize` 360×400（`:261`） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_ui/test/live_room_card_test.dart` 的 GridColumns 组 | 列数公式、393 宽 2 列、拖窗口只在跨档时变 |
| `packages/live_ui/test/room_card_test.dart` | 网格卡片高度跟随字号（A01.1 P10） |
| `packages/live_ui/test/components_test.dart` | 状态页横屏 852×393 左图右文、区块不横排；转圈大小（393 宽 28、1280 宽 32） |
| `packages/live_ui/test/popups_test.dart`、`small_menu_test.dart` | 对话框、面板、提示条在竖屏、横屏、宽屏的位置和宽度；小菜单在 852×393、393×852、1280×800 |
| `packages/live_ui/test/widgets_test.dart` | `ReadableContent` 最宽 720 |
| `apps/pure_live/test/desktop_window_test.dart:459`、`:619` | 360×400 最小窗口、落到手机布局 |
| `apps/pure_live/test/features/live_play/live_play_layouts_test.dart` | 直播间各布局、字号 |
| `apps/pure_live/test/features/home/home_test.dart` | 首页导航（底部 / 侧边） |

## 3.x 基线

- 宽度：一个分界 680、读整屏：`lib/common/base/base_page_view.dart:57`（电脑翻页）、`lib/common/widgets/app_status_view.dart:389`（转圈大小 `Get.width > 680`）；网格固定断点 640 / 960 / 1280（`lib/modules/area_rooms/area_rooms_page.dart:52`：2～5 列；`lib/modules/areas/areas_grid_view.dart:263`：3～9 列；`lib/modules/favorite/room_grid_view.dart:38-40`），设置内容最宽 960（`lib/common/widgets/widget_extensions.dart:8`）。
- 高度：没有分档，直播间各自判断（`lib/modules/live_play/widgets/content_first_panel_layout.dart:25` 宽 <720 或高 <520；`video_controller_panel.dart:2131` 横屏且高 <620；`iptv_schedule_dialog.dart:49` 高 ≤600 或字大于 1.5 倍）。
- 文字：`lib/main.dart:184` `TextScaler.linear(textScaleFactor)` 替换系统字号，范围 0.5～2（`lib/common/services/settings/font_settings_controller.dart:16-18`）；设置行 `stackTrailingOnNarrow` 宽 <360 或字大于 1.5 倍换行（`widget_extensions.dart:235-257`）。
- 触控：计数两块 48×48；回到顶部 40（`lib/common/base/base_page_view_extension.dart:64-99`）。
- 要保留：手机上 2 列卡片、平板和电脑的侧边导航、电脑翻页栏（宽 >680）、设置行窄屏换行；规范第 5.1 节第 5 条说 3.x 读整屏、拖窗口时有的页面不跟随是要修的问题。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 没有高度分档的定义，9 处读整屏高度，其他各写 480 | 见代码地图 | 竖屏分屏、小窗口时按整屏判断；以后的判断没有统一定义 | A04.1 阶段 1 |
| 没有处理折叠屏铰链 | 全应用没有 `displayFeatures`；小菜单没有避让（A02.3 偏差） | 半开时内容和弹窗压在铰链上 | A04.1 阶段 1 |
| 文字缩放没有上限 | `text_styles.dart:175`、`app/app.dart:242-247` | 系统最大 × 应用 200% 约 4 倍，页面截断 | A04.1 阶段 2（上限 2 倍，可借鉴 `git show v4-archive:packages/live_ui/lib/src/text_scale.dart`） |
| 没有触控区域的自动检查；`VisualDensity.compact` 8 处、`shrinkWrap` 1 处可能不到 48 | `apps/pure_live/test` 里 0 处 `meetsGuideline`；清单见 A04.1 README | 小按钮难点 | A04.1 阶段 3、A05.1 |
| 直播间详情把手 20 高 | `features/live_play/layout/room_details.dart:119` | 难拖 | A03.3 阶段 4 |
| 面板位置、网格的窗口宽读整屏宽度 | `popular_page.dart:157`、`search_scope.dart:82`、`room_panel.dart:89`、`adaptive_panel.dart:29` | 分屏、两栏时可能放错一侧 | A04.1 可以顺手改（不强求）；网格的最小卡宽按窗口是规范 5.3 有意的 |
| 状态页按窗口判断横排 | `status_view.dart:236` | 分屏时按整窗口 | 有意的（`SliverFillRemaining` 里不能用 `LayoutBuilder`），A04.1 只换常量 |
| 分界常量分散（600、680、840、480、960） | 见代码地图 | 改分界要逐处找 | A04.1 阶段 1 至少把高度的集中；宽度的可以一起整理（写进记录） |

## 相关决定和规范

- D-018（“文字大小”`textScaleFactor` 的键名和 0.5～2 的范围不变）；A11.2 C-5（文字大小乘系统字号，见 [A11.2](../A11-设置界面/A11.2-外观/README.md)）。
- [specs/UI.md](../../specs/UI.md) 第 5.1 节（宽度、高度分档，高度紧凑优先，折叠屏姿态，只读约束）、第 5.2 节（出图尺寸：393×852、852×393、740×360、1280×800、1920×1080）、第 5.3 节（网格列数公式、内容最宽 720、大屏方向锁定、桌面最小 360×400、系统字体 1.3 和 1.5 倍不截断）、第 5.4 节（48×48、间距 8）、第 8.2 节（画面上的文字最多 1.3 倍）。
- 调研报告 [V03.2](../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md) 第 3 节（设备落到哪个分档、D1～D4）。

## 测试和验证

- 自动测试：上表；跑法 `cd packages/live_ui && flutter test`，`cd apps/pure_live && flutter test test/desktop_window_test.dart test/features/live_play/live_play_layouts_test.dart test/features/home/home_test.dart`。缺的：报告 D1 的 8 个尺寸（360×400、400×420、400×869、821×400、673×841、841×673、1280×800、1500×1000）× 1.3 / 1.5 / 2.0 倍字号的布局测试；分屏 400×420 不当横屏手机的测试；`meetsGuideline`。都在 A04.1 任务书里。
- 真机：K90 上 `adb shell wm size 720x1600`、`adb shell wm density 320` / `540` 模拟其他机型（测完 `wm size reset`、`wm density reset`）；系统字体最大 + 应用 200%；分屏。[S02 的真机清单](../../S-质量和验证/S02-真机验证/CHECKLIST.md)里没有尺寸和字号的条目，A04.1 完成后写进它的 `verify.md`。

## 路线

1. [A04.1](A04.1-尺寸和字号适配/README.md)（第二档，暂停）：先在维护者本机看旧工作区 `worktree-agent-a39fe9339ffb138a9` 还在不在、改动能不能用；然后高度分档（含分屏、折叠屏）→ 文字上限 2 倍 → 触控区域检查。和 A01.2 第 3 阶段都改设置页，不要并行。
2. A04.1 之后，A05.1 用同样的测试辅助函数把触控检查扩到全应用。
3. 以后：电视和苹果平台的尺寸归 A17、X；新想法写进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：`packages/live_ui/lib/src/theme/grid_columns.dart`、各页面
- 进度：`████████████░░░░░░░░` 60%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A04.1 | 尺寸和字号适配：高度分档、分屏、折叠屏、字号上限、触控区域 | 性能 | 开发中 | — | — | [设计或说明](A04.1-尺寸和字号适配/README.md)、[任务书](A04.1-尺寸和字号适配/brief.md)、[记录](A04.1-尺寸和字号适配/record.md) |

## 还没完成的

- **A04.1 尺寸和字号适配：高度分档、分屏、折叠屏、字号上限、触控区域**（开发中，第二档，规模 中）
  - 阶段：✓ 高度分档 → ✓ 字号上限 → 触控区域
  - 接着做：第 3 阶段触控区域
  - 分支：本机工作区 worktree-agent-a0aa96c1b7aaaa422

<!-- docs:生成结束 -->
