# A06.1 手机首页

- 日期：2026-10-01
- 设计：[docs/A-界面设计/A06-首页和全局/A06.1-手机首页/README.md](README.md)（第 1 版，用户已确认；X1～X3 按建议 A）；跨任务：A09.9 的 Z1 选 A（“历史记录”改名“观看记录”）
- 范围：手机首页外壳：底部导航、各首页标签顶栏的菜单、搜索、更多和它们弹出的菜单。页面内容（关注、热门、分区）由 I 做，这里没改。
- 改动的目录：`apps/pure_live/lib/features/home/`、`packages/live_ui`（只做添加）、四个首页标签页里决定顶栏按钮的一行（见“和别的任务的交界”）、`recorder_page.dart` 顶栏的一行、门禁基线、文档。
- 没有改原生部分，没有构建 APK，没有往手机安装。

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 底部导航四项、图标、文字、高度；显示和顺序由“导航栏显示控制”决定，只剩一项不显示；再点“关注”刷新；返回键回桌面；回前台超过 15 秒刷新；菜单按钮 `Icons.menu_rounded` 和位置 | ✅ | `NavigationBar` 照旧；返回键和回前台的代码没动（返回键只在 Android 生效，Linux 上的测试跑不到） |
| c2 | 两个菜单用同一个小菜单组件：字 14、图标 24 次要色、圆角 8、每行 48、贴着按钮弹出 | ✅ | `live_ui` 新增 `showAppMenu` / `AppMenuButton`（A07.6 确认的样子：`surfaceContainerHighest` 底、最小宽 128），按钮下方隔 4 弹出，下面放不下时在上方；左上菜单和按钮左边对齐，“更多”和按钮右边对齐 |
| c3 | 历史记录挪到“更多”第一项；左上菜单留设置、关于、备份与恢复（Windows 另有“新建独立播放窗口”） | ✅ | 名字按 A09.9 改成“观看记录”（已有的 `watch_history`）；“新建独立播放窗口”失败照旧提示“新窗口启动失败，请重试” |
| c4 | 右上拆成搜索（`CustomIcons.search`，点一下进搜索页）和“更多”`Remix.more_2_fill`（观看记录、链接解析、多画面） | ✅ | 设置里关了多画面就少一项；长按显示“搜索直播”“更多” |
| c5 | “链接访问”改叫“链接解析” | ✅ | 用 `toolbox_title`；`open_link` 键留在翻译文件里（3.x 的文件只加不删） |
| c6 | 录制中心标签页右边也有搜索和“更多”，排在“打开文件夹”“设置”后面 | ✅ | 只在手机排法时有（宽屏在侧边栏） |
| c7 | “分区”导航图标换成 `Remix.shapes_line/fill` | ✅ | 直播间菜单仍是四宫格 `AppIcons.roomMenu`；分区页空状态的四宫格在 A09.4 |

偏差：

1. **菜单离屏幕边至少 8**：Material 菜单不贴屏幕边，左上菜单的左边是 8（效果图 12），“更多”的右边是 385（393 宽）。
2. **组件名沿用**：页面里用的 `MenuButton`、`CommonAppBarActions` 名字没变（内容换了），这样关注、热门、分区页不用为顶栏再改；`CommonAppBarActions` 现在是“搜索 + 更多”两个按钮。

## 和别的任务的交界

- **首页标签页的一行**：关注、热门、分区、录制中心（以及 `shared/under_construction.dart`）原来用 `MediaQuery.sizeOf(context).width <= homeTabletBreakpoint` 判断要不要显示顶栏按钮（读整屏宽，v3 `Get.width`）。改成 `showsHomeBarButtons(context, inHome: ...)`：问首页外壳选了哪种排法（`HomeLayoutScope`），不在外壳里时才看宽度。每个文件只改这一行，I 同时在改这几个页面，合并时可能在这一行冲突，保留新写法即可。
- **关注页状态标签变窄**：右上从一个按钮变成两个，360 宽的手机上“已开播 12”这类带数字的标签会按比例缩小一点（`FittedBox`，不截断）。原测试要求缩放比 > 0.9（测试字体的数字是真实字体的两倍宽），改成 > 0.7 并写明原因。A09.3 如果想在窄手机上不缩，可以减小标签内边距。

## v3 文件 → v4 文件

| v3 | v4 |
|---|---|
| `modules/home/home_page.dart`、`mobile_view.dart` | `features/home/home_page.dart`、`home_views.dart`（`HomeMobileView`）、`home_menu.dart` |
| `common/widgets/menu_button.dart` | `features/home/menu_button.dart`（`MenuButton`、`AppMenuItem`） |
| `common/widgets/common_appbar_actions.dart`、`search_button.dart` | `features/home/menu_button.dart`（`CommonAppBarActions`、`HomeAction`） |
| 两套弹出菜单的样子 | `packages/live_ui/lib/src/widgets/app_menu.dart` |

## `live_ui` 的添加

- `AppMenuEntry`、`showAppMenu`、`AppMenuButton`、`appMenuMinWidth`、`appMenuGap`。
- `AppIcons`：`homeFavorites(Selected)`、`homePopular(Selected)`、`homeAreas(Selected)`（三个形状）、`homeRecord(Selected)`、`appMenu`、`search`、`more`、`watchHistory`、`openLink`、`multiview`、`settings`、`about`、`backup`、`newPlayerWindow`。

## 新设置

无。

## 门禁

- `home` 直接写的颜色和图标 **23 → 0**（`tools/gate/ui_baseline.json` 去掉这一项）。
- 没有新增跨功能引用（页面用的仍是基线里已有的 `home/home_menu.dart`、`home/menu_button.dart`）。

## 测试

- `apps/pure_live/test/features/home/home_test.dart`：6 → 15 个。手机：顶栏按钮的顺序、图标、位置和 48 的点击区域，搜索一点就到；底部导航四项的顺序和图标（分区是三个形状，没有四宫格）；两个菜单的条目、顺序、图标 24 次要色、字 14、行高 48、底色和圆角、在按钮下方并对齐；多画面关掉时少一项；观看记录、关于能打开；Windows 菜单项的条件；录制中心标签页右边的顺序；字体放大 1.3 倍不溢出。宽屏的测试在 [A06.2](../A06.2-宽屏首页/record.md)。
- `live_ui`：`test/app_menu_test.dart` 2 个（小菜单的尺寸、颜色、位置、上方弹出、Esc），`AppIcons` 对照表加了这次的图标。
- 原有测试照实改了的：

| 测试 | 原断言 | 改为 | 原因 |
|---|---|---|---|
| `home_test` 菜单 | `visibleHomeMenus(tablet: true)` 不含录制中心 | 两种排法同一组；什么都没存时显示全部 | A06.2 c3 |
| `favorite_test` 状态标签 | 360 宽时缩放比 > 0.9 | > 0.7 | 右上多了一个按钮（c4），见上 |

全部测试：`apps/pure_live` 306 个通过（开始时 278 个，A06.1～A06.3 合计新增 28 个）；`flutter analyze` 无问题；`check_ui_structure.py` 通过。
