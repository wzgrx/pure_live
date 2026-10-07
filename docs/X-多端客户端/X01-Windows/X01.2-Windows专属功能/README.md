# X01.2 Windows 专属功能（功能清点第 13 节的 14 项）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：清点。[inventory/FEATURES.md](../../../inventory/FEATURES.md) 第 13 节“Windows 专属（以后）”14 项（F-WIN-01～14，都是“Android：否”）；[specs/UPGRADES.md](../../../specs/UPGRADES.md) X-1 的余项“Windows 用 WinHTTP 通道恢复 Kick”（V03.3 把它的去向定为本任务）。
- 旧编号：T17c.1
- 相关：决定 D-004（Windows 是第二个客户端）；依赖 X01.3 第 1 阶段（能在 Windows 上构建运行）；关联 A16.1（桌面窗口的界面，完成）、X01.1（键鼠，F-WIN-08、09、13 的操作部分）、E03.16（Kick，仅 Android）、D01.31（Kick 弹幕）、A08（Windows 10 上的 emoji 字体）

## 目标

4.1（Windows）发布前，3.x 在 Windows 上有的 14 项专属功能在 4.x 上逐项实际能用：每项在 Windows 主机上走过一遍，有问题的修掉，缺的补上（主要是 Kick 的 WinHTTP 通道和退出前写盘），结果写进 `verify.md`。

## 3.x 和现状

| 编号 | 功能 | 3.x（`git show v3.2.11:lib/...`） | 4.x 现在（文件:行） | 要做到 |
|---|---|---|---|---|
| F-WIN-01 | 自绘标题栏（拖动时显示尺寸） | `common/global/platform/desktop_manager.dart:263` | `apps/pure_live/lib/app/desktop/title_bar.dart:34` `DesktopTitleBar`（A16.1 c1、c3、c4、c11、c13） | Windows 上看一遍 |
| F-WIN-02 | 窗口大小（立即应用）、位置 | `common/services/settings/window_size_controller.dart:6` | `desktop_window.dart:286` `_start`、`_saveGeometry`；位置记忆是新加的（meta `window.position`） | 同上；多显示器、拔掉显示器后回到正中 |
| F-WIN-03 | 托盘（显示、隐藏、退出） | `common/global/platform/desktop_tray_service.dart:7` | `tray.dart:49` `DesktopTray`（录制时写“正在录制 N 个直播间”） | 同上 |
| F-WIN-04 | 关闭窗口时：询问、最小化到托盘、退出 | `plugins/utils.dart:7` | `close_dialog.dart:48` `WindowCloser`、`:170` `CloseWindowDialog`；设置键 `exitChoose`、`dontAskExit` | 同上；录制中退出先问 |
| F-WIN-05 | 开机启动（注册表） | `common/global/win_auto_start.dart:8`、`common/services/settings/startup_controller.dart:12` | `startup_entry.dart:36` `applyStartupEntry`，值名 `PureLiveV4`（`:12`），只有 release 构建按设置补写或删除 | 同上；**不碰 3.x 的 `pure_live` 启动项** |
| F-WIN-06 | 单实例、在新窗口打开直播间 | `common/utils/windows_multi_instance_launcher.dart:18` | `apps/pure_live/windows/runner/main.cpp:85-104`；`lib/app/launch_args.dart:108` `startWindowProcess`；新窗口共用数据（`lib/app/desktop/shared_data.dart`） | 同上；两个窗口里改关注互相生效 |
| F-WIN-07 | 桌面小窗（置顶、记住位置） | `player/utils/window_helper.dart` | `lib/app/desktop/mini_window.dart`（默认尺寸 `:43`、最小 140×90 `:62`、位置 `:64`） | 同上 |
| F-WIN-08 | 窗口内全屏按钮 | `modules/live_play/widgets/video_player/video_controller_panel.dart:1882` | `RoomDisplay.windowFullscreen`（`lib/features/live_play/logic/room_layout.dart:6`） | 同上 |
| F-WIN-09 | 控制栏音量（悬停出滑块、一键静音） | `modules/live_play/widgets/video_player/volume_control.dart:10` | `lib/features/live_play/player/bar_parts.dart:150` `VolumeSlider` | 同上 |
| F-WIN-10 | Windows 动态刷新率信息 | `modules/settings/pages/general_settings_page.dart:24` | 运行器 `pure_live/display_mode` 通道（`windows/runner/flutter_window.cpp:40-53`、`ReadDisplayMode` `:113`）；Dart 侧 `lib/platform/display_mode.dart` | 同上；设置里显示的刷新率和系统一致 |
| F-WIN-11 | RTX 超分 | `common/services/settings/player_settings_controller.dart`（`enableRtxVsr`） | 设置行只在 Windows（`lib/features/settings/settings_catalog.dart:1274-1281`）；`packages/live_player/lib/src/mpv_options.dart:154` 传给 mpv | 有 NVIDIA RTX 显卡时看效果，没有时不报错 |
| F-WIN-12 | Kick 的 WinHTTP 通道 | 3.x 有（UPGRADES X-1） | **缺**：`lib/app/bootstrap.dart:160` 只在 Android 建 `AndroidNativeHttp`，Windows 上 `kickApi` 为空，Kick 不可用 | 加 Windows 的原生 HTTP 通道（WinHTTP，用系统 TLS），Kick 在 Windows 上恢复 |
| F-WIN-13 | 鼠标悬停显示控制层、右键菜单 | `modules/live_play/widgets/layout/control_hover_region.dart` | `lib/features/live_play/player/player_view.dart:799`（`onHover`）、各处 `onSecondaryTap` | 和 X01.1 一起看 |
| F-WIN-14 | 退出前写盘（`didRequestAppExit`） | `common/global/platform/desktop_manager.dart:765` | 没有 `didRequestAppExit`；`desktop_window.dart:406-419` `exit()` 存几何、停录制（最多 3 秒）、`destroy`；存储是 SQLite（每次写入即提交） | 核对：退出时正在进行的写入（关注、设置、历史）是否完成；需要时在 `exit()` 里等存储空闲或关闭 |

另外两项不在清点里、但 Windows 上要一起看的：本地互动的礼物和徽章 emoji 在 Windows 10 上可能画成空白（`lib/features/live_play/local_interaction/local_interaction_scope.dart:58`，A08 已知问题）；3.x 在 Windows 上的数据导入（3.x 的 `<exe 目录>\AppData`，`lib/app/data_root.dart:12-13`，J06 的 Windows 部分）。

## 方案

- c1 逐项验证（F-WIN-01～11、13）：Windows 主机上按 brief 的真机步骤走，结果写 `verify.md`；有问题的定位根因（文件:行），小的直接修，大的开新任务。
- c2 Kick 的 WinHTTP（F-WIN-12）：照 `lib/platform/native_http.dart`（Android 的 `pure_live/native_http` 通道）在 Windows 运行器里实现同一个通道（`WinHttpOpen`、`WinHttpSendRequest`，按设置的代理），`bootstrap.dart:160` 在 Windows 上也建通道；Kick 在 Windows 上重新启用（E03.16 的“仅 Android”限制解除）。
- c3 退出写盘（F-WIN-14）：确认 `LiveStore` 有没有在途的写入，`exit()` 里在 `destroy` 前等它完成（有超时）；加测试。
- c4 Windows 10 的 emoji：在 Windows 10 上看礼物面板，画不出来就让 Windows 用系统 emoji 字体（`local_interaction_scope.dart:58` 的判断）。
- c5 3.x 数据导入（Windows）：用一份 3.x 便携版的 `AppData` 副本（不是用户的 `D:\Soft` 下的）试一次导入，结果交给 J06。

## 验证

- 自动测试：`apps/pure_live/test/desktop_window_test.dart`（已有 26 个）加 F-WIN-14 的“退出前等存储写完”；Kick 的通道加 Dart 侧的通道测试（假通道）。
- 真机：Windows 主机，`verify.md` 逐项（brief 的真机步骤）。现在“待真机”以前的所有项都**没在 Windows 上看过**。

## 留下的问题

- 还没开始；前提是 X01.3 第 1 阶段能在 Windows 上构建运行。
- C++ 的 WinHTTP 通道没有自动测试的条件（只能真机），实现时把协议（方法名、参数、返回）和 Android 那边写成同一份说明。
