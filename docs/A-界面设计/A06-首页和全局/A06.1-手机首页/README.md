# A06.1 手机首页：设计（第 1 版，已确认并完成）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 范围：手机首页的外壳：底部导航、每个首页标签顶栏左右的按钮和它们弹出的菜单（页面本身的内容在 A09.2～A09.4、A10.1）
- 对应：[inventory/UI.md](../../../inventory/UI.md#a061)（A06.1-01～05）、[inventory/V3_UI.md](../../../inventory/V3_UI.md) 第 1 节（核对代码后的出入见文末“清单里和代码不符的地方”）；[specs/UI.md](../../../specs/UI.md) 第 14 节候选 C-1；相关决定 D-003（选择按建议 A）；宽屏在 [A06.2](../A06.2-宽屏首页/README.md)
- 评审页：claude.ai 私有页面（只有项目所有者能打开），每条改动可以点“满意 / 不满意 / 再想想”；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)
- 图片：v3 按 `v3.2.11` 代码还原（文字取自 `assets/translations/zh.json`，颜色是 `ColorScheme.fromSeed(Colors.blue)`）；封面和头像是示意图片，卡片和标签照 v3 画，样子在 A09 定
- 旧编号：U.3a、T07a.4（[MAPPING.md](../../../MAPPING.md)）

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| A06.1-01 | 首页外壳：底部导航 + 当前页面 | 启动页之后；任何页面返回到底 | 竖屏（v3 宽度 ≤680；新设计 <600，见 A06.2） | 四项、两三项、只剩一项（不显示导航栏）；四个标签各自选中 |
| A06.1-02 | 左上菜单 | 关注、热门、分区、录制中心标签页顶栏左边的菜单按钮 | 竖屏 | Android 四项；Windows 窄窗口且开了“新建独立播放窗口”时五项（新设计：三项 / 四项） |
| A06.1-03 | 右上菜单 | 关注、热门、分区标签页顶栏右边 | 竖屏 | 多画面开 / 关（关时少一项） |
| A06.1-04 | 录制中心标签页的顶栏 | 底部导航“录制中心” | 竖屏 | — |
| A06.1-05 | 提示条“新窗口启动失败，请重试” | 左上菜单“新建独立播放窗口”失败 | Windows 窄窗口 | — |
| A06.1-06 | 按钮名称提示“菜单”“更多”（新设计加“搜索直播”） | 长按（手机）、悬停（电脑） | 竖屏 | — |
| A06.1-07 | 启动后的“新版本”对话框 | 首页出现 2 秒后自动检查 | 竖屏、横屏、宽屏 | 在 [A06.3](../A06.3-全局弹窗/README.md) |
| — | 返回键 | 首页按系统返回 | Android | 回到桌面，应用不退出（没有界面） |

## 3.x 的样子和问题

**外壳**（`lib/modules/home/home_page.dart`、`mobile_view.dart`）

- 宽度按父组件给的约束判断：`constraint.maxWidth > 680` 用宽屏排法，否则手机排法（`home_page.dart:232`）；但关注、热门、分区页决定顶栏要不要显示按钮时读的是整屏宽度 `Get.width <= 680`（`favorite_page.dart:17`、`popular_page.dart:15`、`areas_page.dart:19`）。
- 底部 `NavigationBar`（Material 3 默认：高 80，表面容器色底，选中项是 64×32 的次色容器胶囊，图标 24，文字 12 号 `labelMedium`）。四项，图标和文字（`mobile_view.dart:28-64`）：关注 `Remix.heart_3_line/fill`、热门 `Remix.fire_line/fill`、分区 `Remix.apps_2_line/fill`、录制中心 `Remix.download_2_line/fill`。
- 显示哪几项、什么顺序由设置“导航栏显示控制”决定（`savedMenuIds`，默认四项全开，至少留一项：`app_settings_controller.dart:69`、`:145-153`、`:164-175`；设置页 `navigation_settings_page.dart`）；只剩一项时不显示导航栏（`mobile_view.dart:68`）。
- 关注已选中时再点“关注”= 刷新关注（`home_page.dart:187-191`）。
- 返回键不退出，`moveToDesktop` 回到桌面（`home_page.dart:218-222`）。
- 从后台回来、离开超过 15 秒：450 毫秒后刷新当前的热门或分区（`home_page.dart:141-165`）。
- 首页第一帧后 2 秒检查更新，有新版且开着“自动检查更新”就弹“新版本”对话框（`home_page.dart:99-104`、`:198-216`，对话框在 A06.3）。
- 四个页面都保留状态（`AutomaticKeepAliveClientMixin`，`home_page.dart:49`、`:281`）。

**各标签页顶栏**（页面自己的 `AppBar`，手机上才有这两个按钮）

- 关注、热门、分区：左 `MenuButton`，右 `CommonAppBarActions`；标题位置分别是三个状态标签（已开播、录播、未开播）、平台标签、平台标签（`favorite_page.dart:22-38`、`popular_page.dart:24-35`、`areas_page.dart:22-33`）。
- 录制中心：左 `MenuButton`（从别处打开时是返回），标题“录制中心”，右边“打开文件夹”`Remix.folder_video_line`（22）和“设置”`Remix.settings_5_line`（22），**没有右上菜单**（`recorder_page.dart:35-53`）。

**左上菜单**（`common/widgets/menu_button.dart`）

- 按钮：`Icons.menu_rounded`，48×48，提示“菜单”（`:15-23`）。
- 弹出：按钮下方、右移 12，圆角 8（`:17-19`）；每行左边图标 24（次要色），间隔 12，文字 12 号 `labelMedium`（`:67-84`）。
- 四项：设置 `Remix.settings_5_line`、关于 `Remix.information_line`、历史记录 `Remix.history_line`、备份与恢复 `Remix.cloud_line`（`:35-55`）；Windows 并且开着设置“新建独立播放窗口”时多一项“新建独立播放窗口”`Icons.add_to_photos_outlined`（`:56-61`），失败时提示条“新窗口启动失败，请重试”（`:25-31`）。

**右上菜单**（`common/widgets/common_appbar_actions.dart`）

- 按钮：`Remix.menu_search_line`（菜单线条加放大镜），24，提示“更多”（`:13-14`、`:69-72`）。
- 弹出：按钮下方 10，圆角 14（`:15-17`）；每行图标 20、**主色**，间隔 12，文字 14 号（`:36-41`）。
- 三项：搜索直播 `Remix.search_line`、链接访问 `Remix.link`、多画面 `Remix.layout_grid_line`（设置里关了多画面就没有）（`:32-68`）。
- 同目录的 `search_button.dart` 有 `SearchButton`（`CustomIcons.search`）和 `LinkButton`（`Icons.link`），v3 没有用到。

**3.x 的问题**

| 编号 | 问题 | 位置 |
|---|---|---|
| P1 | “历史记录”在左上菜单里，和设置、关于、备份与恢复放在一起；看过的直播间属于“找直播”，却和应用管理混在一起（计划书 C-1） | `menu_button.dart:11`、`:46-50` |
| P2 | 两个菜单是两套样子：左上字 12 号、图标 24 灰色、圆角 8；右上字 14 号、图标 20 主色、圆角 14、离按钮 10。左上的字小于弹窗最小 14 号 | `menu_button.dart:17-18`、`:79`；`common_appbar_actions.dart:15-16`、`:38-40` |
| P3 | 搜索要点两下：右上角是“菜单+放大镜”图标，点开再选“搜索直播”；宽屏侧栏搜索点一下就到 | `common_appbar_actions.dart:36-41`、`:69-72`；`tablet_view.dart:130-137` |
| P4 | 同一个功能名字、图标不一样：手机菜单叫“链接访问”，宽屏提示和页面标题叫“链接解析”；搜索在手机菜单是 `Remix.search_line`，宽屏是 `CustomIcons.search` | `common_appbar_actions.dart:38`、`:52`；`tablet_view.dart:126`、`:135`；`toolbox_page.dart:16` |
| P5 | 录制中心标签页的顶栏没有右上菜单：在这一页找不到搜索、链接访问、多画面，要先切到别的标签 | `recorder_page.dart:38-52` |
| P6 | “分区”导航图标 `Remix.apps_2_line` 和直播间右上角菜单是同一个图标，意思不同 | `mobile_view.dart:50-51`；`live_play_menu_button.dart:38` |

没有问题、照 v3 的：底部导航的样子和行为、只剩一项不显示、再点关注刷新、返回键回桌面、回前台刷新、菜单按钮的图标和位置。

必须保留的操作习惯（[specs/UI.md](../../../specs/UI.md) 附录 A）：第 15 条 Windows 在新窗口打开（左上菜单“新建独立播放窗口”）。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 四张对比（首页、左上菜单、右上菜单、录制中心标签）、按钮用法、三处选择 | 2026-10-01 确认，X1～X3 按建议 A；跨任务 A09.9 的 Z1 选 A（“历史记录”改名“观看记录”） |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [对比](page/02-对比.jpg)
- [v3 的问题](page/03-v3-的问题.jpg)
- [改了什么](page/04-改了什么.jpg)
- [每个按钮是干什么的、怎么用](page/05-每个按钮是干什么的-怎么用.jpg)
- [各客户端](page/06-各客户端.jpg)
- [需要你选的](page/07-需要你选的.jpg)
- [性能要点](page/08-性能要点.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-home.jpg](v3-home.jpg)、[v4-home.jpg](v4-home.jpg)、[v4-home-n.jpg](v4-home-n.jpg) | 首页（关注）：v3 / 新设计 / 按钮编号 |
| [v3-menu.jpg](v3-menu.jpg)、[v4-menu.jpg](v4-menu.jpg) | 左上菜单 |
| [v3-search-menu.jpg](v3-search-menu.jpg)、[v4-more-menu.jpg](v4-more-menu.jpg) | 右上菜单：v3 的搜索菜单 / 新设计的“更多” |
| [v3-record-tab.jpg](v3-record-tab.jpg)、[v4-record-tab.jpg](v4-record-tab.jpg)、[v4-record-tab-n.jpg](v4-record-tab-n.jpg) | 录制中心标签页的顶栏 |

## 确认的改动

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 保留 | 底部导航（四项、图标、文字、高度，显示和顺序由“导航栏显示控制”决定，只剩一项不显示）、再点“关注”刷新、返回键回桌面、回前台超过 15 秒刷新、菜单按钮 `Icons.menu_rounded` 和位置 | — |
| c2 | 修改 | 两个菜单用同一个小菜单组件（A07.6 已确认的样子）：字 14 号、图标 24 次要色、圆角 8、每行 48 高、贴着按钮弹出 | P2 |
| c3 | 修改 | 历史记录挪到右上“更多”菜单第一项（名字按 A09.9 Z1 改成“观看记录”）；左上菜单留设置、关于、备份与恢复（Windows 另有“新建独立播放窗口”）（选择 X1） | P1 |
| c4 | 增强 | 右上角拆成两个按钮：搜索（点一下进搜索页，`CustomIcons.search`，和宽屏同一个图标）和“更多”`Remix.more_2_fill`（观看记录、链接解析、多画面）（选择 X2） | P3 |
| c5 | 修改 | “链接访问”改叫“链接解析”，和页面标题、宽屏一致 | P4 |
| c6 | 修改 | 录制中心标签页右边也有搜索和“更多”，排在“打开文件夹”“设置”后面 | P5 |
| c7 | 修改 | “分区”导航图标换成 `Remix.shapes_line/fill`（三个形状，通用的“分类”图标），直播间菜单仍是四宫格（选择 X3） | P6 |

## 按钮的作用和用法

编号对应 [v4-home-n.jpg](v4-home-n.jpg)。

| 编号 | 控件 | 怎么用 |
|---|---|---|
| 1 | 菜单 | 点开菜单：设置、关于、备份与恢复；Windows 窄窗口开了“新建独立播放窗口”时多这一项。长按显示“菜单”。 |
| 2 | 搜索（新） | 点一下进搜索页。长按显示“搜索直播”。 |
| 3 | 更多 | 点开菜单：观看记录、链接解析、多画面（设置里关了多画面就没有）。长按显示“更多”。 |
| 4 | 关注 | 切到关注；已经在关注时再点一下刷新关注。 |
| 5 | 热门 | 切到热门。 |
| 6 | 分区 | 切到分区（图标换了）。 |
| 7 | 录制中心 | 切到录制中心；这一页顶栏右边是打开文件夹、设置、搜索、更多。 |
| — | 系统返回 | 回到桌面，应用不退出。 |

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 上图。宽度 <600 用这个排法（分界在 A06.2 定）。 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 侧边导航栏，见 [A06.2](../A06.2-宽屏首页/README.md)：同样的入口，菜单、搜索、观看记录、链接解析、多画面在侧边栏上各是一个按钮。窄窗口（<600）同手机，悬停显示按钮名称；Windows 菜单里有“新建独立播放窗口”。 |
| 电视 | 不适用。电视首页外壳在 A17.2（以 pure_live_TV 为基线，左侧导航已有“搜索”“观看记录”两项）。 |
| 苹果平台差异 | iPhone 底部导航留出主屏指示条的安全区；iOS 没有返回键，首页是第一页，不需要返回；其他同 Android。 |

## 待选和决定

- X1 历史记录放哪：**A** 右上“更多”菜单第一项；B 照 v3 留在左上菜单。→ 用户选 A（2026-10-01）。
- X2 搜索：**A** 右上角单独一个搜索按钮，点一下就到；B 照 v3 一个按钮弹菜单，再选“搜索直播”。→ 用户选 A。
- X3 分区图标：**A** 换成三个形状；B 照 v3 四宫格。→ 用户选 A。

## 拿不准的地方（设计时记下的）

- 底部导航下面的系统手势区按 20 高画；K90 上的实际值没有量。
- 录制中心空状态的图标 v3 是 `Icons.video_collection_outlined`，效果图工具没有 Material 的 outlined 字体，用圆角版近似。
- 卡片、状态标签、平台标签照 v3 代码示意，样子在 A09.2～A09.4 定；录制中心页面本身在 A10.1。
- X3 选 A 时，分区页的空状态图标（`areas_grid_view.dart:147` 等，也是四宫格）在 A09.4 一起换；设置里“平台显示与授权”也用四宫格（`settings_page.dart:151`），在 J 看。

## 清单里和代码不符的地方

`V3_UI_INVENTORY.md`（现 [inventory/V3_UI.md](../../../inventory/V3_UI.md)）第 1 节（不在本任务里改，供更新清单时参考）：

- 左上菜单的 Windows 项文字是“新建独立播放窗口”，而且要开着设置“新建独立播放窗口”才有（清单写“新窗口打开（仅 Windows）”）。
- 宽屏侧栏 `Remix.link` 的提示是“链接解析”（`toolbox_title`），清单写“工具箱”。
- “v4 现在：导航图标换成了 Material”已经过时：v4 当时的 `features/home/` 图标、菜单项、样子都和 v3 一样（包括上面这些问题）；本任务完成后按上面的确认改动变了。

## 实现和验证

**实现**（详见 [record.md](record.md)；2026-10-01，和 A06.2～A06.4 一起合并，合并提交 `938c65a5b`“Merge U.3a-d: home shell, splash and global dialogs”，登记表记的是分支上最后的记录提交 `6e00ef1dc`；代码提交 `c4c3772a3`（`live_ui` 小菜单和图标）、`22f25e729`（手机和宽屏外壳））

| 编号 | 做到 | 现在的代码 |
|---|---|---|
| c1 | ✅ | `apps/pure_live/lib/features/home/home_page.dart`：再点关注刷新 `:114-120`、返回键 `moveToBack` `:122-131`、回前台 15 秒 `:94-112`；`home_views.dart:34` 只剩一项不显示导航栏；`home_menu.dart:6-38` 四项和 `savedMenuIds` |
| c2 | ✅ | `packages/live_ui/lib/src/widgets/app_menu.dart` 的 `showAppMenu`、`AppMenuButton`（`surfaceContainerHighest` 底、最小宽 128、按钮下方隔 4 弹出，下面放不下时在上方）；左上菜单和按钮左边对齐，“更多”和右边对齐 |
| c3 | ✅ | `features/home/menu_button.dart:15` 的 `AppMenuItem`（设置、关于、备份与恢复、新窗口）；“观看记录”是 `HomeAction.history`（`:97`），用已有的 `watch_history` 文字；“新建独立播放窗口”失败照旧提示 |
| c4 | ✅ | `menu_button.dart:131` 的 `CommonAppBarActions`：搜索 `IconButton`（提示“搜索直播”）+ `AppMenuButton<HomeAction>`；多画面关掉少一项（`:124-125`） |
| c5 | ✅ | `HomeAction.openLink` 用 `toolbox_title`（`:100`）；`open_link` 键留在翻译文件（3.x 的文件只加不删） |
| c6 | ✅ | 录制中心页顶栏右边加搜索和“更多”，只在手机排法时有（`features/recorder/recorder_page.dart:276` 的 `showsHomeBarButtons`） |
| c7 | ✅ | `AppIcons.homeAreas(Selected)` 三个形状；直播间菜单仍是 `AppIcons.roomMenu` 四宫格 |

- 偏差：①菜单离屏幕边至少 8（Material 菜单不贴屏幕边），左上菜单左边是 8（效果图 12），“更多”的右边是 385（393 宽）；②组件名沿用 `MenuButton`、`CommonAppBarActions`（内容换了），关注、热门、分区页不用为顶栏再改。
- 和别的任务的交界：关注、热门、分区、录制中心（和 `shared/under_construction.dart`）原来用 `MediaQuery.sizeOf(context).width <= homeTabletBreakpoint` 判断要不要显示顶栏按钮（读整屏宽，v3 `Get.width`），改成 `showsHomeBarButtons(context, inHome: ...)`（`home_menu.dart:76-79`，问首页外壳选了哪种排法）；关注页状态标签在 360 宽的手机上按比例缩小一点（`FittedBox`，不截断），原测试缩放比从 > 0.9 改成 > 0.7。
- 门禁：`home` 直接写的颜色和图标 23 → 0（`tools/gate/ui_baseline.json` 去掉这一项）。

**验证**

- 自动测试：`apps/pure_live/test/features/home/home_test.dart` 6 → 15 个（手机：顶栏按钮的顺序、图标、位置和 48 的点击区域，搜索一点就到；底部导航四项的顺序和图标（分区是三个形状）；两个菜单的条目、顺序、图标 24 次要色、字 14、行高 48、底色和圆角、在按钮下方并对齐；多画面关掉少一项；观看记录、关于能打开；Windows 菜单项的条件；录制中心标签页右边的顺序；字体放大 1.3 倍不溢出）；`packages/live_ui/test/app_menu_test.dart` 2 个；`AppIcons` 对照表。当时 `apps/pure_live` 306 个全部通过。
- 真机：[S02.2](../../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md)（2026-10-02，K90，构建 `288fec0ec`）看了首页“关注”和底部四个导航，通过。顶栏菜单、“更多”、录制中心标签顶栏没有单独在真机上点过。
- 留下的问题和去向：状态栏和导航栏的样式和 3.x 的差别 → [A06.5](../A06.5-首页状态栏和导航栏颜色/README.md)；分区页空状态的四宫格 → A09.4；设置里“平台显示与授权”的四宫格 → J。
