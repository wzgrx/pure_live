# O05.3 退出横屏全屏后回到竖屏：记录

- 日期：2026-10-08
- 执行者：Claude（Opus 5.5，本机工作区，没有真机）
- 分支和提交：本机工作区，`25d794210`
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 退出时先竖屏再放开（直播间、多画面） | 做了 | 手机（Android）上自动旋转**关着**（或问不到）时：先要 `[portraitUp]`、3 秒后放开 `[]`，不论从全屏按钮、双击、菜单“横屏全屏”还是竖屏全屏进的；页面在全屏里被关掉时同样。自动旋转**开着**时照旧直接放开（验收 3：退出后跟着手机方向，不先转回竖屏再转回横屏）；菜单“横屏全屏”进的照旧不管开没开都先竖屏（附录 A 第 11 条）。iOS 照旧直接放开 |
| c1 的读设置 | 做了 | 为了验收 3 原生加了 `autoRotate`：只读 `Settings.System.ACCELEROMETER_ROTATION`，不写、不申请权限。这是 c2 里“读系统设置”的一小部分，c2 其余部分（记下 user_rotation、对比后再处理）没做，见下 |
| c2 | 没做 | 按任务书要等 K90 确认 c1 够不够。只看代码判断不了：c2 写的“先 PORTRAIT 再 UNSPECIFIED”和 c1 做的是同一件事；不写 `WRITE_SETTINGS` 就改不了 user_rotation |
| c3 | 没做 | 同上，c1 在 K90 上不够时再评估，要加新决定 |
| 方向请求集中 | 做了 | 直播间、多画面的方向请求都走 `ScreenOrientation`（`landscape`、`portrait`、`free`、`restore`）；“3 秒后放开”的定时器只有一个，任何新的方向请求都先取消它。原来直播间的定时器在页面里，页面关掉后 3 秒内进别的房间全屏会被它放开 |

## 根因

- 进横屏全屏用 `SCREEN_ORIENTATION_SENSOR_LANDSCAPE`（`SystemAccessPlugin.kt` 的 `sensorLandscape`，D-023）。K90（HyperOS，Android 17）自动旋转关着时，屏幕被它转成横屏后，系统把 `user_rotation` 从 0 改成了 3（V03.4-08 实测）。
- 退出时（改前 `live_play_page.dart` 的 `_restoreSystemUi(upright: false)`、`multiview_page.dart` 的 `_restoreSystemUi`）直接 `setPreferredOrientations(const [])` = `SCREEN_ORIENTATION_UNSPECIFIED`；自动旋转关着时 UNSPECIFIED 用的是 `user_rotation`，于是停在 3（横屏），应用和别的应用都横着。只有菜单“横屏全屏”进的（`_restorePortrait`）先要竖屏。
- 按 AOSP 的 `DisplayRotation`，应用请求的方向（包括 SENSOR_LANDSCAPE）只决定屏幕转到哪，不写 `user_rotation`（写它的是快捷开关的锁定、旋转建议按钮），所以这里大概是 HyperOS 自己的逻辑，规则看不到。推断：HyperOS 在锁定时把屏幕的实际方向记成 `user_rotation`；如果是这样，c1 先要 PORTRAIT 把屏幕转回 0，`user_rotation` 也会跟着回到 0，3 秒后放开就停在竖屏。这要在 K90 上确认。

## 改了哪些文件

- `apps/pure_live/lib/platform/screen_orientation.dart`：新增 `portrait()`、`free()`、`restore({upright})`、`settle`（3 秒）、全应用一个放开定时器；`restore` 在 Android 上问 `autoRotate`，关着或问不到时先竖屏。
- `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/SystemAccessPlugin.kt`：通道 `pure_live/system_access` 新增 `autoRotate`（只读 `ACCELEROMETER_ROTATION`）。
- `apps/pure_live/lib/features/live_play/live_play_page.dart`：进、出全屏都走 `ScreenOrientation`；去掉页面自己的 `_releaseOrientation`。
- `apps/pure_live/lib/features/multiview/multiview_page.dart`：退出全屏走 `ScreenOrientation.restore()`。
- 文档：本文件、O05 的 README（现状、代码地图）、登记表。

## 新设置、翻译键、门禁基线

- 无。

## 测试

- 新增 `apps/pure_live/test/platform/screen_orientation_test.dart` 6 个：自动旋转关着先竖屏、3 秒后放开；开着直接放开；`upright` 开着也先竖屏；问不到当作关着；3 秒内再进全屏（横屏、竖屏全屏、跟随系统）不会被旧的定时器放开；iOS 直接放开。
- `live_play_layouts_test.dart` 新增 3 个（O05.3 组）：自动旋转关着时全屏按钮进、返回出，双击进、双击出，调用顺序都是 `[landscapeLeft, landscapeRight]` → `sensorLandscape` → `[portraitUp]` → 3 秒后 `[]`；开着时直接 `[]`；全屏里关掉直播间也先竖屏再放开。原有的“横屏全屏”胶囊测试不变、通过。
- `multiview_page_test.dart` 新增 1 个：多画面全屏退出同样的顺序。
- 先写测试、看到失败（直播间 2 个、多画面 1 个是 `[]` 而不是 `[portraitUp]`；单元测试是没有这些方法），再改代码。
- 通过范围：见提交前的检查（`test/features/live_play`、`test/features/multiview`、`test/platform`，以及最后整个 `apps/pure_live` 的 `flutter test`）。

## 真机上要看的

照[任务书](brief.md)“真机验证”的 0～7 步，重点：

1. 自动旋转关着、手机横放：全屏按钮进 → 返回出，应用回到竖屏且 3 秒后**不再转回横屏**；`adb shell settings get system user_rotation` 等于进全屏前的值（0）。这一条决定要不要做第 2 阶段。
2. 退出后马上（3 秒内）和 3 秒后各看一次：`adb shell dumpsys activity activities | grep -i requestedOrientation` 应先是 `PORTRAIT`（1）再是 `UNSPECIFIED`（-1）；`user_rotation` 在先竖屏后有没有回到 0。
3. 双击进出、菜单“横屏全屏”进出、多画面全屏进出、全屏里直接关掉直播间：都回到竖屏。
4. 自动旋转开着、手机横放：退出全屏后**直接**跟着手机方向（不应先闪一下竖屏再转回横屏）。
5. 进全屏仍按 D-023 跟着手机翻转（横屏时转 180° 画面跟着翻）。
6. 如果第 1 条里 `user_rotation` 停在 3、放开后又转回横屏：c1 不够，开第 2 阶段。可选的做法（要评估、要新决定）：锁定时不放开、一直要求竖屏（`user_rotation` 仍是 3，别的应用照样横着，只能保住本应用）；或 c3 锁定时退回 3.x 的 `USER_LANDSCAPE`（不翻转，但不会动 `user_rotation`）。

## 停在哪（没做完时写）

- 做完的阶段：1（c1，代码和测试）。
- 正在做的阶段做到：等 K90 结果。
- 已知问题：c1 能不能让 `user_rotation` 回到 0 只能在 K90 上看。
- 下一步：维护者按上面“真机上要看的”在 K90 上看；够了就改“完成”、在 V03.4 记录里把 08 标成已修；不够就做第 2 阶段。
