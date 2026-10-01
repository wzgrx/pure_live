# U.15h 电视壁纸：设计（第 1 版）

- 状态：待确认（第 1 版，2026-10-01）
- 范围：电视界面背后的背景（壁纸）：背景设置页、壁纸库 / 随机壁纸 API / 分组 / 分类列表、壁纸网格（含纯色和视频壁纸）、预览、沉浸式、清除背景，以及设好以后在各页面后面的样子；见下面的界面清点表
- 对应：[TASKS.md](../../TASKS.md)、[INVENTORY.md](../../INVENTORY.md#u15h)、[TASK_FILES.md](../../TASK_FILES.md#u15h)；依赖 U.15b（外壳）；入口在电视设置（U.15i）；字号、焦点、子页面默认焦点见 [U.15f](../U.15f/README.md)
- 基线：pure_live_TV（`~/ref/pure_live_TV/lib/features/wallpaper`、`services/background_config`），手机版没有这个功能；v4 电视外壳现在背景是纯色（`tv/tv_theme.dart` 的 `TvBackground`），导航轨里留了一个不显示的“壁纸”占位（`tv/home/tv_home_page.dart`）
- 评审页：源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)（公共部分 [../U.15f/src/tvkit.py](../U.15f/src/tvkit.py)）
- 图片：还原图按 pure_live_TV 代码和默认值（等比覆盖、遮罩 35% 黑、不模糊，`background_config_model.dart:12-16`）画；壁纸是示意图片，壁纸库的来源和分类名是示意（远端目录，代码里没有）

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| U.15h-07 | 背景设置（`WallpaperPage`） | 设置 → 主题外观 → 背景设置（`theme_settings_section.dart:65`） | 整页 | 背景来源四项；显示设置：填充模式、遮罩、高斯模糊、清除背景 |
| — | 选择框（填充模式 7 项、遮罩 21 项、高斯模糊 10 项） | 显示设置的三行 | 对话框（`TvDialogUtils.showSelect`） | 当前项 |
| U.15h-06 | 壁纸库（`WallpaperLibraryPage`） | 背景设置 · 壁纸库 | 整页列表 | 列表；远端目录为空 |
| U.15h-03 | 来源（`WallpaperGalleryPage`）：分类列表 | 壁纸库里点来源 | 整页列表 | 多分类；只有一个分类时直接进网格；该来源暂无数据 |
| U.15h-02 | 随机壁纸 API（`WallpaperApiPage`）：必应壁纸、栗次元、无铭 API、UAPI 随机图、360壁纸、其他图源、性感美女 | 背景设置 · 随机壁纸 API | 整页列表 | — |
| U.15h-01 | API 分组（`WallpaperApiGroupPage`）：序号、来源名、接口主机名 | 点分组 | 整页列表 | — |
| U.15h-05 | 壁纸网格（`WallpaperItemsPage` + `WallpaperTile`） | 分类、纯色、视频壁纸 | 整页网格 4 列 | 加载、加载更多、空；当前用的打勾；视频格子有播放图标；纯色是渐变色块 |
| U.15h-08 | 预览（`WallpaperPreviewPage`） | 点格子、点 API 来源 | 全屏 | 图片、视频（播放 / 暂停、音量图标）、随机 API（换一张，取图中转圈）、取图失败、视频失败；设为背景中 |
| U.15h-04 | 沉浸式（`WallpaperImmersivePage`） | 预览 · 沉浸式 | 全屏 | 提示几秒后淡出；设为背景中 |
| — | 应用后的背景（`TvAppBackground`） | 全部页面后面 | 背景层 | 纯色、渐变、图片、视频；遮罩；模糊 |
| 提示条 | 已设为背景、背景已清除、设置失败：{msg}、获取图片失败，请重试、视频播放失败、视频下载失败，已改用在线播放 | 各操作结果 | 底部 | 自动消失 |

## pure_live_TV 的样子（按代码）

- **背景设置**（`wallpaper_page.dart`）：TvPageScaffold “背景设置”，“返回”有开场焦点；组标题“背景来源”（t16 主色 85%），设置卡片（卡片色 5% 底、10% 边、圆角 20）里四个跳转行：纯色（`gradient_outlined`，“纯色与渐变填充”）、视频壁纸（`movie_outlined`，“动态视频背景”）、壁纸库（`photo_library_outlined`，“官方、Wallhaven、必应等图库”）、随机壁纸 API（`auto_awesome_outlined`，“每次打开随机取一张图”）；组标题“显示设置”：填充模式（`aspect_ratio_outlined`，值 + `expand_more`）、遮罩（`brightness_6_outlined`）、高斯模糊（`blur_on_outlined`）、清除背景（`layers_clear_outlined`，只有一个空选项，点了直接清除并提示“背景已清除”，`:92-99`）。行（`core/widgets/tv_settings_row.dart`）：图标 30、标题 t22 600、副标题 t16、右边值 t20 600 或 `chevron_right`；焦点时换焦点卡片色加发光；不聚焦时行没有底色。
- **选项**（`wallpaper_display_options.dart`）：填充 7 种（拉伸填充、完整包含、等比覆盖、适配宽度、适配高度、原始大小、等比缩小），遮罩 0–100% 每 5% 一档（21 档），模糊 关闭、2、4、6、8、12、16、24、32、48。
- **列表页**：设置行；API 页每行左边是序号（`NumberLeading`），副标题“N 个来源”；分组页副标题是接口主机名。
- **壁纸网格**（`wallpaper_items_page.dart`、`wallpaper_tile.dart`）：4 列（`cardGridDelegate`，宽高比 1.3），格子整张图圆角 12，右下大小（例如“2.4M”），视频左下播放图标，当前用的右上角 `check_circle`（`:78`）；焦点放大 1.04、3 像素主色边、发光；离末尾 4 个时加载下一页。
- **预览**（`wallpaper_preview_page_parts.dart`）：整屏图（套用当前的模糊和遮罩）；顶部渐变：标题 t20 600、“3/24”，视频多一个音量图标；底部渐变：“←→ 选择按钮 · OK 确认 · 返回退出”（t18），一排高 56、圆角 26 的按钮（图标 24 + t20 600，焦点填主色）：上一个、下一个（随机 API 是“换一张”，视频前面多“播放 / 暂停”）、填充模式的值、模糊的值、遮罩的值、设为背景、沉浸式；第一个按钮有开场焦点。填充、模糊、遮罩按一下换下一档，直接写全局设置（`:285-298`）。
- **沉浸式**（`wallpaper_immersive_page.dart`）：整屏图；底部居中提示“↑↓ 切换 · OK 设为壁纸 · 返回退出”（黑 65% 圆角，t20），几秒后淡出；↑↓ 换图，←→ 被吞掉（`:151`），确认直接设为背景。
- **应用后**（`core/widgets/tv_scaffold_background.dart`、`services/background_config/background_blur.dart`）：背景在导航器下面一层，导航轨用背景色 62% 透明盖在上面（`home_page.dart`），页面本身透明；模糊用 `ImageFiltered`（`:17`），视频壁纸也一样。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 照 pure_live_TV 还原 6 组界面，只修 7 个具体问题 | 待评审 |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [背景设置](page/02-对比-背景设置.jpg)、[清除背景先确认](page/03-清除背景先确认.jpg)、[列表页](page/04-对比-列表页-随机壁纸-API-壁纸库-分组-分类同一种.jpg)、[壁纸网格](page/05-对比-壁纸网格.jpg)
- [预览](page/06-对比-预览.jpg)、[预览里调遮罩](page/07-预览里调遮罩.jpg)、[沉浸式](page/08-对比-沉浸式.jpg)、[设好以后的样子](page/09-设好以后的样子.jpg)
- [没单独出图的界面](page/10-没单独出图的界面.jpg)、[问题](page/11-pure_live_TV-的问题.jpg)、[改了什么](page/12-改了什么.jpg)
- 按钮用法：[背景设置](page/13-每个按钮是干什么的-怎么用-背景设置.jpg)、[预览](page/14-每个按钮是干什么的-怎么用-预览.jpg)
- [焦点路线](page/15-焦点路线.jpg)、[各客户端](page/16-各客户端.jpg)、[需要你选的](page/17-需要你选的.jpg)、[性能要点](page/18-性能要点.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-settings.jpg](v3-settings.jpg)、[v4-settings.jpg](v4-settings.jpg)、[v4-settings-n.jpg](v4-settings-n.jpg) | 背景设置（新设计滚到显示设置，焦点在遮罩滑块）；编号 1–7 |
| [v4-clear.jpg](v4-clear.jpg) | 清除背景确认 |
| [v3-api.jpg](v3-api.jpg)、[v4-api.jpg](v4-api.jpg)、[v4-api-n.jpg](v4-api-n.jpg) | 随机壁纸 API 列表 |
| [v3-items.jpg](v3-items.jpg)、[v4-items.jpg](v4-items.jpg)、[v4-items-n.jpg](v4-items-n.jpg) | 壁纸网格 |
| [v3-preview.jpg](v3-preview.jpg)、[v4-preview.jpg](v4-preview.jpg)、[v4-preview-n.jpg](v4-preview-n.jpg) | 预览；编号 1–7 |
| [v4-preview-mask.jpg](v4-preview-mask.jpg) | 预览里调遮罩（滑块） |
| [v3-immersive.jpg](v3-immersive.jpg)、[v4-immersive.jpg](v4-immersive.jpg) | 沉浸式 |
| [v3-applied.jpg](v3-applied.jpg)、[v4-applied.jpg](v4-applied.jpg) | 设好以后：视频首页后面的壁纸 |

## pure_live_TV 的问题

| 编号 | 问题 | 位置 |
|---|---|---|
| W1 | 预览的填充、模糊、遮罩按钮只写值，看不出是哪个设置；按一下换一档，遮罩 21 档 | `wallpaper_preview_page_parts.dart:285-298`、`:339-355` |
| W2 | 预览里改的是全局设置，没按“设为背景”正在用的背景就变了，退出也不还原 | `wallpaper_preview_page_parts.dart:285-298` |
| W3 | 遮罩打开 21 项列表、模糊 10 项列表 | `wallpaper_page.dart:77-90`、`wallpaper_display_options.dart:18-44` |
| W4 | 清除背景没有确认 | `wallpaper_page.dart:92-99` |
| W5 | 沉浸式 ←→ 被吞掉；“设为壁纸”“设为背景”两个叫法 | `wallpaper_immersive_page.dart:151`、`:241` |
| W6 | 模糊用 `ImageFiltered` 每帧模糊整个背景，视频壁纸也一样 | `services/background_config/background_blur.dart:17` |
| W7 | 子页面焦点在“返回”、字号小；设置行不聚焦时没有底色，字压在亮的壁纸上 | `core/widgets/tv_settings_card.dart:15` |

## 改动（待确认）

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| h1 | 保留 | 四种来源、列表、分类、网格、预览、沉浸式、显示设置的选项和默认值、视频壁纸、壁纸在所有页面后面 | — |
| h2 | 修改 | 预览按钮写“填充 · 等比覆盖”等；填充弹小菜单，遮罩和模糊弹滑块 | W1 |
| h3 | 修改 | 预览里调的只作用在预览上，设为背景时一起保存（Z1） | W2 |
| h4 | 修改 | 背景设置里遮罩、模糊用设置滑块行，←→ 调整 | W3 |
| h5 | 修改 | 清除背景先确认，焦点在“取消” | W4 |
| h6 | 修改 | 沉浸式 ←→ 和 ↑↓ 都换图；统一叫“设为背景” | W5 |
| h7 | 修改 | 静态图在设为背景时模糊一次存下来；视频壁纸不能模糊（Z2） | W6 |
| h8 | 修改 | 子页面默认焦点在第一行 / 第一张；设置行有自己的底色；网格写“✓ 当前” | W7 |

## 按钮的作用和用法

见对比页两节（背景设置 1–7、预览 1–7）。遥控器按键：

| 键 | 用法 |
|---|---|
| 确认 | 进入、选择、执行；沉浸式里设为背景 |
| 上下 | 列表、网格移动；沉浸式换图 |
| 左右 | 网格移动、预览选按钮、滑块调整（设置页和预览弹出的滑块）；沉浸式换图 |
| 返回 | 关闭弹出的菜单 / 滑块 / 对话框 → 退出页面 |
| 长按确认 / 菜单键 | 这几页没有用到 |

## 焦点路线

| 页面 | 默认焦点 | 方向键 |
|---|---|---|
| 背景设置 | 第一行（纯色） | ↑↓ 走行，滑块行 ←→ 调整，↑ 到顶是返回 |
| 列表页 | 第一行 | ↑↓ |
| 壁纸网格 | 第一张 | 按行列；↑ 返回 |
| 预览 | 第一个按钮（照旧） | ←→ 选按钮 |
| 沉浸式 | — | ←→ / ↑↓ 换图 |

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 不适用（手机版没有界面壁纸） |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 不适用 |
| 电视 | 本页；入口在电视设置（U.15i） |
| 苹果平台差异 | 不适用 |

## 待选（A 是建议）

- Z1 预览里调填充、模糊、遮罩：A 只改预览，设为背景时一起保存；B 照旧直接改全局设置。
- Z2 高斯模糊：A 设为背景时把静态图模糊一次存下来，视频壁纸不能模糊；B 照旧实时模糊。
- Z3 壁纸从哪进：A 照 pure_live_TV 在设置 → 主题外观 → 背景设置；B 导航轨单独一项“壁纸”（v4 M14.1 的占位）。

## 拿不准的地方

- 壁纸库的来源、分类来自远端目录（`backgroundCatalogProvider`），代码里没有具体名字；图里的“Wallhaven · 风景”是按设置页副标题“官方、Wallhaven、必应等图库”编的。
- 清除背景后填充、遮罩、模糊是不是保留：按 `setNone()` 只改来源推测，没追到存储层；确认框文字按“保留”写。
- 内置的随机 API 里有“性感美女”分组（20 个来源）和“黑丝”“白丝”等来源（`wallpaper_api_source.dart:136-160`、`:307-`），电视常是全家一起用，要不要保留、要不要加开关请你定；这一版照代码保留。
- 设置滑块行、选择框的电视样式由 U.15i 定，这里只画了内容和位置。
