# U.6a 设置总览（含 U.1c 的设置行）

- 日期：2026-10-01
- 设计：[docs/ui/compare/U.6a/README.md](../compare/U.6a/README.md)（第 1 版，用户已确认；S1～S4 按建议 A）；计划书 [UI_PLAN.md](../UI_PLAN.md) 第 3、5、7–10 节
- 一并处理的跨任务待同步：U.6c～U.6e → U.6a（小窗弹幕只留总览一个入口、“视频”“通用”说明对上页面内容、横屏手机顶栏太高、配置预览挪进“数据”组）；U.10b → U.1c（说明只显示一行、对比度 3.4:1）；U.4f → U.1c（开关滑块和底色同为主色）；U.10a K1（“三方认证”改名“平台账号”）
- 改动的目录：`apps/pure_live/lib/features/settings/`、`packages/live_ui`（只做添加）、翻译文件、门禁基线、文档；外观部分（U.6b）见 [U.6b.md](U.6b.md)
- 没有改原生部分，没有构建 APK，没有往手机安装

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 入口、每行图标和子页照 v3 | ✅ | 首页 ≡ 菜单“设置”不变；图标按 v3（`AppIcons.settings*`），“弹幕”用 v3 的弹幕设置图片 `DanmakuIcon` |
| c2 | 5 组：界面、直播来源、播放、通用和网络、数据；一组一张卡片 | ✅ | `SettingsArea` + `SettingsSection`（16 行，顺序照设计图） |
| c3 | “主题定制”改名“外观”；副标题重写、最多两行 | ✅ | “视频”“通用”的说明按 U.6c、U.6d 定稿的页面内容写（主控追加）；“平台显示与授权”里的“三方认证”行名是“平台账号”（v4 原来就是） |
| c4 | 统一设置行；组名、副标题对比 ≥4.5:1；卡片和分隔线看得见 | ✅ | `live_ui` 的 `SettingsGroup`/`SettingsRow` 等（下节）；组名 13 号 600 主色；卡片 `surfaceContainerLow`、圆角 16；分隔线 `outlineVariant` 70%，从文字起 |
| c5 | “配置预览”挪到“数据”组最后一行“本地配置预览” | ✅ | 顶栏不再有这个按钮 |
| c6 | “播放”组加“弹幕”“录制” | ✅（有偏差） | “录制”打开录制中心的录制设置页（路由）。“弹幕”打开设置里的弹幕页（v4 原来那组设置，和直播间改的是同一套存储）；直播间里的弹幕设置组件在 `live_play` 功能里，设置不能直接引用，等 U.2e 开发时给它一个路由再换成同一页 |
| c7 | “小窗弹幕”只在总览留一个入口 | ✅ | 视频页（暂用 v4 的行）里没有小窗弹幕；U.6c 按它的设计做 |
| c8 | 搜索：结果就是设置行；Ctrl+F / Cmd+F；Esc 清空 | ✅ | 结果按“页面 › 分组”分组，关键词在标题和说明里标出；开关、滑块、选择直接改；会打开别的页的行（跳转行）改为进到它所在的页并把它高亮 1.5 秒（在子页的行先进页再进子页）；输入停 150 毫秒后才过滤；Esc 只在有字时清空，否则照常返回 |
| c9 | ≥840 左右两栏（左 360、右最宽 720 靠左），下一级页在右栏；600–839 一栏最宽 720 | ✅ | 右栏是一个嵌套的导航器：从右栏打开的页（房间卡片、字体、加载动画、分页设置……）都在右栏里，带返回；返回键先关右栏里的页 |
| c10 | 按所在区域宽度排；缩放分屏时保留位置 | ✅ | `LayoutBuilder`，不读整屏；跨过 840 时右栏的页（和它上面的子页）保留，一栏时直接显示那一页 |
| 主控追加 | 横屏手机顶栏用紧凑高度 | ✅ | 窗口高度 <480 时所有设置页顶栏 48 高（原 56），852×393 下测试固定 |

## 设置行（U.1c 的设置行部分，`packages/live_ui/lib/src/widgets/settings_row.dart`）

| 要求 | 做到 | 说明 |
|---|---|---|
| 跳转、开关、选择、滑块、计数五种，右边按类型变 | ✅ | `SettingsLinkRow`（值 + 箭头；颜色用 `SettingsSwatch`）、`SettingsSwitchRow`（点整行切换）、`SettingsSliderRow`（数值胶囊 + 整行滑块 + 刻度 + 下方示例）、`SettingsCounterRow`（− 值 +，点值输入）、`SettingsChipsRow`（两三个短选项摆在行里）；共用 `SettingsRow` |
| 按下、键盘焦点、悬停、不能用（副标题写原因）、处理中 | ✅ | 按下 10%、悬停 6% 覆盖；焦点框 2 像素主色，只在用键盘时显示；不能用 38% 透明、`disabledReason` 替换说明、不响应点击和焦点；处理中右边转圈、不响应点击 |
| 字体放大 1.5 倍或宽度 <360 时值换到标题下 | ✅ | 开关不换位置 |
| 说明 12 号次要色、最多两行，对比 ≥4.5:1 | ✅ | `onSurfaceVariant` 在 `surfaceContainerLow` 上；测试对四个种子色、深浅两套逐一算对比度 |
| 开关滑块看得见（U.4f） | ✅ | 用 Material 3 默认的开关颜色（打开时白色滑块在主色轨道上），不再设 `activeThumbColor: primary` |
| 电视样式 | ✅（组件部分） | `SettingsRowStyle(tv: true)`：焦点放大 1.05 倍、3 像素近白描边、字大一级；电视的设置页在 U.15i |
| 组、说明 | ✅ | `SettingsGroup`（可以不要卡片，放预览、预设）、`SettingsNote`、`SettingsHighlight`（搜索标记）、`SettingsSearchField` |

v4 设置页原来的通用行（开关、滑块、选择、数字、跳转、动作）全部换成这个组件；其余设置页（视频、弹幕、播放器内核、平台、刷新、通用、网络、缓存）的行也已经用它画，内容和分组仍是 v4 原来的，等 U.6c～U.6e 按设计重做。`live_ui` 原来的 `buildTile`/`buildModernCard` 等没有改（别的功能还在用）。

## 和设计不同的地方

1. **“弹幕”行**：见 c6。
2. **“本地互动体验”**：v4 还没有本地互动功能（U.2k 开发中），这一行打开一个“还在开发，做好后在这里设置”的空状态页。
3. **去掉的 v4 自加项**：v4 原来设置里的“关于”分区（关于、检查更新）、每个分区的“恢复本分区默认值”和改动数角标、“录制中心”和“WebDAV”两个链接不在设计里，去掉了；关于和检查更新在首页 ≡ 菜单，WebDAV 在备份页，录制中心在底部导航和录制设置里。“恢复全部默认设置”“日志管理”留在“缓存与数据管理”页（U.6e 再定）。
4. **搜索结果的分组标题**整行用主色（设计图里“›”后面是次要色）。

## v3 文件 → v4 文件

| v3 | v4 |
|---|---|
| `modules/settings/settings_page.dart` | `features/settings/settings_page.dart`（总览、搜索、两栏）、`settings_model.dart`（分组、页面、条目）、`settings_section_view.dart`（目录驱动的页、子页、高亮） |
| `common/widgets/widget_extensions.dart`（`buildGroupTitle`、`buildModernCard`、`buildTile`、`buildSwitchTile`、`buildMenuTile`、`buildSliderTile`） | `packages/live_ui/lib/src/widgets/settings_row.dart`；`features/settings/settings_tiles.dart`（绑定设置的行、`settingsAppBar`、`SettingsPageBody`） |

## 新增

- 设置：没有（总览只是入口）。
- 翻译：中英各加 77 条（两个任务合计，`settings_area_*`、`settings_*_desc` 等），按键名排序。

## 门禁

- `settings` 直接写的颜色和图标 **209 → 126**（`tools/gate/ui_baseline.json` 已改）；新写的总览、外观、导航、字体页都用 `AppIcons`，剩下的在 U.6c～U.6e 那几页的行里。
- 没有新增跨功能引用（导航栏页用的 `settings -> home/home_menu.dart` 原来就在基线里）；`search -> settings/settings_model.dart` 仍可用（`SettingsSection.network` 还在）。

## 测试

- `apps/pure_live/test/features/settings/settings_page_test.dart`：25 个（原 13 个按新结构重写：原来的“分区列表”“分区恢复默认”“主题模式三按钮”“语言跟随系统”“宽屏分区”断言和新设计冲突，改成新结构的同类断言）。总览：五组和 16 行的顺序、图标、两行说明、顶栏没有配置预览；行打开页、返回；返回链（先关子页再回总览，附录 A 第 7 条）；1280×1400 两栏（左 360、右栏子页、选中态）；852×393 两栏和 48 高顶栏；760 宽一栏最宽 720；跨 840 缩放保留页；搜索（分组标题、标记、就地开关、每个词都要匹配、空结果、清空）；结果里的跳转行进页并高亮；Ctrl+F 和 Esc。
- `packages/live_ui/test/settings_row_test.dart`：16 个（组和分隔线位置、两行说明和对比度、开关整行点、开关颜色、不能用、处理中、窄屏和 1.5 倍字体换行、计数、滑块、选项、搜索标记、电视焦点放大和描边；颜色选择器 3 个、主题 3 个，见 U.6b）。
- 全部：`apps/pure_live` 290 个、`live_ui` 61 个、`live_store` 36 个通过；`flutter analyze`/`dart analyze --fatal-infos` 三个包无问题；`check_ui_structure.py` 通过。
- 没有做 profile 帧时间（本机只跑了单元和组件测试）；设置列表行数少（每页 ≤30 行），页面用一次性构建的滚动视图，以便搜索高亮时滚到那一行。
