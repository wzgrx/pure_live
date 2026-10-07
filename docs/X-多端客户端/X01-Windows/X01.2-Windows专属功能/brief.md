# X01.2 Windows 专属功能：任务书

## 背景

- 来源：功能清点 [inventory/FEATURES.md](../../../inventory/FEATURES.md) 第 13 节 F-WIN-01～14；UPGRADES X-1 余项“Windows 用 WinHTTP 通道恢复 Kick”（V03.3 定去向为本任务）。登记时的旧编号 T17c.1。
- 现象：14 项里 13 项在 4.x 已经有代码（M12.3 / O03.1 的桌面外壳 `c0218fb7a`、A16.1 的界面、直播间和设置的 Windows 分支），但 4.x 从没在 Windows 上运行过；F-WIN-12（Kick 的 WinHTTP）完全没有，Windows 上 Kick 不可用；F-WIN-14（退出前写盘）没有 3.x 的 `didRequestAppExit` 对应物。
- 为什么现在做：第三档，**等 4.1（Windows）开工**（D-004：当前只做 Android）。
- **前置条件**：X01.3 第 1 阶段完成（`flutter build windows --release` 在 Windows 主机上成功、`pure_live.exe` 能启动到首页）。没有这一步，本任务除了 c2、c3 的 Dart 部分什么都做不了。
- 已经做过的：O03.1（Windows 桌面外壳）、A16.1（桌面窗口界面，c1～c15）、A07.4、A07.5（窗口内全屏、宽屏）、R02.1（显示模式通道）。

## 目标和验收

1. `verify.md`：F-WIN-01～11、13 在 Windows 主机上逐项走过（brief 的真机步骤），每项有结果和截图；不通过的有根因（文件:行）和处理（修掉，或开新任务写编号）。
2. F-WIN-12：Windows 上 Kick 能搜索、进直播间、播放、连弹幕；通道只对白名单主机（和 Android 的 `allowedHosts` 一致）走 https、最多 8 MiB。
3. F-WIN-14：退出（标题栏 ✕ 选“退出”、托盘“退出应用”、Alt+F4）时，正在进行的存储写入完成后才销毁窗口（有超时）；有测试。
4. Windows 10（如果有设备或虚拟机）上本地互动的礼物和徽章 emoji 能显示；画不出时改用系统 emoji。
5. 3.x 便携版数据（`AppData` 的副本）导入一次的结果写进 `record.md`，交给 J06。
6. 全部测试和门禁通过。

## 现状（读代码得出，写文件:行）

- 外壳：`apps/pure_live/lib/app/desktop/desktop_window.dart`：`DesktopShell`（`:227`）、`supported`（`:257`，只有 Windows）、`_start`（`:286`）、`exit`（`:406-419`：`_saveGeometry`、`_recording?.dispose()` 3 秒超时、新窗口删自己的任务键、托盘释放、`setPreventClose(false)`、`destroy`）。`title_bar.dart:34`、`tray.dart:49`、`close_dialog.dart:48`/`:170`、`startup_entry.dart:36`（值名 `PureLiveV4` `:12`）、`mini_window.dart`、`shared_data.dart:16`。
- 运行器：`apps/pure_live/windows/runner/main.cpp:85-104`（单实例、新窗口）、`flutter_window.cpp:40-53`（`pure_live/display_mode` 通道）；**没有** `pure_live/native_http` 通道。
- Kick：`apps/pure_live/lib/app/bootstrap.dart:159-160`（`AndroidNativeHttp.isAvailable ? AndroidNativeHttp(proxy: proxy) : null`）、`:179`（`kickApi: native`）；Dart 侧通道 `apps/pure_live/lib/platform/native_http.dart`（`allowedHosts`，注释要求和 Kotlin 的 `NativeHttpChannel.ALLOWED_HOSTS` 一致）；Android 实现 `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/AppChannelsPlugin.kt:34`、`:52`。
- 存储：`packages/live_store`（drift + SQLite），每次写入是一个事务；`LiveStore` 有没有“在途写入”的计数要读代码确认。
- emoji：`apps/pure_live/lib/features/live_play/local_interaction/local_interaction_scope.dart:58`（`_bundledEmoji`：除 iOS、macOS 外都用自带的 COLRv1 Noto 子集）。
- 3.x 导入：`apps/pure_live/lib/app/data_root.dart:12-13`（3.x 的 `<exe 目录>\AppData` 只由导入读取）；`packages/live_store/lib/src/legacy/`。

## 3.x 基线

- `git show v3.2.11:lib/common/global/platform/desktop_manager.dart`：`:263` 标题栏、`:765` `didRequestAppExit`（退出前 Hive flush）。
- `lib/common/global/platform/desktop_tray_service.dart:7`、`lib/plugins/utils.dart:7`（关闭询问）、`lib/common/global/win_auto_start.dart:8`、`lib/common/services/settings/startup_controller.dart:12`、`lib/common/utils/windows_multi_instance_launcher.dart:18`、`lib/player/utils/window_helper.dart`、`lib/modules/live_play/widgets/video_player/video_controller_panel.dart:1882`（窗口内全屏）、`volume_control.dart:10`、`lib/modules/settings/pages/general_settings_page.dart:24`（刷新率信息）、`lib/common/services/settings/player_settings_controller.dart`（RTX 超分）、`lib/modules/live_play/widgets/layout/control_hover_region.dart`。
- 必须保留：3.x 的设置键（`exitChoose`、`dontAskExit`、`window_width`、`window_height`、`enableRtxVsr` 等，D-018）；specs/UI.md 附录 A 第 13、14、16 条。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 10 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`（第 3、6 节）；`docs/specs/UI.md` 第 5.4 节、附录 A。
3. 本文件夹的 `README.md`；`docs/X-多端客户端/X01-Windows/README.md`；`docs/A-界面设计/A16-桌面界面/A16.1-桌面窗口/README.md`（c1～c15 和“实现和验证”）；`docs/O-Android系统集成/O03-分享接收和快捷方式/O03.1-插件接入和Windows桌面/README.md`、`record.md`；`docs/E-直播平台/E03-海外平台/E03.16-Kick/README.md`。

## 范围

- 可以改：`apps/pure_live/windows/runner/`（加 native_http 通道）；`apps/pure_live/lib/app/bootstrap.dart`（Windows 也建通道）、`lib/platform/native_http.dart`（平台判断）、`lib/app/desktop/`（退出写盘、发现的问题）、`local_interaction_scope.dart:58`（emoji 判断）；对应测试；本文件夹的文档。
- 不能改：桌面界面的样子（A16.1 确认过的设计）；Android 的原生代码；3.x 的设置键名和含义；版本号、`assets/version.json`、`assets/releases.json`；签名配置。
- 绝对不能：动 `D:\Soft\PureLive`、`D:\Soft\pure_live` 和它们的开机启动项（HKCU Run 的 `pure_live`）；用用户的 3.x 数据做导入测试（复制一份到工作目录再试）。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 逐项验证 F-WIN-01～11、13；c4 Windows 10 emoji | `verify.md`；小问题的修复 | 每项有结果；不通过的有根因和去向 |
| 2 | c2 Kick 的 WinHTTP 通道 | `windows/runner/`、`bootstrap.dart`、`native_http.dart`、测试 | Windows 上 Kick 搜索、播放、弹幕通 |
| 3 | c3 退出写盘；c5 3.x 便携数据导入 | `desktop_window.dart`、`packages/live_store`（只在需要“等写完”的接口时）、测试、`record.md` | 测试通过；导入结果交给 J06 |

每个阶段都要能单独合并（门禁通过）。

## 测试

- 第 2 阶段：`apps/pure_live/test/` 里 Kick 通道的 Dart 侧测试（假的 `MethodChannel`）：Windows 平台下 `bootstrap` 建了通道、白名单外的主机被拒；C++ 部分只能真机验证。
- 第 3 阶段：`test/desktop_window_test.dart` 加“exit 等进行中的写入完成再 destroy（超时后照样退出）”；改之前会失败。
- 测试里的定时器至少 1 秒；不访问真实平台。

## 真机验证（维护者在 Windows 主机上做）

| 步骤 | 期望 |
|---|---|
| 1. 第一次启动 | 1280×720 居中；自绘标题栏“纯粹直播”、最小化 / 最大化 / 关闭三个按钮，悬停有名称 |
| 2. 拖窗口边缘改大小 | 标题栏显示“[宽 × 高]”；松开后消失 |
| 3. 移到第二个显示器、最大化，退出再开 | 回到第二个显示器、最大化；拔掉第二个显示器再开回到正中 |
| 4. 点 ✕ | 关闭对话框：“最小化到托盘”“退出应用”“不再询问”；选最小化后托盘有图标，单击托盘显示窗口 |
| 5. 开始录制一个直播间，托盘右键 | 第一行“正在录制 1 个直播间”（灰）；“退出应用”先问 |
| 6. 设置 → 通用和网络 →“启动”一组的开机启动打开，注销重登 | 4.x 自动启动；注册表 `HKCU\…\Run` 只多了 `PureLiveV4`，3.x 的 `pure_live` 没变 |
| 7. 再双击 exe | 不开第二个主窗口，已有窗口到前面 |
| 8. 直播间菜单“在新窗口打开” | 新窗口进同一个直播间；在新窗口里关注一个主播，主窗口的关注页也有 |
| 9. 直播间进桌面小窗，点图钉，拖到角落，关掉再开小窗 | 小窗置顶；位置记住 |
| 10. 直播间点窗口内全屏；鼠标移到音量图标 | 画面铺满窗口但不是系统全屏；出现音量滑块，点图标静音 |
| 11. 设置 → 通用和网络 →“显示”一组的刷新率 | 显示的刷新率和系统设置一致 |
| 12. 有 RTX 显卡时打开“RTX 视频超分辨率”看 720p 直播；没有时打开 | 有：画面更清晰；没有：不报错照常播 |
| 13. 开着代理搜索 Kick、进直播间（第 2 阶段后） | 能播放、有弹幕 |
| 14. 改了设置后立刻托盘退出，再开 | 设置还在 |
| 15. Windows 10：直播间 → 本地互动 → 礼物 | 礼物图案看得见 |

## 风险和注意

- Windows 上跑 flutter 命令时设备参数一律写全 `--device-id=windows`（2026-09-25 的事故：`-d` 被 PowerShell 当成 `-Debug`，选中了手机，卸载了手机上的 3.x）。
- 开机启动只在 release 构建按设置写注册表；验证时用 release 包，验证完把设置关掉（删掉 `PureLiveV4`）。
- WinHTTP 通道必须和 Android 一样只服务白名单主机，不能变成通用的请求工具。
- 可能冲突的文件：`lib/app/bootstrap.dart`（I01、Q 组）、`lib/app/desktop/`（X01.1、X02.1）、`windows/runner/`（X01.3）。

## 环境和提交

- Windows 主机：`C:\Users\123\claude-work\pure_live`（先拉分支）、`C:\Users\123\claude-work\flutter\bin\flutter.bat`（全路径）、JDK `C:\Users\123\claude-work\jdk\jdk-27+35`；根目录先 `tools\ffmpeg_kit\fetch.ps1`，再 `flutter pub get`；在 `apps\pure_live` 里 `flutter build windows --release`，运行 `build\windows\x64\runner\Release\pure_live.exe`。GUI 检查用 `C:\Users\123\claude-work\wingui.ps1` + WSL 的 `~/tools/wg.sh`（后台截窗口、点按）。
- WSL：`source ~/tools/purelive-env.sh`；Dart 部分的测试在 WSL 跑。
- 分支 `ai/X01.2` 或本机工作区；提交信息以 `[X01.2]` 开头（英文）；不推 master。
- 提交前：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（`verify.md` 走到第几步、WinHTTP 做到哪）、更新登记表的 `done`、`next`、`branch`（登记表现在没有写阶段，开工时按上表补上）。

## 报告（中文，简洁）

14 项各自的结果；修了什么、根因；Kick 在 Windows 上通没通；退出写盘的做法；Windows 10 emoji；3.x 便携数据导入的结果；测试数量；改了哪些文件；需要维护者决定的；可能冲突的文件。
