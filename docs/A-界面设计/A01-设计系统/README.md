# A01 设计系统

`live_ui` 的主题和图标：颜色角色、文字角色和字号、组件主题、页面切换、按用途命名的图标，以及应用怎么把用户的外观设置变成这套主题。页面只用这里的角色和图标名，不直接写颜色、图标常量。

## 范围

- 包括：
  - `packages/live_ui/lib/src/theme/` 的 `live_theme.dart`（主题、组件主题、字体、字号）、`text_styles.dart`（3.x 的命名文字样式、文字缩放）、`live_colors.dart`（画面上的颜色、语义色、纯黑、色板）、`dynamic_color.dart`（系统色板）；`tv_colors.dart` 的文件在这里，内容由 A17.1 定。
  - `packages/live_ui/lib/src/icons/` 全部（`AppIcons`、`CustomIcons`、`DanmakuIcon`、`PlatformLogos`、`TvIcons`）和资源 `packages/live_ui/assets/fonts/CustomIcons.ttf`、`assets/images/video/danmu_open.svg`、`danmu_close.svg`、`danmu_setting.svg`、`assets/platforms/*.png`（36 张）。
  - `packages/live_ui/lib/src/scope.dart`：组件要的文字（`LiveUiStrings`）和设置（`LiveUiConfig`）。
  - 应用里把设置变成主题的一段：`apps/pure_live/lib/app/app.dart:153-250`、`apps/pure_live/lib/i18n/i18n.dart:107`、`apps/pure_live/lib/app/fonts.dart`（下载字体的注册）。
  - 门禁“界面结构”的第 2 条（`features/`、`tv/` 不直接写 `Color(0x…)`、`Colors.*`、`Icons.*`、`Remix.*`）：`tools/gate/check_ui_structure.py`、`tools/gate/ui_baseline.json`。
- 不包括（归哪里）：
  - `theme/motion.dart`（弹簧、快滑阈值）→ [A03](../A03-动效和手感/README.md)；`theme/grid_columns.dart`（宽度分档、网格列数）→ [A04](../A04-尺寸和适配/README.md)。
  - 组件本身（`packages/live_ui/lib/src/widgets/`）→ [A02](../A02-组件/README.md)；对比度、焦点、读屏的全应用检查 → [A05](../A05-无障碍/README.md)。
  - 外观设置页（主题色、动态取色、纯黑、字号、字体、加载样式的界面）→ A11.2；这些设置的存取和 3.x 迁移 → J02.1、J06。
  - 电视的设计系统（`TvColors`、`TvIcons` 的内容、焦点放大）→ A17.1；录制图形 `RecordGlyph` → A10.3。

## 现状：做到哪、怎么工作的

- 用户看得到的：
  - 颜色：Material 3，用户的主题色作种子，默认品牌蓝 `#2E6FE0`（白字 4.7:1，A11.2 C-3），用 fidelity 方案让主色保持选中的颜色；3.x 默认的 `Colors.blue`（`FF2196F3`）覆盖安装时迁移成品牌蓝（`packages/live_store/lib/src/legacy/legacy_rules.dart:24`）。可选动态取色（Android 12+、Windows），深色的动态色板把错误色换成 `#FF6347`（照 3.x）。深色可选“纯黑”（A11.2 C-4，默认关）。浅色、深色、跟随系统；电视只有深色。
  - 画面上（播放器、全屏、多画面、画中画、小窗）所有主题下都是黑底白字，控制条下 60% 黑渐变，白字在最亮的画面上也有 5.7:1（`OnVideoColors`）。“直播”红 `#D92D20` 配白字、录制红、成功绿、警告黄固定不随主题（`LiveSemanticColors`）。
  - 文字：五个字号设置（正文小 12、正文 13、正文大 14、标题中 15、标题大 20）派生全部文字样式；“文字大小”（0.5～2 倍）乘在系统字号上（A11.2 C-5，3.x 是替换系统字号）；Windows 默认微软雅黑，可以下载字体设为应用字体。人数、码率、时长用等宽数字。
  - 组件主题：去掉水波；标题栏无阴影、标题照 3.x 实际运行的样子靠左（录制中心、热门、分区、工具箱、观看记录、关注 6 页居中，D-011）；按钮、芯片、标签有键盘焦点框；卡片圆角 16、列表行 12（标题 15/400）、输入框 12、对话框 24（标题 20/600、正文 14）、底部面板顶角 16、提示条反色圆角 8；页面切换 `FadeForwards`（Android、Windows）。
  - 图标：每个位置照 3.x 用的图标（Remix、Material、3.x 自带的 `CustomIcons`、弹幕开关三张 SVG），页面按用途取名；34 个平台标志加网络电视和应用标志，不认识的平台给应用标志。
- 内部怎么工作：

```text
设置（packages/live_store/lib/src/settings/settings.dart：themeMode、themeColorSwitch :155、enableDynamicTheme :150、
      pureBlackTheme :165、fontSize* :204 起、fontFamilyName :249、textScaleFactor :200、loadingStyle :192 …）
  → apps/pure_live/lib/app/app.dart:153-185  watchSetting → ThemeMode、种子色 parseThemeColor（:269）、LiveFontSizes、
                                              resolveAppFontFamily、LiveUiConfig（文字 _strings.ui = i18n.dart:107）
  → :187-208  LiveDynamicColorBuilder（系统色板已转成 Flutter 的 ColorScheme）→ LiveTheme(...).light / .dark
  → :209-222  MaterialApp.router(theme, darkTheme, themeMode；电视固定深色)
  → :223-250  builder：MaterialUiThemeBridge → AdaptiveRefreshRateScope（Android）→ DesktopFrame →
              LiveUiScope(config) → MediaQuery(textScaler: AppTextScaler(系统, 文字大小))
  → 页面：Theme.of(context).colorScheme、context.textStyles.t13、AppIcons.xxx、OnVideoColors、LiveSemanticColors
```

  主题是普通对象：设置一变，`watchSetting` 让 `MaterialApp` 拿到新的 `ThemeData`，读 `Theme.of` 和 `context.textStyles` 的组件跟着重建（3.x 读 `Get.theme` 和设置单例，局部 `Theme` 读不到，A01.1 P2）。
- 完成度（和 3.x 对照）：
  - 一致的：五个字号和派生比例（`live_theme.dart:221-242` 对 3.x `lib/common/style/theme.dart:57-87`）、字重常量、组件主题的圆角、深色动态错误色、页面切换、`AppTextStyles` 的名字和字号（`t11`/`t12`、`t15`/`t16`、`t18`/`t20` 两两同号）、每个位置的图标。
  - 确认过的改动：品牌蓝和 fidelity、纯黑（A11.2 C-3、C-4）；文字大小乘系统字号（C-5）；标题对齐照 3.x 运行时（D-011）；焦点框（A02.1 c21）；对话框正文 14、标题 20/600（A02.2 c5）；底部面板顶角 24 → 16、表面色（A02.2）；列表行标题 15/400（A02.1 c16、C3）；画面上的颜色一组角色（A07.1）；不认识的平台给应用标志（A01.1 P9）。
  - 还缺的：间距没有常量，应用页面里的圆角和时长大多还写数字（`AppRadii`、`AppDurations` 只用在主题和 `live_ui` 组件）；直播间和画面上的字号还写死；同一个图标两种意思的几组等维护者定（见“已知问题”）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_ui/lib/live_ui.dart` | 包的出口：导出 `src/` 的主题、图标、组件，再导出 `remixicon`；`dynamic_color.dart` 只导出 `LiveDynamicColorBuilder`、`MaterialUiThemeBridge`、`toFlutterColorScheme`；`anchored_menu.dart` 不导出 |
| `packages/live_ui/pubspec.yaml` | 依赖（`dynamic_color`、`material_ui`、`remixicon`、`flutter_svg`、三个加载动画库、`cached_network_image`、`qr`、`scroll_animator`）；打包 `assets/images/video/`、`assets/platforms/` 和 `CustomIcons` 字体 |
| `packages/live_ui/lib/src/theme/live_theme.dart` | `appPageTransitionsTheme`（`:12`，Android、Windows 用 `FadeForwards`）；`centredPageTitle`（`:24`，D-011 的 6 页）；`FocusFrame`（`:31`，按钮的键盘焦点框）；`_TabOverlay`（`:64`，标签悬停和按下的底色）；`resolveAppFontFamily`（`:88`，下载的字体 > Windows 微软雅黑 > 系统字体）；`LiveFontSizes`（`:101`，五个字号，默认 12/13/14/15/20）；`LiveTheme`（`:159`）：`brandBlue`（`:177`）、`legacyBlue`（`:180`）、字重常量（`:183-192`）、`darkDynamicError`（`:195`）、`_textTheme`（`:221`，五个字号派生全部样式）、`_build`（`:244`，色板、纯黑、组件主题 `:268-378`：标题栏、标签、芯片、按钮焦点框、卡片、列表行、输入框、底部面板、对话框、提示条） |
| `packages/live_ui/lib/src/theme/text_styles.dart` | `AppTextStyles`（`:19`，3.x 的 `t11`～`t32Bold` 从当前主题读）；`context.textStyles`（`:167`）；`AppTextScaler`（`:175`，系统缩放 × 应用“文字大小”，保留系统的非线性曲线；上限归 A04.1） |
| `packages/live_ui/lib/src/theme/live_colors.dart` | `OnVideoColors`（`:9`，画面上的前景、次要白、渐变、状态遮罩、手势卡片、芯片、黄色“非默认”）；`LiveSemanticColors`（`:160`，直播红、录制红、成功、警告、提醒底色，深浅各一套）；`WindowButtonColors`（`:248`，桌面关闭按钮红，A16.1）；`InkOnColor`（`:258`，平台给的颜色上按对比度选深字或白字）；`LiveTextStyleX`（`:299`，`tabular`、`regular`、`emphasis`）；`LivePureBlack`（`:314`，纯黑的几层表面）；`LivePalettes`（`:345`，颜色选择器的推荐色和 Material 色板）；`LiveTvColors`（`:394`，电视焦点框的近白） |
| `packages/live_ui/lib/src/theme/dynamic_color.dart` | `toFlutterColorScheme`（`:14`，dynamic_color 2.x 的色板转成 Flutter 的 `ColorScheme`）；`toMaterialUiColorScheme`（`:74`）、`toMaterialUiThemeData`（`:152`）；`MaterialUiThemeBridge`（`:177`，把应用主题同步给 `material_ui`，否则颜色选择器等用浅色兜底）；`LiveDynamicColorBuilder`（`:195`） |
| `packages/live_ui/lib/src/theme/tv_colors.dart` | `TvColors`（`:6`）：电视焦点环 `#F1F3F9`、对话框遮罩、关注的粉色（A17.1） |
| `packages/live_ui/lib/src/icons/app_icons.dart` | `AppIcons`（`:12`）：485 个用途名、350 个字形，按区域分节（首页外壳 `:13`、直播间 `:84` 起、录制中心、桌面标题栏、切换直播间、`live_ui` 组件在最后）；每个名对应 3.x 在那个位置用的图标，每个名至少用一处（门禁第 4 条） |
| `packages/live_ui/lib/src/icons/custom_icons.dart` | `CustomIcons`（`:10`）：3.x 自带图标字体的 13 个字形，`fontPackage: 'live_ui'` |
| `packages/live_ui/lib/src/icons/danmaku_icon.dart` | `DanmakuIconKind`（`:5`，开、关、设置）、`DanmakuIcon`（`:24`）：3.x 的三张 SVG 像 `Icon` 一样画，带控制层的阴影 |
| `packages/live_ui/lib/src/icons/platform_logo.dart` | `PlatformLogos`（`:6`，35 个平台 id 的标志路径，不认识的给 `app.png`）、`PlatformLogo`（`:34`） |
| `packages/live_ui/lib/src/icons/tv_icons.dart` | `TvIcons`（`:9`）：电视外壳的 49 个用途名（A17.1） |
| `packages/live_ui/lib/src/scope.dart` | `LiveUiStrings`（`:9`，组件用到的 35 条文字，`zh`、`en` 是 3.x 原文）；`ImageHeadersResolver`（`:213`）；`LiveUiConfig`（`:218`，文字、加载样式和颜色、图片缓存、请求头、缓存代数）；`LiveUiScope`（`:289`） |
| `apps/pure_live/lib/app/app.dart` | `:153-185` 读外观设置；`:187-222` 建主题和 `MaterialApp`；`:223-250` 根部的桥接、刷新率、桌面框、`LiveUiScope`、文字缩放；`parseThemeColor`（`:269`）；`AppScrollBehavior`（`:283`，归 A03） |
| `apps/pure_live/lib/i18n/i18n.dart` | `:107` 把当前语言的翻译交给 `LiveUiStrings` |
| `apps/pure_live/lib/app/fonts.dart` | 下载字体的注册（`resolveAppFontFamily` 用的 `registered`） |
| `apps/pure_live/lib/app/launch_failure.dart` | `:74-75` 启动失败页用默认 `LiveTheme()` |
| `packages/live_ui/lib/src/theme/metrics.dart` | `AppRadii`（卡片 16、按钮 12、文字按钮 8、列表行 12、输入框 12、对话框 24、小菜单 8、芯片 8、面板顶角和侧边 16）、`AppDurations`（100、150、200、300 毫秒），A01.2 |
| `tools/gate/check_ui_structure.py`、`tools/gate/ui_baseline.json` | 第 2 条：`features/**`、`tv/**` 不直接写颜色和图标（`scan` `:36`）；基线 `raw_styles` 现在是空的（0 处） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_ui/test/theme_test.dart`（7） | 字体选择；字号和字重跟随设置；字体名到每个样式；标题栏和页面切换（3.x `main.dart` 的覆盖）；动态色板和深色错误色；`toFlutterColorScheme`；文字样式读局部主题 |
| `packages/live_ui/test/design_system_test.dart`（11） | `AppIcons` 对照表（`:18` 起，每个用途对 3.x 的字形）；`OnVideoColors.accent`；`DanmakuIcon`；`RecordGlyph` 四条；`ListenableSelector`；画面上的颜色角色；`AmbientBackdrop`；关闭按钮红和录制提示 4.5:1 |
| `packages/live_ui/test/widgets_test.dart` 的 icons 组 | 平台标志齐全、不认识的 id 给应用标志；图标字体随包打包；`InkOnColor.contrastOn` |
| `packages/live_ui/test/settings_row_test.dart` 的 theme 组 | 品牌蓝和 fidelity（C-3）、纯黑（C-4）、文字大小（C-5） |
| `packages/live_ui/test/components_test.dart` | 深浅主题下的对比度（`:166-168`、`:222-224`、`:501-504`）、焦点框只在键盘时 |

## 3.x 基线

- `lib/common/style/theme.dart`（186 行）：`appPageTransitionsTheme`（`:4-13`）；`resolveAppFontFamily`（`:21-33`）；`MyTheme`（`:35`）的字重常量（`:41-44`）、文字主题（`:57-87`，五个字号派生）、深色动态错误色 `#FF6347`（`:97`）、`NoSplash`（`:114`）、标题栏（`:115-121`，居中、600——被 `lib/main.dart:162-169` 整个替换，从没生效，D-011）、标签栏（`:122-130`）、卡片 16（`:131-136`）、实心按钮 12（`:137-144`）、文字按钮 8（`:145-150`）、列表行 12 标题 14/500（`:151-158`）、输入框 12（`:159-170`）、底部面板顶角 24（`:171-176`）、对话框 24（`:177-183`）。
- `lib/common/style/app_text_styles.dart`（77 行）：静态 getter 读 `Get.theme` 和设置单例（`:7-10`），`t11`～`t32Bold`。
- `lib/common/styles/dynamic_color_adapter.dart`（183 行）：`toFlutterColorScheme`（`:12`）、`MaterialUiThemeBridge`（`:174`）。
- `lib/common/services/settings/theme_settings_controller.dart:13`（默认 `Colors.blue`）、`:18-19`（动态取色、主题色）；`font_settings_controller.dart:15-33`（文字大小 0.5～2，五个字号的默认值和范围）；`lib/main.dart:184`（`TextScaler.linear` 替换系统字号）。
- 图标：没有统一入口，页面直接写 `Remix.*`（193 种）、`Icons.*`（182 种）、`CustomIcons.*`（`lib/common/widgets/custom_icons.dart`，13 个字形，字体 `assets/icons/CustomIcons.ttf`）；弹幕开关是 `assets/images/video/danmu_*.svg`；平台标志 `lib/core/sites.dart:209-215` 的 `logoForId`（不认识的 id `throw StateError`，`:213`）。
- 必须保留的操作习惯：本子分类没有操作；外观上保留五个字号设置、字体设置、主题色和动态取色的含义（D-018）、每个位置的图标（[specs/UI.md](../../specs/UI.md) 第 3 节第 2 条）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 应用页面的圆角、时长还写数字；间距没有常量 | `BorderRadius.circular(n)` 应用 139 处（直播间另有 56 处）；`Duration(milliseconds: …)` 应用 36 处（直播间另有 23 处，含计时器） | 改圆角和时长要逐处找 | 常量已有（A01.2），改到哪个页面顺手换 |
| 直播间和画面上的字号写死 | `features/live_play/` 的 `fontSize: <数字>` 54 处；`live_ui` 的 `video_state_view`、`record_glyph`、`pip_danmaku_preview` | 调五个字号设置时直播间的字不变 | 直播间任务定要不要跟（规范只说画面上随系统放大最多 1.3 倍）；其余页面 A01.2 已改，门禁第 5 条锁住 |
| 同一字形几种意思（`tv_2_line` 4 种、`cloud_line` 3 种、`heart_3_line` 4 种） | `app_icons.dart`，建议见 A01.3 README“待选和决定” | 设置、网络电视、多画面里同一个图标表示不同的事 | 维护者按 D-003 定，定了只改 `app_icons.dart` |
| 电视的焦点白有两份、值不同 | `live_colors.dart:417`（`LiveTvColors.focusFrame` `#F2F2F2`，`settings_row.dart:513` 用）和 `tv_colors.dart:10`（`TvColors.focusRing` `#F1F3F9`，电视外壳用） | 设置行在电视上的焦点框和其他电视控件差一点点 | 没有任务管，建议在 A17 登记一个小任务合成一个 |
| 代码注释里还有旧编号和旧文件名（`U.1c`、`U.6b C-3`、`UI_PLAN §5.3`、`P02` 等） | `packages/live_ui/lib` 147 处，其中 `UI_PLAN` 在 `live_ui` 和应用共 52 处 | 按注释找文档时要先查 [MAPPING.md](../../MAPPING.md) | 没有任务管，建议在 Z 组登记一次性替换 |

## 相关决定和规范

- D-001（照 3.x 逐块重构）、D-003（“需要你选的”按建议 A）、D-005（文字中文、走翻译）、D-011（标题位置照 3.x 实际运行的样子）、D-018（3.x 的设置键名和含义不变：主题色、动态取色、字号、字体）。
- [specs/UI.md](../../specs/UI.md) 第 3 节第 2 条（图标照 3.x）、第 6 条（一个动作一个图标）；第 8.1～8.4 节（颜色、文字、间距圆角、图标）；第 10 节（门禁：`features/`、`tv/` 不直接写颜色和图标）；第 14 节 C-2（换 Material Symbols Rounded，待定）、C-3、C-4、C-7。
- [specs/ENGINEERING.md](../../specs/ENGINEERING.md) 第 4 节（`live_ui` 不依赖其他 `live_*` 包，`tools/gate/check_deps.py`）、第 7 节（颜色和图标从 `live_ui` 取）。

## 测试和验证

- 自动测试：`cd packages/live_ui && flutter test`（主题、图标、颜色角色的测试见上表；`metrics_test.dart` 是圆角、时长、字重和字号跟设置走）；`python3 tools/gate/check_ui_structure.py`（第 2 条直接写的颜色和图标，扫 `features/`、`shared/`、`tv/` 和 `live_ui` 组件；第 4 条每个 `AppIcons` 名至少用一处；第 5 条直播间、电视以外不写死字号、字重只有 400/600）。
- 真机：没有单独的清单；主题和图标随 [S02.2](../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md) 的 K90 冒烟看过（首页卡片、直播间控制层图标、设置总览和视频页“通过”）。[S02 的真机清单](../../S-质量和验证/S02-真机验证/CHECKLIST.md)里相关的：第 1 节第 19 条（深浅色下状态栏、导航栏图标看得清）、第 5 节第 5 条（下载字体设为应用字体，重启后还在）。A01.2、A01.3 完成后照它们的任务书看。

## 路线

1. [A01.2](A01.2-颜色、文字、间距、动效/README.md)、[A01.3](A01.3-图标/README.md) 第 3 阶段做完（2026-10-08，待真机）：照两个任务书的“真机验证”在 K90 上看；字重从 500 改成 600 / 400 是看得见的改动，看着别扭可以改回。
2. 等维护者定：A01.3 README 里同一字形几种意思的 G2～G4；直播间的字号要不要跟五个字号设置走（直播间任务）。
3. 以后：C-2（全换 Material Symbols Rounded）待定，`AppIcons` 已经是换库只改一处的结构；电视焦点白合并（A17）；代码注释的旧编号（Z）。新想法写进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：`packages/live_ui/lib/src/theme/`、`icons/`
- 进度：`███████████████████░` 97%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A01.1 | 界面基础：主题、通用组件、图标（模块重构） | 界面 | 完成 | 2026-10-01 | c8f1ca08d | [设计或说明](A01.1-界面基础/README.md)、[记录](A01.1-界面基础/record.md) |
| A01.2 | 颜色、文字、间距、动效 | 界面 | 待真机 | 2026-10-08 | 52a429e8e | [设计或说明](A01.2-颜色、文字、间距、动效/README.md)、[任务书](A01.2-颜色、文字、间距、动效/brief.md)、[记录](A01.2-颜色、文字、间距、动效/record.md) |
| A01.3 | 图标 | 界面 | 待真机 | 2026-10-08 | cf5988255 | [设计或说明](A01.3-图标/README.md)、[任务书](A01.3-图标/brief.md)、[记录](A01.3-图标/record.md) |
| A01.4 | 全局细节打磨：单字折行、说明截断、空状态标点、图标含义、最小字号、输入框计数位置 | 界面 | 完成 | 2026-10-08 | 24142b783 | [设计或说明](A01.4-全局细节打磨/README.md)、[任务书](A01.4-全局细节打磨/brief.md)、[记录](A01.4-全局细节打磨/record.md) |

<!-- docs:生成结束 -->
