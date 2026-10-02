# T07b.2 热门：设计（第 1 版）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 范围：首页“热门”页：平台标签、房间网格、页面上的提示和各种状态、电脑的翻页栏；新加的“全部平台”面板
- 对应：[TASKS.md](../../../TASKS.md)、[inventory/UI.md](../../../inventory/UI.md#t07b2)、[inventory/V3_UI.md](../../../inventory/V3_UI.md) 第 2 节；卡片见 [T07d.1](../../T07d/T07d.1/README.md)
- 评审页：claude.ai 私有页面；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)（用 [T07d.1/src/cards.py](../../T07d/T07d.1/src/cards.py) 的公共部分）
- 图片：v3 按 `v3.2.11` 代码还原；封面和头像是示意图片，主播名和标题是虚构的；底部导航栏、左侧导航栏是 T07 的，照 v3 画

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| T07b.2-02 | 热门页（`PopularPage`） | 首页底部“热门” / 左侧导航“热门”；回到前台超过 15 秒自动刷新 | 竖屏（底部导航）、横屏和宽屏（左侧导航）；电脑多底部翻页栏 | 列表、刷新中（顶上细进度条）、没有平台（v3 空白页） |
| T07b.2-01 | 一个平台的网格（`PopularGridView`） | 平台标签、左右滑动 | 同上 | 第一次加载、列表、空（“未发现直播”）、出错（“网络请求失败”）、需要登录（“需要登录账号”）、加载更多、到底 |
| — | 平台说明 | 部分平台（CHZZK、SHOWROOM、niconico 等 20 个）页顶 | 同上 | — |
| — | 移动流量提示 | 用移动网络时页顶 | 同上 | “不再显示” |
| — | 回到顶部、回到底部按钮 | 滚动后出现在右下 | 同上 | — |
| 新 | 全部平台面板 | 平台标签末尾的 ⌄ | 竖屏底部、宽屏右侧 | 当前平台打勾 |

## v3 的样子（按代码）

- **顶栏**（`modules/popular/popular_page.dart:20-38`）：标题居中，标题位置就是平台标签（`ScrollableTabBar`，可横向滚动，只有平台名文字；电脑上滚轮、拖动也能滚）；整屏宽度 ≤680 时左边菜单 `Icons.menu_rounded`、右边搜索菜单 `Remix.menu_search_line`（`:15`、`:24-25`），否则不显示（功能在左侧导航栏）。
- **平台**：设置“平台显示”（`hotAreasList`）里的平台，默认全部 34 个，顺序为哔哩哔哩、斗鱼、虎牙、抖音、快手、网易CC、Twitch、Soop、YY、AcFun 直播、Picarto、TwitCasting、猫耳 FM、映客、克拉克拉、小红书、niconico、微博直播、SHOWROOM、CHZZK、LiveMe、TikTok LIVE、YouTube Live、Bigo Live、PandaTV、FC2 Live、Steam Broadcasts、京东直播、酷狗直播、百度直播、六间房直播、LOOK 直播、17LIVE、网络（`core/sites.dart:217-267`）；第一页是首选平台（默认哔哩哔哩）。一个都没有时 `return const Scaffold()`，整页空白（`popular_page.dart:19-21`）。
- **标签样式**（`common/style/theme.dart` 的 `tabBarTheme`）：15 号，选中主色 600、未选次要色 80%，指示条跟文字宽，无分隔线。
- **网格**（`popular_grid_view.dart:16-85`）：页面宽 >1280 五列、>960 四列、>640 三列、其余两列；外边距 6，行列间距取设置（默认 6）；小号卡片 `RoomCard(dense: true)`；自然行高。
- **页顶**（`common/base/base_page_view.dart:66-134`）：平台说明（`bodySmall`，部分平台，最多占半屏）、移动流量提示（圆形图标 + “您当前正在使用移动蜂窝流量，请注意流量消耗。”+“不再显示”）、有内容时的出错横幅。
- **状态**（`base_page_view.dart:137-178`、`:204-223`、`popular_grid_view.dart:21-29`）：第一次加载整页一个转圈（样式取“加载样式”设置）；空：`RemixIcons.fire_fill`、“未发现直播”“请点击上方按钮切换平台”“刷新”；出错：`Icons.wifi_off_rounded`、“网络请求失败”、报错原文、“重试”；需要登录：“需要登录账号”“该平台数据已被风控隐藏，请登录账号后重试”“前往登录”；刷新时顶上 2.5 像素进度条。
- **翻页**（`base_page_view_extension.dart:6-61`）：手机和平板（`PlatformUtils.isMobile`）下拉刷新、滑到底自动加载；Windows、Linux、macOS 且宽 >680 时底部翻页栏（`desktop_components.dart:44-185`：“刷新”、“上一页”、页码、“下一页”、“每页:”、“跳转至 [ ] 页”），键盘 ← → 翻页。
- **悬浮按钮**（`base_page_view_extension.dart:64-100`）：右下 16、底部 20（电脑 70），小号 `Icons.arrow_upward_rounded` 回到顶部、`Icons.arrow_downward_rounded` 回到底部，滚动后出现（设置“页面”里可关）。
- **其他行为**（`popular_controller.dart`）：切换标签停稳 80 毫秒后加载；0.7 秒后预取下一个平台；改人数口径设置后刷新当前平台；回到前台超过 15 秒刷新当前平台（`home_page.dart:142-165`）。

### V3_UI_INVENTORY 第 2 节需要更正的地方（本任务不改那个文件）

- 空状态写的是“未发现直播”“请点击上方按钮切换平台”，按钮“刷新”，不是“暂无直播”。
- 分页不只是“回到顶部”和每页数量：电脑上是完整的翻页栏（刷新、上一页、页码、下一页、每页、跳转至）和 ← → 键；还有“回到底部”按钮。
- 页顶还有平台说明和移动流量提示两块。
- 清单里的问题 2“页面没有标题”：底部导航和左侧导航都标着“热门”，这里不当作问题，标签照旧放标题位置。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 照 v3 结构；加“全部平台”；补没有平台、骨架；改空、出错、平台说明的文字 | 待评审 |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [对比：竖屏](page/02-对比-竖屏.jpg)
- [全部平台](page/03-全部平台.jpg)
- [对比：平台说明和流量提示](page/04-对比-平台说明和流量提示.jpg)
- [对比：加载、空、出错、没有平台](page/05-对比-加载-空-出错-没有平台.jpg)
- [对比：横屏和宽屏](page/06-对比-横屏和宽屏.jpg)
- [v3 的问题](page/07-v3-的问题.jpg)
- [改了什么](page/08-改了什么.jpg)
- [每个按钮是干什么的、怎么用](page/09-每个按钮是干什么的-怎么用.jpg)
- [各客户端](page/10-各客户端.jpg)
- [需要你选的](page/11-需要你选的.jpg)
- [性能要点](page/12-性能要点.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-phone.jpg](v3-phone.jpg)、[v4-phone.jpg](v4-phone.jpg)、[v4-phone-n.jpg](v4-phone-n.jpg) | 竖屏 393×852 |
| [v4-phone-picker.jpg](v4-phone-picker.jpg)、[v4-phone-picker-n.jpg](v4-phone-picker-n.jpg)、[v4-wide-picker.jpg](v4-wide-picker.jpg) | 全部平台：竖屏 / 宽屏 |
| [v3-phone-notice.jpg](v3-phone-notice.jpg)、[v4-phone-notice.jpg](v4-phone-notice.jpg)、[v4-phone-notice-n.jpg](v4-phone-notice-n.jpg) | 平台说明（CHZZK）和移动流量提示；编号 1–6 |
| [v3-phone-loading.jpg](v3-phone-loading.jpg)、[v4-phone-loading.jpg](v4-phone-loading.jpg) | 第一次加载 |
| [v3-phone-empty.jpg](v3-phone-empty.jpg)、[v4-phone-empty.jpg](v4-phone-empty.jpg) | 没有直播 |
| [v3-phone-error.jpg](v3-phone-error.jpg)、[v4-phone-error.jpg](v4-phone-error.jpg) | 出错 |
| [v3-phone-noplatform.jpg](v3-phone-noplatform.jpg)、[v4-phone-noplatform.jpg](v4-phone-noplatform.jpg) | 平台全关 |
| [v3-land.jpg](v3-land.jpg)、[v4-land.jpg](v4-land.jpg) | 手机横屏 852×393 |
| [v3-wide.jpg](v3-wide.jpg)、[v4-wide.jpg](v4-wide.jpg)、[v4-wide-n.jpg](v4-wide-n.jpg) | 宽屏 1280×800（Windows）；编号 2、3、5、7–11 |

## 改动（待确认）

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 保留 | 标签在标题位置、左右滑动、小号卡片网格、菜单和搜索菜单、下拉刷新和自动加载、电脑翻页栏和 ← →、回到顶部 / 底部、流量提示、刷新进度条、15 秒回来刷新、首选平台、预取下一个 | — |
| c2 | 增强 | 标签末尾 ⌄ 打开“全部平台”面板（竖屏底部、宽屏右侧） | B1 |
| c3 | 增强 | 平台全关时说明原因，给“平台显示”按钮 | B2 |
| c4 | 修改 | 空状态说明改成能照着做的话 | B3 |
| c5 | 修改 | 出错按原因写一句话（v4 已有文字） | B4 |
| c6 | 修改 | 平台说明改成人话，放带 ⓘ 的浅色条，最多两行 | B5 |
| c7 | 增强 | 第一次加载用静态骨架 | B6 |
| c8 | 修改 | 列数按公式（T07d.1 c15） | B7 |
| c9 | 修改 | 按页面自己的宽度排版，不读整屏宽度 | B8 |

## 按钮的作用和用法

见对比页“每个按钮是干什么的、怎么用”（1–14）。手势照 v3：左右滑动切平台，下拉刷新，滑到底加载，电脑 ← → 翻页。

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 竖屏 2 列、横屏 4 列；“全部平台”从底部升起 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 列数按公式；“全部平台”在右侧；Windows、Linux、macOS 有翻页栏（照 v3），平板滑到底加载；悬停显示完整标题 |
| 电视 | T18b.1 出图（以 pure_live_TV 为基线）；“全部平台”是同一面板的电视样式 |
| 苹果平台差异 | iOS 同 Android 手机，iPad 同 Android 平板，macOS 同 Windows |

## 待选

- B1 找平台：建议加“全部平台”面板；另一种是照 v3 只能横滑。
- B2 第一次加载：建议静态骨架；另一种是照 v3 转圈。
- B3 电脑翻页：建议照 v3（电脑翻页栏、触屏自动加载）；另一种是都自动加载、翻页栏做成设置项。

## 拿不准的地方

- 手机横屏时 v3 左侧导航栏把“关注 / 热门 / 分区”挤到屏幕外（`home/tablet_view.dart:85-140`，导航栏 `leadingAtTop: false` 加 `scrollable: true`，五个按钮和页面入口一起滚动）——按 Flutter 源码推算，没在真机上看；这是 T07 的事，新设计图里照 v3 画。
- 出错图里的报错原文是按 Dio 的常见报错写的示例，实际文字取决于平台和网络。
- 电脑翻页栏三组之间没有间距（`desktop_components.dart:113-179`），照代码画得比较挤；真机上按钮自带的内边距会留一点空。
- “全部平台”面板的 34 个平台图标用的是应用里现有的平台图标（`packages/live_ui/assets/platforms/`）。
