# O05.3 退出横屏全屏后回到竖屏，不改动系统的旋转锁定方向：任务书

## 背景

- 来源：2026-10-08 K90 真机对照（V03.4-08）：K90 自动旋转关着、横放在支架上；直播间点全屏按钮进横屏全屏，按返回退出后，整个应用停在横屏（直播间变成手机横屏的左右分栏，回首页也是横屏）。`adb shell settings get system user_rotation` 从 0 变成 3。
- 为什么是第一档：改到了用户手机的旋转锁定方向，退出应用后别的应用也横着。
- 已经做过的：O05.2（issue #36：横屏全屏跟着手机翻转，D-023）。

## 目标和验收

1. 自动旋转关着时：全屏按钮、双击、菜单“横屏全屏”三种方式进横屏全屏，退出后应用都回到竖屏。
2. 退出后 `user_rotation` 等于进全屏前的值（K90 上是 0）。
3. 自动旋转开着时行为不变（退出后跟着手机方向）。
4. 进横屏全屏仍按 D-023 跟着手机翻转。
5. 多画面全屏同样。

## 现状（读代码得出，写文件:行）

- 进：`apps/pure_live/lib/features/live_play/live_play_page.dart:525-557`（`_enterFullscreen`，`_restorePortrait = landscape` 只在菜单“横屏全屏”时为真）；`apps/pure_live/lib/platform/screen_orientation.dart:13-27`；`SystemAccessPlugin.kt:112-116`。
- 出：`live_play_page.dart:575-591`（`_exitFullscreen`）、`:595-606`（`_restoreSystemUi`：`upright` 为假时直接 `setPreferredOrientations(const [])`）；页面关闭时 `:464`。
- 多画面：`apps/pure_live/lib/features/multiview/multiview_page.dart:164`、`:403-416`。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/` 里的 `exitFullscreenWithOrientationRestore`（先竖屏、再放开）；3.x 用 `USER_LANDSCAPE`，锁定时不翻转，也就不会碰到 user_rotation 被改。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5、8、10、14 节）。
2. 本文件夹的 `README.md`；`docs/O-Android系统集成/O05-方向、刷新率、常亮/O05.2-横屏全屏随手机方向翻转/README.md` 和 `verify.md`；`docs/DECISIONS.md` 的 D-023。
3. `docs/V-需求和反馈/V03-审查和调研/V03.4-界面真机对照/record.md` 的 08。

## 范围

- 可以改：`live_play_page.dart` 的进出全屏、`multiview_page.dart` 的全屏、`screen_orientation.dart`、`SystemAccessPlugin.kt`（只读系统设置）、对应测试、本文件夹的文档。
- 不能改：D-023 的进全屏行为（除非走 c3 并加新决定）；不申请 `WRITE_SETTINGS`；不碰正式包。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1：退出时一律先要竖屏再放开（直播间、多画面）；K90 上看 user_rotation | `live_play_page.dart`、`multiview_page.dart`、测试 | 验收 1、3、4、5；记下 user_rotation 是否回到 0 |
| 2（阶段 1 不够时） | c2 或 c3 | `SystemAccessPlugin.kt`、`screen_orientation.dart`；c3 要加决定 | 验收 2 |

## 测试

- `apps/pure_live/test/features/live_play/` 新增或扩展全屏测试：进（全屏按钮）→ 出，断言 `SystemChrome.setPreferredOrientations` 的调用顺序是 `[landscapeLeft, landscapeRight]` → `[portraitUp]` → `[]`。
- 多画面同样一条。定时器至少 1 秒。

## 真机验证（K90；先确认另一个会话没在用手机）

| 步骤 | 期望 |
|---|---|
| 0. `adb shell settings put system accelerometer_rotation 0`，记下 `user_rotation`（应为 0），手机横放 | — |
| 1. 进一个直播间，点全屏按钮 | 横屏全屏，翻转手机画面跟着翻 |
| 2. 按返回 | 回到竖屏直播间 |
| 3. `settings get system user_rotation` | 和第 0 步相同 |
| 4. 双击画面进全屏，再双击退出；菜单“横屏全屏”进、返回退出 | 都回到竖屏 |
| 5. 多画面全屏进出 | 回到竖屏 |
| 6. 打开自动旋转重复 1～2 | 退出后跟着手机方向 |
| 7. 结束后恢复 `accelerometer_rotation=1`、`user_rotation=0` | — |

## 风险和注意

- 这台 K90 另一个会话也在用，测试前用 `ListAgents` 和 adbd 日志确认，约好时间段。
- 放开方向（UNSPECIFIED）太早会被系统按旧的 user_rotation 又转回横屏，放开时机要在真机上试。

## 环境和提交

- `source ~/tools/purelive-env.sh`；分支 `ai/O05.3` 或本机工作区；提交信息以 `[O05.3]` 开头（英文）；不推 master。
- 提交前：`apps/pure_live` 跑 format、analyze、全部 `flutter test`；`tools/gate/gate.sh --all`。

## 停下时

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条验收做到没有；user_rotation 的实测；改了哪些文件；要不要新决定。
