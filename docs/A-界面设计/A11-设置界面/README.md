# A11 设置界面

设置总览和外观、播放、通用和网络、数据各分页。

一句话：设置的样子和操作：总览的五组、搜索、宽屏两栏，每个分页的分组、行、对话框，以及共用的设置行组件；设置项的含义和存储不在这里。

## 范围

- 包括：
  - 设置总览（A11.1）：五组 17 行（界面、直播来源、播放、通用和网络、数据）、搜索（Ctrl+F / Cmd+F、Esc 清空）、宽 840 起左右两栏；`live_ui` 的设置行组件（跳转、开关、滑块、计数、选项五种）。
  - 外观（A11.2）：主题、房间卡片和列表、语言和界面、字体和字号四组；颜色对话框、间距、文字大小、加载动画、房间卡片设置、导航栏、字体管理、精细化字号。
  - 播放（A11.3）：视频页六组、竖屏直播适配、观看数据与排行口径、播放内核、MPV 驱动选项、小窗弹幕。
  - 通用和网络（A11.4）：通用（刷新率、启动、更新、窗口、定时退出）、平台、刷新、网络与代理。
  - 数据（A11.5）：缓存与下载、本地配置预览、日志管理入口。
- 不包括（归哪里）：
  - 设置项本身（键名、默认值、迁移、存储）在 [J01 设置](../../J-设置和数据/J01-设置/README.md)，键名和含义不变（D-018）。
  - 弹幕设置页（总览“弹幕”行打开的那页）是直播间弹幕设置的同一个组件，在 [A08](../A08-弹幕界面/README.md)（A08.5 合并，A08.6 补组）；录制设置页在 [A10.2](../A10-录制界面/A10.2-录制设置/README.md)；备份、WebDAV、账号页在 [A12](../A12-账号和数据界面/README.md)；网络电视管理在 [A13.1](../A13-网络电视和多画面界面/A13.1-网络电视管理/README.md)；本地互动在 [A08](../A08-弹幕界面/README.md)。
  - 刷新率策略本身在 [R02](../../R-性能和流畅度/R02-刷新率/README.md)；电视的设置页在 [A17.9](../A17-电视界面/A17.9-电视设置/README.md)。

## 现状：做到哪、怎么工作的

- **用户看得到的**：首页 ≡ 菜单“设置”打开总览：五组卡片，每行图标、标题、两行说明。宽 <840 一栏（600～839 最宽 720 居中），宽 840 起左边总览 360、右边打开的页最宽 720 靠左，右栏里再打开的页也在右栏、带返回。搜索结果就是设置行本身（开关、滑块可以直接改），会打开别的页的行进到那一页并高亮 1.5 秒。窗口高 <480（横屏手机）时所有设置页顶栏 48 高。
- **内部怎么工作**：
  - 总览和每一页都由目录驱动：`SettingsArea`（五组）→ `SettingsSection`（17 个入口，有的是路由，例如 IPTV、录制设置、备份、日志）→ `SettingsSubpage`（竖屏、观看数据、分页设置等子页），定义在 `features/settings/settings_model.dart`；每一页有哪些行由 `settingsCatalog`（`settings_catalog.dart:321`，一个大表）给出，行是 `SettingsEntry`（标题、说明、图标、搜索词、依赖条件、怎么画）。
  - 行组件：`live_ui` 的 `SettingsRow` 一族（`packages/live_ui/lib/src/widgets/settings_row.dart`）；应用侧把它们绑到 `live_store` 的设置上（`settings_tiles.dart` 的 `SettingToggleTile`、`SettingSliderTile`、`SettingChoiceTile` 等，`writeSetting` :16）。依赖项用 `SettingRequirement`（`needsOn` / `needsOff`，:22）变灰并写“打开……后生效”。
  - 两栏：`SettingsPage`（`settings_page.dart:31`）按自己的宽度（`LayoutBuilder`）判断，右栏是嵌套导航器；跨过 840 时保留右栏的页。搜索：`searchSettings`（`settings_model.dart:291`）每个词都要在标题或说明里出现。
- **完成度**：5 个任务全部完成（2026-10-01～02 合并）。3.x 的设置项一项不少、键名一个没改；确认过的改动见各任务 README（“主题定制”改名“外观”、五组、两栏、搜索；C-3 品牌蓝 #2E6FE0 和 3.x 默认蓝迁移、C-4 纯黑背景、C-7 文字大小叠在系统字号上；依赖项变灰不消失；恢复默认统一；内核固定 mpv 等）。真机上看过的：设置总览和“视频”页（S02.2）、后台播放的权限流程（S02.2，O03.2）；其余分页没有在真机上单独记录。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/features/settings/settings_page.dart` | 总览 `SettingsPage`（:31）：五组 `_Overview`（:303）、搜索结果 `_SearchResults`（:349）、Ctrl+F / Esc（:260～:283）、两栏分界 840（:19）和左栏宽 360（:22） |
| `apps/pure_live/lib/features/settings/settings_model.dart` | 五组 `SettingsArea`（:10）、17 个入口 `SettingsSection`（:35，`byName` 给路由参数用）、子页 `SettingsSubpage`（:145）、平台环境 `SettingsEnv`（:170，手机 / 电脑 / 高刷屏）、条目 `SettingsEntry`（:212）、搜索（:285、:291） |
| `apps/pure_live/lib/features/settings/settings_catalog.dart` | 每一页的分组和行（`settingsCatalog` :321）、组下说明（:307）、页首说明（:314）；小窗弹幕、竖屏、内核的“恢复默认”范围（:1741、:1760、:1776）；平台判断（`_android`、`_windows`、`_desktop` 等 :69～:74） |
| `apps/pure_live/lib/features/settings/settings_section_view.dart` | 目录驱动的一页 `SettingsSectionView`（:14）、高亮闪一下 `_Flash`（:85）、单独打开的页和子页（:109、:145） |
| `apps/pure_live/lib/features/settings/settings_tiles.dart` | 绑定设置的行（开关 :75、滑块 :132、选择 :260、数字 :352、计数 :442、跳转 :517、动作 :585）、依赖条件（:22～:45）、打开并高亮（`openOrReveal` :64）、设置页顶栏 `settingsAppBar`（:645）、页面主体和右栏标记 |
| `apps/pure_live/lib/features/settings/settings_dialogs.dart` | 对话框框架（:18）、选项行“主色 + 勾”（`SettingsChoiceRow` :64）、选项 / 确认 / 时长对话框（:107、:137、:155）、颜色对话框（:317） |
| `apps/pure_live/lib/features/settings/appearance_pages.dart` | 外观的行和子页：主题模式、纯黑、主题颜色、语言（:45～:145）、间距和对话框（:193）、文字大小（:348）、字体行（:391）、精细化字号页（:444）、加载动画页（:580）、房间卡片设置页（:764）、分页设置（:1013）、导航栏列表（:1176） |
| `apps/pure_live/lib/features/settings/font_manager_page.dart` | 字体页：字体卡片、⋮ 菜单（打开所在文件夹、删除）、下载进度、字重单选 |
| `apps/pure_live/lib/features/settings/loading_style_names.dart` | 86 种加载动画的名字 |
| `apps/pure_live/lib/features/settings/playback_tiles.dart` | 播放的行和页：全局静音（:29）、需要权限的开关 `GatedToggleTile`（:85，权限被拒时红字）、小窗置顶（:158）、内核行固定 mpv（:209）、播放代理跳网络页（:230）、MPV 驱动选项页（:325）、恢复默认 `RestoreDefaultsTile`（:437）、弹幕样式页（:484）、小窗弹幕页和预览（:604、:690） |
| `apps/pure_live/lib/features/settings/audience_pages.dart` | 观看数据与排行口径：模式、能开的平台、只有热度的平台一行、各平台口径说明页 |
| `apps/pure_live/lib/features/settings/settings_editors.dart` | 专门的编辑行：MPV 选项清单（:22、:91）、重置小窗位置（:144）、首选平台（:182，带搜索）、Twitch 语言（:286）、代理地址和端口（:420）、开机窗口尺寸（:535）、关闭窗口时三选一（:719）、定时退出（:767～:867）、界面刷新率（:901）、开机启动（:1017） |
| `apps/pure_live/lib/features/settings/data_tools.dart` | 缓存大小（:140、:169）、清空（:228）、刷新缩略图（:285）、下载目录和恢复默认（:334、:378）、本地配置预览（:408） |
| `apps/pure_live/lib/features/settings/danmaku_page.dart` | 总览“弹幕”行打开的页：直播间同一个 `DanmakuSettingsContent` 加“更多”一组（A08.5） |
| `packages/live_ui/lib/src/widgets/settings_row.dart`、`settings_tiles.dart`、`settings_page_frame.dart` | 设置行五种和组、说明、搜索框、高亮；电视样式 `SettingsRowStyle(tv: true)`；设置页的内容宽度 |
| `packages/live_ui/lib/src/widgets/color_picker.dart`、`json_tree.dart`、`pip_danmaku_preview.dart` | 颜色选择器（推荐、常用、鲜艳、调色盘、色阶、代码）、配置预览的 JSON 树、小窗弹幕预览 |
| `packages/live_ui/lib/src/theme/live_theme.dart`、`live_colors.dart` | fidelity 配色、纯黑深色（`LivePureBlack`）、文字大小 `AppTextScaler` 的用法（主题在 `apps/pure_live/lib/app/app.dart` 生成） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/settings/settings_page_test.dart` | 总览五组和行序、返回链、两栏（1280、852×393）、一栏 720、跨 840 缩放、搜索（标记、就地开关、多词、清空、跳转高亮）、Ctrl+F 和 Esc；外观各行和对话框、颜色预览、间距、分页设置、加载动画、房间卡片、导航栏 |
| `apps/pure_live/test/features/settings/settings_playback_test.dart` | 视频页六组、依赖项变灰、时长和选项对话框、权限被拒、竖屏页、观看数据页、内核页、驱动选项、小窗弹幕页（一栏和两栏、计数、恢复默认） |
| `apps/pure_live/test/features/settings/settings_general_test.dart` | 通用页四组、刷新率、定时退出、Windows 的窗口项、iOS 高刷、平台页、刷新页、网络页 |
| `apps/pure_live/test/features/settings/settings_data_test.dart` | 缓存页、清空确认、下载目录、配置预览、日志入口 |
| `apps/pure_live/test/features/settings/settings_danmaku_test.dart`、`match_frame_rate_test.dart`、`refresh_rate_limited_test.dart` | 弹幕页和直播间同一组件；刷新率的帧率声明和 60 Hz 限速提示（R02.2） |
| `packages/live_ui/test/settings_row_test.dart`、`settings_playback_widgets_test.dart` | 行的五种类型、对比度（四个种子色、深浅两套）、不能用和处理中、窄屏和 1.5 倍字体换行、电视样式；颜色选择器；长值、按住连续变、预览、JSON 树 |
| `packages/live_store/test/theme_color_test.dart` | 品牌蓝默认值和 3.x 默认蓝迁移只做一次 |

## 3.x 基线

- 总览 `git show v3.2.11:lib/modules/settings/settings_page.dart`（184 行）：一个列表、按 `buildGroupTitle` 分组（主题 `:56`、IPTV `:67`、刷新 `:77`、视频 `:87`、内核 `:104`、网络 `:114`、本地互动 `:125`、通用 `:136`……），每组一两行；行组件 `lib/common/widgets/widget_extensions.dart` 的 `buildModernCard`、`buildTile`、`buildSwitchTile`、`buildSliderTile`。
- 分页（`lib/modules/settings/pages/`）：外观 `theme_settings_page.dart`（524 行）、颜色 `widgets/app_color_picker_dialog.dart`、加载动画 `loading_style_settings_page.dart`、房间卡片 `room_card_settings_page.dart`、分页 `page_settings.dart`、导航栏 `navigation_settings_page.dart`、字体 `font_family_manager_page.dart`、字号 `font_settings_page.dart`；视频 `video_settings_page.dart`（720 行）、竖屏 `portrait_live_settings_page.dart`、观看数据 `audience_metric_settings_page.dart`、内核 `player_kernel_settings_page.dart`、MPV 选项 `mpv_option_page.dart`、小窗弹幕 `pip_danmaku_settings_page.dart`（744 行）；通用 `general_settings_page.dart`、平台 `platform_settings_page.dart`、刷新 `refresh_settings.dart`、网络 `network_proxy_settings_page.dart`；缓存 `cache_data_settings_page.dart`、配置预览 `local_config_preveiw.dart`（3.x 的文件名拼写）。
- 3.x 已知问题（各任务 README 的“v3 的问题”）：页码跳转开关不生效、全局字体缩放替换系统字号、默认色块和界面颜色不一致、分页设置按整屏宽度判断、多画面开关只有 Windows（A11.2 修）；内核页的警告压在行里、代理在两处改（A11.3 修）。
- 必须保留：所有设置键名和含义（D-018）；返回链“先关子页再回总览”（[specs/UI.md](../../specs/UI.md) 附录 A 第 7 条）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 设置项还没逐条和功能清点核对 | `settings_catalog.dart` | 可能漏项或说明和行为不符 | [J01.2](../../J-设置和数据/J01-设置/README.md) |
| 设置里的弹幕页少“弹幕列表”“小窗弹幕”两组 | `danmaku_page.dart` | 这两组只能在直播间或总览的小窗弹幕行里改 | [A08.6](../A08-弹幕界面/README.md) |
| 打包的 libmpv 实际支持哪些解码器没核对，Android 驱动清单照设计图的 9 个 | `settings_editors.dart` 的 `mpvOptionsFor` | 选到不支持的会回落默认 | 归 G01（引擎），有问题时再开任务 |
| 字体页没有组件测试；字名用本字体显示只对本次已加载的字体生效 | `font_manager_page.dart` | 布局回归只靠真机 | [S03.1](../../S-质量和验证/S03-统一验证/README.md) 时看 |
| macOS 的“登录时打开”、Mac 上不显示“关闭窗口时”没做 | `settings_editors.dart` 的 `StartupTile`、`CloseWindowTile` | 苹果平台还不构建 | [A18.2](../A18-苹果平台界面/A18.2-macOS差异设计/README.md) |
| 只在模拟器尺寸下测过，profile 帧时间没量 | 设置各页 | 每页 ≤30 行，风险小 | R01.2 有需要时 |
| 跨功能引用 `settings -> home/home_menu.dart`、`search -> settings/settings_model.dart` | `tools/gate/ui_baseline.json` | 门禁基线里 2 条 | 首页菜单挪到 `shared/` 时去掉 |

## 相关决定和规范

- D-003（A11.1 的 S1～S4、A11.2 的 T1～T4、A11.3 的 X1～X4、A11.4 的 Y1～Y4、A11.5 的 Z1～Z3 按建议 A）、D-010（刷新率策略，界面刷新率行的说明）、D-018（键名不变；A11.2 的品牌蓝是唯一改了已有默认值的地方，用迁移处理）、D-024（翻译键这次不清理）。
- [specs/UI.md](../../specs/UI.md) 第 5.3 节（阅读型内容最宽 720）、第 7 节（选项对话框“主色 + 勾”）、第 8.1 节（C-3 品牌蓝、C-4 纯黑）、第 14 节（C-7 文字大小）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/settings`；`cd packages/live_ui && flutter test test/settings_row_test.dart test/settings_playback_widgets_test.dart`；`cd packages/live_store && dart test test/theme_color_test.dart`。共用测试台 `test/features/settings/settings_harness.dart`（provider 覆盖、减少动态效果）。缺：字体页、配置预览出错状态。
- 真机：[S02 的 CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 18 条（界面刷新率）、第 5 节第 5 条（下载字体设为应用字体）。S02.2 看过设置总览和“视频”页、后台播放开关的权限流程（通过）。

## 路线

1. [A08.6](../A08-弹幕界面/README.md)：设置的弹幕页补“弹幕列表”“小窗弹幕”两组（第二档）。
2. [J01.2](../../J-设置和数据/J01-设置/README.md)：设置项逐条核对，发现漏项回到这里改行。
3. [S03.1](../../S-质量和验证/S03-统一验证/README.md)：外观（颜色、纯黑、文字大小、字体）、通用、数据各页补真机。
4. 电视设置（A17.9）复用这里的设置行（电视样式）和目录，内容和顺序要一致。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：`features/settings/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A11.1 | 设置：设置总览 | 界面 | 完成 | 2026-10-01 | 3f53f8123 | [设计或说明](A11.1-设置总览/README.md)、[记录](A11.1-设置总览/record.md)、[评审页](A11.1-设置总览/page/01-说明.jpg) |
| A11.2 | 设置：外观 | 界面 | 完成 | 2026-10-01 | 3f53f8123 | [设计或说明](A11.2-外观/README.md)、[记录](A11.2-外观/record.md)、[评审页](A11.2-外观/page/01-说明.jpg) |
| A11.3 | 设置：播放 | 界面 | 完成 | 2026-10-02 | e9e41d557 | [设计或说明](A11.3-播放/README.md)、[记录](A11.3-播放/record.md)、[评审页](A11.3-播放/page/01-说明.jpg) |
| A11.4 | 设置：通用和网络 | 界面 | 完成 | 2026-10-02 | e9e41d557 | [设计或说明](A11.4-通用和网络/README.md)、[记录](A11.4-通用和网络/record.md)、[评审页](A11.4-通用和网络/page/01-说明.jpg) |
| A11.5 | 设置：数据 | 界面 | 完成 | 2026-10-02 | e9e41d557 | [设计或说明](A11.5-数据/README.md)、[记录](A11.5-数据/record.md)、[评审页](A11.5-数据/page/01-说明.jpg) |

<!-- docs:生成结束 -->
