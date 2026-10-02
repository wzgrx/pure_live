# A01.1 界面基础：主题、通用组件、图标（模块重构）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（完成，2026-10-01）
- 范围：把 3.x 的 `lib/common/style/`、`lib/common/styles/`、`lib/common/widgets/`（标签 `v3.2.11`，约 5000 行）和它们用到的图标字体、平台标志搬进新包 `packages/live_ui`：外观照 3.x，去掉 GetX 和全局单例，修审查发现的 11 个问题
- 旧编号：M11、T01a.1（见 [MAPPING.md](../../../MAPPING.md)）
- 对应：[inventory/V3_UI.md](../../../inventory/V3_UI.md) 第 0 节（全局外观）、第 4 节（房间卡片）；[specs/UI.md](../../../specs/UI.md) 第 8、10 节；[specs/ENGINEERING.md](../../../specs/ENGINEERING.md) 第 4 节（分层：`live_ui` 不依赖任何 `live_*` 包，门禁 `tools/gate/check_deps.py`）
- 评审页：无。这是模块重构，任务定的是“外观照 3.x、只改结构和 bug”，没有出效果图和评审页；外观上的改动从界面重构（A02、A07～A12）开始逐个出图确认
- 记录：[record.md](record.md)（开发记录，本文件的事实都来自它）
- 设计参考：归档 v4 的 `packages/live_ui`（分支 `archive/v4`）：只借鉴了“房间卡片吃小输入类型、平台图标放在包里”的结构；它的设计系统、图标集和外观与 3.x 不同，没有采用（D-001、D-002）

## 界面清点表

不是单个界面，而是 3.x 全应用共用的外观和组件。每行一个搬过来的部分；“状态”一列是它带的状态。

| 编号 | 界面（组件） | 从哪出现 | 形态 | 状态 |
|---|---|---|---|---|
| — | 主题（`LiveTheme`、`AppTextStyles`、动态取色） | 全应用 | 深色、浅色；种子色或系统色板 | 五个字号设置、字体设置生效 |
| — | 状态页（`AppStatusView`、`EmptyView`、85 种加载动画） | 列表第一次加载、空、出错；卡片封面失败 | 整页、迷你（卡片封面） | 加载、空、出错 |
| — | 房间卡片（当时的 `RoomCard`，现在是 A09.1 的 `LiveRoomCard`） | 热门、关注、分区、搜索、历史 | 网格卡片、紧凑行 | 直播中、未开播、回放、受限、核验中、可删除 |
| — | 头像、网络图片（`CommonAvatar`、`LiveNetworkImage`） | 卡片、直播间顶栏、口令导入、多画面选房 | — | 图片、加载中、首字 |
| — | 设置页积木（当时的 `buildGroupTitle`、`buildModernCard`、`buildSwitchTile`、`buildTile`、`buildSliderTile`、`CardTile`、`SectionTitle`、`MenuListTile`） | 所有设置页 | 竖屏、宽屏（最宽 960） | 开关、跳转、滑块、窄屏换行 |
| — | 计数按钮、标签栏、二维码、`KeepAliveWrapper`、`EmoteText` | 弹幕设置、各标签页、设备同步、聊天 | — | 长按连加；滚轮横滚 |
| — | 滚动（`PureLiveScrollPhysics`、`PureLiveBoundedScrollPhysics`、Windows 滚轮控制器） | 全部列表和标签条 | — | — |
| — | 刷新率（`AdaptiveRefreshRateController`、`AdaptiveRefreshRateScope`） | Android 全应用 | — | 省电、均衡、性能三档 |
| — | 图标（`CustomIcons` 字体、34 个平台标志 + 应用标志、再导出 `remixicon`） | 全应用 | — | 未知平台用应用标志 |

## 3.x 的样子和问题

- 样子：主题、文字样式、卡片、状态页、设置块的尺寸、颜色、圆角、动画（[inventory/V3_UI.md](../../../inventory/V3_UI.md) 第 0、4 节）；3.x 的组件从 `Get.theme`、`SettingsService.to` 读主题和设置；`RoomCard` 在卡片里打开直播间、弹关注 / 标签 / 分享菜单。
- 3.x 文件和行数（标签 `v3.2.11`）：

| 3.x 文件 | 行数 | 搬到 | 说明 |
|---|---|---|---|
| `style/theme.dart` | 186 | `theme/live_theme.dart` | `MyTheme` → `LiveTheme`；字体大小、字体名改为参数；把 3.x `main.dart` 叠在主题上的覆盖（标题栏、页面切换）合进来 |
| `style/app_text_styles.dart` | 77 | `theme/text_styles.dart` | 静态 getter → 从主题读的对象；名字和数值不变 |
| `styles/dynamic_color_adapter.dart` | 183 | `theme/dynamic_color.dart` | 原样保留，加 `LiveDynamicColorBuilder` |
| `widgets/app_status_view.dart`、`empty_view.dart` | 575 | `widgets/status_view.dart`、`widgets/loading_styles.dart` | 85 个 `switch` 分支改为三张表；样式、颜色从 `LiveUiScope` 读 |
| `widgets/room_card.dart` | 1411 | `widgets/room_card.dart` | 只保留卡片的画法（约 500 行）；长按菜单、关注按钮、标签对话框交给页面 |
| `widgets/room_card_layout.dart` + `services/settings/room_card_settings_controller.dart` 的 `RoomCardAppearance` | 52 + 245 | `widgets/room_card_appearance.dart` | 外观值、预设、旧键读取放进来；存取（Hive、预设记忆）留给 J02.1 |
| `widgets/common_avatar.dart` | 65 | `widgets/avatar.dart`、`widgets/network_image.dart` | 缓存管理器、请求头、缓存代数从 `LiveUiScope` 读 |
| `widgets/widget_extensions.dart`、`section_listtile.dart`、`menu_button.dart` 的 `MenuListTile` | 455 + 61 + 18 | `widgets/settings_tiles.dart` | 见问题 3、4、5 |
| `widgets/count_button.dart` | 205 | `widgets/count_button.dart` | 见问题 7 |
| `widgets/scrollable_tab_bar.dart`、`qr_code_widget.dart`、`keep_alive_wrapper.dart` | 270 | 同名文件、`widgets/scrolling.dart` | 行为不变 |
| `widgets/pure_live_scroll_physics.dart`、`pure_live_scroll_controller.dart` | 93 | `widgets/scrolling.dart` | 行为不变 |
| `widgets/adaptive_refresh_rate_scope.dart` + `utils/latest_async_value_queue.dart` | 156 + 80 | `widgets/refresh_rate.dart` | 静态状态 → 应用持有的对象；平台调用注入；见问题 8 |
| `widgets/custom_icons.dart` | 61 | `icons/custom_icons.dart` | 字体随包打包（`fontPackage: 'live_ui'`） |
| `core/sites.dart` 的 `logoForId` 和 34 张标志 | — | `icons/platform_logo.dart`、`assets/platforms/<平台 id>.png` | 见问题 9 |
| `widgets/menu_button.dart`（`MenuButton`）、`common_appbar_actions.dart`、`search_button.dart` | 182 | 不搬（I01.1 和页面任务） | 内容是路由跳转和设置项，属于首页外壳 |
| `widgets/download_apk_dialog.dart`、`download_directory_dialog.dart`、`share_command_import_dialog.dart` | 953 | 不搬（页面任务） | 更新下载、分享口令导入的页面流程，依赖下载服务和房间模型 |

- 被谁调用（3.x `lib/` 里本块以外的引用）：`AppTextStyles` 55 个文件 262 处；`buildTile` 95 处、`buildGroupTitle` 86 处、`buildModernCard` 74 处、`buildSwitchTile` 48 处、`buildSliderTile` 14 处；`PureLiveScrollPhysics` 61 处、`PureLiveBoundedScrollPhysics` 27 处；`AppStatusView` 37 处、`EmptyView` 11 处；`MenuButton` 16 处；`SectionTitle` 21 处；`RoomCard` 8 处；`createPureLiveScrollController`、`pureLiveTabTransitionDuration` 各 8 处；`ScrollableTabBar` 6 处；`MyTheme` 8 处（`main.dart`、主题和字体设置）。`SearchButton`、`LinkButton`、`CupertinoSwitchListTile`、`buildMenuTile` 没有调用者（死代码，不搬）。
- 问题（审查发现，每条都修了）：

| # | 问题 | 位置（3.x） | 根因 | 处理 |
|---|---|---|---|---|
| P1 | `MyTheme` 的标题栏设置（居中标题、无阴影、标题字重）从来没生效 | `main.dart:163`、`:167` | `lightTheme.copyWith(appBarTheme: const AppBarTheme(surfaceTintColor: ...))` 整个替换了 `MyTheme` 的 `appBarTheme` | 保留用户实际看到的外观：`LiveTheme` 直接给 `AppBarTheme(surfaceTintColor: transparent)`，标题对齐跟随平台（Android、Windows 靠左；3.x 只有几个页面自己写了居中，后来 D-011 定为 6 页）；死设置删掉 |
| P2 | 文字样式不跟着局部主题、也不登记依赖 | `style/app_text_styles.dart:7-10` | 静态 getter 读 `Get.theme` 和设置单例；对话框里的 `Theme` 覆盖读不到，字体设置变了只能靠整个应用重建 | 改为从 `Theme.of(context)` 读；字体大小已经在主题的文字主题里，结果和 3.x 相同 |
| P3 | 设置卡片靠类型名字认行 | `widgets/widget_extensions.dart:47-53` | `runtimeType.toString().contains('ListTile' / 'Obx')`；混淆构建下名字会变，任何 `Obx` 都被当成行，`buildTile(stackTrailingOnNarrow: true)` 返回的 `LayoutBuilder` 又认不出来，它两边少了分隔线 | 按类型判断（`ListTile`、`SwitchListTile`、`CheckboxListTile`、`RadioListTile`、`ExpansionTile`），再加标记 `CardTile`；`buildTile`、`buildSwitchTile` 的结果自带标记 |
| P4 | 滑块行每次布局泄漏两个 `TextPainter` | `widgets/widget_extensions.dart:387` | 量完宽度没有 `dispose()` | 量完立即释放 |
| P5 | 设置滑块用 Syncfusion（专有许可证） | `widgets/widget_extensions.dart:438` | — | 换成 Flutter 的 `Slider`，用 `settingsSliderTheme` 做成同样的样子（激活轨道 6、未激活 4、圆形滑块半径 10、主色、未激活主色 15%）；值超出范围时夹到范围内 |
| P6 | `buildSwitchTile` 要传 GetX 的 `RxBool` 并自己写回 | `widgets/widget_extensions.dart:114-151` | 组件和状态库绑死 | 改成 `value` + `onChanged`，由页面保存 |
| P7 | 长按 ± 连续调整时，父组件没来得及重建就会一直发同一个值 | `widgets/count_button.dart:167`、`:183` | 每 100 毫秒从 `widget.selectedValue` 算下一个值 | 记住上一步的值，父组件改值时再同步 |
| P8 | 刷新率：手指还按着时滚动结束就开始 1.5 秒倒计时；状态是全局静态的 | `widgets/adaptive_refresh_rate_scope.dart:140`、`:26-27` | 滚动结束被当成“抬起一根手指”，计数被减到 0；静态字段让多个窗口、测试共用一份 | 滚动结束只在没有手指时倒计时（`endScroll`）；控制器改成应用持有的对象，平台调用注入 |
| P9 | 不认识的平台 id 让卡片菜单抛异常 | `core/sites.dart:213` | `logoForId` 对未知 id `throw StateError` | `PlatformLogos.assetFor` 对未知 id 给应用标志（3.x 对已下线平台本来就这样） |
| P10 | 用户调大字体后，网格卡片的高度不够 | `widgets/room_card_layout.dart:47-50` | 按默认字号 15/13（紧凑 13/12）算高度，而卡片按设置里的字号画 | `RoomCardLayoutMetrics` 加 `fontSizes` 参数，默认值与 3.x 相同 |
| P11 | 加载动画尺寸看窗口宽度 | `widgets/app_status_view.dart:389` | `Get.width` | 改为 `MediaQuery.sizeOf(context).width`（同样是窗口宽度，行为不变，去掉 GetX） |

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| — | 没有出图：任务定为“外观照 3.x 的数值，只改结构和 bug”，没有需要用户选的外观改动 | 不用评审（模块重构，随 D-001 定的做法） |

## 对比页（按章节导出）

无（没有评审页，见上）。

## 单张图

无。

## 确认的改动

做法（任务开始时定，属于 D-001“在 3.x 代码上逐块重构”）：

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 保留 | **外观照 3.x**：主题、文字样式、卡片、状态页、设置块的尺寸、颜色、圆角、动画全部照抄 3.x 的数值 | — |
| c2 | 修改 | **去掉 GetX 和全局单例**：主题由 `LiveTheme(primaryColor | colorScheme, fontSizes, fontFamily)` 生成，字体大小（`LiveFontSizes`）由应用从设置传入；文字样式 `AppTextStyles` 从 `Theme.of(context)` 读（`context.textStyles.t13`），跟着主题重建；组件要的“设置”（多语言文字、加载动画样式和颜色、图片缓存管理器、图片请求头、缓存代数）放在 `LiveUiScope(config: LiveUiConfig(...))` 里，应用在根部放一次 | P2、P6、P8、P11 |
| c3 | 修改 | **页面逻辑留给页面**：3.x 的 `RoomCard` 在卡片里打开直播间、弹关注 / 标签 / 分享菜单；现在卡片只负责画，`onTap`、`onLongPress`（含右键）交给页面 | — |
| c4 | 修改 | 审查发现的 11 个问题按上表修 | P1～P11 |

保留的 3.x 行为：

- `t11`/`t12`、`t15`/`t16`、`t18`/`t20` 两两同一个字号（3.x 的命名和实际字号不一致，但改了会变样）。
- 深色动态色板把错误色换成 `#FF6347`；种子色生成的深色主题不换。
- 回放徽章用 `theme.primaryColor`：浅色是主色，深色是表面色（M3 的 `ThemeData` 就是这样给的）。
- 状态页的弹出动画（1 秒 elasticOut）、迷你模式在标题和说明为空时只显示图标。（后来 A02.1 c6 按确认的设计去掉了弹出动画。）
- 默认加载动画自带动画控制器，换样式时旧动画随之销毁。
- 卡片封面加载时只显示静态图标；图片不淡入、换地址时保留旧图；解码宽度 240～720（头像 48～256）。
- 卡片 JSON 读写保留 3.x 的旧键（`showPlatform`、`showSubtitle`、`showRecordBadge`、`cardBorderRadius`、`showAsListTile`）和 3.1.4 紧凑预设快照的修复。

有意差异：

| 差异 | 原因 |
|---|---|
| `buildSliderTile` 去掉第一个位置参数 `BuildContext` | 扩展本身就在 `BuildContext` 上，参数是多余的；页面替换时删掉这个实参即可 |
| `buildSwitchTile` 改为 `value` + `onChanged` | 去掉 GetX（P6） |
| `AppTextStyles.t13` → `context.textStyles.t13` | 去掉全局主题（P2） |
| `RoomCard` 的输入从 `LiveRoom` 换成 `RoomCardData`，外观从参数 `appearance` 传 | `live_ui` 不能依赖 `live_core`；设置由页面读 |
| 卡片可显示 `restrictionLabel`（封面左下角、紧凑行的徽章） | 已批准的统一原则“卡片标出受限类型”；不给就和 3.x 一样 |
| `buildMenuTile`、`SearchButton`、`LinkButton`、`CupertinoSwitchListTile` 不搬 | 3.x 里没有调用者 |
| 图标字体、平台标志随 `live_ui` 打包，平台标志按平台 id 命名 | 页面和应用不再自己管理这些资源 |

## 按钮的作用和用法

无：组件的操作方式照 3.x 不变（卡片点按进房、长按和右键交给页面；计数点按和长按连加；标签条滚轮横滚）。

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 同 3.x；刷新率三档只在 Android（`AdaptiveRefreshRateScope`，应用的 `apply` 调原生的刷新率接口） |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 同 3.x；Windows 字体默认微软雅黑（`resolveAppFontFamily`），滚轮用 Chromium 的平滑曲线（`createPureLiveScrollController`） |
| 电视 | 当时不涉及；电视的设计系统在 A17.1 |
| 苹果平台差异 | 列表照 3.x 用 Bouncing（`PureLiveScrollPhysics`） |

## 待选和决定

无（没有需要用户选的外观改动）。

## 实现和验证

- 对外接口（`package:live_ui/live_ui.dart`，2026-10-01 时）：

| 方面 | 接口 |
|---|---|
| 主题 | `LiveTheme`（`.light`、`.dark`）、`LiveFontSizes`、`resolveAppFontFamily`、`appPageTransitionsTheme`、`AppTextStyles`（`context.textStyles`） |
| 动态取色 | `LiveDynamicColorBuilder`（系统色板已转成 Flutter 的 `ColorScheme`）、`toFlutterColorScheme`、`MaterialUiThemeBridge` |
| 设置传入 | `LiveUiScope`、`LiveUiConfig`、`LiveUiStrings`（`zh`、`en` 是 3.x 的原文） |
| 状态页 | `AppStatusView`、`AppStatusType`、`EmptyView`、`LoadingStyles`（85 种加载动画）、`DefaultLoadingIndicator` |
| 房间卡片 | `RoomCard`、`RoomCardData`、`RoomAudience`、`RoomAudienceKind`、`RoomCardAppearance`（含预设和 JSON 读写）、`RoomCardLayoutMetrics`、`CountChip`、`CoverMetricBadge` |
| 图片 | `CommonAvatar`、`LiveNetworkImage` |
| 设置页积木 | `context.buildGroupTitle / buildModernCard / buildSwitchTile / buildTile / buildSliderTile`、`CardTile`、`settingsSliderTheme`、`SectionTitle`、`MenuListTile`、`settingsContentMaxWidth` |
| 其他组件 | `CountButton`、`ScrollableTabBar`、`QrCodeWidget`、`KeepAliveWrapper`、`EmoteText`（`ChatSegment`） |
| 滚动 | `PureLiveScrollPhysics`、`PureLiveBoundedScrollPhysics`、`createPureLiveScrollController`、`PureLiveRouteScrollScope`、`pureLiveTabTransitionDuration` |
| 刷新率 | `AdaptiveRefreshRateController`、`AdaptiveRefreshRateScope`、`RefreshRateMode` |
| 图标 | `CustomIcons`（3.x 的图标字体，随包打包）、`PlatformLogos` / `PlatformLogo`（34 个平台标志 + 应用标志）、再导出 `remixicon`（3.x 页面用了 454 处） |

- 已批准的升级（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）里和本任务有关的：

| 编号 | 本任务的部分 | 当时的状态 |
|---|---|---|
| B-11 niconico 评论位置和字体 | 屏幕弹幕层在直播间，`live_ui` 里没有对应组件；模型已有 `LiveMessagePlacement` | 本任务不涉及，余下给直播间 |
| B-12 CHZZK 表情图片 | `EmoteText`：文字和表情图混排，图高 1.4 倍字号、居中、加载中或失败显示表情代码 | 部分完成，余下：消息模型带表情片段（`live_core`、`live_danmaku`）、直播间接入 |
| B-13 YouTube 频道表情图片 | 同 B-12 | 部分完成，余下同上 |
| B-14 17LIVE 名字颜色、徽章 | 聊天行的样子属于直播间页面 | 余下给直播间 |

- 交给其他任务的部分：
  - **J02.1（设置存储）**：主题模式、主题色、动态取色开关、字体大小和字体、加载样式和颜色、卡片外观（每种屏幕一份和预设记忆）的读写和迁移；`RoomCardAppearance.fromJson/toJson` 可直接用。
  - **I01.1（应用骨架）**：`MaterialApp` 用 `LiveDynamicColorBuilder` + `LiveTheme(...).light/.dark` + `themeMode`；`builder` 里放 `LiveUiScope`、`MaterialUiThemeBridge`、Android 的 `AdaptiveRefreshRateScope`（控制器的 `apply` 调原生的刷新率接口）、文字缩放；`MenuButton`、`CommonAppBarActions`（路由菜单）；`MyCustomScrollBehavior`（在 3.x `desktop_manager.dart`）用 `PureLiveScrollPhysics`；应用的 `pubspec.yaml` 要有 `uses-material-design: true`。
  - **页面任务**（当时的页面模块，后来在 C01.1、I02～I05、A09.1 等）：卡片的长按菜单（关注、标签、分享）、`FollowButton`、关注确认框；把 `LiveRoom` 换成 `RoomCardData`（观众数格式化、受限文字）；更新下载框、下载目录框、分享口令导入框；B-11、B-12～B-14 的接入。
  - **图片地址规范化和请求头**：3.x 的 `normalizeNetworkImageUrl`、`networkImageHeaders` 由应用实现后放进 `LiveUiConfig.imageHeaders`，地址在建 `RoomCardData` 时规范化。
- 依赖变化：新增（当时都是最新稳定版）`cached_network_image 4.0.4`、`flutter_cache_manager 3.4.5`、`dynamic_color 2.1.0`、`material_ui 1.5.0`、`flutter_spinkit 5.2.2`、`loading_animation_widget 1.3.0`、`loading_indicator 4.0.2`、`qr 4.0.0`、`remixicon 4.9.3`、`scroll_animator 0.3.0`；开发依赖 `flutter_test`、`very_good_analysis 11.0.0`。去掉 `syncfusion_flutter_sliders`（专有许可证，P5）。根 `pubspec.yaml` 加了 `dependency_overrides: test_api: 0.7.14`：这是第一个 Flutter 成员，Flutter 3.47.5 的 `flutter_test` 固定 `test_api 0.7.12`，而纯 Dart 包用的 `test 1.32.0` 要 0.7.14；`flutter_test` 在 0.7.14 上运行正常（本包测试全部通过）。归档 v4 用的是同一个覆盖。
- 提交：`c8f1ca08d`（`feat(live_ui): theme, shared widgets and icons`，67 个文件、+5000 行）；合并提交 `aaf8ac461`（2026-10-01）。登记表写的是前者。
- 自动测试（当时 `packages/live_ui/test/` 共 35 个）：
  - `theme_test.dart`（7）：字体选择；字号和字重跟随设置；字体名到达每个样式；标题栏和页面切换（P1）；动态色板和深色错误色；`toFlutterColorScheme`；文字样式读局部主题（P2）。
  - `status_view_test.dart`（6）：空状态默认文字；错误状态重试和英文文字；迷你模式；加载样式和颜色；85 种样式和回退；每种样式都能建出来。
  - `room_card_test.dart`（9）：封面布局（标题、主播、字母头像、观众、封面兜底、自动平台标）；待刷新和未开播；详细预设、回放、受限、核验中、删除；点击、长按、右键；紧凑布局和窄卡片；网格高度跟随字号（P10）；外观的往返、预设、旧键、3.1.4 快照修复和严格模式。
  - `widgets_test.dart`（13）：平台标志齐全、未知 id 回退（P9）；图标字体打包；字母头像；设置卡片分隔线含窄屏堆叠行（P3）和开关回调；滑块行；标题积木；`CountButton` 点按和长按连续（P7）；刷新率均衡模式（P8）和性能模式；`EmoteText`；二维码尺寸；`ScrollableTabBar` 滚轮滚动。
- 真机：没有单独的 `verify.md`。`live_ui` 的主题、图标、状态页、卡片在 S02.2 的 K90 冒烟（2026-10-02，提交 `288fec0ec` 的 arm64 profile）里随主流程看过：首页关注和热门的卡片、直播间控制层图标、设置总览和视频页都“通过”（[S02.2 记录](../../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md)）。
- 后来的变化（以现在的代码为准，接口表是 2026-10-01 的）：
  - 3.x 的设置构建函数（`buildGroupTitle` 等）、`CardTile`、`settingsSliderTheme`、`SectionTitle`、`MenuListTile`、960 的 `settingsContentMaxWidth` 在 A02.1 被 A11.1 的 `SettingsGroup`/`SettingsRow` 一族和 720 的 `ReadableContent` 取代并删除（`packages/live_ui/lib/src/widgets/settings_tiles.dart:3-8` 的注释）。
  - 旧 `RoomCard`、`CoverMetricBadge`、`CountChip` 被 A09.1 的 `LiveRoomCard`（`live_room_card.dart:36`）取代并删除；`room_card.dart` 只剩 `RoomCardData`、`RoomAudience`、`RoomAudienceKind`。
  - `AppStatusView` 的 1 秒弹出动画在 A02.1 c6 去掉；标题对齐在 A02.1 按 D-011 改成 `centredPageTitle`。
  - `live_ui` 现在有 42 个组件文件、18 个测试文件，见[子分类页](../README.md)的代码地图。
- 留下的问题：无（本任务范围内）。后续的设计系统工作在 [A01.2](../A01.2-颜色、文字、间距、动效/README.md)、[A01.3](../A01.3-图标/README.md)。
