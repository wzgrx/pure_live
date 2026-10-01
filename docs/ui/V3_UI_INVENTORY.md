# v3 界面清单与审查

- 来源：标签 `v3.2.11`（`~/ref/v3ref`，界面代码和归档 `legacy/` 一致）。只读代码整理，不截图。
- 每个界面写四件事：**v3 的样子**（结构、控件、图标、操作，按代码）、**v3 的问题**（根因和位置）、**v4 现在的偏差**（M13 写的页面和 v3 不一致的地方）、**v3 文件 → v4 文件**。
- 图标名写 v3 的原名：`Remix.*` 是 Remix 图标库，`CustomIcons.*` 是 v3 自带字体（`assets/icons/CustomIcons.ttf`），`danmu_*.svg` 是 `assets/images/video/` 里的弹幕图标，`Icons.*` 是 Material 图标。

## 0. 全局外观

**主题**（`lib/common/style/theme.dart`、`app_text_styles.dart`、`common/services/settings/theme_settings_controller.dart`、`font_settings_controller.dart`）

- Material 3，用户主题色作种子（默认 `Colors.blue`），可选动态取色；深色模式错误色改为 `#FF6347`。
- 字号来自设置：正文小 12、正文 13、正文大 14、标题中 15、标题大 20（标题大用于顶栏，半粗）；Windows 默认字体“微软雅黑”。
- 去掉水波纹（`NoSplash`）；顶栏无阴影、标题居中；标签栏无分隔线、指示条跟文字宽、选中半粗主题色、未选常规灰；卡片圆角 16、无阴影；按钮圆角 12（实心）/8（文字）；列表行圆角 12；输入框填充、圆角 12；底部面板圆角 24 带拖动条；对话框圆角 24。
- 页面切换：Android、Windows 用 `FadeForwardsPageTransitionsBuilder`。

v3 的问题：
1. `AppTextStyles` 是全局 getter（`Get.theme`），页面里直接拼 `t12/t13/t14…`，和主题字号两套并存，同一角色在不同页面字号不一。
2. 卡片、弹幕行等处硬编码 `Colors.white`/`Colors.grey[900]`，没走 `colorScheme` 的表面色，换主题色或深色时层次不一致（`room_card.dart:1071`、`danmaku_list_view.dart:470`）。

v4 现在：`packages/live_ui` 的主题基本照 v3（同样的字号和形状）。**图标没照**：v3 的界面代码用了 193 种 Remix 图标、182 种 Material 图标和几个自带的 `CustomIcons`（搜索、小窗、弹幕开、热门），每个位置用哪个是固定的；v4 页面大多换成了别的 Material 图标。

## 1. 首页外壳

**v3 的样子**（`lib/modules/home/home_page.dart`、`mobile_view.dart`、`tablet_view.dart`）

- 宽度 ≤680：手机布局，底部 `NavigationBar`，最多四项，顺序和显示由设置“首页菜单”决定（只剩一项时不显示导航栏）：
  - 关注 `Remix.heart_3_line/fill`、热门 `Remix.fire_line/fill`、分区 `Remix.apps_2_line/fill`、录制中心 `Remix.download_2_line/fill`。
  - 关注页已选中时再点一次“关注”= 刷新关注。
- 宽度 >680：左侧 `NavigationRail`（标签全显示，可滚动），顶部依次是菜单按钮、多画面 `Remix.layout_grid_line`（开了多画面才有）、链接解析 `Remix.link`（提示文字是“链接解析”）、搜索 `CustomIcons.search`、录制中心 `Remix.download_2_line`（录制不作为导航项，改为顶部按钮）；中间竖分隔线；右侧是页面。
- 返回键：不退出，`moveToDesktop` 回到桌面。
- 回到前台超过 15 秒：刷新当前的热门/分区。
- 启动 2 秒后检查更新，有新版弹“新版本”对话框。

**各页顶栏的公共部分**

- 左：菜单按钮 `Icons.menu_rounded`（`common/widgets/menu_button.dart`），弹出菜单：设置 `Remix.settings_5_line`、关于 `Remix.information_line`、历史记录 `Remix.history_line`、备份与恢复 `Remix.cloud_line`、“新建独立播放窗口”（仅 Windows，并且要打开对应设置才出现，`Icons.add_to_photos_outlined`）。
- 右：`CommonAppBarActions`，图标 `Remix.menu_search_line`，弹出菜单：搜索直播 `Remix.search_line`、链接访问 `Remix.link`、多画面 `Remix.layout_grid_line`（开了才有）。
- 宽屏（>680）时这两个按钮不显示，功能在侧边导航栏里。

v3 的问题：
1. “历史记录”藏在左上菜单里，和设置、关于、备份混在一起，常用功能入口太深。
2. 手机上“多画面”“链接访问”在右上搜索菜单里，宽屏在侧边栏，两处入口名字和图标不同（`Remix.link` 在宽屏叫工具箱、在手机叫链接访问）。
3. 分区导航图标 `Remix.apps_2_line` 和直播间右上菜单是同一个图标，含义不同却长得一样。

v4 现在（2026-10-01 核对）：导航图标已和 v3 一样；其余差异见 [compare/U.3a](compare/U.3a/README.md)。

| v3 | v4 |
|---|---|
| `lib/modules/home/*` | `apps/pure_live/lib/features/home/*` |
| `lib/common/widgets/menu_button.dart`、`common_appbar_actions.dart` | `apps/pure_live/lib/features/home/`、`lib/shared/` 里的对应部件 |

## 2. 热门

**v3 的样子**（`lib/modules/popular/popular_page.dart`、`popular_grid_view.dart`）

- 顶栏：左菜单按钮、右搜索菜单（手机）；**标题位置放平台标签栏**（`ScrollableTabBar`，可横向滚动，只有平台名文字，居中）。
- 正文：每个平台一页（左右滑切换），房间网格：宽 >1280 五列、>960 四列、>640 三列、其余两列；外边距 6，行列间距来自设置；卡片用 `RoomCard(dense: true)`。
- 分页：设置里可开“回到顶部”按钮和每页数量选择；空状态 `AppStatusView`（`RemixIcons.fire_fill`、“暂无直播”、刷新按钮）。

v3 的问题：
1. 平台很多时（三十多个），顶栏里的标签栏只能横向滚动找，没有平台图标，也没有直达某个平台的方式。
2. 标签栏占用标题位置，页面没有标题（只看标签不知道这是“热门”）。

v4 现在：标题位置写成“热门”二字，平台标签另起一行，右端多了一个“全部平台”按钮——结构和 v3 不同。

## 3. 关注

**v3 的样子**（`lib/modules/favorite/favorite_page.dart`、`room_grid_view.dart`）

- 顶栏：左菜单、右搜索菜单（手机）；**标题位置是三个固定等宽标签：已开播、录播、未开播**。
- 下面一行：平台标签栏（全部 + 有关注的平台，可滚动，只有文字）。
- 再下一行：分组标签（`ChoiceChip` 横向列表，“全部”+ 用户建的分组，没有分组时不显示）。
- 正文：每个平台一页，房间网格（同热门的列数规则），下拉刷新、分页；空状态分“没有已开播”和其他。
- 刷新：底部导航再点一次“关注”或下拉。

v3 的问题：
1. 内容之上有三行导航（状态、平台、分组），手机上内容区被压缩。
2. 标签上不显示数量，看不出各状态、各平台有几个房间。
3. 没有可见的刷新按钮（只能下拉或再点导航），桌面上不直观。

v4 现在：结构照 v3，另加了数量徽标和平台行右端的刷新按钮；真机上“已开播 1”的文字被截断（M13.16 已修）。

## 4. 房间卡片（通用）

**v3 的样子**（`lib/common/widgets/room_card.dart`，1411 行）

- `Card`：浅色白、深色 `grey[900]`，圆角来自设置（卡片外观），无阴影；点按进房、长按/右键弹出菜单。
- 封面 16:9，圆角同卡片；封面上：左上平台标（平台 id 大写文字，黑色半透明底，可在设置里关）、右上“回放”标、右下人数（`CoverMetricBadge`，按设置显示在线/热度/累计）、正在核验时右下显示“核验中”、可删除时右上删除按钮。
- 封面下是 `ListTile`：头像（`CommonAvatar`，可关）、标题（13 号半粗，一行）、主播名（12 号，一行，可关）；宽卡片时右侧自动显示平台标。
- 另有“紧凑布局”（`_buildCompactLayout`），在设置“卡片外观”里选。

v3 的问题：
1. 平台标显示的是平台 id 的大写（`BILIBILI`、`DOUYU`），不是中文名或平台图标。
2. 颜色硬编码白/`grey[900]`，不随主题色的表面层次变化。
3. 标题只有一行，长标题信息丢失（直播标题常常较长）。

v4 现在：`live_ui` 的 `RoomCard` 基本照 v3 的封面加信息行；平台标、人数位置和图标有差异（人数用火焰图标）。

## 5. 直播间（竖屏普通布局）

**v3 的样子**（`lib/modules/live_play/`，67 个文件，18475 行）

整体（宽度 ≤680，`live_play_content.dart` `LivePlayNormalLayout` 的 `portraitStack`）从上到下：

1. **顶栏**（`widgets/layout/live_play_header.dart`，`AppBar` 56 高）：返回；头像（半径 16）；两行小字（主播名、`平台 / 分区`，都是 `labelSmall`）；右侧三个按钮：
   - 关注：手机上是圆形浅色填充按钮 `IconButton.filledTonal`，`Remix.heart_3_line/fill`（宽屏是“关注/已关注”文字按钮）；取消关注先确认。
   - 录制：`Remix.record_circle_line`（录制中 `record_circle_fill`、已完成 `checkbox_circle_fill`），手机只显示图标，宽屏图标+文字。
   - 菜单：`Remix.apps_2_line`，弹出：打开直播间（跳平台 App）、切换直播间、投屏 `Remix.tv_2_line`、定时关闭 `Remix.time_line`、房间音量 `Remix.volume_up_line`、获取直链 `Remix.link_m`、分享 `share_forward_line`、本地互动体验（开了才有）、新窗口打开（仅 Windows）。
2. **画面**（16:9），点一下显示/隐藏控制层，双击全屏，左右半边上下滑调亮度/音量（中间显示音量卡片），长按画面上的弹幕可操作。控制层：
   - **上栏**（56 高，黑色 45% 渐变）：房间标题（白色 16 号粗体，网络电视多一行“正在播放：节目”）；右侧（Android）**纯音频** `Remix.headphone_line/fill`、**投屏** `Remix.tv_2_line`、**小窗** `CustomIcons.float_window`；网络电视多一个节目单 `Icons.assignment_outlined`。
   - **下栏**（56 高，渐变）：左侧 **播放/暂停**、**刷新** `Icons.refresh_rounded`、**关注**（白字小胶囊“✓ 已关注 / × 关注”）、**弹幕开关**（`danmu_open.svg` / `danmu_close.svg`）、**弹幕设置**（`danmu_setting.svg`，弹出设置面板）；右侧 **方向**（`Icons.screen_rotation_alt_rounded`，按房间记忆）、**画面比例**（文字按钮，显示当前比例名）、**全屏**（`Icons.fullscreen_rounded`，固定在最右，不随滚动）。手机放不下时中间部分可横向滚动。
3. **信息行**（`resolution_selector/resolutions_row.dart`，56 高）：左侧一个人数（图标 + “在线 1.2万”，按设置选在线/热度/累计）；右侧画质（如“原画”）、线路（“线路1”），都是主题色小字，点开弹出菜单。
4. 分隔线。
5. **四个等宽标签**：弹幕列表、醒目留言、弹幕设置、屏蔽管理（左右滑切换）。
6. **弹幕列表**：每条是一张小卡片（白色 72% 底、圆角 10、细边框），左边一个 8 像素的彩色圆点（弹幕颜色），“用户名：”粗体 + 内容（14 号，表情图片）；双击复制，长按/右键弹出操作；往上翻时右下角出现“有 N 条新弹幕”按钮；开了本地互动时底部有输入框。

竖屏流（主播竖屏开播，设置开了“竖屏自适应”）：画面铺满，下方一张可拖动的面板（三档高度，含信息行、标签、弹幕），面板顶部有把手和“下滑进入竖屏全屏”提示，面板右上浮一个“横屏全屏”按钮。

v3 的问题：
1. 顶栏主播名和“平台 / 分区”都是 `labelSmall`，没有主次，名字不突出（`live_play_header.dart:40-53`）。
2. 关注在顶栏和画面下栏各有一个，两处样式不同（圆形心形按钮 vs 白字胶囊），同屏重复。
3. 画面下栏在手机上 8 个控件放不下，靠横向滚动，滚出去的按钮看不见（`video_controller_panel.dart:1477-1502`）；“画面比例”是一段文字，宽度随内容变化，挤压其他按钮。
4. 信息行只显示一个人数，开播时长、其他口径看不到；画质、线路是 `labelSmall` 小字，点击区域小。
5. 弹幕每条都是带边框的卡片，加上 8+8+4+4 的内边距，一屏能看的弹幕少，视觉噪点多；彩色圆点含义不明（`danmaku_list_view.dart:476-500`）。
6. 菜单图标 `Remix.apps_2_line` 和首页“分区”导航同一个图标。
7. 控制层上下栏只有 45% 黑的渐变，明亮画面上白色图标看不清（真机测试也发现）。

v4 现在（偏差最大）：
- 竖屏时画面**上栏不显示**（只在全屏时出现），纯音频、投屏、小窗被挪到了下栏。
- 下栏变成：播放/暂停、刷新、弹幕开关（换成字幕图标 `Icons.subtitles`）、纯音频、锁定 …… 投屏、小窗、全屏；**没有关注胶囊、弹幕设置、方向、画面比例**。
- 信息行变成两行：标题 + 在线/热度/累计三个数 + 开播时长 + 画质线路，比 v3 挤。
- 顶栏右侧只有心形和 `⋮`，**没有录制按钮**（M13.16 后改到别处），菜单图标也不是 v3 的。
- 弹幕列表去掉了卡片和圆点，系统消息用斜体。

| v3 | v4 |
|---|---|
| `pages/live_play_page.dart`、`widgets/layout/*` | `features/live_play/live_play_page.dart`、`room_panels.dart` |
| `widgets/video_player/video_controller_panel.dart`、`video_controller.dart` | `features/live_play/player/player_view.dart`、`player_gestures.dart` |
| `widgets/layout/live_play_header.dart`、`widgets/button/*` | `features/live_play/live_play_page.dart`、`record_button.dart`、`room_menu_button.dart` |
| `widgets/resolution_selector/*` | `features/live_play/layout/room_panels.dart`、`stream_dialogs.dart` |
| `widgets/danmaku/*`、`pages/danmaku_settings_page.dart`、`keyword_block_page.dart`、`super_chat_page.dart` | `features/live_play/danmaku/chat_panel.dart`、`chat_feed.dart`、`lib/shared/danmaku/*` |
| `dialogs/*` | `features/live_play/dialogs/room_dialogs.dart`、`room_switcher.dart`、`stream_dialogs.dart` |

## 6. 直播间（横屏全屏，U.2c）

**v3 的样子**（`lib/modules/live_play/widgets/video_player/video_controller_panel.dart`）

- 进入：画面下栏全屏按钮、自动方向时把手机横过来、双击画面。退出：返回、全屏按钮、Esc、双击。
- 顶栏（高 56，渐变透明 → 45% 黑）：返回；Android 上紧跟时间（14 号白字）和电量（35×15 的电池框，9 号数字）；标题（16 号粗体，网络电视多一行“正在播放：节目名”）；网络电视的节目单 `Icons.assignment_outlined`；切换直播间 `Icons.swap_horiz_outlined`（带 26% 黑圆底）；非 Android 平台时间和电量在这里；纯音频 `Remix.headphone_line/fill`；投屏 `Remix.tv_2_line`（Android）；小窗 `CustomIcons.float_window`（Android、Windows）。顺序由 `resolveTopActionLeadingSlots` / `resolveTopActionTrailingSlots`（:42-66）固定。
- 下栏（高 56）：左组 播放/暂停、刷新、“✓ 已关注”文字、弹幕开关、弹幕设置（后两个在弹幕显示打开时才有）；中间本地弹幕输入框（最宽 420，左边 ✨ 改样式，右边发送）；右组 “⚙ 原画 · 线路1”合并按钮（打开半屏两栏对话框）、方向（移动端）、“默认比例”文字按钮、Windows 音量条、Windows 窗口内全屏（非真全屏时）、退出全屏。宽度不到 760 时左组去掉刷新和已关注、右组去掉画面比例（:1439-1441、:1546-1578）。
- 右侧中间锁定按钮 `Icons.lock_open_rounded / lock_rounded`（所有平台的全屏都有，:1009）。
- 手势：左半边上下滑调亮度、右半边调音量（中间显示黑色进度卡片），单击显示或隐藏控制栏（触屏播放中第二次点击隐藏），双击退出全屏，长按画面上的弹幕打开屏蔽操作；控制栏范围内的点击不当作点弹幕（`shouldHandleVideoSurfaceTap`）。
- 键盘（`widgets/keyboard/video_keyboard.dart`）：Esc 退出全屏、空格暂停或继续、R 刷新、上下键音量、媒体键。

**v3 的问题**：F1 全屏时没有录制入口、打不开右上角菜单；F2 宽度不到 760 时三个按钮消失；F3 时间电量位置随平台变；F4 切换直播间带深色圆底，样式不统一；F5 画面比例和已关注是文字，和图标混排；F6 渐变 45% 黑偏淡；F7 清晰度线路合并按钮和半屏对话框（U.2f 已改）。

**对比和设计**：见 [compare/U.2c](compare/U.2c/README.md)。

## 7. 直播间（宽屏左右分栏，U.2d）

**v3 的样子**（`lib/modules/live_play/widgets/layout/live_play_content.dart`、`live_play_header.dart`、`video_controller_panel.dart`）

- 宽度 ≤680 用竖屏排法，>680 左右分栏（`resolveLivePlayNormalLayout`，:20-22）：左边画面（黑底，16:9 居中），右边聊天栏，宽度是可用宽度的 34%，夹在 300–400（:94）；聊天栏从上到下是 `ResolutionsRow`（人数、原画、线路，11 号字）、分隔线、四个标签和弹幕列表（卡片样式）。网络电视不显示聊天栏（`showPanel`）。
- 顶栏：宽度 ≥600 时关注是文字按钮（`FilledButton`，圆角 6，12 号字，“关注”主色底、“已关注”半透明主色底），录制是带字的按钮（图标 14 + 11 号字：录制 / 已监控 / 录制中）；<600 时是心形图标按钮和圆圈图标（`favorite_floating_button.dart:62-93`、`record_action_content.dart`）。主播名和“平台 / 分区”都是 `labelSmall`（:42-55）。
- 画面上栏：标题、纯音频、投屏（Android）、小窗（Android、Windows）。下栏（不是全屏时）：左 播放/暂停、刷新、“✓ 已关注”、弹幕开关、弹幕设置；右 方向（移动端）、“默认比例”文字按钮、Windows 音量条、Windows 窗口内全屏（`unfold_more`，:1882-1905）、全屏。
- 窗口内全屏（Windows）：画面占满窗口，顶栏和聊天栏藏起来，Esc 退出（`video_keyboard.dart`）。
- 鼠标：移动时显示控制栏，静止后隐藏，鼠标指针也隐藏（`ControlHoverRegion`）。

**v3 的问题**：W1 680–839 时画面只剩一小块；W2 顶栏名字和分区同字号；W3 关注和录制按钮随宽度换样子；W4 “默认比例”文字按钮、窗口内全屏图标看不出意思；W5 聊天栏顶上没有标题和信息；W6 窄栏里卡片样式弹幕；W7 没有只收起聊天栏的办法。

**对比和设计**：见 [compare/U.2d](compare/U.2d/README.md)。

## 各任务的 v3 清单

第 7 节以后，每个任务的“v3 的样子、问题、文件对照”写在各自的 README 里：

| 任务 | 位置 |
|---|---|
| U.2b 竖屏流和竖屏全屏 | [compare/U.2b](compare/U.2b/README.md) |
| U.2e 弹幕列表和弹幕设置页 | [compare/U.2e](compare/U.2e/README.md) |
| U.2j 小窗 | [compare/U.2j](compare/U.2j/README.md) |
| U.5a 搜索 | [compare/U.5a](compare/U.5a/README.md) |
| U.5b 网页搜索 | [compare/U.5b](compare/U.5b/README.md) |
| U.5c 观看历史 | [compare/U.5c](compare/U.5c/README.md) |
| U.4a 房间卡片 | [compare/U.4a](compare/U.4a/README.md)（第 4 节和代码对不上的地方以这里为准：标是“录播”、默认不标平台、卡片默认圆角 20） |
| U.4b 热门 | [compare/U.4b](compare/U.4b/README.md)（第 2 节的空状态原文是“未发现直播”） |
| U.4c 关注 | [compare/U.4c](compare/U.4c/README.md) |
| U.2g 直播间的状态 | [compare/U.2g](compare/U.2g/README.md) |
| U.4d 分区 | [compare/U.4d](compare/U.4d/README.md) |
| U.4e 分区房间 | [compare/U.4e](compare/U.4e/README.md) |
| U.4f 关注的分区、平台显示 | [compare/U.4f](compare/U.4f/README.md)（v3 的 HotAreasPage 实际是“平台显示”页） |
| U.3a～U.3d 首页外壳、宽屏首页、启动页、全局弹窗 | [compare/U.3a](compare/U.3a/README.md)、[U.3b](compare/U.3b/README.md)、[U.3c](compare/U.3c/README.md)、[U.3d](compare/U.3d/README.md)（第 1 节以这里为准） |
| U.2k 本地互动 | [compare/U.2k](compare/U.2k/README.md) |
| U.9 网络电视管理 | [compare/U.9](compare/U.9/README.md) |
| U.10a 账号总览 | [compare/U.10a](compare/U.10a/README.md) |
| U.10b 登录和 Cookie | [compare/U.10b](compare/U.10b/README.md) |
| U.10c 云账号停用说明 | [compare/U.10c](compare/U.10c/README.md) |
| U.6a 设置总览 | [compare/U.6a](compare/U.6a/README.md) |
| U.6b 外观 | [compare/U.6b](compare/U.6b/README.md) |
| U.6c 播放设置 | [compare/U.6c](compare/U.6c/README.md) |
| U.6d 通用和网络 | [compare/U.6d](compare/U.6d/README.md) |
| U.6e 数据 | [compare/U.6e](compare/U.6e/README.md) |
| U.7a 录制中心 | [compare/U.7a](compare/U.7a/README.md) |
| U.8 多画面 | [compare/U.8](compare/U.8/README.md) |
| U.7b 录制设置 | [compare/U.7b](compare/U.7b/README.md) |
| U.11a 备份与恢复 | [compare/U.11a](compare/U.11a/README.md) |
| U.11b WebDAV | [compare/U.11b](compare/U.11b/README.md) |
| U.11c 设备同步 | [compare/U.11c](compare/U.11c/README.md) |
| U.12a 工具箱（链接解析） | [compare/U.12a](compare/U.12a/README.md) |
| U.12b 关于和版本 | [compare/U.12b](compare/U.12b/README.md) |
| U.12c 标签管理 | [compare/U.12c](compare/U.12c/README.md) |
| U.12d 弹幕屏蔽（设置） | [compare/U.12d](compare/U.12d/README.md) |
| U.15i 电视设置 | [compare/U.15i](compare/U.15i/README.md) |
| U.13 桌面窗口 | [compare/U.13](compare/U.13/README.md) |
| U.14 系统界面 | [compare/U.14](compare/U.14/README.md) |
| U.15d 电视直播间 | [compare/U.15d](compare/U.15d/README.md) |
| U.15e 电视网络电视和链接放映 | [compare/U.15e](compare/U.15e/README.md) |
| U.17a iOS 和 iPadOS | [compare/U.17a](compare/U.17a/README.md) |
| U.17b macOS | [compare/U.17b](compare/U.17b/README.md) |
| U.1c 通用组件 | [compare/U.1c](compare/U.1c/README.md) |
| U.1d 弹窗组件 | [compare/U.1d](compare/U.1d/README.md) |
| U.15a 电视设计系统和通用组件 | [compare/U.15a](compare/U.15a/README.md) |
| U.15b 电视外壳 | [compare/U.15b](compare/U.15b/README.md) |
| U.15c 电视直播浏览 | [compare/U.15c](compare/U.15c/README.md) |
| U.3b 宽屏首页 | [compare/U.3b](compare/U.3b/README.md) |
| U.3c 启动页 | [compare/U.3c](compare/U.3c/README.md) |
| U.3d 全局弹窗 | [compare/U.3d](compare/U.3d/README.md) |
