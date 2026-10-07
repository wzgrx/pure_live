# O06.1 预测返回在 ColorOS 14 上验证：任务书

## 背景

- 来源：上游 pure_live 提交 `a424399e6`（liuchuancong，2026-10-01）：“关闭预测性返回, 修复 ColorOS 14 全面屏手势返回卡死”。原话：“`enableOnBackInvokedCallback=true` 时 Android 14 走 OnBackInvokedCallback 预测返回路径；ColorOS 14 的该实现与 GetX RouterDelegate 的异步 popRoute 应答不兼容——手势返回提交后路由无响应（卡死），而左上角箭头是 programmatic pop 走传统通道所以正常；ColorOS 16 修复了系统侧实现。”上游删掉了清单里两处开关。2026-10-03 的上游对照（W01.1）把它开到这里。在本仓库看：`git show a424399e6`（`upstream` 远端）。
- 现象（上游）：ColorOS 14 手机，打开全面屏手势，在设置页等页面从屏幕边缘滑动返回 → 页面不动、之后返回都没反应；点左上角箭头能退。
- 为什么现在做：第二档、小。4.x 两处开关都开着（和 3.x 一样）；如果 ColorOS 14 用户遇到，整个应用的手势返回都会失效。
- 已经做过的：C03.1（直播间接管返回，按持有者放开）；S02.3 在 K90 上看过“返回逐级退出”（当时构建还没有接管）。

## 目标和验收

1. 有 ColorOS 14 设备时：下面“真机验证”第 1～10 步都做完，结果写 `verify.md`。
2. 不卡死：登记表改“完成”；报告里写“4.x 不受影响”，建议维护者在 W01 记下。
3. 卡死：做一个去掉两处开关的对照包（不合并），确认去掉后不卡、直播间返回顺序仍对；结论和日志写进 `record.md`；报告建议开修复任务（是否关掉开关由维护者决定，D-003 默认按建议）。
4. 没有 ColorOS 14 设备：在 K90 上把第 1～10 步走一遍并记录（证明 4.x 自己的返回没问题）；登记表改“受阻”，`note` 写“没有 ColorOS 14 设备；解除条件：借到设备或用云真机”。
5. 第 9 步（连按两次返回）的结果单独写出：会不会连退两层。

## 现状（读代码得出，写文件:行）

`apps/pure_live/` 下：

- 清单 `android/app/src/main/AndroidManifest.xml`：`application` 的 `android:enableOnBackInvokedCallback="true"`（:61），`MainActivity` 的同一属性（:68）。
- 原生 `android/app/src/main/kotlin/com/mystyle/purelive/MainActivity.kt`：Android 13 的 `OnBackInvokedCallback`（:155-161）、14+ 的 `OnBackAnimationCallback`（:164-188，把 `backStarted`、`backProgress`、`backCancelled` 发给 Dart，Dart 现在只处理 `backInvoked`）；`setPredictiveBackEnabled`（:630）、`registerPredictiveBack`（:639-650，`PRIORITY_OVERLAY`，注释：Flutter 在 DEFAULT 注册，直播间要先收到）；`onBackPressed`（:663-671，厂商系统的返回键仍到这里）；`onResume` 重新注册（:714-716）、`onStop` 注销（:721）。
- Flutter 一侧：go_router 18（`pubspec.yaml:52`，路由表 `lib/routes/app_router.dart`）；`RouterDelegate.popRoute` 是异步的（和 GetX 一样），所以上游的根因（异步应答）不能直接排除。
- 有自己返回处理的页面：首页 `lib/features/home/home_page.dart:143`（`PopScope(canPop: false)` + `_onBack` :122 → `moveToBack`）；设置 `lib/features/settings/settings_page.dart:132-133`（宽屏右栏嵌套 `Navigator`）、`:225`（`PopScope`）；观看记录 `lib/features/history/history_page.dart:224`（搜索框打开时先关）；内置浏览器 `lib/shared/in_app_web.dart:111`；Cookie 编辑 `lib/features/account/cookie_editor.dart:393`（没保存时确认）；直播间 `lib/features/live_play/live_play_page.dart:262`（Android 上 `RoomBackChannel.hold`）、`:646-658`（`_nativeBack`，没有防重入）。
- 页面切换 `FadeForwardsPageTransitionsBuilder`（`packages/live_ui/lib/src/theme/live_theme.dart:12-17`），没有预测返回的页面动画。

## 3.x 基线

- `git show v3.2.11:android/app/src/main/AndroidManifest.xml:49`、`:56`（两处开关，和 4.x 相同）；`android/app/src/main/kotlin/com/mystyle/pure_live/MainActivity.kt:184-221`（`PRIORITY_OVERLAY` 和 `onBackPressed`，和 4.x 相同）。
- `lib/modules/live_play/widgets/layout/live_play_back_scope.dart`（130 行）：`_handleNativeBack` 有 `_handlingBack` 防重入，上面有路由先 `maybePop`。
- 要保留：[specs/UI.md](../../../specs/UI.md) 附录 A 第 7 条（直播间返回链：弹层 → 全屏 → 普通 → 离开）；首页返回退到后台（3.x move_to_desktop）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 10 节真机验证、第 14 节规则）。
2. 本文件夹的 `README.md`；`docs/O-Android系统集成/O06-返回手势、平板和折叠屏/README.md`；`docs/C-直播间/C03-直播间工具/README.md`（直播间的返回链）；`docs/W-上游借鉴/W01-定期对照/W01.1-2026-10-03上游对照/README.md` 第 23 行那一条。
3. `git show a424399e6`（上游的改动和说明）。

## 范围

- 可以改：本文件夹（`verify.md`、`record.md`、截图）；登记表本任务的状态和 `note`；对照包只在本机分支上改两处清单开关，不提交到 master。
- 不能改：合并进 master 的任何代码（要关开关时另开任务）；W 组和 S 组文档（建议写进报告）；用户的正式包和 3.x；借来的设备上除测试包以外的东西；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1：找设备；同时在 K90 上走一遍第 1～10 步 | `verify.md`（K90 一列） | K90 的结果都有；设备有着落或登记表改“受阻” |
| 2 | c2：ColorOS 14 上走第 1～10 步 | `verify.md`（ColorOS 一列）、截图 | 结果都有 |
| 3 | c3（只在卡死时）：对照包、日志、结论 | `record.md` | 根因和建议写清 |

## 测试

- 不改合并的代码，不加测试。上机前确认构建的提交是好的：`cd apps/pure_live && flutter test test/features/live_play/room_extras_test.dart`。
- 对照包（只在卡死时）：本机分支删掉 `AndroidManifest.xml:61`、`:68` 两处属性，`flutter build apk --debug`，装成测试包对比。

## 真机验证（ColorOS 14 设备；没有时 K90）

准备：系统设置里打开“全面屏手势”；装合并后 master 的测试包 `com.mystyle.purelive.v4dev`；`adb shell getprop ro.build.version.release`（14）、`adb shell getprop ro.build.version.opporom` 或“关于手机”记下 ColorOS 版本。每一步用边缘滑动返回，卡住时再试左上角箭头。

| 步骤 | 期望 |
|---|---|
| 1. 首页 → 设置 → 任意一个子页（例如“视频”），手势返回两次 | 一级一级退回首页，每次都有反应 |
| 2. 设置子页里再打开一层（例如“小窗弹幕”页），手势返回 | 退一层；再返回再退一层 |
| 3. 横过来或用宽屏（`adb shell wm size 1600x2560`，测完 `wm size reset`）打开设置，右栏打开子页，手势返回 | 先退右栏的子页，再返回离开设置 |
| 4. 首页手势返回 | 应用退到后台（不关掉），从最近任务回来仍在首页 |
| 5. 观看记录 → 打开搜索框 → 手势返回 | 先关搜索框，再返回离开页面 |
| 6. 进直播间，打开右上角菜单 → 手势返回；打开清晰度面板 → 手势返回 | 先关菜单、再关面板，不离开直播间 |
| 7. 双击进横屏全屏 → 手势返回；再返回 | 先退出全屏，再离开直播间 |
| 8. 工具箱或网页搜索打开内置浏览器，点进一个链接 → 手势返回两次 | 先后退网页，再关浏览器 |
| 9. 直播间里很快连续两次手势返回（全屏状态下） | 记下结果：只退出全屏，还是连带离开直播间（`_nativeBack` 没有防重入） |
| 10. 第 1～9 步中任何一步卡住时：点左上角箭头 | 记下箭头能不能退（上游的现象是箭头正常） |

卡住时：`adb logcat -d -v time | grep -iE 'OnBackInvoked|WindowOnBackDispatcher|BackNavigation|flutter|purelive' > verify/logcat.txt`。

## 风险和注意

- 借来的设备或云真机：只装测试包、只点测试包；测完卸载测试包、恢复手势设置（D-019 的精神）。
- 云真机通常没有 adb 日志或手势模拟不真实，结论要写明是在什么环境下得出的。
- 关掉清单开关不是无代价的：Android 14 上系统就不再调 `OnBackInvokedCallback`，直播间接管只剩 `onBackPressed`；Android 16+、targetSdk 36+ 时预测返回是默认行为，关掉开关的效果要在 K90（Android 17）上再确认。所以卡死时也不要直接改 master。
- 和 S02.6 第 1 阶段（K90 上的返回）步骤重叠：K90 的结果可以两边共用。

## 环境和提交

- 构建：`source ~/tools/purelive-env.sh`；根目录 `bash tools/ffmpeg_kit/fetch.sh`、`flutter pub get`；`cd apps/pure_live && flutter build apk --profile`。安装：`adb -s <设备> install -r build/app/outputs/flutter-apk/app-profile.apk`。
- 提交只有文档（`verify.md`、`record.md`、截图、登记表），信息以 `[O06.1]` 开头（英文）；运行 `python3 tools/docs/docs.py` 和 `--check`。对照包的分支不推送。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：做完的步骤写进 `verify.md` 并提交；登记表写 `next`（例如“等 ColorOS 14 设备，K90 已做完”）。

## 报告（中文，简洁）

用的设备和系统版本；第 1～10 步的结果（K90、ColorOS 各一列）；卡不卡死、日志位置；对照包的结论（只在卡死时）；第 9 步连按两次的结果；建议（保持现状 / 开任务关开关 / 加防重入）；登记表改成了什么。
