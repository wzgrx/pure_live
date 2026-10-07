# A16.2 直播间菜单的“在新窗口打开”接上 A16.1 的新窗口，补回误删的翻译键：设计（沿用 A16.1 第 1 版）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（未开始，第三档，规模小）
- 来源：[A16.1](../A16.1-桌面窗口/README.md) 确认的改动 c12 只做了一半：首页菜单接上了，直播间菜单那一半当时在 A07 手里，A16.1 只留了接口（[A16.1 记录](../A16.1-桌面窗口/record.md)“给其他任务的接口”）；给它准备的翻译键 `open_in_new_window`“在新窗口打开”因为没人用，被 `00f5edf18`（2026-10-02，清理 930 个不用的键）删掉了。2026-10-07 docs v2 A 组核对时登记
- 范围：直播间右上角四宫格菜单里“在新窗口打开”这一项（显示条件、文字、图标、位置、点了以后）；不改首页菜单、不改新窗口本身
- 对应：[inventory/UI.md](../../../inventory/UI.md) 的直播间菜单；[specs/UI.md](../../../specs/UI.md) 附录 A 第 15 条（Windows 在新窗口打开直播间）；A16.1 c12、c14（新窗口和主窗口共用数据）；[A07.6](../../A07-直播间界面/A07.6-直播间弹窗/README.md) c6（菜单分组）；[A11.4](../../A11-设置界面/A11.4-通用和网络/README.md)（设置“新建独立播放窗口”的说明已经写成“首页菜单和直播间菜单里显示‘在新窗口打开’”）；决定 D-003、D-004、D-024
- 评审页：不另出。样子在 A16.1 第 1 版已经确认（评审页章节 [直播间菜单里的 在新窗口打开](../A16.1-桌面窗口/page/09-直播间菜单里的-在新窗口打开.jpg)，效果图 [v4-room-menu.jpg](../A16.1-桌面窗口/v4-room-menu.jpg)、编号图 [v4-room-menu-n.jpg](../A16.1-桌面窗口/v4-room-menu-n.jpg)），这里只是把它做完
- 任务书：[brief.md](brief.md)

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| A16.2-01 | 直播间菜单第二组的“在新窗口打开” | 直播间顶栏右上角四宫格按钮（竖屏普通布局的应用栏 `layout/room_header.dart:108`）；横屏全屏、宽屏画面控制层的同一个按钮（`player/player_controls.dart:374-377`） | Windows（以后 Linux，有桌面外壳时）；Android、电视不显示 | 有（有桌面外壳且设置“新建独立播放窗口”开）/ 没有（设置关、或没有桌面外壳）；点了：新窗口打开并直接进这个直播间；失败：提示条“新窗口启动失败，请重试” |
| 相关 | 首页左上菜单“新建独立播放窗口” | 首页菜单 | Windows | 不变（A16.1 已做） |
| 相关 | 设置 → 通用“新建独立播放窗口” | 设置 | Windows | 不变；说明已经写着“首页菜单和直播间菜单里显示‘在新窗口打开’”（`settings_new_window_desc`，`apps/pure_live/assets/translations/zh.json:1979`），现在和直播间不符 |

## 3.x 的样子和问题

- 3.x：直播间右上角菜单（`git show v3.2.11:lib/modules/live_play/widgets/button/live_play_menu_button.dart`）最后一项“在新窗口播放此直播间”（`open_room_in_new_window`），图标 `Icons.open_in_new_rounded`，**只看 `Platform.isWindows`，不看设置**（`:206`）；第一项“打开直播间”用的是同一个图标（`:188`）。点了另起一个进程，带着全部设置的临时副本（A16.1 的 D12）。
- 4.x 现在（2026-10-07 master）：
  - P1 显示条件还是按平台：`roomMenuGroups(windows:)`（`apps/pure_live/lib/features/live_play/buttons/room_menu_button.dart:158-180`，`:173` `if (windows) RoomMenuEntry.newWindow`），`windows` 来自 `TargetPlatform.windows`（`player/player_controls.dart:73`、`live_play_page.dart:1108` 的 `_platform.windows`）。关掉设置“新建独立播放窗口”后直播间菜单里仍有这一项；首页菜单已经看设置（`features/home/menu_button.dart:56`）。两处规则不一样，正是 A16.1 的 D10。
  - P2 文字和图标是旧的：`:300` 显示“在新窗口播放此直播间”（`open_room_in_new_window`）、图标 `AppIcons.newWindow`（`Icons.open_in_new_rounded`，`packages/live_ui/lib/src/icons/app_icons.dart:289`，和“在<平台>打开”的外链图标太像）。A16.1 c12 定的是“在新窗口打开”、图标 `add_to_photos`（`AppIcons.newPlayerWindow`，`app_icons.dart:68`，和首页菜单同一个）。
  - P3 走旧接口：`:254-261` 调 `launchNewWindow(services.store, services.cipher, room: room)`（`app/launch_args.dart:115`，参数已用不上，注释写着“new code calls `DesktopWindow.openNewWindow`”），失败提示自己写一遍；不经过 `DesktopWindow.newWindowLauncher`，所以测试里换不掉，Linux 有桌面外壳时也不会走对的启动器。
  - P4 翻译键没了：`open_in_new_window` 被 `00f5edf18` 删掉（那次的 diff 里 `zh.json` 第 1231 行），现在两个翻译文件里都没有。
  - 位置已经对：第二组“在<平台>打开”后面（`:172-173`），不用改。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| A16.1 第 1 版 | 直播间菜单里的“在新窗口打开”：跟设置走、改名、换图标、放在“在哔哩哔哩打开”后面、Linux 也有（c12） | 用户确认第 1 版，T1～T4 按建议 A（D-003） |

## 对比页（按章节导出）

- 用 A16.1 的：[直播间菜单里的 在新窗口打开](../A16.1-桌面窗口/page/09-直播间菜单里的-在新窗口打开.jpg)、[在新窗口打开](../A16.1-桌面窗口/page/08-在新窗口打开.jpg)。

## 单张图

| 图 | 内容 |
|---|---|
| [A16.1 的 v3-room-menu.jpg](../A16.1-桌面窗口/v3-room-menu.jpg)、[v4-room-menu.jpg](../A16.1-桌面窗口/v4-room-menu.jpg) | 直播间右上角菜单（Windows）：“在新窗口打开”的图标和位置 |
| [A16.1 的 v4-room-menu-n.jpg](../A16.1-桌面窗口/v4-room-menu-n.jpg) | 编号示意图（第 12 项） |

## 确认的改动

都来自 A16.1 c12（已确认），这里拆成可检查的几条：

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 修改 | 显示条件改成 `DesktopWindow.offersNewWindow(settings)`（有桌面外壳且“新建独立播放窗口”开），不看平台名；设置改了菜单下次打开时跟着变 | P1 |
| c2 | 修改 | 文字“在新窗口打开”（新加回 `open_in_new_window`，英文 “Open in a new window”），图标 `AppIcons.newPlayerWindow`（`add_to_photos_outlined`） | P2、P4 |
| c3 | 修改 | 点了调 `DesktopWindow.openNewWindow(room: controller.room)`，失败提示由它统一给（“新窗口启动失败，请重试”）；删掉没人用的 `launchNewWindow` | P3 |
| c4 | 保留 | 位置：第二组最后、“在<平台>打开”后面；网络电视频道也显示（新窗口里同样能播网络电视）；打开菜单的按钮、其他各项不变 | — |

## 按钮的作用和用法

| 编号 | 控件 | 怎么用 |
|---|---|---|
| 12 | 在新窗口打开（直播间菜单） | 在一个新窗口里打开这个直播间，原窗口接着用；两个窗口共用关注、历史和设置（A16.1 c14）。设置里关掉“新建独立播放窗口”后这一项不出现 |

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 不显示（没有桌面外壳，`DesktopWindow.newWindowLauncher` 为空） |
| 宽屏（平板、Windows、Linux、iPad、macOS） | Windows：照上面；Linux：桌面外壳启动后自动有（X02.1 加运行器时）；平板、iPad 不显示；macOS 见 A18.2 |
| 电视 | 不显示 |
| 苹果平台差异 | 不在本任务（A18.2） |

## 待选和决定

- 无：A16.1 已定。翻译键按 D-024 不清理旧的 `open_room_in_new_window`（改完后没人用，留着，以后按 D-016 统一清）。

## 实现和验证（开发后补）

- 实现：还没开始。
- 验证：自动测试见任务书；真机要在 Windows 上看（D-004：现在只做 Android，归 [X01.1](../../../X-多端客户端/X01-Windows/X01.1-键盘鼠标操作核对/README.md) 一起看），K90 上只看“没有这一项”。
- 留下的问题：A16.1 自己的 Windows 真机结果也还没有（见 [A16 说明](../README.md)“已知问题”）。
