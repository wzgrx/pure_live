# A02.3 贴着按钮的小菜单：按实测高度定位、从按钮方向展开：说明

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（待真机：代码 2026-10-02 合并，K90 还没逐项看，见 [verify.md](verify.md)）
- 旧编号：B03、T01d.2（见 [MAPPING.md](../../../MAPPING.md)）
- 范围：`packages/live_ui` 的两个小菜单函数 `showSmallMenu`（清晰度、线路、画面比例、竖屏全屏画面模式）和 `showAppMenu`（首页菜单、各页的 ⋮、搜索排序、翻页栏每页条数等）——怎么定位、往哪边展开、动画；菜单的样子不变
- 来源：用户问题 03：“手机横屏的时候，点击画质和线路弹出的UI动画不行，是从上面然后显示的，不整齐，应该是从下到上”；全面审查 A-03、B-7（[V03.1](../../../V-需求和反馈/V03-审查和调研/V03.1-全面审查/README.md)）
- 设计：没有单独出图（任务定为“出设计：不用”）。菜单的样子照 [A02.2](../A02.2-弹窗组件/README.md) 的小菜单（c2～c4）和 [A07.6](../../A07-直播间界面/A07.6-直播间弹窗/README.md) 已确认的清晰度、线路菜单；位置规则照 [specs/UI.md](../../../specs/UI.md) 第 7 节“贴着按钮，放得下的一边”
- 任务书：[brief.md](brief.md)；记录：[record.md](record.md)

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| A02.3-01 | 清晰度、线路菜单（`StreamMenuButton` → `showSmallMenu`） | 直播间竖屏信息行“原画 ⌄”“线路1 ⌄” | 竖屏 | 向下展开；当前项主色加勾；选后按钮转圈 |
| A02.3-02 | 同上 | 横屏全屏下栏（`preferAbove`） | 横屏 852×393、窄横屏 | 向上展开；7 档时在菜单里滚动 |
| A02.3-03 | 画面比例（`VideoFitButton`） | 全屏下栏 | 横屏 | 向上 |
| A02.3-04 | 画面模式（`PortraitModeButton`，标题行 + 说明行 + 固定宽度） | 竖屏全屏 | 竖屏全屏 | 向上 |
| A02.3-05 | 多画面焦点栏、格子控制条 | 多画面 | 竖屏、横屏 | 照空间 |
| A02.3-06 | 首页左上菜单、右上“更多”（`AppMenuButton` → `showAppMenu`） | 首页 | 竖屏、宽屏 | 向下；左边的按钮左对齐、右边的右对齐 |
| A02.3-07 | 搜索排序、备份文件行、WebDAV 文件行和“更多”、录制中心任务卡片 ⋮ | 各页 | 竖屏、宽屏 | 向下，列表底部放不下时向上 |
| A02.3-08 | 平板 1280×800 上的以上菜单 | — | 宽屏 | 下方放得下向下，否则向上 |

## 3.x 的样子和问题

- 样子：3.x 用 Flutter 的 `PopupMenuButton`（10 处）：清晰度、线路 `lib/modules/live_play/widgets/resolution_selector/resolution_selector.dart:24-80`（表面容器最高色、圆角 8、下移 5、11 号字）；首页左上 `lib/common/widgets/menu_button.dart:14-84`；右上 `common_appbar_actions.dart:13-68`；搜索排序 `modules/search/search_page.dart:261-280`。Flutter 的菜单从按钮位置往下长。
- 4.0（改之前）的问题和根因（[record.md](record.md)“根因”，用 Flutter 3.47.5 源码核对过）：
  - P1 展开方向：`material/popup_menu.dart` 的 `_PopupMenuRouteLayout.getPositionForChild` 只用 `y = position.top`，`_PopupMenu` 的动画是 `Align(alignment: topEnd, heightFactor: 动画值)`，永远从顶边往下长。旧代码向上时把顶边算成“按钮顶 − 4 − 估计高度”，于是菜单先在按钮上方远处出现一条线，再往下长到按钮。实测（3 档，横屏，按钮外框顶 349）：动画 60 毫秒时菜单底边在 221，160 毫秒时 301，最后停在 333——就是用户说的“从上面往下”。
  - P2 高度靠估算：旧 `_menuPosition` 用“条数 × 48 + 16”（标题行按 36）。7 档在 393 高的横屏上估计 352，大于按钮上方的空间，仍选向上，顶边算成负数，被 `showMenu` 的 `_fitInsideScreen` 推回到 y=8，菜单底边到 360，**压住按钮外框（顶 349）11 个点**；标题行实际 33 高，估成 36，带标题的菜单底边离按钮差 3。
  - P3 贴的是点击区：`StreamMenuButton` 把 48 高的点击区交给菜单，外框只有 32 高、居中，所以菜单和看得见的按钮之间隔 12，不是 4。
  - P4 `showMenu` 的动画固定 300 毫秒，不看“减少动态效果”。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| — | 没有出图：修的是定位和动画，样子照已确认的 A02.2、A07.6；做完后用 widget 测试把展开过程按 0、25、50、75、100、150 毫秒渲染成图自己核对（图在当时的本机 scratchpad，没进仓库） | 用户问题 03 提出；任务书由维护者定 |

## 对比页（按章节导出）

无。

## 单张图

无（渲染核对图没进仓库，结论写在 [record.md](record.md)“自己看的结果”）。

## 确认的改动

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 修改 | 不再用 Flutter 的 `showMenu`，改成自己的 `PopupRoute` + `CustomSingleChildLayout`：先排版、拿到**实测高度**再定方向——偏好向上且上方放得下 → 向上（`y = 按钮顶 − 4 − 菜单高度`）；下方放得下 → 向下（`y = 按钮底 + 4`）；都放不下 → 去空间大的一侧；最大高度是所选一侧的空间，长列表在菜单里滚动，不压按钮和底栏；水平贴按钮、和靠屏幕边的那条边对齐，离屏幕边和安全区至少 8 | P1、P2 |
| c2 | 修改 | 动画：打开 150 毫秒，淡入（`easeOut`）+ 从按钮那条边展开（`easeOutCubic`，向上时从下往上）；关闭 100 毫秒只淡出（“退出比进入快”）；展开用绘制时的裁剪，不改排版尺寸；系统“减少动态效果”时没有动画 | P1、P4 |
| c3 | 保留 | Esc、返回键关闭；方向键和回车选择（焦点在菜单里循环）；当前项主色加勾；说明行、标题行、危险项（红）；行还是 `PopupMenuItem`、分组线还是 `PopupMenuDivider` | — |
| c4 | 修改 | 所有用到这两个函数的地方自动受益；清晰度、线路菜单贴按钮**看得见的 32 高外框**，菜单离外框正好 4（以前离 48 的点击区 4，看起来隔 12） | P3 |

## 按钮的作用和用法

| 编号 | 控件 | 怎么用 |
|---|---|---|
| 1 | 清晰度、线路按钮 | 点开菜单；选一档菜单关闭、按钮转圈，旧画面继续播到新的出来（[specs/UI.md](../../../specs/UI.md) 附录 A 第 9 条） |
| 2 | 菜单里的行 | 点一项就关；电脑上下键移动、回车选；当前项主色加勾 |
| 3 | 关闭 | 点外面、返回键、Esc；打开时转屏（尺寸变化）菜单直接关掉 |

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 竖屏向下、横屏全屏向上，紧贴按钮 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 按空间：下方放得下向下，否则向上；键盘操作同上 |
| 电视 | 不涉及（电视的菜单在 A17） |
| 苹果平台差异 | 无；折叠屏铰链没有避让（Flutter 菜单的 `DisplayFeatureSubScreen` 没照搬），归 A04.1 |

## 待选和决定

- 维护者可以看一眼（不必须）：图标按钮（画面比例等）的菜单贴 48 的点击区，看起来离图标比清晰度菜单离外框远一点；要统一成贴图标的 40 圆形区域时，改 `apps/pure_live/lib/features/live_play/player/bar_parts.dart` 两处的 anchor（[record.md](record.md)“需要维护者决定的”）。

## 实现和验证（开发后补）

- 实现：新文件 `packages/live_ui/lib/src/widgets/anchored_menu.dart`（不从 `live_ui.dart` 导出）：`showAnchoredMenu`（`:47`）推 `PopupRoute`（不变暗、点外面关，`TraversalEdgeBehavior.closedLoop` `:89`）；方向在 `_AnchoredMenuLayout.getPositionForChild`（`:192-209`），最大高度在 `getConstraintsForChild`（`:178`）；间隔 `anchoredMenuGap` 4（`:15`）、边距 `anchoredMenuMargin` 8（`:18`）；时长 150 / 100 毫秒（`:22`、`:25`）；减少动态效果（`:62`）；尺寸变化时关掉（`:124-129`）。`showSmallMenu`（`stream_menu_button.dart:174`）和 `showAppMenu`（`app_menu.dart:88`）改用它，`showMenu` 和估算高度的 `_menuPosition`、`_position` 删掉；`StreamMenuButton` 的菜单贴外框（`_outline` 键，`stream_menu_button.dart:80`）；标题行改为普通组件。当前项在长列表里打开时自动滚进可见区。调用处没改（`features/live_play/buttons/`、`player/bar_parts.dart` 都没动）。
- 各调用处的位置（[record.md](record.md) 有完整表）：竖屏信息行向下离外框 4；横屏全屏下栏向上离外框 4、放不下时滚动；平板照空间；画面比例向上离 48 的按钮区 4；竖屏全屏画面模式向上；多画面照空间；首页菜单向下、按左右对齐；搜索排序、备份、WebDAV、录制中心向下，列表底部放不下向上。
- 偏差：贴外框不贴点击区（“按钮顶 − 4”按看得见的按钮理解）；屏幕尺寸变化时菜单直接关掉（键盘弹出收起不算）；没有照搬折叠屏铰链的避让；宽度规则照旧（最小 128、最大 280 或调用处给的固定宽度，按 56 一档取整）。
- 没有新设置、没有新翻译键、没有改 Android 原生代码。
- 提交：开发提交 `39b570ee6`（`fix(live_ui): small menus placed by measured height, unfolding from the button`，登记表写的是这个）；合并提交 `66492c34c`（2026-10-02）；记录 `e0f833068`。
- 自动测试：新 `packages/live_ui/test/small_menu_test.dart` 12 条（改之前 8 条失败：数字见“3.x 的样子和问题”的 P1、P2）；`apps/pure_live/test/features/live_play/live_play_popups_test.dart` 横屏一条加了“菜单底 = 外框顶 − 4、不出屏幕”。合并时 `live_ui` 111 条、`apps/pure_live` 741 条通过；`python3 tools/gate/check_ui_structure.py` 通过。
- 真机：待真机，步骤在 [verify.md](verify.md)。
- 留下的问题：图标按钮贴 48 点击区（见“待选和决定”）；折叠屏铰链（A04.1）。
