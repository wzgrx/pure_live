# F.1c 直播间小项：快手 App 跳转、切换直播间刷新、预测返回

- 日期：2026-10-02
- 任务：[F.1c/README.md](../F.1c/README.md)
- 改动：`features/live_play/buttons/room_menu_button.dart`、`dialogs/room_switcher.dart`、`live_play_page.dart`、`logic/predictive_back.dart`（新）；`app/app.dart`

## 逐条对照

| 编号 | 做到 | 说明 |
|---|---|---|
| c1 快手 App 跳转 | ✅ | `externalRoomTarget` 加快手：本场的 `liveStreamId` 先看详情的 `KuaishouRoomData`，再看弹幕参数 `KuaishouDanmakuArgs`，地址和参数照 v3（`kuaishouAppLink`）；没开播（没有 id）只开网页。Android 先试 App、打不开提示后开网页是现有流程。`live_core` 没改（`liveStreamId` 早就在） |
| c2 切换直播间刷新 | ✅ | 标题右边加刷新按钮（`AppIcons.refresh`，提示“刷新”），刷新中换成转圈、不能再点；调用关注的全部刷新（`refreshAll(visible: false)`：静默、不等冷却，照 v3 的 `_fullRefreshRooms(showLoading: false)`）。列表看存储，刷新写回后自己更新。功能目录不能互相引用，`RoomSwitcher.refreshFollows` 由 `app/app.dart` 接上（和 `installPluginHooks` 一样的钩子），没接时不显示按钮 |
| c3 预测返回 | ✅ | `RoomBackChannel`（`pure_live/predictive_back`）：直播间在 Android 上打开时 `setEnabled(true)`，离开时关。原生把返回交过来：上面有对话框或弹层 → 关掉它；面板、详情、全屏、桌面小窗 → 原来的返回链；否则退出直播间，直播间是第一页时交给系统（`SystemNavigator.pop`，和没接管时 Flutter 的默认一样）。谁打开谁关：换房间时新页面先打开、旧页面后关闭，旧页面的关闭不会把新页面的关掉（v3 用一组全局回调，旧页面 dispose 会清掉新页面的） |

## 根因

- P1：M13.14 搬菜单时漏了快手分支。
- P2：M13.14 留给后续；关注的刷新在 `features/favorite/`，直播间不能直接引用。
- P3：原生通道在 M12 搬了，Dart 的服务和直播间的接入没搬，所以 `PRIORITY_OVERLAY` 的回调从没注册。

## v3 → v4

`room_external_opener.dart:193-200` → `room_menu_button.dart` 的 `kuaishouStreamId`、`kuaishouAppLink`；`play_other.dart:117-136` + `favorite_controller.dart:172-181`、`:238-240` → `RoomSwitcher.refreshFollows` + `app/app.dart`；`android_predictive_back_service.dart`、`live_play_back_scope.dart` → `logic/predictive_back.dart` + `live_play_page.dart` 的 `_nativeBack`。

## 设置

无。

## 测试

`test/features/live_play/room_extras_test.dart` 5 个：快手 App 地址（详情、弹幕参数、没开播）；刷新按钮（没接时没有、点了调用、刷新中转圈且点不动、写回后列表更新）；应用接上和放开钩子；Android 返回（打开时接管、全屏先退全屏、对话框先关、再退出直播间并放开）；换房间时旧页面的放开不影响新页面。

## 要在 K90 上看的

- TASKS 第 5 节 5.1 第 14 条：快手直播间“在快手打开”跳到 App 的直播间（K90 装了快手时）；切换直播间点刷新，转圈后列表更新。
- 5.1 第 5 条和返回相关的：全屏时手势返回只退全屏；弹出清晰度、设置面板时返回先关面板；平常返回退出直播间；HyperOS 上的返回键同样。
- 接管后直播间里的返回没有系统的预测动画（v3 也是这样）。

## 合并时注意

- 原生没有改（通道、`onBackPressed`、`PRIORITY_OVERLAY` 注册都已在 `MainActivity.kt`），所以没跑 `flutter build apk`。
- `app/app.dart` 现在引用 `features/favorite/favorite_controller.dart` 和 `features/live_play/dialogs/room_switcher.dart`（`app/` 不受“功能目录互不引用”的限制）。
