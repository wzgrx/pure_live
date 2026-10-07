# O05.2 横屏全屏随手机方向翻转：任务书（剩下的真机验证）

> 代码已在 `3c1aa45ee`（2026-10-02）合并，登记表是“待真机”。本任务书只交代剩下的事：在 K90 上照 [verify.md](verify.md) 验证；不通过时找根因、开修复任务。

## 背景

- 来源：GitHub issue #36（2026-10-02）：“手机端横屏全屏看直播时，没有自动旋转功能，就是那个横屏全屏时整个界面会随手机的方向而改变”。维护者定 D-023：横屏全屏按传感器翻转，开着旋转锁也翻（常见视频应用的做法）。
- 现象（修之前）：横屏全屏时把手机转 180°，画面倒着；3.x 也是这样（Flutter 的两个横向在 Android 上是 `USER_LANDSCAPE`，开着旋转锁时停在进全屏那一边）。
- 为什么现在做：修复随构建号 5001 发给了用户（D-008），issue 已关闭，但没有真机结果；登记表要真机结果才能“完成”。
- 已经做过的：`3c1aa45ee`（原生 `sensorLandscape`、`ScreenOrientation.landscape()`、直播间和多画面改调它、测试）；提交时 `dumpsys` 看过方向值，没手动翻转。

## 目标和验收

1. verify.md 第 1～9 步都通过：关着、开着旋转锁，直播间横屏全屏、“横屏全屏”胶囊、多画面全屏，转 180° 都跟着翻；竖起手机不变成竖屏；退出后照旧恢复竖屏和放开方向。
2. 第 10 步（“进入全屏时的方向：跟随系统”）记录实际表现（设计如此：跟系统）。
3. 结果和截图写进 `verify.md`；通过时登记表改“完成”。
4. 不通过时：根因线索写进 `verify.md`，报告建议的修复任务。

## 现状（读代码得出，写文件:行）

`apps/pure_live/` 下：

- `lib/platform/screen_orientation.dart:13`：`ScreenOrientation.landscape()`：`SystemChrome.setPreferredOrientations([landscapeLeft, landscapeRight])`，然后在 Android 上 `MethodChannel('pure_live/system_access').invokeMethod('sensorLandscape')`；`PlatformException`、`MissingPluginException` 时只是不翻。
- `android/app/src/main/kotlin/com/mystyle/purelive/SystemAccessPlugin.kt:112-116`：`sensorLandscape`：`activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE`；没有 Activity 时回答 false。
- `lib/features/live_play/live_play_page.dart`：`_enterFullscreen`（:526）：竖屏全屏 `[portraitUp]`（:552）；“跟随系统”且不是胶囊 `[]`（:554）；其他 `ScreenOrientation.landscape()`（:556）。`_restoreSystemUi`（:595-606）：胶囊进的先 `[portraitUp]`、`Timer(3 秒)` 后 `[]`；否则 `[]`。
- `lib/features/multiview/multiview_page.dart:403`（进全屏）、`:414`（退出 `[]`）。
- 设置“进入全屏时的方向” `portraitFullscreenPolicy`（`packages/live_store/lib/src/settings/settings.dart:340`）：`followSource`（默认）、`followSystem`、`landscape`；`FullscreenOrientation.of`（`lib/features/live_play/logic/room_layout.dart:124`）。
- 测试：`test/features/live_play/live_play_layouts_test.dart:64-72`（假通道记下 `sensorLandscape`）、`:729`（胶囊进入时先两个横向再 `sensorLandscape`，退出 `[portraitUp]`，然后 `[]`）。

## 3.x 基线

- `git show v3.2.11:lib/player/utils/fullscreen.dart`：`landScape`（:260-278，Android 上 `setPreferredOrientations([landscapeLeft, landscapeRight])`，:267-270）、`verticalScreen`（:281-284）；`lib/common/global/platform/mobile_manager.dart:55-60` 启动时放开四个方向。3.x 开着旋转锁不翻，这是确认过要改的（D-023），不要当成和 3.x 不一致。
- 要保留：[specs/UI.md](../../../specs/UI.md) 附录 A 第 11 条（强制横屏全屏退出后恢复竖屏）、第 12 条（默认全屏）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 10 节真机验证）。
2. `docs/S-质量和验证/S02-真机验证/README.md`（上机做法）。
3. 本文件夹的 `README.md`、`verify.md`；`docs/O-Android系统集成/O05-方向、刷新率、常亮/README.md`；`docs/S-质量和验证/S02-真机验证/S02.5-4.0.0构建号5001/brief.md` 的 1B-21、1B-22、1D-06。

## 范围

- 可以改：本文件夹（`verify.md`、`verify/` 截图）；登记表本任务的状态。不通过时**不在本任务里改代码**，开新任务。
- 不能改：代码；用户的正式包和 3.x；用户手机的系统设置（旋转锁、“进入全屏时的方向”测完恢复）；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 照 verify.md 第 1～11 步在 K90 上做，写结果和截图 | `verify.md`、`verify/*.jpg` | 每步都有结果；通过时登记表“完成”，不通过时写清根因线索 |

## 测试

- 不改代码。上机前确认构建的提交是好的：`cd apps/pure_live && flutter test test/features/live_play/live_play_layouts_test.dart`。
- （以后改这一块时要补的测试，不在本任务）双击进全屏和多画面全屏也断言调了 `sensorLandscape`。

## 真机验证（维护者在 K90 上做）

步骤和期望见 [verify.md](verify.md)（11 步）。要点：

| 步骤 | 期望 |
|---|---|
| 1～3. 横屏画面的直播间双击进全屏；关着、开着旋转锁各转 180° | 两种都跟着翻 |
| 4. 开着旋转锁把手机竖起来 | 保持横屏 |
| 5～7. 退出；竖屏主播点“横屏全屏”胶囊、转 180°、退出 | 翻转；退出后先竖屏，3 秒后放开 |
| 8～9. 多画面全屏转 180°、退出 | 翻转；退出回竖屏 |

## 风险和注意

- HyperOS 开着旋转锁时可能在屏幕角上显示“旋转”小按钮（系统的旋转建议），那是系统的，不是应用的；只看画面是不是自己翻过来了。
- 测完把旋转锁和“进入全屏时的方向”恢复成测之前的状态（D-019：不改用户的设置）。
- 和 S02.5 第一阶段同一次做，结果两边都写，不要重复上机。

## 环境和提交

- 构建：`source ~/tools/purelive-env.sh`；根目录 `bash tools/ffmpeg_kit/fetch.sh`、`flutter pub get`；`cd apps/pure_live && flutter build apk --profile`，`adb -s 192.168.1.2:5555 install -r build/app/outputs/flutter-apk/app-profile.apk`。
- 提交只有文档（`verify.md`、截图、登记表），信息以 `[O05.2]` 开头（英文）；运行 `python3 tools/docs/docs.py` 和 `--check`。

## 停下时（额度或时间不够）

已做的步骤写进 `verify.md` 并提交，末尾写“停在第几步”。

## 报告（中文，简洁）

每步结果；方向值；不通过时的现象和根因线索、建议的修复任务；系统设置已恢复。
