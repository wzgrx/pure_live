# A02.1 通用组件：设计（第 1 版）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 范围：页面共用的小组件：状态页（骨架、加载、空、出错、受限、离线）、头像、计数按钮、二维码、标签栏和标签芯片、列表行、设置行（开关、选择、滑块、计数、跳转）、滚动和列表外壳（刷新、加载更多、回到顶部 / 底部、页顶横幅）。是一份组件目录：每个组件 v3 和新设计并排，按默认、悬停、键盘焦点、按下、禁用、进行中排，浅色和深色各一张
- 对应：[TASKS.md](../../../TASKS.md)、[inventory/UI.md](../../../inventory/UI.md#a021)（A02.1-01～03）、[inventory/UI_FILES.md](../../../inventory/UI_FILES.md#a021)；弹窗在 [A02.2](../A02.2-弹窗组件/README.md)
- 评审页：claude.ai 私有页面（待发布）；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)（公共样式和小部件在 [src/parts.py](src/parts.py)，A02.2 也用）
- 图片：v3 按 `v3.2.11` 代码还原（文字取自 `assets/translations/zh.json`，`tools/ui/strings.py`）；头像、封面是示意图片，二维码是示意图案（不是真码），报错原文是按 Dio 常见报错写的示例
- 新设计不另起炉灶：行、开关、滑块、计数照 [A07.6](../../A07-直播间界面/A07.6-直播间弹窗/README.md)（已确认）；状态照 A08.1、A07.7、A09.2（评审中）

生成：`python3 docs/A-界面设计/A02-组件/A02.1-通用组件/src/gen.py && python3 tools/ui/mock/render.py docs/A-界面设计/A02-组件/A02.1-通用组件/src --annotate`；深色图对五张组件图（status、misc、tabs、rows、scroll）再加 `--dark`。

## 界面清点表

组件的调用处合并成一行；“状态”一列是这一批出图的清单。

| 编号 | 界面（组件） | 从哪出现 | 形态 | 状态 |
|---|---|---|---|---|
| A02.1-01、02 | 状态页（`AppStatusView`、`EmptyView`，40 + 11 处） | 列表第一次加载、空、出错、风控；卡片封面失败（isMini）；下拉刷新头里的小转圈 | 整页、区块、卡片封面；竖屏、横屏、宽屏 | 加载、空、出错、受限（需要登录）、离线（v3 没有单独的）；新：骨架、画面上（A07.7） |
| — | 列表外壳（`BasePageView`） | 热门、分区、分区房间、关注等列表页 | 同上 | 刷新进度条、下拉刷新头（拖动、松手前、刷新中、完成）、上拉加载尾、没有更多、回到顶部 / 底部、页顶说明、流量提醒、有内容时出错横幅、电脑翻页栏 |
| — | 头像（`CommonAvatar`，7 处） | 直播间顶栏 32、卡片 34 / 40、口令导入 48、多画面选房 38 | — | 图片、加载中、没头像（首字）、没名字、加载失败；新：可点时悬停、焦点、按下 |
| — | 计数按钮（`CountButton`，2 处） | 弹幕设置（顶部留白、区域底部留白、合并时间）、小窗弹幕（最大同时显示数量） | — | 默认、悬停、焦点、按下、到下限 / 上限、长按连加、不可用 |
| — | 二维码（`QrCodeWidget`、`BilibiliLoginQrCode`） | 设备同步、哔哩哔哩扫码登录 | 竖屏、宽屏 | 加载中、等待扫码、已扫描、已失效、出错 |
| — | 标签栏（`ScrollableTabBar`，7 处；主题 `tabBarTheme`） | 直播间四个标签、热门 / 分区 / 关注的平台、关注的状态、分区的分类、关注分区 | 竖屏、宽屏 | 选中、未选、悬停、焦点、按下；新：数量、角标、末尾 ⌄、二级标签、禁用 |
| — | 标签芯片（`ChoiceChip`、`FilterChip`） | 关注分组、搜索平台条、弹幕观看模板 | — | 选中、未选、悬停、焦点、按下、禁用 |
| — | 列表行（`ListTile` 主题） | 长按弹幕面板、账号、各种列表 | — | 一行、两行、带头像、带操作、悬停、焦点、按下、选中、禁用、危险 |
| A02.1-03 | 设置行（`buildGroupTitle`、`buildModernCard`、`buildSwitchTile`、`buildTile`（含 `standardTile`）、`buildMenuTile`、`buildSliderTile`；87 / 76 / 49 / 97 / 0 / 15 处） | 所有设置页、弹幕设置、平台显示 | 竖屏、宽屏 | 开关（开、关、悬停、焦点、不可用、处理中、出错）、选择、滑块（悬停、拖动、焦点、不可用）、计数、跳转、窄屏和大字体时换行 |
| — | 按钮名称提示 | 见 A02.2 | — | — |

INVENTORY 把 `standardTile`（`widget_extensions.dart:309`）记成对话框，实际 :309 是 `buildMenuTile` 弹出的单选对话框（`_openMenuDialog`），而 `buildMenuTile` 本身代码里没有调用；选项对话框归 A02.2。

## v3 的样子（`v3.2.11`，`lib/` 下）

**状态页**（`common/widgets/app_status_view.dart`）
- 三种类型 `loading / empty / error`（:10）。加载只画转圈，样子随设置“加载样式”（`_getSpinKit` 等 :43-381，默认是带渐隐的圆环 :497-530），大小 `isMini` 24，否则整屏宽 >680 时 32、否则 24（:387-391）；不显示标题（:407-413）。
- 空和出错（:415-480）：圆圈（内边距 22，`surfaceContainerHighest` 15% 底、主色 5% 细边）里一个 42 的图标（主色 60%；空默认 `Icons.live_tv_rounded`，出错 `Icons.wifi_off_rounded`）；1 秒 `elasticOut` 放大入场（:426-431）；20 → 标题 15 号 600（默认“暂无数据”/“网络请求错误”）→ 说明 13 号提示色、行高 1.5、左右 28、最宽 320（默认“这里空空如也，什么都没有发现”/“请检查您的网络连接或稍后再试”）→ 16 → `TextButton.icon` 刷新图标 18 + 文字（默认“重新加载”），只有给了回调才有（:470-477）。
- `isMini`（卡片封面失败）：圆圈内边距 8、图标 16、没有按钮（:434-445）。`EmptyView` 就是 `type: empty`（`empty_view.dart`）。

**列表外壳**（`common/base/base_page_view.dart`、`base_page_view_extension.dart`、`desktop_components.dart`、`plugins/global.dart`）
- 第一次加载：`AppStatusView(loading, title: "加载中...")`，标题不显示（:170）。空：图标同上、“无数据”、说明空（:167）。出错：`wifi_off`、“网络请求失败”、说明是 `errorMsg`（原始报错）、按钮“重试”或“刷新”（:215-224、`live_directory_controller.dart:64`）。需要登录：`Icons.account_circle_outlined`、“需要登录账号”“该平台数据已被风控隐藏，请登录账号后重试”“前往登录”（:204-213），按钮图标仍是刷新。
- 有内容时：刷新顶上 2.5 高主色进度条（:180-198）；出错是 `MaterialBanner`（错误容器色、信息图标、原始报错、按钮在下，:103-132）；页顶说明 `bodySmall` 12 号没有底色（:78-82）；流量提醒是主色容器 25% 底、圆形信号图标、“您当前正在使用移动蜂窝流量，请注意流量消耗。”“不再显示”（:258-307）。
- 下拉刷新（`EasyRefresh` 的 `ClassicHeader`，`plugins/global.dart:17-38`）：向下箭头（outline 色）+ 拖动文字 `refresh_pull_up_to_refresh`“上拉刷新”、松手前“松开加载”、刷新中小转圈 + “正在刷新...”、完成“加载成功”、下面一行“上次加载时间 %T”；上拉加载（:40-62）拖动文字“下拉加载”、到底“没有更多数据了”。
- 回到顶部 / 底部（`base_page_view_extension.dart:64-99`）：小号 `FloatingActionButton`（40）、`cardColor` 底（浅色白、深色 #424242）、阴影 3；滚过 400 出现；右 16、底 20（电脑 70）；设置可关。
- 电脑（宽 >680 且不是手机系统）：翻页栏“刷新、上一页、页码、下一页、每页、跳转至 _ 页”和 ← → 键（`desktop_components.dart:94-188`），样子已在 A09.2、A09.5 还原。
- 滚动手感：`PureLiveScrollPhysics`（苹果回弹，其他不回弹，`pure_live_scroll_physics.dart`）；Windows 滚轮用 Chromium 的平滑曲线（`pure_live_scroll_controller.dart`）；`KeepAliveWrapper` 保留标签页状态。

**头像**（`common_avatar.dart`）：半径默认 20、`dense` 17（:17）；有地址时 `ClipOval` 里缓存图，按显示尺寸解码、关掉淡入（:42-62）；加载中是 `disabledColor` 20% 底（:58）；没地址或失败是 `disabledColor` 约 31% 的圆底加名字首字（字号半径 × 0.8、粗体，:22-35），没名字时只有灰圈。

**计数按钮**（`count_button.dart`）：左右两块 48×48 的 `ElevatedButton`，主色底、图标默认白色（:69-71），外侧圆角 12；中间数字主色粗体（调用处传 14 号），上下 2 像素主色边（:108-122）；长按每 100 毫秒加减（:180-204）；到上下限时点了没反应，按钮样子不变（:166-178）。调用处是一行：标题 15 号 600 + 计数（`danmaku_settings_page.dart:578-610`、`pip_danmaku_settings_page.dart:395-420`）。

**二维码**：`QrCodeWidget`（白底、黑码、直角、内边距 12、默认 180，`qr_code_widget.dart`），用在设备同步（`remote_sync_page.dart:226`）；扫码登录另写了一个 `BilibiliLoginQrCode`（同样画法，`bilibili_login_qr_code.dart`），放在 `buildModernCard` 里、圆角 12、边长 140–180（`qr_login_page.dart:72-100`）；状态：加载“正在加载二维码…”（28 转圈）、等待扫码“请使用 哔哩哔哩 手机客户端扫码登录”、已扫描“已扫描，请在手机上确认登录”（主色 10% 底）、失效时二维码整个换成 `error_warning` 图标 + “二维码已失效” + “刷新二维码”（:36-70、:183-215）。

**标签栏**（`theme.dart:122-130`、`scrollable_tab_bar.dart`）：15 号（`titleMedium`），选中主色 600、未选 `onSurfaceVariant` 80% 400；指示条和文字一样宽（M3 的 3 像素圆头）；没有分隔线；放得下居中。`ScrollableTabBar` 让电脑也能用滚轮和鼠标拖动横滚。主题关了水波（`splashFactory: NoSplash`，:114）。没有数量和角标。

**标签芯片**：关注分组 `ChoiceChip` 12 号、选中主色底白字粗体、圆角 10（`favorite_page.dart:182-273`）；搜索平台条 13 号 500、描边、选中次色容器、不带勾（`search_platform_strip.dart:63-95`）；弹幕观看模板选中主色底白字加勾、未选浅灰底（`danmaku_settings_page.dart:97-157`）。

**列表行**（`theme.dart:151-158`）：圆角 12；标题 `bodyLarge` 14 号 500；说明 `bodyMedium` 13 号次要色；选中主色 6% 底、主色字。

**设置行**（`widget_extensions.dart`）
- 内容最宽 960 居中（:8-18）。组标题 12 号粗体、主色 65%、字距 0.5、左 8 下 8（:21-36）。卡片：`surfaceContainerHighest` 15% 底、圆角 20、5% 细边；行之间 0.5 的分隔线（5%），首尾行自动圆角——靠类型名猜哪些是行（:38-112）。
- 开关行 `buildSwitchTile`：左图标 22 主色，标题 15 号 600，说明 12 号提示色 75%（默认一行省略，`isLong` 时多行），E04.1 默认开关（开着主色底白滑块），整行可点；`enabled: false` 整行变灰（:114-152）。出错时调用处把说明换成错误色（`video_settings_page.dart:180-181`）。
- 跳转 / 值行 `buildTile`：同上的图标和文字；右边默认 ›（提示色 40%、20 号，:227）；给了 `trailing` 就不显示 ›；`stackTrailingOnNarrow` 时宽 <360 或字体放大 >1.5 倍把右边换到标题下面（:235-257）。
- 选择：`buildMenuTile`（值 14 号提示色 + ›，弹出单选对话框，:260-350）代码里没有调用；实际的选择行是 `buildTile` 加值文字（视频设置：主色 600，一行默认字号、一行 13 号，`video_settings_page.dart:133-136`、`:148-151`），点了各页自己写单选对话框（A02.2）。
- 滑块行 `buildSliderTile`：图标 22，标题 16 号 600，右边数值小块（主色 10% 底、圆角 6、13 号粗体），放不下时换行；Syncfusion 滑块（主色，未激活主色 15%）（:352-454）。
- 8 处开关写了 `activeThumbColor: primary`（`hot_areas_page.dart:49`、`danmaku_settings_page.dart:643`、`keyword_block_page.dart:372`、`pip_danmaku_settings_page.dart:440`、`navigation_settings_page.dart:115`、`room_volume_dialog.dart:137`、`room_timer_dialog.dart:101`、`iptv_manage.dart:780`）：按 Flutter 3.47.5（v3 的 `.fvmrc`）`switch.dart:973-980`，没给 `activeTrackColor` 时底色取滑块色的 50% 透明，所以开着时底是主色 50%、滑块是主色。
- `section_listtile.dart` 的 `CupertinoSwitchListTile`、`SectionTitle` 没有调用。

**宽度分支**：状态转圈大小读整屏宽度（`app_status_view.dart:389`）；列表外壳电脑判断 `context.width > 680`（`base_page_view.dart:56-57`）；设置行按约束 360 换行；设置内容 960。

**手势和快捷键**：下拉刷新、上拉加载；电脑 ← → 翻页；计数长按连加；标签左右滑、滚轮横滚。没有别的快捷键。

**v4 现在**（`packages/live_ui/lib/src/widgets/`）：`status_view.dart`、`settings_tiles.dart`、`count_button.dart`、`avatar.dart`、`qr_code_widget.dart`、`scrollable_tab_bar.dart`、`scrolling.dart` 基本是 v3 搬过来的（`AppStatusView` 多了 `buttonIcon`）；A07.6 开发时在直播间面板里做了新的行、开关、计数样子，还没有收进 `live_ui` 的公共组件。

## v3 的问题

| 编号 | 问题 | 位置 |
|---|---|---|
| P1 | 加载只有转圈，不说在等什么；BasePageView 传了“加载中...”，加载态也不显示 | `app_status_view.dart:407-413`、`base_page_view.dart:170` |
| P2 | 出错一律断网图标；说明是原始英文报错；按钮图标固定是刷新（“前往登录”也是） | `app_status_view.dart:441`、`:472-476`、`base_page_view.dart:204-224` |
| P3 | 离线、受限、出错一个样子 | `base_page_view.dart:204-224` |
| P4 | 空和出错的圆圈 15% 透明、图标 60%，几乎看不见；1 秒弹性入场会回弹 | `app_status_view.dart:426-445` |
| P5 | 同类状态各页自己画（醒目留言空、扫码失效等） | `super_chat_page.dart:12-34`、`qr_login_page.dart:183-215` |
| P6 | 横屏手机内容区约 300 高，竖排的状态占满，报错长就要滚 | `app_status_view.dart:422-480` |
| P7 | 头像没名字时是空灰圈；加载中、没头像也是灰圈 | `common_avatar.dart:22-35`、`:58` |
| P8 | 计数按钮图标写死白色，深色主题对比约 1.7:1；两块实心主色比滑块重 | `count_button.dart:69-71` |
| P9 | 计数到上下限按钮看起来照样能点 | `count_button.dart:166-178` |
| P10 | 二维码两套实现、两种圆角；失效时二维码整个换掉，位置跳 | `qr_code_widget.dart`、`bilibili_login_qr_code.dart`、`qr_login_page.dart:59-65` |
| P11 | 标签芯片三种样子 | `favorite_page.dart:182-273`、`search_platform_strip.dart:63-95`、`danmaku_settings_page.dart:97-157` |
| P12 | 设置组标题主色 65% 透明，约 2.9:1；说明提示色 75%，约 3.3:1 | `widget_extensions.dart:28-31`、`:136`、`:203` |
| P13 | 设置卡片 15% 透明底、5% 边和分隔线，分组几乎看不出 | `widget_extensions.dart:88-111` |
| P14 | 开关两种样子（8 处 `activeThumbColor`），约 2.8:1 | 见上 |
| P15 | “选择”行三种样子；`buildMenuTile` 没用上；选择框三种 | `video_settings_page.dart:133-151`、`widget_extensions.dart:260-350`、`utils.dart:447-505` |
| P16 | “跳转”的 › 两种颜色大小 | `widget_extensions.dart:227`、`video_settings_page.dart:166`、`:276` |
| P17 | 行标题三种：14/500、15/600、16/600 | `theme.dart:153`、`widget_extensions.dart:130`、`:381` |
| P18 | 设置内容最宽 960（计划书 5.3 是 720） | `widget_extensions.dart:8` |
| P19 | 下拉刷新的字反了（往下拉写“上拉刷新”，往上拉写“下拉加载”，松手前都是“松开加载”） | `plugins/global.dart:17-62` |
| P20 | 回到顶部 / 底部是 40 的小按钮，点击区域不到 48 | `base_page_view_extension.dart:64-99` |
| P21 | 没有键盘焦点框（主题关了水波，焦点只是底色） | `theme.dart:114` |
| P22 | 转圈大小按整屏宽度选 | `app_status_view.dart:387-391` |

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 五张组件对照图（浅色、深色）、设置页和横屏状态整屏图、“用在哪”对照、四处选择 | 待评审 |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [对比：状态页](page/02-对比-状态页.jpg)
- [对比：头像、计数按钮、二维码](page/03-对比-头像-计数按钮-二维码.jpg)
- [对比：标签栏和标签芯片](page/04-对比-标签栏和标签芯片.jpg)
- [对比：列表行和设置行](page/05-对比-列表行和设置行.jpg)
- [对比：滚动和列表外壳](page/06-对比-滚动和列表外壳.jpg)
- [放在页面里：设置页、横屏的状态](page/07-放在页面里-设置页-横屏的状态.jpg)
- [用在哪（已出的设计）](page/08-用在哪-已出的设计.jpg)
- [v3 的问题](page/09-v3-的问题.jpg)
- [改了什么](page/10-改了什么.jpg)
- [每个按钮是干什么的、怎么用](page/11-每个按钮是干什么的-怎么用.jpg)
- [各客户端](page/12-各客户端.jpg)
- [需要你选的](page/13-需要你选的.jpg)
- [性能要点](page/14-性能要点.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-status.jpg](v3-status.jpg)、[v4-status.jpg](v4-status.jpg)（及 `-dark`） | 状态页：整页五种、区块、卡片、画面上、页顶横幅、按钮的状态 |
| [v3-misc.jpg](v3-misc.jpg)、[v4-misc.jpg](v4-misc.jpg)（及 `-dark`） | 头像、计数、二维码 |
| [v3-tabs.jpg](v3-tabs.jpg)、[v4-tabs.jpg](v4-tabs.jpg)（及 `-dark`） | 一级标签、二级标签、标签芯片 |
| [v3-rows.jpg](v3-rows.jpg)、[v4-rows.jpg](v4-rows.jpg)（及 `-dark`） | 列表行、设置行（开关、选择、滑块、计数、跳转、窄屏） |
| [v3-scroll.jpg](v3-scroll.jpg)、[v4-scroll.jpg](v4-scroll.jpg)（及 `-dark`） | 刷新进度条、下拉刷新、上拉加载、回到顶部 / 底部 |
| [v3-settings-phone.jpg](v3-settings-phone.jpg)、[v4-settings-phone.jpg](v4-settings-phone.jpg)、[v4-settings-phone-n.jpg](v4-settings-phone-n.jpg) | 视频设置竖屏 393×852；编号 1–5 |
| [v3-settings-wide.jpg](v3-settings-wide.jpg)、[v4-settings-wide.jpg](v4-settings-wide.jpg) | 视频设置 1280×800（最宽 960 / 720） |
| [v3-status-land.jpg](v3-status-land.jpg)、[v4-status-land.jpg](v4-status-land.jpg) | 横屏手机 852×393 的出错状态 |

## 改动（待确认）

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 保留 | 状态出现的时机、“加载样式”、头像尺寸和缓存、计数长按连加、二维码画法、一级标签的样子和滚轮横滚、设置页结构（组标题 + 卡片 + 行、左边图标）、窄屏换行、回到顶部 / 底部、电脑翻页栏、滚动手感 | — |
| c2 | 修改 | 一个状态组件：六种状态、四种场合，结构固定 | P3、P5 |
| c3 | 修改 | 列表第一次加载用静态骨架；其他加载转圈加一句话 | P1 |
| c4 | 修改 | 出错按原因选图标、写人话，原始报错收进“详情”（C4） | P2 |
| c5 | 修改 | 按钮图标跟动作；第一个浅色实心、第二个文字按钮（C1） | P2 |
| c6 | 修改 | 圆圈实色、图标不透明、不弹跳；转圈大小看所在区域 | P4、P22 |
| c7 | 修改 | 横屏手机（内容高 <360）状态左图右文 | P6 |
| c8 | 增强 | 页顶横幅一个组件三种颜色（说明、提醒、出错） | — |
| c9 | 修改 | 头像：加载中浅灰、没头像首字、没名字人形图标；可点时悬停和焦点 | P7 |
| c10 | 修改 | 计数用 A07.6 的描边样式；上下限变灰；不可用变灰不消失 | P8、P9 |
| c11 | 修改 | 二维码一个组件；状态盖在原位置；深色也白底 | P10 |
| c12 | 增强 | 标签栏的数量、角标、“全部平台”⌄、二级标签 | — |
| c13 | 修改 | 标签芯片一种：36 高、圆角 8、选中次色容器加勾 | P11 |
| c14 | 修改 | 开关一种（E04.1 默认），去掉 8 处 `activeThumbColor` | P14 |
| c15 | 修改 | 设置配色：组标题 13/600 主色不透明、说明次要色、卡片表面容器低圆角 16 | P12、P13 |
| c16 | 修改 | 一个行组件，标题 15（字重 C3）、说明 12 | P17 |
| c17 | 修改 | 选择行：值 + ⌄，弹选项对话框；跳转行：›（C2） | P15、P16 |
| c18 | 修改 | 阅读型内容最宽 720 | P18 |
| c19 | 修改 | 下拉刷新、上拉加载文字改对 | P19 |
| c20 | 修改 | 回到顶部 / 底部点击区域 48 | P20 |
| c21 | 增强 | 所有可点组件有悬停、键盘焦点框、按下、禁用、进行中 | P21 |

新加的文字（开发时加进翻译）：没有网络连接；检查网络后重试；连上网络后会自动刷新；加载失败（v3 有 `refresh_load_failed`）；详情；下拉刷新；松开刷新；上拉加载；刷新失败；加载失败，点这里重试。其余用 v3 已有的键（`refresh_loading`、`login_required_*`、`go_to_login`、`retry`、`refresh`、`refresh_refreshing`、`refresh_no_more_data`、`refresh_release_to_load`、`refresh_last_updated_at`、`qr_*`、`refresh_qr`、`never_show`、`cellular_warning_msg`）。示例里的具体原因句（“平台拒绝了请求（412）…”“这个分区现在没有人在播…”）跟着各页面任务。

## 用在哪（已出的设计）

见对比页同名一节。要同步给其他任务的：

| 任务 | 要改的 |
|---|---|
| A09.2、A09.3、A09.7 | 状态页按钮按 C1（A09.2、A09.7 画的是文字按钮，A09.3 是主色实心） |
| A07.7 | 受限按钮文字用 v3 的“前往登录”（A07.7 写的“去登录”），图标 `login` |
| A07.6（已确认）、开发 | 观看模板芯片画成全圆角，录制清晰度芯片是圆角 8；建议开发时统一成 8（不改布局） |
| A09.6 | TASKS 第 7 节的开关问题：属实但不是“看不出”，是底色 50% 透明、和设置页不一样；c14 统一 |
| A09.9 | 下拉刷新头照这里（c19） |
| J、A10.2、K、J | 设置页、二维码用这里的组件 |

## 按钮的作用和用法

编号对应 [v4-settings-phone-n.jpg](v4-settings-phone-n.jpg)。

| 编号 | 控件 | 怎么用 |
|---|---|---|
| 1 | 返回 | 回上一页；返回键、iOS 左边缘滑动、Esc 一样 |
| 2 | 开关行 | 点整行或开关切换；处理中不能再拨；电脑空格 |
| 3 | 滑块行 | 拖或点；电脑 ← → |
| 4 | 选择行 | 弹选项对话框（A02.2），点一项就关 |
| 5 | 跳转行 | 进下一页 |
| — | 状态页按钮 | 第一个是主要的下一步，第二个是另一条路 |
| — | 计数 | 点 − ＋，长按连加；电脑 ← → |
| — | 二维码“刷新” | 失效、出错时盖在二维码上 |
| — | 标签、芯片 | 点切换；标签可左右滑；电脑滚轮横滚 |
| — | 回到顶部 / 底部 | 滚过 400 出现；设置可关 |

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 竖屏如图；横屏手机状态左图右文；下拉刷新、上拉加载 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 设置内容最宽 720 居中；悬停、键盘焦点框；滚轮横滚标签；电脑列表用翻页栏（照 v3），平板下拉刷新；右键等于长按 |
| 电视 | 同一组件的电视样式（A17.1）：焦点放大 1.05 倍、近白描边、字号大一级；设置行整行聚焦，开关确认键、计数和滑块左右键；二维码用于手机扫码登录 |
| 苹果平台差异 | 列表回弹（照 v3）；开关不换 Cupertino（v3 的 `CupertinoSwitchListTile` 没用上）；iPad 指针同宽屏；macOS 用 Cmd |

## 待选（A 是建议）

- C1 状态页的按钮：A 第一个浅色实心、第二个文字按钮；B 照 v3 都是文字按钮（只改图标）。
- C2 选择行的标记：A 值 + ⌄；B 照 v3 值 + ›。
- C3 行标题字重：A 400（和 A07.6 一致）；B 照 v3 600。
- C4 出错的原始报错：A 收进“详情”；B 照 v3 直接显示。

## 拿不准的地方

1. v3 的“加载样式”默认圆环是 `ShaderMask` 加扫掠渐变，图里用圆锥渐变近似；其余 50 多种加载动画没画。
2. E04.1 默认 `TextButton`、`ListTile`、`TabBar` 的悬停、焦点、按下叠层透明度按 Flutter 默认（8% / 10% / 10%）画，v3 主题关了水波，按下时只有底色——没有在真机上看。
3. Windows 标题栏在 v3 是 `DesktopManager.buildWithTitleBar` 自绘的，这里画的是示意（A16.1 定）。
4. `buildMenuTile` 没有调用处是按 `grep` 得出的（`lib/` 下只有定义）；如果 3.x 里有动态调用，请指出。
5. 二维码是示意图案（有定位块，但不是真码）；真码的模块数随内容变。
6. v3 卡片封面加载中的底色：`room_card.dart` 用 `grey.shade100`，图里用 #F5F5F5。
7. 计数在 A07.6 里画的是 36 高、点击区域没写；这里定为看起来 36、点击区域 48。

## 需要改工具的地方

- `kit/kit.css` 的 `.toast` 只有浅色主题的深底，没有深色主题的反色；这次在任务自己的样式里写了 `--inv` 等变量（`src/parts.py`），建议收进 kit。
- `kit.css` 的 `Noto Sans SC` 把 500 字重映射到粗体，v3 的 500（按钮、菜单）在图里显得偏粗。
- `render.py --dark` 只能对整个目录或逐个文件加，这次逐个文件跑了五对组件图。

## 文件对照

| v3 | v4 现在 |
|---|---|
| `common/widgets/app_status_view.dart`、`empty_view.dart` | `packages/live_ui/lib/src/widgets/status_view.dart`、`loading_styles.dart` |
| `common/widgets/widget_extensions.dart`、`section_listtile.dart` | `packages/live_ui/lib/src/widgets/settings_tiles.dart` |
| `common/widgets/count_button.dart` | `packages/live_ui/lib/src/widgets/count_button.dart` |
| `common/widgets/common_avatar.dart` | `packages/live_ui/lib/src/widgets/avatar.dart` |
| `common/widgets/qr_code_widget.dart`、`modules/account/bilibili/bilibili_login_qr_code.dart` | `packages/live_ui/lib/src/widgets/qr_code_widget.dart` |
| `common/widgets/scrollable_tab_bar.dart`、`pure_live_scroll_*.dart`、`keep_alive_wrapper.dart` | `packages/live_ui/lib/src/widgets/scrollable_tab_bar.dart`、`scrolling.dart` |
| `common/base/base_page_view*.dart`、`desktop_components.dart`、`plugins/global.dart` | 没有公共外壳：各页自己写，下拉刷新用 Material `RefreshIndicator`（`favorite_page.dart:448` 等），翻页栏在 `features/popular/pagination_bar.dart` |
