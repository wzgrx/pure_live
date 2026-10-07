# O06 返回手势、平板和折叠屏

预测返回、平板和折叠屏的系统特性。

Android 的返回（返回键、全面屏手势返回、Android 13 起的预测返回）在整个应用里怎么走，厂商系统上的差异；以及平板、折叠屏、分屏和自由窗口这些大屏形态在系统层面的行为（方向请求被忽略、窗口大小变化不重建）。

## 范围

- 包括：
  - **预测返回的开关和原生分派**：清单 `android:enableOnBackInvokedCallback="true"`（`application` 和 `MainActivity` 两处）；`MainActivity.kt` 的 `pure_live/predictive_back` 通道：Android 13+ 以 `PRIORITY_OVERLAY` 注册回调（14+ 带进度的 `OnBackAnimationCallback`），`onBackPressed` 里接住厂商系统仍走老路径的返回键；`pure_live/app` 的 `moveToBack`（首页返回时退到后台而不是关掉应用）。
  - **全应用的返回行为在厂商系统上的验证**（ColorOS、HyperOS 等），以及上游因为厂商问题改了返回开关时的跟进（W01 发现 → 这里验证）。
  - **大屏的系统特性**：`resizeableActivity="true"`、`configChanges`（转屏、改窗口大小、折叠展开不重建 Activity）、`android.allow_multiple_resumed_activities`；Android 16/17 在最短边 ≥600dp 的设备上忽略方向请求。
- 不包括（归哪里）：
  - 直播间里返回链的逻辑（先关面板、再退全屏、再关详情、最后离开）和 `RoomBackChannel` → [C03](../../C-直播间/C03-直播间工具/README.md)（`features/live_play/logic/predictive_back.dart`、`live_play_page.dart` 的 `_nativeBack`）。
  - 大屏的布局（宽度分档、分栏、窗口内全屏）→ A04（尺寸适配）、A07.5（宽屏分栏）、A16（桌面窗口）；画面上下滑避开系统手势区 → A07.15。
  - 横屏全屏的方向请求本身 → [O05](../O05-方向、刷新率、常亮/README.md)。
  - 电视遥控器的返回 → X03、A17。

## 现状：做到哪、怎么工作的

用户看得到的（Android 手机）：

- **普通页面**：返回键和全面屏手势返回都是一级一级退；页面切换用 `FadeForwardsPageTransitionsBuilder`（`packages/live_ui/lib/src/theme/live_theme.dart:12-17`，照 3.x），应用内的页面没有系统的预测返回动画（拖动时不预览上一页）。
- **首页**：返回不关掉应用，而是退到后台（`home_page.dart:122-131` 调 `moveToBack`，3.x 用 move_to_desktop 插件）。
- **设置页**：宽屏两栏时右栏有自己的 `Navigator`（`features/settings/settings_page.dart:132-133`），返回先退右栏的子页（`PopScope`，:225）。
- **直播间**：打开期间原生把返回交给页面（C03）：上面有弹窗或面板先关、全屏先退、详情先关，最后离开；直播间里也没有预测返回动画（3.x 也没有）。
- **其他接了 `PopScope` 的页面**：多画面（:445）、观看记录（搜索框打开时先关搜索，:224）、内置浏览器（先后退网页，`shared/in_app_web.dart:111`）、哔哩哔哩网页登录、Cookie 编辑（改过没保存时先确认放弃）、更新下载（`update_download.dart:601`，先走自己的返回处理）。
- **平板、折叠屏**：同一个 APK，宽度 ≥600 起按宽屏排（[specs/UI.md](../../specs/UI.md) 第 5.1 节）；转屏、折叠展开、分屏改大小时 Activity 不重建（`configChanges`），Flutter 直接重新排版；Android 16/17 在大屏上忽略应用的方向请求（横屏全屏、竖屏全屏都不转），按当前方向排（specs/UI.md 第 5.3 节）。

内部怎么工作：

```text
清单 enableOnBackInvokedCallback=true（AndroidManifest.xml:61、:68）
  → Android 13+：系统不再调 onBackPressed 给手势返回，改调注册的 OnBackInvokedCallback
  → Flutter 引擎自己注册一个（PRIORITY_DEFAULT），框架按路由栈和 PopScope 处理（go_router + Navigator）
直播间打开：RoomBackChannel.hold → 通道 setEnabled(true) → MainActivity.setPredictiveBackEnabled（:630）
  → registerPredictiveBack（:639）：Android 14+ OnBackAnimationCallback（backStarted/backProgress/backCancelled 发给 Dart，:164-188），
    13 OnBackInvokedCallback（:155-161），优先级 PRIORITY_OVERLAY（:648），比 Flutter 的先收到
  → 返回 → dispatchPresentationBack（:624）→ 通道 backInvoked → Dart _nativeBack
  厂商系统的返回键仍走 onBackPressed（:663-671）：开着时同样转给 Dart
  onResume 重新注册（:714-716）、onStop 和 onDestroy 注销（:721、:737）
首页：PopScope(canPop: false) → _onBack → pure_live/app moveToBack（MainActivity.kt:251）→ moveTaskToBack(true)
```

- 完成度：清点第 2 节 F-AND-08（预测返回）“没验证”：C03.1 接上直播间的返回接管（合并在 K90 用的构建之后），接管后的手势返回和 HyperOS 返回键归 S02.6 第 1 阶段；S02.3 在 K90 上看过“返回逐级退出”通过（当时构建还没有接管）。ColorOS 14 上会不会像上游那样卡死没验证（[O06.1](O06.1-预测返回在ColorOS14/README.md)）。大屏只在 K90 上用 `wm size` 模拟过宽屏布局（A 组任务），没有真的平板或折叠屏。
- 和 3.x 比：清单开关、`PRIORITY_OVERLAY`、`onBackPressed` 接住厂商返回键都和 3.x 一样（`git show v3.2.11:android/app/src/main/kotlin/com/mystyle/pure_live/MainActivity.kt` :26、:184-221）；3.x 是 GetX 路由，4.x 是 go_router（不一定有上游在 GetX 上遇到的问题）；3.x 的 Dart 一侧是一组全局回调，换房间时旧页面会清掉新页面的，4.x 按持有者放开（C03.1 c3）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/android/app/src/main/AndroidManifest.xml` | `application` 的 `enableOnBackInvokedCallback="true"`（:61）、`MainActivity` 的同一属性（:68）、`resizeableActivity="true"`（:67）、`configChanges`（:66）、`launchMode="singleTask"`（:63）、`allow_multiple_resumed_activities`（:72） |
| `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/MainActivity.kt` | `PREDICTIVE_BACK_CHANNEL`（:92）；`predictiveBackEnabled`、`predictiveBackRegistered`（:129-130）；回调（:155-188）；通道 `setEnabled`（:322-336）；`dispatchPresentationBack`（:624）、`setPredictiveBackEnabled`（:630）、`registerPredictiveBack`（:639-650，`PRIORITY_OVERLAY` 的理由写在 :646-647 的注释）、`unregisterPredictiveBack`（:653）、`onBackPressed`（:663-671）；生命周期（:714-716、:721、:737）；`pure_live/app` 的 `moveToBack`（:251） |
| `apps/pure_live/lib/features/live_play/logic/predictive_back.dart`（72 行） | `RoomBackChannel`（:15）：`hold`（:31）、`release`（:42，只放开自己持有的）、`backInvoked`（:70）；行为归 C03 |
| `apps/pure_live/lib/features/home/home_page.dart` | `PopScope<Object?>`（:143）+ `_onBack`（:122，Android 上 `moveToBack`） |
| `apps/pure_live/lib/features/settings/settings_page.dart` | 宽屏右栏的嵌套 `Navigator`（:132-133）和 `PopScope`（:225） |
| `apps/pure_live/lib/routes/app_router.dart` | go_router 的路由表（`go_router: ^18.0.2`，`apps/pure_live/pubspec.yaml:52`） |
| `packages/live_ui/lib/src/theme/live_theme.dart` | `appPageTransitionsTheme`（:12-17，Android 用 `FadeForwardsPageTransitionsBuilder`，没有预测返回的页面动画） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/live_play/room_extras_test.dart`（“F.1c”组） | 直播间打开时接管返回、对话框先关、全屏先退、再退出并放开；换房间时旧页面不放掉新页面的 |
| 各页面测试里的 `tester.binding.handlePopRoute()` | 普通页面、设置右栏、多画面、观看记录搜索框的返回（例如 `live_play_page_test.dart:168`、`:235`） |

原生的回调注册、厂商系统的分派只能在真机看；没有平板和折叠屏的自动测试（布局测试用不同的窗口尺寸代替，归 A04）。

## 3.x 基线

- `git show v3.2.11:android/app/src/main/AndroidManifest.xml:49`、`:56`：同样两处 `enableOnBackInvokedCallback="true"`。
- `android/app/src/main/kotlin/com/mystyle/pure_live/MainActivity.kt`（378 行）：`PREDICTIVE_BACK_CHANNEL`（:26）、回调（:86-105）、`registerPredictiveBack` 用 `PRIORITY_OVERLAY`（:184-199）、`onBackPressed`（:213-221）。
- `lib/modules/live_play/services/android_predictive_back_service.dart`（50 行，一组全局回调）、`widgets/layout/live_play_back_scope.dart`（130 行，`_handlingBack` 防重入）。
- 上游 pure_live（liuchuancong）在 3.2.11 之后的 `a424399e6`（2026-10-01）“关闭预测性返回，修复 ColorOS 14 全面屏手势返回卡死”：两处清单开关删掉，理由是 ColorOS 14 的预测返回实现和 GetX `RouterDelegate` 的异步 `popRoute` 应答不兼容，手势返回后路由无响应（设置页等），左上角箭头正常；ColorOS 16 已修。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| ColorOS 14（Android 14）上全面屏手势返回会不会卡死没验证；上游在 GetX 上遇到，4.x 是 go_router | `AndroidManifest.xml:61`、`:68` | 卡死时整个应用的手势返回失效（左上角箭头还能用） | [O06.1](O06.1-预测返回在ColorOS14/README.md) |
| 接管后的手势返回、HyperOS 返回键（`onBackPressed` 路径）没在真机走过 | `MainActivity.kt:624-671` | 直播间里返回可能不按“面板 → 全屏 → 离开”的顺序 | S02.6 第 1 阶段 |
| `_nativeBack` 没有 3.x `_handlingBack` 那样的防重入 | `apps/pure_live/lib/features/live_play/live_play_page.dart:646-658` | 很快连按两次返回可能连退两层（读代码得出，没复现） | O06.1 的真机步骤里顺带看；复现就在 C03 开任务 |
| 应用内页面没有预测返回的页面动画（拖动时不预览上一页） | `live_theme.dart:12-17` | 和 Android 14+ 系统应用的手感不同；照 3.x | 不做；要做时先在 V01 提议（A03 动效） |
| Android 16 起 targetSdk 36+ 的应用预测返回是默认行为，清单开关的效果会变；4.x targetSdk 37 | `apps/pure_live/android/app/build.gradle.kts:47` | 如果 O06.1 结论是要像上游那样关掉，关掉在新系统上不一定有效 | O06.1 写清：要关时还要在 K90（Android 17）上确认关掉后的行为 |
| 没有真的平板和折叠屏验证过 | — | 折叠展开时播放、全屏、画中画的表现不清楚 | 没有任务；有设备时在 S02 登记验证任务 |

## 相关决定和规范

- D-004（只做 Android）、D-019（真机只点测试包）、D-027（每周对照上游，O06.1 的来源）。
- [specs/UI.md](../../specs/UI.md) 第 5.1 节（宽度分档）、第 5.3 节（大屏方向锁定被系统忽略）、附录 A 第 7 条（直播间返回链：弹层 → 全屏 → 普通 → 离开）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/live_play/room_extras_test.dart`，以及各页面测试里的 `handlePopRoute`。
- 真机：CHECKLIST 第 1 节第 5 条（返回）；Android 13+ 的手势返回、返回键、厂商系统各走一遍。看回调注册：`adb shell dumpsys activity activities | grep -i -A3 OnBackInvoked`（各系统输出不同，以实际为准）。

## 路线

1. **O06.1**（第二档，小）：在 ColorOS 14 设备上验证全面屏手势返回；没有设备时先在 K90 上走一遍同样的步骤（排除 4.x 自己的问题），ColorOS 14 的结论标“受阻”等设备。
2. S02.6 第 1 阶段：K90 上接管后的手势返回和返回键。
3. 以后：有平板或折叠屏时登记真机验证；应用内页面的预测返回动画先在 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [O Android系统集成](../README.md)。

- 代码：`android/`、`features/live_play/logic/predictive_back.dart`
- 进度：`░░░░░░░░░░░░░░░░░░░░` 0%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| O06.1 | 预测返回在 ColorOS 14 上验证全面屏手势返回（上游在 GetX 上遇到卡死） | 验证 | 未开始 | — | — | [设计或说明](O06.1-预测返回在ColorOS14/README.md)、[任务书](O06.1-预测返回在ColorOS14/brief.md) |

## 还没完成的

- **O06.1 预测返回在 ColorOS 14 上验证全面屏手势返回（上游在 GetX 上遇到卡死）**（未开始，第二档，规模 小）
  - 说明：上游 pure_live a424399e6 关掉了预测返回；4.x 用 go_router，不一定受影响

<!-- docs:生成结束 -->
