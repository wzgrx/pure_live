# O05.2 横屏全屏随手机方向翻转，开着旋转锁也翻（issue #36）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（含 Android 原生）
- 来源：GitHub issue [#36](https://github.com/wzgrx/pure_live/issues/36)（用户 957957qwer，2026-10-02，标题“功能缺失”）：“手机端横屏全屏看直播时，没有自动旋转功能，就是那个横屏全屏时整个界面会随手机的方向而改变”。登记在 [V02.3](../../../V-需求和反馈/V02-用户反馈和issue/V02.3-issue36横屏翻转/README.md)；维护者 2026-10-02 回复“已经修复”并关闭（V02.1）
- 旧编号：T13e.2
- 相关：决定 **D-023**（横屏全屏按传感器翻转，开着旋转锁也翻；依据 issue #36 和常见视频应用的做法）；全屏逻辑 C01（`live_play_page.dart`）、界面 A07.4（横屏全屏）；多画面 N01；随构建号 5001 发给用户（D-008），真机验证在 [S02.5](../../../S-质量和验证/S02-真机验证/S02.5-4.0.0构建号5001/README.md) 第一阶段的 1B-21、1B-22、1D-06；验证清单 [verify.md](verify.md)；任务书 [brief.md](brief.md)

## 目标

手机横屏全屏看直播（以及多画面全屏）时，把手机从一边横着转到另一边（转 180°），画面跟着翻过来，不会倒着；即使用户打开了系统的旋转锁（很多人常开）也照样翻。退出全屏后照旧：从“横屏全屏”胶囊进的转回竖屏，3 秒后方向放开。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 做之前（4.0.0） | 现在（`apps/pure_live/` 下） |
|---|---|---|---|
| 进横屏全屏请求的方向 | `lib/player/utils/fullscreen.dart:267-270`：`setPreferredOrientations([landscapeLeft, landscapeRight])` | 同 3.x（`live_play_page.dart` 里直接调） | `lib/platform/screen_orientation.dart:13` `ScreenOrientation.landscape()`：先同样的两个横向，再在 Android 上调 `pure_live/system_access` 的 `sensorLandscape` |
| Android 实际的方向值 | Flutter 把两个横向换成 `SCREEN_ORIENTATION_USER_LANDSCAPE`：跟用户的旋转设置，开着旋转锁时停在进全屏那一边 | 同左 | `SCREEN_ORIENTATION_SENSOR_LANDSCAPE`（`android/app/src/main/kotlin/com/mystyle/purelive/SystemAccessPlugin.kt:112-116`）：只看传感器，旋转锁开着也在两个横向之间翻 |
| 开着旋转锁转 180° | 不翻，画面倒着 | 不翻 | 翻 |
| 退出全屏 | `verticalScreen`（:281-284）+ 放开 | 胶囊进的 `[portraitUp]`，3 秒后 `[]`；否则 `[]` | 不变（`live_play_page.dart:595-606`）；下一次 `setPreferredOrientations` 覆盖掉 `SENSOR_LANDSCAPE` |
| 多画面全屏 | — | 两个横向 | `lib/features/multiview/multiview_page.dart:403` 同样 `ScreenOrientation.landscape()` |
| “进入全屏时的方向：跟随系统” | 跟系统 | 横屏直播进全屏用 `[]`（跟系统，旋转锁开着不转） | 不变（`live_play_page.dart:553-554`），用户选了跟随系统就跟系统 |

## 结果

- 提交：`3c1aa45ee`（2026-10-02，`fix(live_play): the landscape fullscreen turns over with the phone (#36)`），直接在 master 上；登记表 `date` 2026-10-02。
- 改了 5 个文件：`android/.../SystemAccessPlugin.kt`（+`sensorLandscape`，注释写明 issue #36 和 `USER_LANDSCAPE` 的区别）、`lib/platform/screen_orientation.dart`（新，27 行）、`lib/features/live_play/live_play_page.dart`（进全屏的三个分支，现在 :551-557）、`lib/features/multiview/multiview_page.dart`（:403）、`test/features/live_play/live_play_layouts_test.dart`（假通道 :64-72，“横屏全屏”胶囊的用例 :729 断言先两个横向再 `sensorLandscape`）。
- 没有新设置、没有新翻译键；`portraitFullscreenPolicy` 的三个选项含义不变（D-018）。
- 提交时在 K90 上用 `dumpsys` 看过请求的方向值：横着时 `SENSOR_LANDSCAPE`，离开时 `PORTRAIT`，3 秒后 `UNSPECIFIED`；**没有手动翻转手机看画面**。

## 验证

- 自动测试：`apps/pure_live/test/features/live_play/live_play_layouts_test.dart:729`（“横屏全屏: once sideways with the ambient sides; leaving turns the phone back upright”）。只覆盖了“横屏全屏”胶囊这一条路；双击横屏直播进全屏、多画面全屏没有断言方向的测试。
- 真机：**待真机**。步骤见 [verify.md](verify.md)（和 S02.5 的 1B-21、1B-22、1D-06 是同样的操作）。

## 留下的问题

- 真机没看：verify.md。
- 测试缺口：双击进全屏（`FullscreenOrientation.followSource`、横屏直播）和多画面全屏没有断言会调 `sensorLandscape`；建议下次改这两处时补（`live_play_layouts_test.dart` 已有假通道，可直接加）。
- 平板、折叠屏展开（最短边 ≥600dp）上 Android 16/17 忽略应用的方向请求（[specs/UI.md](../../../specs/UI.md) 第 5.3 节），那里不会转，也不需要：见 [O06](../../O06-返回手势、平板和折叠屏/README.md)。
