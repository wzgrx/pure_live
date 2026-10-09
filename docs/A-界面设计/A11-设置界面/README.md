# A11 设置界面

设置的样子和操作：总览的五组、搜索、宽屏两栏，外观、播放、通用和网络、数据各分页的分组、行、对话框，以及所有设置页共用的设置行组件；设置项本身的键名、默认值和存储不在这里。

## 范围

- 包括：
  - 设置总览（A11.1）：`features/settings/settings_page.dart` 的五组 17 行（界面、直播来源、播放、通用和网络、数据）、搜索（Ctrl+F / Cmd+F、Esc 清空）、宽 840 起左右两栏；目录驱动的页（`settings_model.dart`、`settings_section_view.dart`）；`live_ui` 的设置行组件（跳转、开关、滑块、计数、选项五种，`packages/live_ui/lib/src/widgets/settings_row.dart`，A02.1 的设置行部分）和绑定设置的行（`settings_tiles.dart`）。
  - 外观（A11.2）：外观页四组（主题、房间卡片和列表、语言和界面、字体和字号）和从它进去的页（主题颜色、加载动画、房间卡片设置、分页设置〔电脑〕、字体、精细化字号）、导航栏显示控制；候选改动 C-3 品牌蓝、C-4 纯黑、C-7 文字大小在界面上的部分。
  - 播放（A11.3）：视频页六组、竖屏直播适配、观看数据与排行口径（含各平台口径说明页）、播放内核、MPV 驱动选项页、小窗弹幕页（带预览）、弹幕样式页。
  - 通用和网络（A11.4）：通用（显示、启动、更新、窗口〔Windows〕、定时退出、分享）、平台显示与授权、刷新设置、网络与代理设置四页和它们的对话框。
  - 数据（A11.5）：缓存与数据管理、本地配置预览两页；总览“数据”组的“日志管理”入口。
  - 设置共用的对话框：选项对话框（主色 + 勾）、确认、时长和数字、颜色（`settings_dialogs.dart`）。
- 不包括（归哪里）：
  - 设置项本身（键名、默认值、迁移、存储、生效位置）→ [J01 设置](../../J-设置和数据/J01-设置/README.md)，键名和含义不变（D-018）；逐条核对 → J01.2。
  - 总览“弹幕”行打开的弹幕页 `features/settings/danmaku_page.dart`（直播间同一个 `DanmakuSettingsContent`）和弹幕屏蔽页 → [A08](../A08-弹幕界面/README.md)（A08.3、A08.5、A08.6）；本地用户与互动页 → A08.2；录制设置页 → [A10.2](../A10-录制界面/A10.2-录制设置/README.md)；备份、WebDAV、设备同步、账号、日志页 → [A12](../A12-账号和数据界面/README.md)；网络电视管理 → [A13.1](../A13-网络电视和多画面界面/A13.1-网络电视管理/README.md)。这些页的入口行在总览里，属于 A11.1。
  - 刷新率策略本身 → [R02](../../R-性能和流畅度/R02-刷新率/README.md)；后台播放、助眠的权限申请 → O03.2；关窗口时的询问对话框和窗口最小尺寸 → [A16.1](../A16-桌面界面/A16.1-桌面窗口/README.md)；电视的设置面板（`tv/pages/tv_settings_pane.dart`，复用 `settings_catalog.dart` 的选项表）→ [A17.9](../A17-电视界面/A17.9-电视设置/README.md)；iOS、macOS 的差异 → A18.1、A18.2。
  - 颜色角色、字体、动效等设计系统本身 → A01；`AppDialog`、提示条等弹窗组件 → A02.2；小菜单 → A02.3。

## 现状：做到哪、怎么工作的

- 用户看得到的（A11.1～A11.5 都登记为完成，2026-10-01～02 合并）：
  - **总览**：首页 ≡ 菜单“设置”（路由 `RoutePath.kSettings`）打开。五组卡片：界面（外观、导航栏显示控制）、直播来源（平台显示与授权、刷新设置、网络电视）、播放（视频、弹幕、小窗弹幕、播放内核、录制）、通用和网络（通用、网络与代理设置、本地互动体验）、数据（缓存与数据管理、备份与恢复、本地配置预览、日志管理）；每行图标、标题、最多两行说明（“弹幕”行用 3.x 的弹幕设置图片 `DanmakuIcon`）。宽 <840 一栏（600～839 最宽 720 居中）；宽 840 起左边总览 360、右边打开的页最宽 720 靠左，右栏里再打开的页也在右栏、带返回，跨过 840 时保留打开的页。顶上搜索框：输入停 150 毫秒后过滤，每个词都要在标题或说明里出现，结果就是设置行本身（开关、滑块、选项可以直接改），按“页面 › 分组”分组并标出关键词；会打开别的页的行进到那一页并把它高亮 1.5 秒。窗口高 <480（横屏手机）时所有设置页顶栏 48 高。
  - **外观**：主题（主题模式、纯黑背景、主题颜色、动态取色、加载动画）→ 房间卡片和列表（房间卡片设置、列间距、行间距、一键置顶按钮、分页设置〔只在电脑上〕）→ 语言和界面（切换语言、界面模式）→ 字体和字号（字体、文字大小、精细化字号）。默认主题色是品牌蓝 #2E6FE0（fidelity 配色，3.x 默认蓝迁移一次）；纯黑背景默认关、浅色时变灰；文字大小 50%～200% 叠在系统字号上。
  - **播放**：视频页六组（音频、画质、播放行为、后台与助眠〔手机；后台播放 Android 和 iOS，助眠只在 Android〕、小窗、弹幕）；竖屏直播适配和观看数据是视频页的子页；播放内核四组（内核固定 mpv、解码、网络、MPV 高级设置）；MPV 驱动选项是整页单选；小窗弹幕页预览在上（宽 ≥840 或横屏时左右两栏）；依赖项变灰不消失并写“打开……后生效”；各页“恢复默认”是最后一行红字、先确认。
  - **通用和网络**：界面刷新率（档位写在右边）、开机启动和开机窗口尺寸（Windows）、启动动画、自动检查更新、关闭窗口时三选一（Windows）、定时退出、剪贴板口令；平台页三组（平台、账号和标签、发现与列表）；刷新页三组（关注列表、直播缩略图、观看记录上限）；网络页两组代理，地址和端口关着时变灰，宽 ≥420 并排。
  - **数据**：缓存（当前大小“点一下重新计算”、刷新缩略图、清空〔红字、确认写现在多大〕）、下载（目录写实际路径和“默认 / 自定义”、恢复默认目录一直显示）；本地配置预览：概况四格、说明“备份格式 v4；这里不显示账号 Cookie 和 WebDAV 设置”、JSON 树和页面一起滚动，顶栏“备份与恢复”。
- 内部怎么工作：
  - 目录驱动：`SettingsArea`（五组，`settings_model.dart:10`）→ `SettingsSection`（17 个入口，`:35`，有的带 `route:`，例如网络电视、录制设置、本地互动、备份、日志）→ `SettingsSubpage`（分页设置、竖屏、观看数据三个子页，`:145`）；每一页有哪些行由 `settingsCatalog`（`settings_catalog.dart:321`，`_build()` 一个大表）给出，行是 `SettingsEntry`（`settings_model.dart:212`：标题、说明、图标、搜索词、平台条件 `when`、依赖、怎么画）。平台条件来自 `SettingsEnv`（`:170`：平台、高刷屏）。
  - 行组件：`live_ui` 的 `SettingsRow` 一族（`settings_row.dart:261` 起）只管样子；应用侧 `settings_tiles.dart` 把它们绑到 `live_store` 的设置上（`writeSetting` `:16`、开关 `:75`、滑块 `:132`〔拖动时只改显示，松手才写〕、选项 `:260`、数字 `:352`、计数 `:442`、跳转 `:517`、动作 `:585`），用 `watchSetting` 只重建用到的行。依赖项用 `SettingRequirement`（`needsOn` / `needsOff`，`:22-45`）变灰并写原因。
  - 两栏和搜索：`SettingsPage`（`settings_page.dart:31`）用 `LayoutBuilder` 按自己的宽度判断（分界 `settingsTwoPaneBreakpoint` 840 `:19`、左栏 `settingsOverviewWidth` 360 `:22`），右栏是嵌套导航器（`_contentNavigator` `:132`）；搜索 `searchSettings`（`settings_model.dart:291`）；跳转高亮 `SettingsReveal` / `openOrReveal`（`settings_tiles.dart:49`、`:64`）和 `_Flash`（`settings_section_view.dart:85`，1.5 秒）。
  - 返回后的位置（A11.6）：手机一栏打开的页在原地换掉总览（不是新页面），总览和搜索结果包着 `KeepScrollPosition`（`live_ui`），返回、跨 840 后回到原来的位置；分页里的子页是嵌套导航器 `push`，下面的页一直在。
  - 主题：`apps/pure_live/lib/app/app.dart:160-246` 读 `themeColorSwitch`、`pureBlackTheme`、`textScaleFactor` 生成主题（`DynamicSchemeVariant.fidelity`、`LivePureBlack`、`AppTextScaler`）。
- 完成度（和 3.x 对照）：
  - 一致的：3.x 的设置项一项不少、键名一个没改；每页的入口、行的图标、子页、平台差异、说明文字；返回链（先关子页再回总览）。
  - 确认过的改动：A11.1 c1～c10（S1～S4）、A11.2 c1～c15（T1～T4：C-3、C-4、C-7、间距计数行）、A11.3 c1～c15（X1～X4）、A11.4 d1～d14（Y1～Y4）、A11.5 e1～e12（Z1～Z3）；都按 D-003 由维护者选建议 A。
  - 后来别的任务改过的：A08.5 把“弹幕”行换成直播间同一个组件；A11.5 加了“日志管理”（17 行）；O03.2 接上后台播放的权限、加了“剪贴板口令”一行；M14.1 加了“界面模式”；A02.2、A02.3 换了对话框主按钮的文字和字体页的 ⋮ 菜单。
  - 还缺：真机只看过设置总览、“视频”页和后台播放的权限流程（S02.2）；外观（颜色、纯黑、文字大小、字体）、内核、小窗弹幕、通用、平台、刷新、网络、数据各页没有 K90 记录（见“已知问题”）。

## 代码地图

`apps/pure_live/lib/features/settings/`：

| 文件 | 职责 | 设计 |
|---|---|---|
| `settings_page.dart`（395 行） | 两栏分界 840（`:19`）、左栏 360（`:22`）、`SettingsPage`（`:31`：搜索防抖 150 毫秒 `:74-87`、打开页 `_openSection` `:94`、搜索结果进页并高亮 `_reveal` `:109`、右栏导航器 `:132`、Ctrl+F / Cmd+F / Esc `:237-239`）、`_ClearSearchAction`（`:270`，只在有字时清空）、`_Overview`（`:303`）、`_SearchResults`（`:349`） | A11.1 c8～c10 |
| `settings_model.dart`（314） | `SettingsArea`（`:10`）、`SettingsSection`（`:35`，`byName` `:136` 给路由参数用）、`SettingsSubpage`（`:145`）、`SettingsEnv`（`:170`）、`SettingsEntry`（`:212`，`matches` `:278`）、`searchWords`（`:285`）、`searchSettings`（`:291`）、`groupsOf`（`:302`） | A11.1 c2、c8 |
| `settings_catalog.dart`（1785） | 时长和选项表（`formatMinutes` `:20`、`videoFitKeys` `:36`、`followRefreshMinutes` `:55`、`coverRefreshMinutes` `:58`，电视设置也用）、平台条件（`_android`、`_windows`、`_desktop` 等 `:69-74`）、依赖表（`:78-90`）、组下说明 `settingsGroupNotes`（`:297`）、组尾 `settingsGroupFooters`（`:307`，MPV 文档链接）、`settingsCatalog`（`:321`）；各页从这里起：外观 `:326`、分页子页 `:476`、导航栏 `:518`、平台 `:537`、刷新 `:600`、视频 `:672`、竖屏 `:909`、观看数据 `:1042`、小窗弹幕 `:1085`、播放内核 `:1238`、通用 `:1341`、网络 `:1463`、缓存 `:1483`、弹幕（只给搜索用）`:1526`；“恢复默认”的范围 `pipDanmakuSettings`（`:1741`）、`portraitSettings`（`:1760`）、`kernelSettings`（`:1776`） | A11.1～A11.5 |
| `settings_section_view.dart`（160） | 目录驱动的一页 `SettingsSectionView`（`:14`，打开时滚到要高亮的行 `:41`）、高亮 `_Flash`（`:85`，1.5 秒）、单独打开的页 `SettingsSectionPage`（`:109`）和子页 `SettingsSubpagePage`（`:145`） | A11.1 |
| `settings_tiles.dart`（713） | `writeSetting`（`:16`）、依赖 `SettingRequirement`（`:22-45`）、`SettingsReveal`（`:49`）、`openOrReveal`（`:64`）、绑定设置的行（开关 `:75`、滑块 `:132`、选项 `:260`、数字 `:352`、计数 `:442`、跳转 `:517`、`openSettingsSubpage` `:576`、动作 `:585`）、顶栏 `settingsAppBar`（`:645`）、页面主体 `SettingsPageBody`（`:668`）、右栏标记 `SettingsPane`（`:698`） | A11.1、A11.3 c5 |
| `settings_dialogs.dart`（361） | `SettingsDialogFrame`（`:18`，圆角 24）、`SettingsChoiceRow`（`:64`，主色 + 勾）、`showChoiceDialog`（`:107`）、`showConfirmDialog`（`:137`）、时长和数字 `showNumberDialog`（`:155`）、颜色代码（`:301`、`:304`）、颜色对话框 `showColorDialog`（`:317`） | A11.2 c10、A11.3 c7、A11.4 d6 |
| `appearance_pages.dart`（1270） | 主题模式（`:45`）、纯黑（`:79`）、主题颜色（`:108`）、语言（`:145`）、间距计数行和对话框（`:193`、`:244`）、文字大小（`:348`）、字体行 `FontFamilyTile`（`:391`）、精细化字号页（`:444`）、加载动画行和页（`:537`、`:580`）、房间卡片设置页（`:764`）、单页数量（`:1013`）、导航栏列表 `HomeMenusList`（`:1176`，引用 `home/home_menu.dart`） | A11.2 |
| `font_manager_page.dart`（415） | 字体页 `FontManagerPage`（`:25`，`danmaku: true` 时是“更换弹幕字体”）：下载和进度（`:102`）、删除确认（`:132`）、打开所在文件夹（`:152`）、换字重（`:166`）、字体卡片的 ⋮ 菜单（`:260`，A02.3 的 `AppMenuButton`） | A11.2 c13 |
| `loading_style_names.dart`（89） | 85 种加载动画的中英文名（3.x `AppConsts.allStyles`） | A11.2 c11 |
| `playback_tiles.dart`（727） | 全局静音（`:29`）、需要权限的开关 `GatedToggleTile`（`:85`，`switchGateProvider`，被拒时红字）、小窗置顶（`:158`）、内核行固定 mpv（`:209`）、播放代理跳网络页（`:230`）、驱动行和 `MpvOptionPage`（`:258`、`:325`）、MPV 文档说明（`:400`）、`RestoreDefaultsTile`（`:437`）、弹幕样式页（`:484`）、小窗弹幕颜色和帧率（`:510`、`:546`）、小窗弹幕页 `PipDanmakuPage`（`:604`，两栏 `:635`）和预览（`:690`） | A11.3 |
| `audience_pages.dart`（258） | 平台顺序（v3 的 19 个在前，`:18-33`）、显示模式（`:47`）、能开的平台（`:78`）、只有热度的平台一行（`:130`）、各平台口径说明页 `AudienceInfoPage`（`:177`） | A11.3 c15 |
| `settings_editors.dart`（1045） | MPV 选项清单（`MpvOptionKind` `:22`、`mpvOptionsFor` `:91`）、重置小窗位置（`:144`）、首选平台带搜索（`:182`）、Twitch 语言（`:286`）、代理（`ProxySettings` `:393`、`ProxyEditorTile` `:420`）、开机窗口尺寸（`:535`）、关闭窗口时（`:719`）、定时退出（`AutoExitTimer` `:767`、`AutoExitTile` `:848`、`AutoExitMinutesTile` `:867`）、界面刷新率（`:901`，60 Hz 限速提示 `:977`）、开机启动（`:1017`） | A11.3、A11.4 |
| `data_tools.dart`（592） | 图片缓存工具 `ImageCacheTools`（`:29`）、定时刷新缩略图 `CoverRefreshTimer`（`:87`，`app/startup.dart` 启动时接上）、`formatBytes`（`:132`）、缓存大小（`:140`、`:169`）、清空（`:228`）、刷新缩略图（`:285`）、下载目录和恢复默认（`:334`、`:378`；缺权限只提示 `:351-353`）、本地配置预览 `ConfigPreviewPage`（`:408`，出错状态 `:458`、顶栏“备份与恢复” `:451`） | A11.5 |
| `danmaku_page.dart`（184） | 总览“弹幕”行打开的页（`DanmakuSettingsPage` `:32`，路由 `RoutePath.kDanmakuSettings`）；内容归 A08 | A08.5 |

共用组件和别处的接线：

| 文件 | 职责 | 设计 |
|---|---|---|
| `packages/live_ui/lib/src/widgets/settings_row.dart`（1170） | 窄屏 360 和 1.5 倍字号换行（`:18`、`:21`）、电视样式 `SettingsRowStyle`（`:26`）、搜索标记 `SettingsHighlight` / `HighlightedText`（`:42`、`:58`）、`SettingsGroup`（`:118`）、组名（`:198`）、说明（`:232`）、`SettingsRow`（`:261`）、跳转（`:500`）、开关（`:640`）、滑块（`:720`）、计数（`:886`，按住连续变）、行内选项（`:994`、`:1042`）、色块（`:1072`）、搜索框（`:1095`） | A11.1（A02.1 的设置行） |
| `packages/live_ui/lib/src/widgets/settings_page_frame.dart`（75）、`settings_tiles.dart`（31） | 设置页顶栏（矮窗口 48 高 `:21`）、`SettingsPageList`（`:49`，最宽 720）；`ReadableContent`（720） | A11.1、A10.2 |
| `packages/live_ui/lib/src/widgets/color_picker.dart`（563）、`json_tree.dart`（210）、`pip_danmaku_preview.dart`（348） | 颜色选择器 `LiveColorPicker`（`:73`：推荐、常用、鲜艳、调色盘、色阶、透明度、代码）；JSON 树 `JsonTreeSliver`（`:79`）；小窗弹幕预览 `PipDanmakuPreview`（`:12`） | A11.2 c10、A11.5 e9、A11.3 c14 |
| `packages/live_ui/lib/src/theme/live_theme.dart`、`live_colors.dart`、`text_styles.dart` | 品牌蓝 `LiveTheme.brandBlue`（`live_theme.dart:177`）、纯黑深色 `LivePureBlack`（`live_colors.dart:314`）、`AppTextScaler`（`text_styles.dart:175`） | A11.2 c5、c8、c9 |
| `packages/live_store/lib/src/settings/settings.dart`、`legacy/legacy_rules.dart` | 3.x 默认蓝迁移：`themeColorMigration`（`settings.dart:169`，内部记录）、`LegacyRules.themeColor`（`legacy_rules.dart:19`） | A11.2 c8 |
| `apps/pure_live/lib/app/app.dart` | 主题和文字大小（`:160-246`） | A11.2 |
| `apps/pure_live/lib/routes/app_router.dart`、`route_path.dart` | `kSettings`（`route_path.dart:35`）、`kDanmakuSettings`（`:72`）、`kLocalInteraction`（`:141`）、`kLogs`（`:145`） | A11.1 |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/settings/settings_page_test.dart`（26 个用例声明） | 总览五组和行序、行打开页和返回、返回链、两栏（1280、852×393）、一栏 720、跨 840 缩放；搜索（分组标题和标记、进页高亮、Ctrl+F 和 Esc、每个词都要匹配）；外观各行、主题模式和语言对话框、纯黑、颜色预览、间距、分页设置、字号、加载动画、房间卡片、导航栏；页码跳转开关生效；设置页两端用 Android 拉伸（D-009） |
| `.../settings/settings_playback_test.dart`（20） | 视频页六组、三种宽度 ≤720、依赖项变灰、时长和选项对话框、弹幕样式同一组件、权限被拒、竖屏页、观看数据页、内核页、驱动选项、小窗弹幕页一栏和两栏、计数、恢复默认 |
| `.../settings/settings_general_test.dart`（10） | 通用页各组、刷新率对话框、定时退出、Windows 的窗口项、iOS 高刷、平台页、刷新页、计数按住、网络页窄屏和宽屏 |
| `.../settings/settings_data_test.dart`（7） | 缓存页、清空确认、下载目录、配置预览、日志入口 |
| `.../settings/settings_danmaku_test.dart`（6）、`match_frame_rate_test.dart`（1）、`refresh_rate_limited_test.dart`（2） | 弹幕页和直播间同一组件（A08.5）；刷新率的帧率声明和 60 Hz 限速提示（R02.1、R02.2） |
| `.../settings/settings_scroll_position_test.dart`（9） | 返回后列表回到原位（A11.6）：手机一栏的总览、两层子页、路由页、弹幕页 → 屏蔽、搜索结果；宽屏 1280 和横屏手机两栏；跨 840 的总览和打开的页 |
| `.../settings/settings_harness.dart` | 共用测试台（provider 覆盖、减少动态效果） |
| `packages/live_ui/test/settings_row_test.dart`（18）、`settings_playback_widgets_test.dart`（5） | 行的五种类型、对比度（四个种子色、深浅两套）、不能用和处理中、窄屏和 1.5 倍字体换行、电视样式；颜色选择器；主题（fidelity、纯黑、文字大小相乘）；长值、按住连续变、预览、JSON 树 |
| `packages/live_store/test/theme_color_test.dart`（4） | 品牌蓝默认值和 3.x 默认蓝迁移只做一次 |

## 3.x 基线

文件都在 `git show v3.2.11:lib/` 下（本机副本 `~/ref/v3ref/lib/`）：

- 总览 `modules/settings/settings_page.dart`（184 行）：一个列表，按 `buildGroupTitle` 分组：主题 `:56`、IPTV `:67`、刷新 `:77`、视频 `:87`、内核 `:104`、网络 `:114`、本地互动 `:125`、通用 `:136`、数据 `:159`、备份 `:170`，每组一两行；行组件 `common/widgets/widget_extensions.dart`（455 行）的 `buildGroupTitle`（`:21`）、`buildModernCard`（`:38`）、`buildSwitchTile`（`:114`）、`buildTile`（`:154`）、`buildMenuTile`（`:260`）、`buildSliderTile`（`:352`）。
- 分页（`modules/settings/pages/`）：外观 `theme_settings_page.dart`（524 行）、颜色 `modules/settings/widgets/app_color_picker_dialog.dart`、加载动画 `loading_style_settings_page.dart`（549）、房间卡片 `room_card_settings_page.dart`（310）、分页 `page_settings.dart`（228）、导航栏 `navigation_settings_page.dart`（207）、字体 `font_family_manager_page.dart`（779）、字号 `font_settings_page.dart`（171）；视频 `video_settings_page.dart`（720）、竖屏 `portrait_live_settings_page.dart`（247）、观看数据 `audience_metric_settings_page.dart`（168）、内核 `player_kernel_settings_page.dart`（442）、MPV 选项 `mpv_option_page.dart`（58）、小窗弹幕 `pip_danmaku_settings_page.dart`（744）；通用 `general_settings_page.dart`（585）、平台 `platform_settings_page.dart`（173）、刷新 `refresh_settings.dart`（216）、网络 `network_proxy_settings_page.dart`（191）；缓存 `cache_data_settings_page.dart`（242）、配置预览 `local_config_preveiw.dart`（297，3.x 的文件名拼写）。加载动画名 `common/consts/app_consts.dart:80` 的 `allStyles`（85 种）。
- 3.x 的已知问题（各任务 README 的“v3 的问题”）：页码跳转开关存了不读、全局字体缩放替换系统字号、默认色块和界面颜色不一致、分页设置按整屏宽度判断、多画面开关只有 Windows（A11.2 修）；内核页的警告压在行里、代理在两处改、依赖项关着时消失（A11.3 修）；“退出不再询问”说不清记住了什么、刷新率和动态刷新率两行（A11.4 修）；清空不说多大、预览原始内容单独一个框滚动（A11.5 修）。
- 必须保留：所有设置键名和含义（D-018）；返回链“先关子页再回总览”（[specs/UI.md](../../specs/UI.md) 附录 A 第 7 条）；首页 ≡ 菜单进设置。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| A11.1～A11.5 登记为“完成”，K90 上只看过设置总览、“视频”页、后台播放的权限流程（S02.2）；外观（颜色、纯黑、文字大小、字体）、内核、小窗弹幕、通用、平台、刷新、网络、数据没有记录 | 各任务 `record.md`；[S02.2 记录](../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md) | 不符合 PROCESS 3.2“完成必须有真机结果” | 写进本单元报告；建议并入 [S03.1](../../S-质量和验证/S03-统一验证/S03.1-统一验证/README.md)，字体并入 S02.4（CHECKLIST 第 5 节第 5 条） |
| 设置项还没逐条和功能清点核对（218 个设置的默认值、范围、生效位置） | `settings_catalog.dart`、`packages/live_store/lib/src/settings/settings.dart` | 可能漏项或说明和行为不符 | [J01.2](../../J-设置和数据/J01-设置/J01.2-设置项逐条核对/README.md) |
| 设置的弹幕页少“弹幕列表”“小窗弹幕”两组；小窗弹幕设置两份实现、顺序不同（设置页按 A11.3 c14 分组，直播间照 3.x 顺序） | `danmaku_page.dart`；`settings_catalog.dart:1085-1234`、`features/live_play/danmaku/danmaku_settings_panel.dart` | 同一个设置两处不一样 | [A08.6](../A08-弹幕界面/A08.6-设置的弹幕页补两组/README.md)（G3 定顺序） |
| 小窗弹幕颜色两种选色方式：设置页 `PipColorTile` 用 `showColorDialog`（`LiveColorPicker`），直播间用 `showDanmakuColorDialog`（10 个色块 + 十六进制） | `playback_tiles.dart:510`、`settings_dialogs.dart:317` | 同一个设置两种选法 | [A08.7](../A08-弹幕界面/A08.7-小窗弹幕颜色改成面板/README.md) |
| 打包的 libmpv 实际支持哪些解码器没核对，Android 驱动清单照设计图的 9 个 | `settings_editors.dart:91`（`mpvOptionsFor`） | 选到不支持的会回落默认 | 归 G01（引擎）；G01.2 在 K90 上看硬解时一起看 |
| Android 选公共下载目录缺权限时只提示，不打开系统设置；平台层没有打开存储权限设置页的方法 | `data_tools.dart:351-353`；`apps/pure_live/lib/platform/system_access.dart` | 用户要自己去系统里开权限 | 没有登记任务；建议在 [O04 权限](../../O-Android系统集成/O04-权限/README.md) 下登记 |
| 字体页没有组件测试；字名用本字体显示只对本次已加载的字体生效 | `font_manager_page.dart` | 布局回归只靠真机 | S02.4、S03.1 时看 |
| 本地配置预览的出错状态没有组件测试（内存存储读不出错） | `data_tools.dart:458` | 出错分支只靠代码审查 | 影响小，不做 |
| macOS 的“登录时打开”、Mac 上隐藏“关闭窗口时”没做；Linux、macOS 是否加开机启动和关窗口选择没定 | `settings_editors.dart:1017`、`:719` | 苹果平台还不构建 | [A18.2](../A18-苹果平台界面/A18.2-macOS差异设计/README.md)；Linux 归 X 组 |
| 电视设置的颜色列表还是 3.x 的蓝、没有品牌蓝；电视去掉“主题模式”没做 | `apps/pure_live/lib/tv/pages/tv_settings_pane.dart` | 电视和手机默认色不一致 | [A17.9](../A17-电视界面/A17.9-电视设置/README.md)（已确认） |
| 设置各页在电脑上按 Esc 不返回（只有总览的 Esc 清空搜索） | `settings_page.dart:239`；各分页没有 `EscapeBack` | 规范 5.4 的 Esc 返回链不全 | A05.1 |
| 只在测试尺寸下测过，profile 帧时间没量 | 设置各页 | 每页 ≤30 行、一次性构建，风险小 | R01.2 有需要时 |
| 跨功能引用 `settings -> home/home_menu.dart`（导航栏列表）、`search -> settings/settings_model.dart`（搜索页打开网络设置） | `tools/gate/ui_baseline.json`；`appearance_pages.dart`、`features/search/search_view.dart:19` | 门禁基线里 2 条 | 首页菜单挪到 `shared/`（A06）时去掉前一条；后一条可改成按路由参数打开 |
| 代码注释里还用旧编号（`U.6a`、`U.6c c9`、`F02 c1`、`M14.1`、`F.0a` 等） | `settings_catalog.dart` 各节标题注释等 | 按注释找文档要先查 [MAPPING.md](../../MAPPING.md) | Z 组一次性替换 |

## 相关决定和规范

- D-003：A11.1 的 S1～S4、A11.2 的 T1～T4、A11.3 的 X1～X4、A11.4 的 Y1～Y4、A11.5 的 Z1～Z3 由维护者按建议 A 定。
- D-009：设置页两端用 Android 拉伸（不回弹），`settings_page_test.dart` 第一个用例固定。
- D-010：刷新率策略（界面刷新率一行的说明和限速提示，R02.2）。
- D-011：标题位置照 3.x 实际运行的样子，设置各页标题靠左。
- D-018：键名不变；A11.2 的品牌蓝是唯一改了已有默认值（`themeColorSwitch`）的地方，用一次性迁移处理（`themeColorMigration`）。
- D-024：翻译键这次不清理（旧行用过的键留着）。
- [specs/UI.md](../../specs/UI.md)：第 3 节（同一件事一种做法：选项对话框统一、恢复默认统一）；第 5.3 节（阅读型内容最宽 720，只读父组件宽度）；第 7 节（选项对话框“主色 + 勾”、确认对话框危险按钮红色）；第 8.1 节（C-3 品牌蓝、C-4 纯黑）；第 14 节（C-3、C-4、C-7 候选改动的结论）；附录 A 第 7 条（返回链）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/settings`；`cd packages/live_ui && flutter test test/settings_row_test.dart test/settings_playback_widgets_test.dart`；`cd packages/live_store && dart test test/theme_color_test.dart`（上表）。覆盖了每个确认的改动。缺：字体页、配置预览出错状态的组件测试；没有截图对照（深色和纯黑只断言颜色值）；没有 profile 帧时间。
- 真机：[S02 的 CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 18 条（界面刷新率，R02.2）、第 5 节第 5 条（下载字体设为应用字体，S02.4）、第 5 节第 6 条（播放代理，S02.4）。S02.2（2026-10-02）看过设置总览、“视频”页、后台播放开关的权限和电池说明流程（通过）。

## 路线

1. 补真机：S02.4（字体、播放代理）和 [S03.1](../../S-质量和验证/S03-统一验证/S03.1-统一验证/README.md)（外观的颜色、纯黑、文字大小；内核、小窗弹幕；通用、平台、刷新、网络；清空缓存、换下载目录、配置预览），给 A11.1～A11.5 补上真机结果；R02.2 的 verify 里看界面刷新率一行。
2. [A08.6](../A08-弹幕界面/A08.6-设置的弹幕页补两组/README.md)、[A08.7](../A08-弹幕界面/A08.7-小窗弹幕颜色改成面板/README.md)：设置的弹幕页补两组、小窗弹幕设置和颜色选择统一成一份（第二档）；会改 `danmaku_page.dart`、`playback_tiles.dart`、`settings_catalog.dart`。
3. [J01.2](../../J-设置和数据/J01-设置/J01.2-设置项逐条核对/README.md)：设置项逐条核对，发现漏项或说明不符回到这里改行。
4. 以后：电视设置（A17.9）复用这里的设置行（电视样式）和选项表，内容和顺序要一致；macOS 差异（A18.2）；存储权限设置页的入口（建议 O04 登记）。新想法写进 V01 提议，不直接加任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：`features/settings/`
- 进度：`████████████████████` 98%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A11.1 | 设置：设置总览 | 界面 | 完成 | 2026-10-01 | 3f53f8123 | [设计或说明](A11.1-设置总览/README.md)、[记录](A11.1-设置总览/record.md)、[评审页](A11.1-设置总览/page/01-说明.jpg) |
| A11.2 | 设置：外观 | 界面 | 完成 | 2026-10-01 | 3f53f8123 | [设计或说明](A11.2-外观/README.md)、[记录](A11.2-外观/record.md)、[评审页](A11.2-外观/page/01-说明.jpg) |
| A11.3 | 设置：播放 | 界面 | 完成 | 2026-10-02 | e9e41d557 | [设计或说明](A11.3-播放/README.md)、[记录](A11.3-播放/record.md)、[评审页](A11.3-播放/page/01-说明.jpg) |
| A11.4 | 设置：通用和网络 | 界面 | 完成 | 2026-10-02 | e9e41d557 | [设计或说明](A11.4-通用和网络/README.md)、[记录](A11.4-通用和网络/record.md)、[评审页](A11.4-通用和网络/page/01-说明.jpg) |
| A11.5 | 设置：数据 | 界面 | 完成 | 2026-10-02 | e9e41d557 | [设计或说明](A11.5-数据/README.md)、[记录](A11.5-数据/record.md)、[评审页](A11.5-数据/page/01-说明.jpg) |
| A11.6 | 从子页面返回后列表回到原来的位置（设置和同类页面） | 界面 | 待真机 | 2026-10-09 | — | [设计或说明](A11.6-返回后列表回到原位/README.md)、[任务书](A11.6-返回后列表回到原位/brief.md)、[记录](A11.6-返回后列表回到原位/record.md)、[真机验证](A11.6-返回后列表回到原位/verify.md) |

<!-- docs:生成结束 -->
