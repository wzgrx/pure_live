# X01.1 键盘鼠标操作核对

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：清点。[specs/UI.md](../../../specs/UI.md) 第 5.4 节（输入方式）和附录 A 第 13、14、16 条要求桌面上的键鼠操作和 3.x 一致；功能清点第 13 节 F-WIN-08、F-WIN-09、F-WIN-13 也是键鼠的一部分。
- 旧编号：T17b.1
- 相关：决定 [D-004](../../../DECISIONS.md)（Windows 是第二个客户端）；依赖 [X01.3](../X01.3-Windows安装包和自动更新/README.md) 第一阶段（能在 Windows 上构建运行）；关联 [X01.2](../X01.2-Windows专属功能/README.md)、[A16.1](../../../A-界面设计/A16-桌面界面/A16.1-桌面窗口/README.md)、[A07.4](../../../A-界面设计/A07-直播间界面/A07.4-横屏全屏/README.md)、[A07.5](../../../A-界面设计/A07-直播间界面/A07.5-宽屏左右分栏/README.md)

## 目标

在 Windows（以及以后的 Linux、macOS）上，3.x 用户习惯的每一个键盘快捷键、鼠标滚轮、悬停、右键、双击都还在，而且有测试守着；4.x 新加的（例如直播间的 F 键）写清楚是确认过的改动。做完以后桌面用户换到 4.x 不会发现“某个键不灵了”。

## 3.x 和现状

| 方面 | 3.x（文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 直播间 Esc | `modules/live_play/widgets/keyboard/video_keyboard.dart:55`：画中画时不管；全屏时退全屏；窗口内全屏时退窗口内全屏；**普通状态离开直播间**（`:35-41` 显式 `maybePop`，注释写明桌面 Flutter 不会自己把 Esc 当返回） | `features/live_play/live_play_page.dart:738` 绑到 `_back()`（`:662-673`）：桌面小窗回直播间、关面板、退全屏、关详情；**普通状态什么都不做**（不离开直播间） | 和 3.x 一样：普通状态按 Esc 离开直播间（附录 A 第 7 条“Esc 走同一条返回链”） |
| 空格暂停/继续 | `video_keyboard.dart:60` | `live_play_page.dart:742` | 保持 |
| 媒体键（播放、暂停、播放/暂停） | `video_keyboard.dart:56-58` | `live_play_page.dart:750-753`（F.1d） | 保持 |
| R 刷新 | `video_keyboard.dart:61` | `live_play_page.dart:748` `controller.load()` | 保持 |
| ↑↓ 音量 ±5% | `video_keyboard.dart:62-79` | `live_play_page.dart:744-747`，`save: true` 记成房间音量 | 保持 |
| F 全屏 | 没有 | `live_play_page.dart:739`（桌面小窗时不响应）；C01.1 的提交 `0249e830e` 加的，记录里没有写依据 | 新加的：请维护者确认留不留，写进本文件 |
| 滚轮调音量 | `video_controller_panel.dart:952` | `features/live_play/player/player_gestures.dart:223`；小窗 `features/live_play/mini/mini_player.dart:199` | 保持，核对每格步长 |
| 鼠标移动显示控制层、静止后隐藏 | `widgets/layout/control_hover_region.dart:5`（处理“组件消失时收不到 onExit”） | `features/live_play/player/player_view.dart:798` `MouseRegion.onHover` → `_touch()`（`:399`） | 核对：鼠标离开画面时控制层按时隐藏；控制条上悬停时不隐藏 |
| 桌面单击只显示控制层、双击全屏 | 附录 A 第 1、3 条 | `player_view.dart` 的点按处理 | 写测试固定 |
| 右键等于长按 | 房间卡片 `common/widgets/room_card.dart:1078`、弹幕列表 `danmaku_list_view.dart:501`、多画面格子 `multiview_page.dart:984` | 卡片 `packages/live_ui/lib/src/widgets/live_room_card.dart:129`、`:692`；聊天列表 `features/live_play/danmaku/chat_list.dart:615`、`:706`；多画面 `features/multiview/widgets/cell_view.dart:84`；新加的：分区卡片 `areas/area_card.dart:74`、录制任务 `recorder/recorder_task_card.dart:260`、网络电视 `iptv/iptv_cards.dart:194`、备份 `backup/backup_page.dart:545`、WebDAV `web_dav/web_dav_page.dart:695` | 3.x 有的都在；播放画面本身 3.x 也没有右键菜单，不加 |
| 标签栏滚轮横向滚动 | `common/widgets/scrollable_tab_bar.dart:92` | `packages/live_ui/lib/src/widgets/scrollable_tab_bar.dart:145` | 保持 |
| ←→ 切换标签页 | `common/base/base_page_view_extension.dart:10-15` | 关注 `favorite/favorite_page.dart:512`、分区 `areas/platform_areas_view.dart:246`、房间网格 `shared/rooms/room_grid.dart:585` | 核对热门、搜索结果等其他用标签页的页面 |
| 多画面 Esc | `modules/multiview/multiview_page.dart:164` | `features/multiview/multiview_page.dart:380` | 保持 |
| 设置页查找 | 没有 | `features/settings/settings_page.dart:237-239`（Ctrl+F、Cmd+F、Esc 清空） | 新加的，保持 |
| 悬停显示按钮名称、焦点框只在用键盘时显示、Tab 顺序和视觉一致 | 部分（3.x 标题栏在导航器外，没有名称） | 标题栏按钮有（A16.1 c3）；其他按钮逐页核对 | specs/UI.md 第 5.4 节 |

## 方案

- c1 列清单：把上表补全到每个页面（首页、热门、分区、搜索、关注、历史、直播间各布局、多画面、录制中心、设置），每一项写 3.x 的文件:行和 4.x 的文件:行，放进本文件。
- c2 修直播间 Esc：`_back()` 在普通状态（`_poppable` 为真，`live_play_page.dart:639-640`）时离开直播间（`Navigator.maybePop`），和 3.x `resolveEscapePresentationAction` 的顺序一致；Android 的返回键不受影响（它走 `PopScope`）。
- c3 F 键：C01.1（`0249e830e`）加的，没有写依据；作为“需要维护者决定的”报告，决定后写进本文件（建议保留：不和 3.x 的任何键冲突）。
- c4 核对每一项，缺的补上（只补 3.x 有的）。
- c5 测试：每个快捷键和鼠标操作至少一个 widget 测试（`TargetPlatform.windows`、1280×800），固定按键和结果。
- c6 Windows 上实际按一遍（键盘布局、输入法开着时空格是否被吃掉、触控板双指滚动）。

## 验证

- 自动测试：`apps/pure_live/test/features/live_play/`（直播间的键盘、滚轮、悬停、右键）、`test/features/multiview/`、`test/features/favorite/`，新用例写在已有的文件里。
- 真机：Windows 主机上按 brief.md 的“真机验证”逐条按；结果写进 verify.md。

## 留下的问题

- 还没开工。读代码时发现的：普通状态下直播间按 Esc 不离开（见上表第一行），疑似回归，开工时先写失败的测试确认。
