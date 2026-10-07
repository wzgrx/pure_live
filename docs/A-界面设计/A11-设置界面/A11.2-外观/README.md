# A11.2 外观：设计（第 1 版，已定稿并实现）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 范围：设置 › 外观（v3“主题定制”）和从它进去的页：主题颜色、加载动画、房间卡片、分页、字体管理、精细化字号；设置 › 导航栏显示控制；候选 C-3（默认品牌蓝）、C-4（纯黑）、C-7（一个文字大小）
- 对应：[TASKS.md](../../../TASKS.md)、[inventory/UI.md](../../../inventory/UI.md#a112)（A11.2-01～17）、[inventory/UI_FILES.md](../../../inventory/UI_FILES.md#a112)；设置首页和设置行在 [A11.1](../A11.1-设置总览/README.md)
- 旧编号：U.6b、T09a.3（见 [MAPPING.md](../../../MAPPING.md)）；相关决定 D-003（T1～T4 按建议 A）、D-018（`themeColorSwitch` 改默认值是唯一例外，用迁移处理）；记录 [record.md](record.md)
- 评审页：claude.ai 私有页面（只有项目所有者能打开）；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)（设置行、两栏排法用 [A11.1/src/skit.py](../A11.1-设置总览/src/skit.py)）
- 图片：v3 按 `v3.2.11` 代码还原（文字取自 `assets/translations/zh.json`，加载样式名取自 `common/consts/app_consts.dart`，字体取自 `assets/fonts/fonts-manifest.json`）；房间卡片封面是示意图片，加载动画是示意图形，字体文件大小是示意数字

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| A11.2-11 | 外观页 `ThemeSettingsPage`（v3“主题定制”） | 设置 › 外观 | 竖屏、横屏、宽屏（右栏） | 默认；宽度 >680 多“分页设置”（v3） |
| A11.2-12 | 主题模式对话框 | 外观 › 主题模式 | 对话框 | 跟随系统 / 深色 / 浅色 |
| A11.2-13 | 切换语言对话框 | 外观 › 切换语言 | 对话框 | English / 简体中文 |
| A11.2-14、15 | 列间距、行间距对话框 `ThemeSpacingDialog` | 外观 › 列间距 / 行间距 | 对话框 | 预设、输入、超出范围“请输入 0 到 64 之间的间距” |
| A11.2-16、17 | 颜色对话框 `_AppColorPickerDialog` | 外观 › 主题颜色；加载动画 › 修改加载颜色（多透明度） | 对话框 | 常用色、鲜艳色、自定义、调色盘；代码错误“请输入 6 位 RGB 或 8 位 ARGB 十六进制颜色代码” |
| A11.2-06 | 加载动画 `LoadingStyleSettingsPage` | 外观 › 修改加载动画 | 竖屏、宽屏 | 选中；86 种 |
| A11.2-10 | 房间卡片设置 `RoomCardSettingsPage` | 外观 › 房间卡片设置 | 竖屏、宽屏 | 移动端 / 桌面端；预设或自定义 |
| A11.2-08 | 分页设置 `PageSettingsPage` | 外观 › 分页设置（v3 宽度 >680；新：电脑） | 宽屏 | — |
| A11.2-09 | 单页可选数量对话框 | 分页设置 › 单页可选数量列表 | 对话框 | 范围错误“请输入 1 至 100 的整数”、重复“该单页数量已在列表中” |
| A11.2-07 | 导航栏显示控制 `NavigationSettingsPage` | 设置 › 导航栏显示控制（A11.1） | 竖屏、宽屏 | 显示 / 隐藏；只剩一个时提示“请至少保留一个底部菜单标签页。”；v3 只有 Windows 有多画面开关 |
| A11.2-01 | 字体管理 `FontFamilyManagerPage` | 外观 › 字体；视频 › 更换弹幕字体（同一页，A11.3） | 竖屏、宽屏 | 系统默认 / 未下载 / 下载中 / 已下载 / 正在使用；加载中（列表空时转圈） |
| A11.2-02、03 | 字重选择 `FontWeightSelectorDialog` | 多字重字体点“应用”或下载完 | 对话框 | 选择中（按钮不能点） |
| A11.2-04 | 精细化字号 `FontSettingsPage` | 外观 › 精细化字号微调 | 竖屏、宽屏 | — |
| A11.2-05 | 重置确认 | 精细化字号右上角 | 对话框 | — |
| — | 提示条 | 上面各页 | 底部 | “已应用字体: {name}”“已应用专属字重: {name} ({subName})”“字体已成功重置为默认值”“字库载入失败，请重试”“字体目录打开失败，请检查目录访问权限”“字体删除失败，请重试”“所选字体未下载或已损坏，请重新选择或下载”“恢复默认” |

## v3 的样子

**外观页**（`theme_settings_page.dart:21-192`）：顶栏“主题定制”居中。7 组：
1. 主题定制：主题模式 `Remix.moon_clear_line`（副标题“切换系统/亮色/暗色模式”，箭头）→ 主题颜色 `palette_line`（右边 28×28、圆角 6 的色块，没有箭头）→ 动态取色 `magic_line`（开关，“启用Monet壁纸动态取色”）→ 修改加载动画（图标位置是正在转的小加载动画，右边 13 号轮廓色的样式名“默认圆环”）。
2. 房间卡片设置：一行 `layout_grid_line`，右边箭头 24 号、颜色和别的行不同（`:98`）。
3. 网格间距设置：列间距 (横向) `arrow_left_right_line`、行间距 (纵向) `arrow_up_down_line`，点开对话框。
4. 分页设置（只在 `Get.width > 680` 时，`:119`）：一行 `pages_line`。
5. 区域与语言：切换语言 `global_line`。
6. 字体样式设置：更换系统默认字体 `font_color`，副标题“当前字体: Default”（存储的名字，`:151`）。
7. 界面字号调节：精细化字号微调 `font_size` → 全局字体缩放比例 `text_spacing` 滑块（0.50–2.00，数值标签“1.00”）→ 居中轮廓色的示例“这是用来预览全局字体大小变化的示例文字”。

**主题模式、语言**（`ThemeChoiceDialog` `:276-337`）：圆角 16，宽度 <420 时左右留 12；标题 20 号粗体；单选行，选完就关。主题模式顺序“跟随系统、深色模式、浅色模式”（`app_consts.dart:25-35`）；语言“English、简体中文”。

**间距**（`ThemeSpacingDialog` `:350-524`）：标题；预设 0/4/6/8/12/16 px（`ChoiceChip`，没有边框，选中是次色容器）；说明；输入框（右边上下两个 48 的箭头按钮，±1）；取消、确认（凸起按钮）。范围 0–64，默认 6。

**颜色**（`app_color_picker_dialog.dart:194-283`，flex_color_picker）：标题“主题颜色”；分段“常用色 / 鲜艳色 / 自定义 / 调色盘”（`自定义`是应用的 14 种：Crimson … Secondary，`app_consts.dart:50-65`）；48×48 圆角 4 的色块，选中打勾；“选择色阶”；“RGB 颜色代码”输入框（提示 `#RRGGBB / 0xRRGGBB`）；取消、确定。选色时背后的界面即时换色，取消恢复。加载颜色多“选择透明度”和 ARGB 代码。

**加载动画**（`loading_style_settings_page.dart:390-548`）：顶栏右边 `arrow_go_back_line`（恢复默认，不确认）；“修改加载颜色”一行（色块）；网格：宽 <360 两列、<600 三列、≥600 四列、≥900 六列，字体放大 1.5 倍以上 1–3 列；格子圆角 16、动画 36、名字 11 号粗体，选中是主色边框加右上角勾。

**房间卡片**（`room_card_settings_page.dart:32-310`）：顶栏右边 `restart_line`（重置当前布局，不确认）；应用到（移动端 / 桌面端）；实时预览；快捷预设（简洁 / 标准 / 详细，改过单项时多一个点不了的“自定义”）；显示内容：显示主播头像、显示主播名称、显示平台徽章（自动 / 始终显示 / 隐藏）、显示观众指标、显示回放徽章；外观：卡片布局（封面卡片 / 紧凑信息行）、圆角大小（0–32，默认 20）；底部说明。这一页的开关行自己画：图标灰色、副标题正文色。

**分页设置**（`page_settings.dart:9-205`）：通用分页控制条：显示单页数量选择器、显示页码跳转按钮、显示一键置顶按钮（开关，默认都开）、单页可选数量列表（副标题是当前列表）。对话框：当前已启用的可选项（带 ✕ 的标签，至少留一个）、“自适应推荐”（转屏图标）、自定义输入尺寸（1–100，后缀“条/页”）和“添加”；取消、确认。

**导航栏显示控制**（`navigation_settings_page.dart:10-206`）：Windows 才有“多画面”开关一组；提示条“长按右侧图标并上下拖动……”；四行（关注 `heart_3_fill`、热门 `CustomIcons.popular`、分区 `apps_2_line`、录制中心 `download_2_fill`），每行开关和排序把手 `sort_asc`（按住就拖）；隐藏的排最后、没有把手。

**字体管理**（`font_family_manager_page.dart:90-612`）：顶栏“字体样式设置”（弹幕时“更换弹幕字体”），右边“打开文件夹”（宽度 <520 只有图标）；系统预设环境：系统默认（Windows 写 Microsoft YaHei），选中时主色边框和勾；扩展个性化字库：每款一张圆角 24 的卡片（投影、渐变）：名字 15 号 800、大小和许可证标签、简介、“N 个字重组件文件”、按钮：未下载“点击下载”，下载中转圈（别的按钮都不能点），已下载删除图标加“应用”，正在用“当前正使用 ✓ 应用”；点已下载的卡片打开它的文件夹。

**字重**（`:625-779`）：“请选择「X」的样式”，“智能跟随系统粗细 (推荐)”，每个文件一行“锁定使用 - Regular 体”，取消；选择中不能关。

**精细化字号**（`font_settings_page.dart:16-170`）：内容最宽 720；两组五个滑块：微型辅助文本 (Body Small) 9–15 默认 12，标准正文大小 (Body Medium) 11–17 默认 13，加粗段落正文 (Body Large) 12–18 默认 14，中号卡片标题 (Title Medium) 13–20 默认 15，大号顶栏标题 (Title Large) 16–26 默认 20；数值写“12px”；右上角重置 → 确认框（“将五项精细字号全部恢复为默认值？”，红色“重置”）→ 提示“恢复默认”。

存储键（都不变）：`themeMode`、`enableDynamicTheme`、`themeColorSwitch`、`language`、`crossAxisSpacing`、`mainAxisSpacing`、`loadingStyle`、`loadingStyleColorSwitch`、`textScaleFactor`、`fontSizeBodySmall/BodyMedium/BodyLarge/TitleMedium/TitleLarge`、`fontFamilyName`、`fontFamilyFileName`、`room_card_mobile_preset`、`room_card_desktop_preset` 和两端配置、`page_show_size_selector`、`page_show_goto_button`、`page_show_scroll_top`、`page_default_size`、`page_size_options_raw`、`savedMenuIds`、`enableMultiView`；v4 已有的 `uiMode`。新加只有纯黑背景一个键（选 C-4 时）。

v4 现在的偏差（J01.1 时自行设计）：外观摊在设置的“外观”分区里，主题模式是行内三个按钮，间距是滑块，语言多了“跟随系统”；新设计回到 v3 的页和弹法，只修具体问题。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 外观页 4 组、行上显示值、各子页修具体问题、C-3/C-4/C-7、四个选择 | 待评审 |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [对比：外观页（手机竖屏）](page/02-对比-外观页-手机竖屏.jpg)
- [对比：横屏和宽屏](page/03-对比-横屏和宽屏.jpg)
- [主题模式、语言、间距的对话框](page/04-主题模式-语言-间距的对话框.jpg)
- [主题颜色](page/05-主题颜色.jpg)
- [主题色和纯黑（C-3、C-4）](page/06-主题色和纯黑-C-3-C-4.jpg)
- [字体管理](page/07-字体管理.jpg)
- [字体管理的弹窗和下载中](page/08-字体管理的弹窗和下载中.jpg)
- [精细化字号](page/09-精细化字号.jpg)
- [加载动画](page/10-加载动画.jpg)
- [房间卡片设置](page/11-房间卡片设置.jpg)
- [导航栏显示控制](page/12-导航栏显示控制.jpg)
- [分页设置（只在电脑上）](page/13-分页设置-只在电脑上.jpg)
- [v3 的问题](page/14-v3-的问题.jpg)
- [改了什么](page/15-改了什么.jpg)
- [每个按钮是干什么的、怎么用](page/16-每个按钮是干什么的-怎么用.jpg)
- [各客户端](page/17-各客户端.jpg)
- [需要你选的](page/18-需要你选的.jpg)
- [性能要点](page/19-性能要点.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-appearance.jpg](v3-appearance.jpg)、[v4-appearance.jpg](v4-appearance.jpg) | 外观页，手机竖屏整页 |
| [v3-appearance-land.jpg](v3-appearance-land.jpg)、[v4-appearance-land.jpg](v4-appearance-land.jpg) | 手机横屏 |
| [v3-appearance-wide.jpg](v3-appearance-wide.jpg)、[v4-appearance-wide.jpg](v4-appearance-wide.jpg) | 1280 宽（Windows） |
| [v3-dialogs.jpg](v3-dialogs.jpg)、[v4-dialogs.jpg](v4-dialogs.jpg) | 主题模式、切换语言、列间距 |
| [v3-color.jpg](v3-color.jpg)、[v4-color.jpg](v4-color.jpg) | 主题颜色对话框 |
| [v4-theme-options.jpg](v4-theme-options.jpg) | v3 默认蓝、品牌蓝（C-3）、深色、纯黑（C-4） |
| [v3-fonts.jpg](v3-fonts.jpg)、[v4-fonts.jpg](v4-fonts.jpg) | 字体管理 |
| [v3-fontweight.jpg](v3-fontweight.jpg)、[v4-font-popups.jpg](v4-font-popups.jpg) | 字重选择；新设计的 ⋮ 菜单、删除确认、字重、下载中 |
| [v3-fontsizes.jpg](v3-fontsizes.jpg)、[v4-fontsizes.jpg](v4-fontsizes.jpg) | 精细化字号（v3 含重置确认） |
| [v3-loading.jpg](v3-loading.jpg)、[v4-loading.jpg](v4-loading.jpg) | 加载动画（新设计含恢复默认确认） |
| [v3-roomcard.jpg](v3-roomcard.jpg)、[v4-roomcard.jpg](v4-roomcard.jpg) | 房间卡片设置 |
| [v3-nav.jpg](v3-nav.jpg)、[v4-nav.jpg](v4-nav.jpg) | 导航栏显示控制 |
| [v3-page.jpg](v3-page.jpg)、[v4-page.jpg](v4-page.jpg)、[v4-page-dialog.jpg](v4-page-dialog.jpg) | 分页设置和单页可选数量（电脑） |
| `v4-*-n.jpg` | 按钮编号示意图（编号 1–97，见对比页的用法表） |

## v3 的问题

| 编号 | 问题 | 位置 |
|---|---|---|
| Q1 | 7 组里 3 组只有一行且组名等于行名；文字相关分两组 | `theme_settings_page.dart:27-188` |
| Q2 | 主题模式、语言、间距看不到当前值；字体写“Default” | `:29-34`、`:106-117`、`:136-141`、`:151` |
| Q3 | 全局缩放替换系统字体大小；显示“1.00” | `main.dart:140`、`:188-189`；`:167-180` |
| Q4 | 分页设置按整屏宽度 >680 显示：手机改不了置顶按钮，平板上前三项无效 | `:119`；`base_page_view.dart:55-57`、`:179` |
| Q5 | “显示页码跳转按钮”不起作用 | `desktop_components.dart:160-180`；`page_settings_controller.dart:15` |
| Q6 | 选的颜色和界面主色对不上（tonalSpot）；#2196F3 白字 3.1:1 | `common/style/theme.dart:107`；`theme_settings_controller.dart:13` |
| Q7 | 颜色对话框“自定义”里是预设色；手机上要滑 | `app_color_picker_dialog.dart:47-50`、`:235-248` |
| Q8 | 加载动画恢复默认不确认；列数按整屏宽度；名字 11 号 | `loading_style_settings_page.dart:396-432`、`:523` |
| Q9 | 房间卡片重置不确认；“自定义”点不了；开关行样式和别的页不同 | `room_card_settings_page.dart:39-44`、`:91-96`、`:184-199` |
| Q10 | 字体：点卡片开文件夹、删除不确认、下载只有转圈、正在用旁还有“应用”、“点击下载”、投影渐变 | `font_family_manager_page.dart:212`、`:432-441`、`:421-423`、`:397-419`、`:182-226` |
| Q11 | 导航栏：多画面开关只 Windows 有；图标和导航栏不同；提示写“长按” | `navigation_settings_page.dart:23-34`、`:89-105`、`:131`；`common_appbar_actions.dart:56`、`tablet_view.dart:111`、`mobile_view.dart:32-60` |
| Q12 | 精细化字号看不到效果，标题是英文术语 | `font_settings_page.dart:45-117` |
| Q13 | 间距预设没边框；输入框被箭头撑高 | `theme_settings_page.dart:436-450`、`:465-489` |
| Q14 | 主题和间距对话框圆角 16，别的对话框 24 | `theme_settings_page.dart:290`、`:416`；`common/style/theme.dart:182` |

## 确认的改动

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 保留 | 全部设置项、存储键、弹法、动画和字体的种类、字号范围 | — |
| c2 | 修改 | 外观页 4 组（主题、房间卡片和列表、语言和界面、字体和字号）；页名改“外观” | Q1 |
| c3 | 修改 | 行上显示当前值；动态取色生效时主题颜色变灰 | Q2 |
| c4 | 修改 | 间距改计数行，对话框预设加边框、输入框正常高 | Q2、Q13 |
| c5 | 修改 | 文字大小叠在系统字体大小上，显示百分比和示例 | Q3 |
| c6 | 修改 | 置顶按钮开关挪到外观、所有设备；分页设置只在电脑上 | Q4 |
| c7 | 修改 | 页码跳转开关生效 | Q5 |
| c8 | 修改 | 默认品牌蓝 #2E6FE0、fidelity；3.x 默认蓝迁移（C-3） | Q6 |
| c9 | 增强 | 纯黑背景开关（C-4） | — |
| c10 | 修改 | 颜色对话框“自定义”改“推荐”放第一；圆形色块；圆角 24 | Q7、Q14 |
| c11 | 修改 | 加载动画：恢复默认确认、列数按内容宽度、名字 12 号 | Q8 |
| c12 | 修改 | 房间卡片：统一设置行、端名注明设备、重置确认、自定义说明 | Q9 |
| c13 | 修改 | 字体：⋮ 菜单、删除确认、下载进度、正在使用、换字重、字名用本字体、去投影 | Q10 |
| c14 | 修改 | 导航栏：多画面开关全平台、图标一致、提示改“按住” | Q11 |
| c15 | 修改 | 精细化字号每项带示例（C-7） | Q12 |

## 按钮的作用和用法

见对比页“每个按钮是干什么的、怎么用”一节（1–97）。

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 上面的图；动态取色 Android 12 起 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 设置右栏，内容最宽 720；电脑多“分页设置”；Windows 的系统默认字体写 Microsoft YaHei |
| 电视 | 只有深色，“主题模式”不显示、“纯黑背景”保留；同一套设置行的电视样式（A17.9） |
| 苹果平台 | 同宽屏；iOS 不显示动态取色；macOS 跟随系统强调色 |

## 待选

- T1 默认主题色（C-3）：建议品牌蓝 #2E6FE0（fidelity），3.x 默认蓝迁移；另一种照 v3。
- T2 纯黑背景（C-4）：建议加开关，默认关。
- T3 文字大小（C-7）：建议“文字大小”为主、五个字号保留在子页；另一种合并掉五个字号（3.x 的值会丢）。
- T4 列间距、行间距：建议计数行；另一种照 v3 只有对话框。

## 拿不准的地方

- 间距对话框的输入框高度：按代码 `suffixIcon` 是两个 48 高的按钮叠起来，推算框高 96；实际渲染请对照 3.x。
- 间距预设没有边框：`ChoiceChip(side: BorderSide.none)` 没选中时按 Material 3 默认是透明底，所以画成只有文字；请对照 3.x。
- 房间卡片的预览卡片按 `room_card.dart` 的结构简化画（封面、右下角人数、头像、标题、主播名），人数“1.3万”的写法以 `readableCount` 为准；卡片本身在 A09.1。
- 字体文件大小（38.6 MB 等）是示意数字，清单里没有大小。
- 纯黑背景的存储键名开发时定（建议 `pureBlackTheme`，`theme` 段）。

## 跨任务待同步（由主控写进 TASKS.md 第 7 节）

- A11.3：“更换弹幕字体”打开本任务的字体页（弹幕范围，标题“更换弹幕字体”），用同样的 ⋮ 菜单、删除确认和下载进度。
- A09.1：卡片的“显示平台徽章”“卡片布局”“圆角大小”在这里设置，卡片设计改了的话这里的预览跟着改。
- A17.9：电视只有深色，外观页去掉“主题模式”，保留“纯黑背景”。
- A01.2：选 C-3、C-4 后，`live_ui` 的颜色角色加品牌蓝（fidelity）和纯黑两套。

## 实现和验证

**定稿**：用户确认第 1 版，T1～T4 按建议 A（C-3 品牌蓝 #2E6FE0 + fidelity 配色、3.x 默认蓝迁移；C-4 纯黑背景默认关；C-7“文字大小”为主、五个字号留在子页；间距用计数行；D-003）。

**实现**（详见 [record.md](record.md)；2026-10-01，提交 `6a61ef4f2`（和 A11.1 一起），合并 `5e77cca15`“Merge U.6a-b: settings overview and appearance”；登记表记的是 `3f53f8123`（记录））

| 编号 | 做到 | 现在的代码（`apps/pure_live/lib/features/settings/` 省略前缀） |
|---|---|---|
| c1 | ✅ | 外观的行在 `settings_catalog.dart:326-516`、导航栏 `:518-535`；3.x 存储键一个没改；85 种加载动画（`loading_style_names.dart`，设计和记录写的“86 种”是笔误，3.x `AppConsts.allStyles` 也是 85 种）、57 种字体、字号范围照旧 |
| c2 | ✅ | 四组：主题 `:327`、房间卡片和列表 `:370`、语言和界面 `:418`、字体和字号 `:441`；页名“外观” |
| c3 | ✅ | 行上的值：主题模式 `ThemeModeTile`（`appearance_pages.dart:45`）、主题颜色色块 `ThemeColorTile`（`:108`，动态取色开着时变灰写原因 `:119-126`，iOS 不算）、语言 `LanguageTile`（`:145`）、字体 `FontFamilyTile`（`:391`，“系统默认”，Windows 写 Microsoft YaHei）；iOS 不显示动态取色（`settings_catalog.dart:359` `_notIos`） |
| c4 | ✅ | `SpacingTile`（`appearance_pages.dart:193`，`SettingsCounterRow` ±1 px、0～64、到头变灰）；点数字开对话框（`:244` 起：0/4/6/8/12/16 px 预设带边框、输入框后缀 px、范围校验） |
| c5 | ✅ | `TextScaleTile`（`:348`，50%～200%，示例随拖动变，停 200 毫秒写入）；`AppTextScaler`（`packages/live_ui/lib/src/theme/text_styles.dart:175`）在 `apps/pure_live/lib/app/app.dart:246` 把系统缩放和应用倍数相乘 |
| c6 | ✅ | 一键置顶按钮在外观、所有设备（`settings_catalog.dart:402-408`）；分页设置只在电脑上（`:410-417`，`when: _desktop`），子页 `SettingsSubpage.paging`（`:476` 起） |
| c7 | ✅ | 页码跳转开关（`:490`）由分页条读：`shared/rooms/room_grid.dart:512`、`features/areas/platform_areas_view.dart:236`、`features/favorite/favorite_page.dart:401` → `PaginationBar`（`shared/rooms/paging.dart:37`）；v4 原来就接上了，补了测试 |
| c8 | ✅ | `LiveTheme.brandBlue`（`packages/live_ui/lib/src/theme/live_theme.dart:177`）；`app.dart:190-204` 用 `DynamicSchemeVariant.fidelity`；`themeColorSwitch` 默认值 `FF2196F3` → `FF2E6FE0`；迁移 `LegacyRules.themeColor`（`packages/live_store/lib/src/legacy/legacy_rules.dart:19`，导入 3.x 数据和 3.x 备份时）和一次性记录 `themeColorMigration`（`packages/live_store/lib/src/settings/settings.dart:169`，已导入过的安装只迁移一次） |
| c9 | ✅ | `PureBlackTile`（`appearance_pages.dart:79`，默认关、浅色时变灰写原因）；新设置 `pureBlackTheme`；深色时 `LivePureBlack`（`packages/live_ui/lib/src/theme/live_colors.dart:314`，`surface` 纯黑、卡片 `#0E0E10`、`#161618`、`#1E1E21`），`app.dart:160` 读它 |
| c10 | ✅ | `showColorDialog`（`settings_dialogs.dart:317`，圆角 24）里是 `LiveColorPicker`（`packages/live_ui/lib/src/widgets/color_picker.dart:73`：推荐第一且品牌蓝排第一、圆形色块、当前色加圈和勾，常用、鲜艳、调色盘、色阶、透明度、代码）；选色时背后界面即时预览，取消恢复 |
| c11 | ✅ | `LoadingStylePage`（`appearance_pages.dart:580`：恢复默认先确认 `_restore` `:584`；每格至少 104 宽、大字号时更宽 `:664-666`，手机 3 列；名字 12 号；颜色行写“现在：…”；每格一个重绘边界） |
| c12 | ✅ | `RoomCardSettingsPage`（`:764`）：“移动端（手机、平板）”“桌面端（电脑）”、重置先确认（`_reset` `:800`）、“当前：自定义”说明；平台徽章、卡片布局是行内选项，圆角是滑块行 |
| c13 | ✅（偏差 1） | `font_manager_page.dart`：卡片的 ⋮ 菜单（`:260`，打开所在文件夹、删除；现在是 A02.3 的 `AppMenuButton`）、删除确认（`:132`）、下载进度“下载中 3/7”和“取消”（`:102`、`:303-321`）、“正在使用”（`:385`）、换字重（`_pickWeight` `:166`，标出现在用的）、去投影渐变；页名“字体”；`danmaku: true` 时是“更换弹幕字体”（A11.3 用） |
| c14 | ✅ | 导航栏页两组“首页入口”“底部导航栏”（`settings_catalog.dart:519`、`:528`）；多画面开关所有平台（`:523`）；`HomeMenusList`（`appearance_pages.dart:1176`）图标和导航栏同一份（`HomeMenu`），提示“按住”，隐藏的排最后写“已隐藏”、至少留一个 |
| c15 | ✅ | `FontSizesPage`（`:444`）：顶上说明、五个滑块各带示例（`:462`）、重置先确认（红色“重置”） |

- 根因（记录，设计里查出的 v3 问题）：页码跳转开关存了不读（Q5）；全局字体缩放替换了系统字号（Q3）；默认色块和界面颜色不一致（Q6，3.x 的配色算法会把种子色调暗）；分页设置按整屏宽度判断（Q4）；多画面开关只有 Windows（Q11）。
- 偏差（记录）：①字体卡片的名字用本字体显示只对本次已加载的字体生效（为显示名字去加载每款几十 MB 的字体太占内存）；②范围外的改动：主题和文字大小只能在 `apps/pure_live/lib/app/app.dart` 生成，`live_store` 改了 `themeColorSwitch` 的默认值并加迁移（D-018 的唯一例外，C-3 本身的要求）。
- 新设置 `pureBlackTheme`（`theme` 段，默认关，进备份；3.x 读备份时忽略）和内部记录 `themeColorMigration`（不进备份）。翻译中英各 77 条（和 A11.1 合计）；`AppIcons` 加 54 个，颜色进 `LivePureBlack`、`LivePalettes`、`LiveTvColors`。门禁：`settings` 直接写的颜色和图标 209 → 126（和 A11.1 合计）。
- 后来的变化：M14.1 在“语言和界面”加了“界面模式”（自动 / 手机 / 电视，`settings_catalog.dart:427-440`）；A11.3 c7 把主题模式、语言对话框改成“主色 + 勾”的选项行；A02.3（`9f68079cc`）把字体卡片的 ⋮ 换成 `AppMenuButton`；颜色对话框的主按钮写“保存”（A02.2）。

**验证**

- 自动测试：`apps/pure_live/test/features/settings/settings_page_test.dart` 的 `appearance (U.6b)`、`navigation (U.6b)` 两组 11 个和页码跳转 1 个（外观四组和行序、行上的值、分页设置只在电脑上；主题模式和语言对话框；纯黑默认关、浅色时变灰；颜色预览、取消恢复、代码校验、动态取色时变灰；间距加减和对话框；分页设置子页；精细化字号示例和重置确认；加载动画 3 列和恢复确认；房间卡片端名、自定义说明、重置确认；导航栏多画面开关、隐藏排最后、至少留一个；页码跳转开关控制分页条）；`packages/live_ui/test/settings_row_test.dart` 里颜色选择器 3 个、主题 3 个（fidelity 主色和白字对比、纯黑只改深色、文字大小相乘）；`packages/live_store/test/theme_color_test.dart` 4 个（默认值、迁移规则、3.x 数据和备份迁移而 v4 备份不迁移、已导入的安装只迁移一次且之后保留用户的选择）。字体页没有组件测试（下载、加载、删除逻辑在 `services_test.dart`）。
- 真机：记录里没有 K90 结果（S02 的 CHECKLIST 第 5 节第 5 条“下载一个字体设为应用字体，重启”归 [S02.4](../../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md)，未开始）。登记表是“完成”，问题见[子分类页](../README.md)“已知问题”；建议 S02.4 和 [S03.1](../../../S-质量和验证/S03-统一验证/S03.1-统一验证/README.md) 补看：设置 → 外观，换主题颜色（背后即时变、取消恢复）、深色下打开纯黑背景、文字大小拖到 150% 看示例和首页、下载一个字体并设为应用字体后重启、加载动画选一个后进直播间看转圈。
- 留下的问题和去向：电视设置的颜色列表还是 3.x 的蓝、电视去掉“主题模式”→ A17.9；A01.2（设计系统）把品牌蓝和纯黑写进颜色角色的文档 → A01.2（开发中）。
