# O06.1 预测返回在 ColorOS 14 上验证全面屏手势返回（上游在 GetX 上遇到卡死）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：验证
- 来源：上游对照 [W01.1](../../../W-上游借鉴/W01-定期对照/W01.1-2026-10-03上游对照/README.md)（2026-10-03）：上游 pure_live（liuchuancong）提交 `a424399e6`（2026-10-01，“fix(android): 关闭预测性返回, 修复 ColorOS 14 全面屏手势返回卡死”）
- 旧编号：T13f.1
- 相关：决定 D-027（每周对照上游，4.x 也可能有的问题开到目标组）、D-019；直播间的返回接管 C03.1、[C03](../../../C-直播间/C03-直播间工具/README.md)；K90 上的返回验证 [S02.6](../../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 第 1 阶段；任务书 [brief.md](brief.md)

## 目标

确认 4.x 在 ColorOS 14（Android 14）上开着预测返回（`enableOnBackInvokedCallback="true"`）时，全面屏手势返回不会像上游那样卡死；据此决定 4.x 是保持现状，还是像上游一样关掉清单开关（以及关掉后直播间的返回接管怎么办）。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 上游 `a424399e6` | 4.x 现在（`apps/pure_live/` 下） |
|---|---|---|---|
| 清单开关 | `application`、`MainActivity` 两处 `enableOnBackInvokedCallback="true"`（`android/app/src/main/AndroidManifest.xml:49`、`:56`） | 两处都删掉，系统回落到老的 KeyEvent 返回 | 两处都开着（`android/app/src/main/AndroidManifest.xml:61`、`:68`） |
| 路由 | GetX（`GetMaterialApp`，`RouterDelegate` 的 `popRoute` 异步应答） | 同左 | go_router 18（`pubspec.yaml:52`）+ `Navigator`；`RouterDelegate.popRoute` 同样返回 `Future`，所以**不能断定不受影响** |
| 直播间接管 | `PRIORITY_OVERLAY` 回调 + `onBackPressed`（3.x `MainActivity.kt:184-221`） | 开关删掉后 Android 13/14 的 `OnBackInvokedCallback` 不再被系统调用，直播间靠 `onBackPressed` | 同 3.x：`MainActivity.kt:639-650`（注册）、`:663-671`（`onBackPressed`）；Dart `RoomBackChannel`（`lib/features/live_play/logic/predictive_back.dart:15`） |
| 卡死的现象 | — | 设置页等手势返回后路由无响应，左上角箭头（程序里的 `pop`）正常；ColorOS 16 已修 | 不知道 |
| targetSdk | 37（`android/app/build.gradle.kts:55`） | — | 37（`android/app/build.gradle.kts:47`）。Android 16 起 targetSdk 36+ 的应用预测返回是默认行为，关掉清单开关在新系统上不一定还管用 |

## 方案

只验证，不先改代码：

- c1 设备：找一台 ColorOS 14（Android 14，OPPO 或一加）的手机。维护者手上只有 K90（HyperOS、Android 17）；可选途径：借设备、OPPO 开放平台的云真机。没有设备时：先在 K90 上把同样的步骤走一遍（排除 4.x 自己的问题），本任务停在“受阻”（原因：没有 ColorOS 14 设备），等设备。
- c2 在 ColorOS 14 上装测试包，打开全面屏手势，按 brief 的步骤走：普通页面、设置页（宽屏两栏有嵌套 `Navigator`，上游卡在设置页）、首页（退到后台）、直播间（原生接管：面板 → 全屏 → 详情 → 离开）、内置浏览器、对话框；每一步用手势返回，对照左上角箭头。
- c3 卡死时：抓日志（`adb logcat` 里 `OnBackInvoked`、`WindowOnBackDispatcher`、`flutter`）；在本机分支上把两处清单开关去掉做一个对照包，再走一遍，看是否消失，以及直播间的返回顺序是否仍正确（Android 14 上开关关掉后系统不调 `OnBackInvokedCallback`，接管只剩 `onBackPressed`）。对照包不合并，结论写进记录，修复另开任务（O06，需要维护者决定）。
- c4 不卡时：结论写 `verify.md`，登记表改“完成”；W01 的“上游借鉴”表里这一条记“4.x 不受影响”（告诉维护者，本任务不改 W 组）。

## 验证

- 自动测试：无法在单元测试里重现厂商系统的返回分派；已有的 `apps/pure_live/test/features/live_play/room_extras_test.dart`（“F.1c”组）只测 Dart 一侧的接管。
- 真机：还没做；步骤在 [brief.md](brief.md)。

## 留下的问题

- 还没开工。最大的不确定是设备：没有 ColorOS 14 时本任务会受阻。
- 顺带要看的：`_nativeBack` 没有防重入（`apps/pure_live/lib/features/live_play/live_play_page.dart:646-658`），很快连按两次返回可能连退两层；在 K90 和 ColorOS 上都试一次。
