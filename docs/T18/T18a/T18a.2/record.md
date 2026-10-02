# T18a.2 电视设计系统和通用组件

- 日期：2026-10-01
- 设计：[docs/T18/T18a/T18a.2/README.md](README.md)（第 1 版，用户已确认；待选 A1～A4 按建议 A）；计划书 [specs/UI.md](../../../specs/UI.md) 第 5.5 节（电视）、第 7 节（弹窗）、第 8 节（设计系统）
- 范围：电视的焦点样子、颜色和字号、按钮、标签、导航项、房间卡片、分区卡片、封面角标、设置行、子页顶栏、状态页、提示条；电视对话框一族（外框、确认、选择、输入、设置房间标签）、卡片长按弹窗、手机推送直播间的对话框。组件在 `apps/pure_live/lib/tv/widgets/`，已有的电视页面换用这些组件，页面结构不动（页面本身是 T18a.3～T18e.2）。
- 改动的目录：`apps/pure_live/lib/tv/`、`apps/pure_live/lib/app/app.dart`（两行：电视固定深色、提示条去重）、`packages/live_ui`（只做添加：`TvIcons`、`TvColors`）、`packages/live_store`（只做添加：设置 `tvFocusZoom`）、翻译文件、门禁基线、文档。别的任务的功能目录没有改（`shared/rooms/room_menu.dart` 只调用 `followRoom`，没有改）。
- 没有改原生部分，没有构建 APK，没有往手机安装。

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 获得焦点 120 毫秒、离开不动画、按下缩小 | ✅ | `TvFocusable`：`tvFocusDuration`，离开 `Duration.zero`，按住 OK 时 0.97 |
| c1 | 长按 OK 0.5 秒算长按，松开不再点按 | ✅ | 同前；长按触发后松开不点按，按住不连发 |
| c1 | 卡片结构、焦点时标题滚动、网络电视频道号、热门等页的已关注标记 | ✅ | `TvRoomCard`；标题滚动是新写的 `TvMarquee`（只有有焦点的那一张在动，停 1 秒后每秒 40 像素，离开就停）；关注页不显示已关注标记（`TvRoomGrid.showFollowed: false`） |
| c1 | 4 列房间网格、6 列分区网格 | ✅ | 列数规则照旧（`tvRoomColumns`）；房间格子的高宽比改为按卡片算（16:9 封面加两行字，`TvRoomCard.heightFor`），原来固定 1.3 会把封面压扁 |
| c1 | 对话框种类、按钮顺序（取消在左）、关闭后焦点回到原处 | ✅ | `TvDialog`、`showTvConfirm`、`showTvChoice`、`showTvInput`；焦点回原处靠路由的焦点范围，有测试 |
| c1 | 选择框打开时焦点在当前项；长列表滚到当前项 | ✅ | `TvOptionRow` 获得焦点时 `Scrollable.ensureVisible` |
| c1 | 设置行的种类和按键：开关 OK 或 ←→，滑块 ←→ 到头放行 | ✅ | `TvSwitchRow`、`TvSliderRow`（照 pure_live_TV 的按键） |
| c1 | 在当前标签上再按 OK 刷新，下面一条进度线 | ✅ | `TvTabBar` 照旧 |
| c2 | 一种焦点样子：近白 3 像素描边（画在外面）；卡片、按钮、标签、导航项放大 1.05；整行的东西不放大；去掉光晕 | ✅ | 描边色 `TvColors.focusRing`（#F1F3F9）；设置行、对话框选项、输入框、房间列表行 `zoom: false`；全部组件没有 `BoxShadow` |
| c2 | 低端盒子可以在设置里关掉放大，只留描边 | ✅ | 新设置 `tvFocusZoom`（默认开），电视设置页加了一行“焦点放大”（开关行） |
| c3 | 选中 = 主色容器底 + 浅色字；焦点 = 描边；两者可同时出现；列表当前项主色字加勾 | ✅ | 标签、导航项、按钮的 `selected`、房间列表当前项；选择框当前项主色加粗加勾，焦点行是高一级的表面色加描边 |
| c4 | 颜色和手机深色主题同一套角色，主题色作种子；按钮平时表面容器底，主要动作主色字、删除类红字；对比度 ≥4.5 | ✅ | `TvPalette` 直接用深色 `ColorScheme` 的角色；电视界面固定深色（`app.dart` 里电视时 `themeMode: dark`）；四种主题色的对比度有测试 |
| c5 | 字号大一级、最小 14：卡片标题 16（600）、主播名 14、角标 14、按钮 16、对话框标题 22、正文 16、设置行标题 17 | ✅ | `TvTextSize`；1080p 电视上全部文字 ≥14 有测试（不算图标和头像占位字） |
| c6 | 分区卡片有自己的底色，图片铺满上半部；已关注右上心形 | ✅ | `TvAreaCard`；分区页换用 |
| c7 | 角标照手机 T07d.1：平台“图标 + 中文名”只在混合列表；“录播”；人数等宽数字；未开播压暗 +“未开播”；受限锁 + 原因 | ✅ | 混合列表 = 观看记录、关注页“全部平台”、搜索“全部平台” |
| c8 | 封面加载中和失败同一个占位，不用断网图标 | ✅ | `TvCover` / `TvCoverPlaceholder`（电视图标） |
| c9 | 卡片长按都打开同一个弹窗：主播、平台 · 房间号、完整标题、设置标签（观看记录多“删除这条记录”）、关闭、＋ 关注 / ✓ 已关注；关注直接关注，取消关注先确认 | ✅ | `showTvRoomDialog`；热门、关注、观看记录、搜索、分区房间、网络电视的网格都换用（原来是手机的 `showRoomMenu`）。关注后弹窗不关，按钮变成“✓ 已关注”，焦点留在原处 |
| c10 | 遥控器菜单键等于长按 OK | ✅ | `TvFocusable` 把 `contextMenu` 当长按 |
| c11 | 设置房间标签：标题下写明直播间，末尾“新建标签”（打开输入框），没有标签时也能新建，“取消 / 确认” | ✅ | `TvRoomTagsDialog`；新建的标签自动勾上；名字最多 15 字（`tagNameMaxLength`），空名和重名提示 |
| c12 | 删除类确认框默认焦点在“取消”，主按钮写明动作、红字；其他确认框焦点在主按钮 | ✅ | `showTvConfirm(danger:)`：取消关注、清空观看记录、删除一条观看记录、清空最近搜索；非删除类打开后 0.5 秒内按 OK 无效（保留 pure_live_TV 的防误触） |
| c13 | 子页不放“返回”按钮：标题 + 副标题，动作在右边，默认焦点在内容第一项 | ✅ | `TvPageHeader`；分区房间页换用（标题是分区、副标题是平台、右边“关注分区”）；电视设置页第一行就是焦点（T18d.1 的同步项） |
| c14 | 第一次加载静态骨架；出错按原因一句话；空状态写遥控器怎么做；图标不弹跳；按钮默认焦点 | ✅ | `TvSkeletonGrid`、`TvStatusView`、`TvStatusView.failure`（网络类标题“网络请求失败”，需要登录时“需要登录账号 / 前往登录”→ 设置里的账号页，说明用 v4 已有的 `describeLoadError`） |
| c15 | 手机推送直播间用 T07a.6“口令导入”同一个对话框 | ⚠️ 只做了外壳 | `showTvRoomPush`：认出直播间时头像、标题、“主播 · 平台 · 房间号”，“进入房间”默认焦点；认不出时显示推送的文字和“搜索这段文字”。v4 电视还没有接收手机推送的部分（pure_live_TV 的 `GlobalRoomPushOverlay`），T07a.6 的口令解析也还没合并，接线见下 |
| c16 | 对话框外框不描边不发光；遮罩 60% 黑；输入框打开就能输入，框下写怎么输入 | ✅（Android 有偏差） | `TvDialog`、`showTvDialog`（`TvColors.scrim`）、`TvInputDialog`。Android 上 `TvTextInput.prompt` 仍走原生输入对话框，见“偏差” |

## 偏差和原因

1. **Android 上的文字输入仍是原生对话框**：T18a.1 发现部分电视盒子上 Flutter 的文本输入调不出系统键盘（flutter#154924，pure_live_TV 也因此用了原生视图），所以 `TvTextInput` 在 Android 上弹原生 EditText 对话框，样子是系统的，不是设计图的 `TvInputDialog`；其他平台和原生调用失败时用 `TvInputDialog`。要在 Android 上也用设计图的样子，需要像 pure_live_TV 那样在 Flutter 对话框里嵌原生输入视图（改原生部分），需要你决定。
2. **选择行不再用 ←→ 直接换值**：T18a.1 给电视设置页的选择行加过 ←→ 换值；设计里选择行只有 OK 弹选择框（pure_live_TV 也是），←→ 留给焦点移动（左键回导航栏）。原有测试“Right steps the interface mode”照设计改成“OK 弹选择框、焦点在当前值、选手机”。
3. **电视设置页去掉“主题模式”一行**：电视固定深色（选择 A2，T09a.3 → T18e.2），这一行在电视上已经不起作用。
4. **清空最近搜索加了确认**：pure_live_TV 有这个确认，v4 原来直接清空；按 c12 加回，焦点在“取消”。
5. **导航项放大 1.05**：照改动清单 c2 的文字；部件图里导航栏的焦点项画的是只描边不放大，导航栏本身由 T18a.3 重做时再定。
6. **分区卡片长按**仍是关注 / 取消关注分区（原来的 `toggleAreaFollow`）；改成统一的卡片长按弹窗是 T18b.1 的 c7。
7. 电视设置页的其余结构（分组、哪些用滑块）是 T18e.2 的；这次只把行换成新组件，分成三组卡片，没有加组标题。

## 手机推送直播间的接线（c15，留给 T07a.6 合并后）

- 电视收到手机推送的文字后，用 T07a.6 的口令解析（`shared/rooms/share_code.dart` 的解码，T07a.6 正在做）认出 `LiveRoom`，再调用 `showTvRoomPush(context, text: 原文, room: 认出的房间或 null)`。
- 返回 `TvRoomPushChoice.open`：`openTvRoom(room)`；平台已下线时 `openTvRoom` 已有提示“该平台已下线…”。
- 返回 `TvRoomPushChoice.search`：`AppNavigator.toNamed(RoutePath.kSearch, arguments: 原文)`（电视的搜索页收到字符串参数会直接搜）。
- 推送的接收端（局域网遥控页）v4 还没有，属于设备同步 / 遥控的任务。

## v3（pure_live_TV）文件 → v4 文件

| pure_live_TV | v4 |
|---|---|
| `core/widgets/tv_focusable.dart`、`tv_focus_style.dart`、`app/app.dart`（长按门） | `tv/widgets/tv_focusable.dart` |
| `core/widgets/tv_button.dart` | `tv/widgets/tv_button.dart` |
| `core/widgets/tv_icon_button.dart` | `tv/widgets/tv_nav_item.dart` |
| `core/widgets/tv_tab_bar.dart`、`tv_tab_view.dart` | `tv/widgets/tv_tabs.dart`、`tv/widgets/tv_grid.dart`（记忆焦点照旧） |
| `core/widgets/tv_room_card.dart`、`tv_cover_chip.dart`、`tv_marquee.dart`、`tv_common_avatar.dart`、`number_leading.dart` | `tv/widgets/tv_room_card.dart`（`TvRoomCard`、`TvCoverChip`、`TvCover`、`TvMarquee`；头像用 `live_ui` 的 `CommonAvatar`） |
| `core/widgets/tv_area_card.dart` | `tv/widgets/tv_area_card.dart` |
| `core/widgets/tv_settings_row.dart`、`tv_settings_switch_tile.dart`、`tv_settings_nav_tile.dart`、`tv_settings_option_tile.dart`、`tv_settings_slider_tile.dart`、`tv_settings_card.dart`、`tv_section.dart` | `tv/widgets/tv_settings_rows.dart` |
| `core/widgets/tv_app_bar.dart`、`tv_page_scaffold.dart`、`tv_page_shell.dart` | `tv/widgets/tv_page_header.dart` |
| `core/widgets/app_status_view.dart`、`empty_scene.dart` | `tv/widgets/tv_status.dart` |
| `core/dialog/tv_dialog.dart`、`tv_confirm_dialog.dart`、`tv_dialog_option_tile.dart`、`tv_input_dialog.dart`、`tv_dialog_focus_guard.dart`、`core/widgets/tv_input_field.dart` | `tv/widgets/tv_dialogs.dart` |
| `core/utils/favorite_operation_util.dart`（三种长按） | `tv/widgets/tv_room_dialog.dart` |
| `domains/device/global_room_push.dart` | `tv/widgets/tv_room_push_dialog.dart`（外壳） |
| `core/theme/tv_palette_defaults.dart`、`themes/dark_theme.dart` | `tv/tv_theme.dart`（`TvPalette` 用手机深色角色）、`live_ui` 的 `TvColors` |
| `core/widgets/tv_digital_clock.dart` | `tv/home/tv_home_page.dart` 的 `_Clock`（字号换成新字号，等宽数字） |
| `ToastUtil`（3 秒内不重复） | `app/app.dart` 的提示条（电视时去重）、`tv/tv_app.dart`（提示条样式） |

`tv_lazy_wrapper.dart`、`tv_locale_rebuilder.dart`、`subtree_reviver.dart`、`tv_scaffold*.dart`、`tv_qr_card.dart`、`remote_sync_*_card.dart`、`tv_platform_logo.dart`：Flutter 本身或 v4 已有的部分代替（`IndexedStack` 保留页面、语言切换整树重建、`PlatformLogo`），二维码卡片随设备同步的任务。

## 新增的东西

- 设置：`tvFocusZoom`（`app` 分组，默认 `true`，“焦点放大”）。只做添加，旧设置和存储键不变。
- `live_ui`：`TvIcons`（电视用到的图标按用途命名，原来散在 `tv/` 里的 `Icons.*`）、`TvColors`（焦点描边、遮罩、已关注的心形）。
- 翻译（中英各 21 条，按键名排序）：`tv_ok`、`tv_input_hint_numeric`、`tv_input_hint_text`、`tv_load_failed`、`tv_empty_platform`、`tv_empty_area`、`tv_empty_follow_group`、`tv_no_history_hint`、`tv_search_empty_hint`、`tv_search_clear_title`、`tv_search_clear_message`、`tv_history_delete_message`、`tv_set_tags`、`tv_room_platform_id`、`tv_tags_room`、`tv_tag_name_hint`、`tv_push_title`、`tv_push_from_phone`、`tv_push_search`、`tv_focus_zoom`、`tv_focus_zoom_desc`。

## 门禁基线

- `tools/gate/ui_baseline.json`：`tv` 直接写的颜色和图标 102 → 0（这一项从基线里去掉）。其余不变，没有新增跨功能引用。

## 测试

- `test/tv/tv_components_test.dart`（新，31 个）：调色板和对比度（四种主题色）；焦点描边和放大、整行不放大、关掉放大；标签选中和焦点分开、按钮顺序和计数；按钮三种文字色、不可用 38% 且焦点跳过；1080p 上最小字号 14；房间卡片各状态和角标位置（直播、混合列表平台和心形、录播、未开播、受限、占位、频道号）、焦点时标题滚动和停止、长按 / 菜单键 / 右键（附录 A 第 14 条）；分区卡片；开关行、滑块行、选择行和跳转行；危险确认框焦点在“取消”、红字、遮罩 60%、无描边、关闭后焦点回原处；普通确认框 0.5 秒防误触；选择框当前项和焦点项；输入框；卡片长按弹窗在 1080p@2x、1080p@1x、720p 三种面板上的内容、按钮位置和不出屏；关注 / 取消关注；观看记录删除先确认；设置标签先关注、新建标签自动勾上并保存；状态页（网络失败、需要登录、骨架、空、不弹跳）；子页顶栏；手机推送两种状态。
- `test/tv/tv_test.dart`（原有 8 个）：照设计改了三处：网格高宽比的检查换成卡片高度；长按打开的是新的卡片弹窗（焦点在“设置标签”），另加菜单键；电视设置页的选择行改成 OK 弹选择框（见偏差 2）。
- `apps/pure_live` 全部测试（379 个）、`live_ui`（49）、`live_store`（33）通过；`flutter analyze` 无问题；`check_ui_structure.py` 通过。
- 测试里等待用的时长都不短于 1 秒（防误触、标题滚动、对话框动画）。

## 真机

没有在电视上看过（这次不安装）。需要在 K90 投屏或电视盒子上看：焦点描边在亮画面封面上是否够醒目、720p 盒子的字号、Android 原生输入对话框和新对话框风格的差别（偏差 1）。
