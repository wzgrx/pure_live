# U.6b 外观

- 日期：2026-10-01
- 设计：[docs/ui/compare/U.6b/README.md](../compare/U.6b/README.md)（第 1 版，用户已确认；T1～T4 按建议 A：C-3 品牌蓝 #2E6FE0 + fidelity、3.x 默认蓝迁移；C-4 纯黑背景默认关；C-7“文字大小”为主、五个字号留在子页；间距用计数行）
- 一并处理的跨任务待同步：U.6b → U.1a（品牌蓝和纯黑两套配色角色）
- 改动的目录：`apps/pure_live/lib/features/settings/`、`apps/pure_live/lib/app/app.dart`（主题和文字大小在这里生成，见“设计范围外的改动”）、`packages/live_ui`、`packages/live_store`、翻译文件、门禁基线、文档
- 设置行、总览、两栏见 [U.6a.md](U.6a.md)；没有改原生部分，没有构建 APK

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 全部设置项、3.x 存储键、弹法、86 种动画、57 种字体、字号范围 | ✅ | 键都没改；主题模式、语言、主题颜色、字重用对话框，房间卡片预设和布局摆在行里 |
| c2 | 外观页 4 组；页名“外观” | ✅ | 主题（主题模式、纯黑背景、主题颜色、动态取色、修改加载动画）→ 房间卡片和列表（房间卡片设置、列间距、行间距、显示一键置顶按钮、分页设置〔电脑〕）→ 语言和界面（切换语言、界面模式）→ 字体和字号（字体、文字大小、精细化字号微调） |
| c3 | 行上显示当前值；动态取色生效时主题颜色变灰写原因 | ✅ | 跟随系统 / 简体中文 / 6 px / 系统默认（Windows 写 Microsoft YaHei），不再显示“Default”；iOS 不显示动态取色，也不让它把主题颜色变灰 |
| c4 | 间距计数行“− 6 px +”，点数字开对话框；预设加边框、输入框正常高 | ✅ | 一次 ±1 px（0–64，到头按钮变灰）；对话框：说明、0/4/6/8/12/16 px 预设（带边框，选中打勾，点了填进输入框）、输入框后缀 px、“0 到 64 之间”、超出范围“请输入 0 到 64 之间的间距”、取消 / 确认 |
| c5 | “文字大小”叠在系统字体大小上，百分比、示例 | ✅ | `AppTextScaler`（系统缩放 × 应用倍数，保留系统的非线性曲线）；50%–200%，刻度 50/75/100/125/150/200；下面的示例按拖动中的大小即时变化，停 200 毫秒才写入 |
| c6 | 置顶按钮开关挪到外观、所有设备；分页设置只在电脑上 | ✅ | 按平台判断（不是 Android/iOS 就显示），不按宽度；分页设置是外观的子页，搜索也能找到里面的行 |
| c7 | 页码跳转开关生效 | ✅ | v4 的分页条早已读这个设置（`popular_grid.dart` → `PopularPaginationBar.showGoto`），补了测试固定 |
| c8 | 默认品牌蓝 #2E6FE0、fidelity；3.x 默认蓝迁移 | ✅ | 应用的配色改用 fidelity（所有种子色，选的颜色就是界面主色）；默认值改为 `FF2E6FE0`；迁移见下 |
| c9 | 纯黑背景开关，默认关；浅色模式下变灰写原因 | ✅ | 深色时 `surface` 纯黑，卡片 `#0E0E10`、`#161618`、`#1E1E21` 几层近黑；动态取色时也生效 |
| c10 | 颜色对话框：“推荐”第一（品牌蓝排第一），圆形色块、当前色加圈和勾；常用色、鲜艳色、调色盘、色阶、颜色代码照旧；圆角 24 | ✅ | `live_ui` 的 `LiveColorPicker`（v3 用 flex_color_picker，v4 之前简化成色块 + 代码，这次补回分页、色阶、调色盘和透明度）；点色块背后的界面即时预览，取消恢复，确定保存；设置的对话框圆角统一 24 |
| c11 | 加载动画：恢复默认先确认、列数按内容宽度、名字 12 号、颜色行写“现在：…” | ✅ | 每格至少 104 宽（大字体时更宽），手机 3 列；确认后样式和颜色都恢复；每格一个重绘边界 |
| c12 | 房间卡片：统一设置行、“移动端（手机、平板）”“桌面端（电脑）”、重置先确认、“当前：自定义”说明 | ✅ | 应用到默认选当前这一端；显示平台徽章、卡片布局是行内选项；圆角是滑块行 |
| c13 | 字体：⋮ 菜单（打开所在文件夹、删除）、删除确认、下载进度、正在使用、换字重、“下载”、去投影渐变、字重单选标出现在用的、页名“字体” | ✅（有偏差） | 卡片不再整块可点；下载中显示进度条和“下载中 3/7”，别的按钮不能点，保留 v4 的“取消”；**字名用本字体显示只对本次已加载的字体生效**（为了显示名字去加载每款几十 MB 的字体太占内存，性能要点也这么要求） |
| c14 | 导航栏：多画面开关所有平台都有；图标和底部导航栏一样；提示改“按住”；隐藏的排最后写“已隐藏” | ✅ | 分“首页入口”“底部导航栏”两组；图标用 `HomeMenu` 的（和导航栏同一份）；隐藏的没有把手；至少留一个，提示照 v3 |
| c15 | 精细化字号：每项带示例；顶上说明 | ✅ | 五个滑块照 v3 范围，数值“12px”，示例用这个字号；重置先确认（红色“重置”），完成提示“恢复默认” |

## 设计里查出的 v3 问题（EXTRA 要求照设计修）

| 问题 | 处理 |
|---|---|
| 页码跳转开关不生效（Q5） | v4 已接上；加测试 |
| 全局字体缩放替换了系统字号（Q3） | `app.dart` 用 `AppTextScaler(系统缩放, 文字大小)` |
| 默认色块和界面颜色不一致（Q6） | fidelity 配色；默认品牌蓝 |
| 分页设置按整屏宽度（Q4） | 按平台 |
| 多画面开关只有 Windows（Q11） | 所有平台；首页三处入口本来就读这个设置 |

## 迁移（C-3，只做添加；3.x 数据照旧能读）

- `themeColorSwitch` 的键不变，默认值从 `FF2196F3` 改为 `FF2E6FE0`（**改了一个已有设置的默认值**，这是 C-3 本身的要求）。
- 3.x 首次启动就把默认蓝写进 Hive，所以“3.x 默认蓝的用户”就是存着 `FF2196F3` 的用户（3.x 里手动选了“Blue”的也一样，无法区分）：
  - 导入 3.x 的 Hive 数据、恢复 3.x 的备份（无版本或版本 ≤3）时换成品牌蓝（`LegacyRules.themeColor`，认 `#`、`0x`、大小写）；v4 自己的备份（版本 4）原样恢复。
  - 已经导入过 3.x 数据的 v4 安装：打开存储时检查一次（新的内部记录 `themeColorMigration`，不进备份），只迁移一次；之后用户再选回 `#2196F3` 会保留。
- 新设置：`pureBlackTheme`（`theme` 段，默认关，进备份；3.x 读备份时忽略）。

## 设计范围外的改动（需要主控知道）

- `apps/pure_live/lib/app/app.dart`：主题和文字大小在这里生成，修 Q3、Q6 和做 C-4 只能改这里（fidelity、纯黑、`AppTextScaler`、读不出颜色时的兜底色）。
- 电视设置面板 `tv/pages/tv_settings_pane.dart` 的颜色列表里还是 3.x 的蓝，没有品牌蓝；电视去掉“主题模式”也没做（都属 U.15i）。

## v3 文件 → v4 文件

| v3（`lib/modules/settings/`） | v4（`features/settings/`） |
|---|---|
| `pages/theme_settings_page.dart` | `settings_catalog.dart`（外观、导航栏的行）、`appearance_pages.dart`（主题模式、纯黑、主题颜色、语言、间距、文字大小、字体行） |
| `widgets/app_color_picker_dialog.dart` | `settings_dialogs.dart`（`showColorDialog`）、`packages/live_ui/lib/src/widgets/color_picker.dart` |
| `pages/loading_style_settings_page.dart` | `appearance_pages.dart`（`LoadingStylePage`） |
| `pages/room_card_settings_page.dart` | `appearance_pages.dart`（`RoomCardSettingsPage`） |
| `pages/page_settings.dart` | 目录里的“分页设置”子页 + `appearance_pages.dart`（`PageSizeOptionsTile`） |
| `pages/navigation_settings_page.dart` | 目录里的“导航栏显示控制”页 + `appearance_pages.dart`（`HomeMenusList`） |
| `pages/font_family_manager_page.dart` | `font_manager_page.dart` |
| `pages/font_settings_page.dart` | `appearance_pages.dart`（`FontSizesPage`） |
| `common/style/theme.dart`、`services/settings/theme_settings_controller.dart`（默认色） | `packages/live_ui/lib/src/theme/live_theme.dart`、`live_colors.dart`（`LivePureBlack`、`LivePalettes`）、`packages/live_store`（默认值和迁移）、`app/app.dart` |

## 门禁

- `settings` 直接写的颜色和图标 209 → 126（和 U.6a 合计）；新加的图标全部进 `AppIcons`（`settings*`、`themeMode`、`pureBlack` 等 54 个），颜色进 `LivePureBlack`、`LivePalettes`、`LiveTvColors`。

## 测试

- `settings_page_test.dart`（和 U.6a 共用，25 个里外观部分 11 个）：外观四组和行序、行上的值、分页设置只在电脑上；主题模式和语言对话框（无按钮、顺序、没有“跟随系统”）；纯黑默认关、浅色时变灰写原因；颜色预览、取消恢复、代码校验、动态取色时变灰；间距加减和对话框；分页设置子页（跳转开关、单页数量的推荐、重复、范围、添加）；精细化字号示例和重置确认；加载动画 3 列、恢复确认；房间卡片端名、自定义说明、重置确认；导航栏多画面开关（Android）、隐藏排最后、至少留一个；页码跳转开关控制分页条。
- `live_ui/test/settings_row_test.dart` 里：颜色选择器 3 个（推荐第一和品牌蓝、色阶、鲜艳色、代码校验；调色盘和透明度；代码格式）、主题 3 个（fidelity 主色和白字对比、纯黑只改深色、文字大小相乘）。
- `live_store/test/theme_color_test.dart`：4 个（默认值、迁移规则、3.x 数据和备份迁移 / v4 备份不迁移、已导入的安装只迁移一次且之后保留用户的选择）。
- 字体页没有组件测试（字体库要真文件和清单，`services_test.dart` 已测下载、加载、删除逻辑）；没有做 profile 帧时间。
