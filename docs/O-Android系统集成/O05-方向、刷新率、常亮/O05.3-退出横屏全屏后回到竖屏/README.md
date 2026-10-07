# O05.3 退出横屏全屏后回到竖屏，不改动系统的旋转锁定方向

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：原生
- 来源：V03.4-08（2026-10-08 K90 真机对照，[记录](../../../V-需求和反馈/V03-审查和调研/V03.4-界面真机对照/record.md)）
- 相关：D-023（横屏全屏按传感器翻转，开着旋转锁也翻）；接 [O05.2](../O05.2-横屏全屏随手机方向翻转/README.md)；A07.4（横屏全屏）；N（多画面全屏同一套）

## 目标

自动旋转关着（竖屏锁定）的手机：进横屏全屏时照 D-023 跟着手机翻转；退出全屏后应用回到竖屏，系统的旋转锁定方向保持用户原来的（竖屏），别的应用不受影响。

## 3.x 和现状

| 方面 | 3.x | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 进横屏全屏 | Flutter 的 landscapeLeft + landscapeRight（Android `USER_LANDSCAPE`，旋转锁开着时不翻转） | `ScreenOrientation.landscape()`（`apps/pure_live/lib/platform/screen_orientation.dart:13-27`）先设两个横向，再走原生 `sensorLandscape`（`apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/SystemAccessPlugin.kt:112-116`，`SCREEN_ORIENTATION_SENSOR_LANDSCAPE`） | 不变（D-023） |
| 退出全屏 | `exitFullscreenWithOrientationRestore`：先转回竖屏再放开 | `_exitFullscreen`（`apps/pure_live/lib/features/live_play/live_play_page.dart:575-591`）→ `_restoreSystemUi(upright: _restorePortrait)`（`:595-606`）：只有菜单“横屏全屏”进的才先要竖屏、3 秒后放开；全屏按钮和双击进的直接 `setPreferredOrientations(const [])`（UNSPECIFIED） | 不管怎么进的，手机上退出时都先要竖屏，再放开 |
| 系统旋转锁 | — | K90（HyperOS，Android 17）实测：自动旋转关着时，应用用 SENSOR_LANDSCAPE 横过来后，`settings get system user_rotation` 从 0 变成 3；退出后 UNSPECIFIED 跟着 user_rotation 停在横屏，首页和别的应用也横着 | 退出后 user_rotation 回到进全屏前的值 |
| 多画面全屏 | — | `apps/pure_live/lib/features/multiview/multiview_page.dart:403-416` 同一种做法 | 同上 |

## 方案

- c1：`_restoreSystemUi` 在手机上一律先 `setPreferredOrientations([portraitUp])`，等转过来后再放开（照现有 `_releaseOrientation` 的 3 秒，或监听方向变化后放开）；多画面同样。
- c2：原生侧加 `restoreOrientation`：进全屏前记下 `Settings.System.USER_ROTATION` 和 `ACCELEROMETER_ROTATION`；退出时如果自动旋转关着且 user_rotation 被系统改了，先把 activity 设成 `SCREEN_ORIENTATION_PORTRAIT` 再设回 `UNSPECIFIED`。只读系统设置，不写（写需要 `WRITE_SETTINGS`，不申请）。先在 K90 上确认只靠 c1 能不能让 user_rotation 回到 0；不能时再做 c2。
- c3：如果 HyperOS 在“锁定 + 应用要传感器横屏”时一定会改 user_rotation，评估退回 3.x 的 `USER_LANDSCAPE`（不跟着翻转）作为锁定时的做法，并在 D-023 后加一条新决定。

## 验证

- 自动测试：`apps/pure_live/test/features/live_play/` 里加退出全屏的测试：不论 `_restorePortrait`，手机上退出后先请求 `portraitUp`（用 `SystemChannels.platform` 的假调用记录）。
- 真机：见任务书。

## 留下的问题

- 无（做完后在 V03.4 的记录里把 08 标成已修）。
