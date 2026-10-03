# A09.2 热门：设计（第 1 版，已定稿并实现）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为完成，2026-10-01；S02.2 冒烟里看过，见“实现和验证”）
- 旧编号：U.4b、T07b.2（见 [MAPPING.md](../../../MAPPING.md)）
- 范围：首页“热门”页：平台标签、房间网格、页面上的提示和各种状态、电脑的翻页栏；新加的“全部平台”面板
- 对应：[inventory/UI.md](../../../inventory/UI.md#a092)（A09.2-01、02）、[inventory/V3_UI.md](../../../inventory/V3_UI.md) 第 2 节；卡片见 [A09.1](../A09.1-房间卡片/README.md)；功能点 F-BRW-01～03、F-BRW-09（[inventory/FEATURES.md](../../../inventory/FEATURES.md)）；数据和逻辑在 [I02](../../../I-浏览和发现/I02-热门/README.md)；相关决定 D-003、D-009、D-011
- 评审页：claude.ai 私有页面；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)（用 [A09.1/src/cards.py](../A09.1-房间卡片/src/cards.py) 的公共部分）；按章节导出在 [page/](page/01-说明.jpg)
- 图片：v3 按 `v3.2.11` 代码还原；封面和头像是示意图片，主播名和标题是虚构的；底部导航栏、左侧导航栏是 I 的，照 v3 画
- 记录：[record.md](record.md)

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| A09.2-02 | 热门页（`PopularPage`） | 首页底部“热门” / 左侧导航“热门”；回到前台超过 15 秒自动刷新 | 竖屏（底部导航）、横屏和宽屏（左侧导航）；电脑多底部翻页栏 | 列表、刷新中（顶上细进度条）、没有平台（v3 空白页） |
| A09.2-01 | 一个平台的网格（`PopularGridView`） | 平台标签、左右滑动 | 同上 | 第一次加载、列表、空（“未发现直播”）、出错（“网络请求失败”）、需要登录（“需要登录账号”）、加载更多、到底 |
| — | 平台说明 | 部分平台（CHZZK、SHOWROOM、niconico 等 20 个）页顶 | 同上 | — |
| — | 移动流量提示 | 用移动网络时页顶 | 同上 | “不再显示” |
| — | 回到顶部、回到底部按钮 | 滚动后出现在右下 | 同上 | — |
| 新 | 全部平台面板 | 平台标签末尾的 ⌄ | 竖屏底部、宽屏右侧 | 当前平台打勾 |

## 3.x 的样子和问题

### 3.x 的样子（`git show v3.2.11:lib/`，按代码）

- **顶栏**（`modules/popular/popular_page.dart:20-38`）：标题居中，标题位置就是平台标签（`ScrollableTabBar`，可横向滚动，只有平台名文字；电脑上滚轮、拖动也能滚）；整屏宽度 ≤680 时左边菜单 `Icons.menu_rounded`、右边搜索菜单 `Remix.menu_search_line`（`:15`、`:24-25`），否则不显示（功能在左侧导航栏）。
- **平台**：设置“平台显示”（`hotAreasList`）里的平台，默认全部 34 个，顺序为哔哩哔哩、斗鱼、虎牙、抖音、快手、网易CC、Twitch、Soop、YY、AcFun 直播、Picarto、TwitCasting、猫耳 FM、映客、克拉克拉、小红书、niconico、微博直播、SHOWROOM、CHZZK、LiveMe、TikTok LIVE、YouTube Live、Bigo Live、PandaTV、FC2 Live、Steam Broadcasts、京东直播、酷狗直播、百度直播、六间房直播、LOOK 直播、17LIVE、网络（`core/sites.dart:217-267`）；第一页是首选平台（默认哔哩哔哩）。一个都没有时 `return const Scaffold()`，整页空白（`popular_page.dart:19-21`）。
- **标签样式**（`common/style/theme.dart` 的 `tabBarTheme`）：15 号，选中主色 600、未选次要色 80%，指示条跟文字宽，无分隔线。
- **网格**（`popular_grid_view.dart:16-85`）：页面宽 >1280 五列、>960 四列、>640 三列、其余两列；外边距 6，行列间距取设置（默认 6）；小号卡片 `RoomCard(dense: true)`；自然行高。
- **页顶**（`common/base/base_page_view.dart:66-134`）：平台说明（`bodySmall`，部分平台，最多占半屏）、移动流量提示（圆形图标 + “您当前正在使用移动蜂窝流量，请注意流量消耗。”+“不再显示”）、有内容时的出错横幅。
- **状态**（`base_page_view.dart:137-178`、`:204-223`、`popular_grid_view.dart:21-29`）：第一次加载整页一个转圈（样式取“加载样式”设置）；空：`RemixIcons.fire_fill`、“未发现直播”“请点击上方按钮切换平台”“刷新”；出错：`Icons.wifi_off_rounded`、“网络请求失败”、报错原文、“重试”；需要登录：“需要登录账号”“该平台数据已被风控隐藏，请登录账号后重试”“前往登录”；刷新时顶上 2.5 像素进度条。
- **翻页**（`base_page_view_extension.dart:6-61`）：手机和平板（`PlatformUtils.isMobile`）下拉刷新、滑到底自动加载；Windows、Linux、macOS 且宽 >680 时底部翻页栏（`desktop_components.dart:44-185`：“刷新”、“上一页”、页码、“下一页”、“每页:”、“跳转至 [ ] 页”），键盘 ← → 翻页。
- **悬浮按钮**（`base_page_view_extension.dart:64-100`）：右下 16、底部 20（电脑 70），小号 `Icons.arrow_upward_rounded` 回到顶部、`Icons.arrow_downward_rounded` 回到底部，滚动后出现（设置“页面”里可关）。
- **其他行为**（`popular_controller.dart`）：切换标签停稳 80 毫秒后加载；0.7 秒后预取下一个平台；改人数口径设置后刷新当前平台；回到前台超过 15 秒刷新当前平台（`home_page.dart:142-165`）。

#### [inventory/V3_UI.md](../../../inventory/V3_UI.md) 第 2 节需要更正的地方（本任务不改那个文件；当时的文件名是 V3_UI_INVENTORY.md）

- 空状态写的是“未发现直播”“请点击上方按钮切换平台”，按钮“刷新”，不是“暂无直播”。
- 分页不只是“回到顶部”和每页数量：电脑上是完整的翻页栏（刷新、上一页、页码、下一页、每页、跳转至）和 ← → 键；还有“回到底部”按钮。
- 页顶还有平台说明和移动流量提示两块。
- 清单里的问题 2“页面没有标题”：底部导航和左侧导航都标着“热门”，这里不当作问题，标签照旧放标题位置。

### 问题（评审页“v3 的问题”）

问题编号 B1～B8 是评审页上的写法，和下面“待选和决定”里的选择 B1～B3 是两套编号（评审页导出图里两处都这样写，这里不改）。

| 编号 | 问题 | 位置 |
|---|---|---|
| B1 | 默认 34 个平台全在标签里，手机上一次只看到三个半，只能横着一直滑，没有总览，也不能直接跳到某个平台 | `popular_page.dart:28-34`、`favorite_room_controller.dart:20` |
| B2 | 在“平台显示”里把平台都关掉后，热门是一整页空白，连顶栏都没有，不知道怎么回事 | `popular_page.dart:19-21` |
| B3 | 某个平台没有直播时写“请点击上方按钮切换平台”，上面其实是平台标签，没有按钮 | `popular_grid_view.dart:21-29` |
| B4 | 加载失败时把程序的报错原文（常常是英文，例如 DioException …）直接当说明显示 | `base_controller.dart:49-56`、`:69-76`、`base_page_view.dart:215-223` |
| B5 | 部分平台顶上的说明是写给开发者看的（游标分页、cvExposure、concurrentUserCount、view_num），而且最多能占半屏 | `live_directory_controller.dart:60-61`、`base_page_view.dart:70-83`、`zh.json chzzk_directory_scope` 等 |
| B6 | 第一次加载整页只有一个转圈，卡片出来时页面跳一下 | `base_page_view.dart:170` |
| B7 | 列数固定分档，拖窗口时卡片忽大忽小，大屏最多 5 列（详见 A09.1 P13） | `popular_grid_view.dart:16` |
| B8 | 是否显示左上菜单和右上搜索看的是整个屏幕的宽度（`Get.width`），不是这一页实际多宽；分屏、窗口缩放时可能和导航栏对不上 | `popular_page.dart:15` |

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 照 v3 结构；加“全部平台”；补没有平台、骨架；改空、出错、平台说明的文字 | 用户确认；选择 B1～B3 按建议 A（D-003） |

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

## 确认的改动

用户确认（第 1 版的“改动（待确认）”原样，“对应问题”一列是上面的问题 B1～B8；每条的完整说明见评审页“改了什么”）：

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 保留 | 标签在标题位置、左右滑动、小号卡片网格、菜单和搜索菜单、下拉刷新和自动加载、电脑翻页栏和 ← →、回到顶部 / 底部、流量提示、刷新进度条、15 秒回来刷新、首选平台、预取下一个 | — |
| c2 | 增强 | 标签末尾 ⌄ 打开“全部平台”面板（竖屏底部、宽屏右侧） | B1 |
| c3 | 增强 | 平台全关时说明原因，给“平台显示”按钮 | B2 |
| c4 | 修改 | 空状态说明改成能照着做的话 | B3 |
| c5 | 修改 | 出错按原因写一句话（v4 已有文字） | B4 |
| c6 | 修改 | 平台说明改成人话，放带 ⓘ 的浅色条，最多两行 | B5 |
| c7 | 增强 | 第一次加载用静态骨架 | B6 |
| c8 | 修改 | 列数按公式（A09.1 c15） | B7 |
| c9 | 修改 | 按页面自己的宽度排版，不读整屏宽度 | B8 |

## 按钮的作用和用法

见对比页“每个按钮是干什么的、怎么用”（1–14）。手势照 v3：左右滑动切平台，下拉刷新，滑到底加载，电脑 ← → 翻页。

| 编号 | 控件 | 怎么用 |
|---|---|---|
| 1 | 菜单（手机） | 设置、关于、历史记录、备份与恢复（照 v3，I 定）。 |
| 2 | 平台标签 | 点一下切到这个平台；也可以在下面左右滑动；电脑上鼠标滚轮或拖动能横着滚标签（照 v3）。 |
| 3 | 全部平台（新） | 打开“全部平台”面板。 |
| 4 | 搜索菜单（手机） | 搜索直播、链接访问、多画面（照 v3，I 定）。 |
| 5 | 卡片 | 点按进直播间，长按或右键打开弹窗（A09.1）。 |
| 6 | 平台说明 | 只是说明，部分平台才有。 |
| 7 | 刷新（电脑） | 重新加载这一页（照 v3）。 |
| 8 | 上一页、下一页（电脑） | 翻页；键盘 ← → 也可以（照 v3）。 |
| 9 | 页码（电脑） | 跳到这一页。 |
| 10 | 每页（电脑） | 每页显示多少个（照 v3，选项在“页面”设置里）。 |
| 11 | 跳转至（电脑） | 输入页码回车。 |
| 12 | 平台 | 切到这个平台并关闭面板。 |
| 13 | 平台显示 | 打开设置里的“平台显示”，隐藏或排序平台。 |
| 14 | 关闭 | 关闭面板；点外面、返回键、Esc、竖屏下拉也可以。 |
| — | 手势 | 手机：下拉刷新，滑到底自动加载下一批，回到顶部 / 回到底部按钮在滚动后出现（照 v3）。 |

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 竖屏 2 列、横屏 4 列；“全部平台”从底部升起 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 列数按公式；“全部平台”在右侧；Windows、Linux、macOS 有翻页栏（照 v3），平板滑到底加载；悬停显示完整标题 |
| 电视 | A17.3 出图（以 pure_live_TV 为基线）；“全部平台”是同一面板的电视样式 |
| 苹果平台差异 | iOS 同 Android 手机，iPad 同 Android 平板，macOS 同 Windows |

## 待选和决定

- 选择 B1 找平台：建议加“全部平台”面板；另一种是照 v3 只能横滑。**用了建议**（D-003）。
- 选择 B2 第一次加载：建议静态骨架；另一种是照 v3 转圈。**用了建议**。
- 选择 B3 电脑翻页：建议照 v3（电脑翻页栏、触屏自动加载）；另一种是都自动加载、翻页栏做成设置项。**用了建议**。

### 设计时拿不准的地方

- 手机横屏时 v3 左侧导航栏把“关注 / 热门 / 分区”挤到屏幕外（`home/tablet_view.dart:85-140`，导航栏 `leadingAtTop: false` 加 `scrollable: true`，五个按钮和页面入口一起滚动）——按 Flutter 源码推算，没在真机上看；这是 I 的事，新设计图里照 v3 画。
- 出错图里的报错原文是按 Dio 的常见报错写的示例，实际文字取决于平台和网络。
- 电脑翻页栏三组之间没有间距（`desktop_components.dart:113-179`），照代码画得比较挤；真机上按钮自带的内边距会留一点空。
- “全部平台”面板的 34 个平台图标用的是应用里现有的平台图标（`packages/live_ui/assets/platforms/`）。

### 性能要点（评审页）

- 一次只建当前平台和相邻平台的网格（照 v3）；看一页时 0.7 秒后预取下一个平台（照 v3）。
- 骨架是静态色块，没有扫光；卡片出来时同尺寸替换，不重新排版。
- “全部平台”的图标是本地小图，按 36 像素解码；面板关掉就释放。
- 平台说明和流量提示在网格外面，变化时不重建网格。
- 窗口宽度变化只在跨过列数阈值时重排，滚动位置保留。

## 实现和验证

- 实现：c1～c9、选择 B1～B3 都做了（逐条见 [record.md](record.md)）。现在的代码：
  - `apps/pure_live/lib/features/popular/popular_page.dart`：`PopularPage`（`:33`）；平台标签在标题位置（`ScrollableTabBar`，键 `popular-platform-tabs`，`:183-184`），末尾 ⌄（`popular-all-platforms`，`:194`）；“全部平台”`PlatformPicker`（`:225`）由 `showAdaptivePanel` 打开（`:155`）：窗口宽 600 起在右侧（宽 360、整高），否则从底部升起（可下拉关闭），说明“N 个平台，点一个直接切过去；在“平台显示”里可以隐藏和排序”；左右的菜单按钮看 `showsHomeBarButtons`（`:168-175`，I 的外壳规则）。
  - `features/popular/popular_grid.dart`：`popularNoticeOf`（`:14`，平台说明）、`PopularPlatformView`（`:23`，只配文字，页面主体是 `apps/pure_live/lib/shared/rooms/room_grid.dart:357` 的 `RoomFeedView`）。
  - 翻页栏挪到 `apps/pure_live/lib/shared/rooms/paging.dart`（`PaginationBar` `:37`，键名改为 `pager-*`）；电脑翻页栏照 v3 看窗口宽 >680 且不是手机系统（`usesDesktopPages` `:18`，输入方式的判断，不是排版）。
  - c3 平台全关：“没有要显示的平台”“在“平台显示”里选择要在热门页显示的平台”、按钮“平台显示”；c4 空：手机“……也可以下拉刷新”，电脑“……也可以点下面的刷新”；有“已隐藏 N 个暂时不能播放的直播”时第一个按钮“显示”、第二个文字按钮“刷新”；c5 出错按 `describeLoadError`（`shared/rooms/room_texts.dart:140`），需要登录（含风控）“需要登录账号”“前往登录”（登录图标）；c6 平台说明 `NoticeBar`，点一下展开全文。
- 偏差：c9 只做到“网格列数用页面的宽度”；“是否用电脑翻页栏”照 v3 看窗口宽；顶栏要不要菜单按钮仍用 I 的外壳规则。
- 没有新设置。门禁：`popular` 直接写的颜色和图标 26 → 0。
- 提交：代码 `2a6bd204b`（`feat(ui): U.4a room card and dialogs, U.4b popular page`）；合并 `0e46099b2`（2026-10-01）；登记表写的是记录提交 `7daeb3805`。
- 后来的变化：A03.1（`a048ea540`）能刷新的列表用 `AppRefreshView`（D-009）；A03.2（`14e8eb6f6`）标签页翻页手感照 Android；D-011（`e320e0e72`）热门标题居中（`centredPageTitle`）；E06.1（`1239eb087`）卡片加“· 已播 N”。
- 自动测试：`apps/pure_live/test/features/popular/popular_test.dart`（现在 19 个用例声明）：全部平台面板（竖屏底部、打勾、点了切过去；宽屏右侧 360、✕ 关闭）、393×852 两列 / 852×393 四列 / 1280×800 五列和边距 6、空状态文字和刷新；照实改的旧断言（标题位置是平台标签、翻页栏键名、`LiveRoomCard`、长按对话框“虎牙 · 房间号 7”）；`home_test.dart` 两处“AppBar 里有‘热门’”改为“热门页在”。
- 真机：没有单独的 `verify.md`。S02.2 冒烟（2026-10-02，K90，`288fec0ec`）：“热门：哔哩哔哩列表、卡片、热度；右下‘到底部’按钮”通过（[S02.2 记录](../../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md)）。全部平台面板、平台说明、平台全关、出错各状态没有记录，对应 [CHECKLIST](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 4 节第 4 条。没在 profile 模式看过滚动帧时间。
- 留下的问题：电视（A17.3）；横屏手机时左侧导航栏把“关注 / 热门 / 分区”挤出屏幕的问题交给 I（A06.2），见“设计时拿不准的地方”第 1 条。
