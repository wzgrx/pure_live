# C03.1 直播间小项：快手 App 跳转、切换直播间刷新、预测返回

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（下面“档位：应该”是当时旧任务表的写法）
- 类型：功能
- 旧编号：F.1c、T05g.3
- 相关：原生通道在 I01.1 搬的 `MainActivity.kt`；切换直播间后来由 A07.13 改成面板；真机核对归 [C01.3](../../C01-进房和房间逻辑/C01.3-直播间功能余项/README.md)；返回在厂商系统上的验证归 [O06.1](../../../O-Android系统集成/O06-返回手势、平板和折叠屏/O06.1-预测返回在ColorOS14/README.md)
- 档位：应该；规模：小
- 功能点：F-RT-05、F-RT-07、F-AND-08（见 [inventory/FEATURES.md](../../../inventory/FEATURES.md)）
- 涉及代码：`features/live_play/buttons/room_menu_button.dart`、`dialogs/room_switcher.dart`、`live_play_page.dart`、`logic/`（新 `predictive_back.dart`）；`app/app.dart`（接上关注的刷新）
- 依赖：—
- 来源：C01.2“留给后续”第 6、7 项，M13.17 任务说明第 4、6、8 项
- 评审页：按授权直接开发（只把 v3 的行为补回来，没有要选的）
- 记录：[record.md](record.md)

## v3 的行为（`~/ref/v3ref/lib`，v3.2.11）

| 行为 | 位置 |
|---|---|
| 快手：有本场直播的 `liveStreamId` 时 App 地址 `kwai://liveaggregatesquare?liveStreamId=…&recoStreamId=…&recoLiveStreamId=…&liveSquareSource=28&path=…&mt_product=H5_OUTSIDE_CLIENT_SHARE`，没有时只开网页 | `modules/live_play/services/room_external_opener.dart:193-200` |
| Android 上先试 App，打不开提示后开网页 | `room_external_opener.dart:228-240` |
| 切换直播间对话框标题右边有刷新按钮，刷新中变灰；发 `refresh_favorite_rooms`，关注页静默做一次全部刷新；刷完列表更新 | `modules/live_play/dialogs/play_other.dart:37`、`:117-136`；`modules/favorite/favorite_controller.dart:172-181`、`:238-240` |
| 直播间打开时让原生接管返回（`pure_live/predictive_back` 的 `setEnabled`），关闭时放开；原生的返回到了：上面有对话框或弹层先关它，全屏等呈现先退出，否则退出直播间 | `modules/live_play/services/android_predictive_back_service.dart:7-49`、`widgets/layout/live_play_back_scope.dart:36-116` |

## v4 现在

- `externalRoomTarget` 没有快手，只开网页（`features/live_play/buttons/room_menu_button.dart:30-58`）。`liveStreamId` 已经在 `live_core` 里（`KuaishouRoomData.liveStreamId`、`KuaishouDanmakuArgs.liveStreamId`，`packages/live_core/lib/src/sites/kuaishou/kuaishou_api.dart:21-47`），不用改 `live_core`（清点时写的“只添加 liveStreamId”不需要）。
- 切换直播间只有标题和三个列表（`dialogs/room_switcher.dart:42-52`），列表直接看存储（`:59`、`:77`），关注被刷新写回后会自己更新。关注的刷新在 `features/favorite/favorite_controller.dart:193`，功能目录之间不能互相引用（`tools/gate/check_ui_structure.py` 规则 1）。
- 原生通道在（`android/.../MainActivity.kt:327-340`、`:629-676`），Dart 没人调用，所以 `PRIORITY_OVERLAY` 的回调从没注册；返回只靠 `PopScope`（`live_play_page.dart:510-514`）。

## 差别和根因

| 编号 | 差别 | 根因 |
|---|---|---|
| P1 | 快手直播间“在快手打开”只开网页 | C01.2 搬菜单时没搬快手分支 |
| P2 | 切换直播间不能刷新开播状态 | C01.2 留给后续；关注的刷新在别的功能目录 |
| P3 | 原生返回仲裁没接上：HyperOS 等机型的返回键走 `onBackPressed`，Android 13+ 的手势走 Flutter 的回调 | 只搬了原生一半（I01.1），Dart 的服务和直播间的接入没搬 |

## 要做的改动

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 补上 | 快手按 `liveStreamId`（详情的 `data` 或弹幕参数）给 App 地址，参数照 v3；Android 先试 App，打不开开网页（现有流程） | P1 |
| c2 | 补上 | 切换直播间标题右边加刷新按钮（`AppIcons.refresh`），刷新中换成转圈、不能再点；调用关注的全部刷新（静默，不出关注页的进度条，照 v3）。功能目录不互相引用：`RoomSwitcher.refreshFollows` 由 `app/app.dart` 接到关注的刷新，没接时不显示按钮 | P2 |
| c3 | 补上 | `logic/predictive_back.dart`：通道服务（谁打开谁关，换房间时旧页面的关闭不会关掉新页面的——v3 用一组全局回调，旧页面 dispose 会清掉新页面的）；直播间在 Android 上打开时 `setEnabled(true)`，离开时关；返回到了：上面有对话框或弹层 → 关它；面板、详情、全屏、桌面小窗 → 现有的返回链；否则退出直播间，已经是第一页时交给系统 | P3 |

## 需要选的

无。

## 测试和验证

- 快手 App 地址（有、没有 `liveStreamId`）；刷新按钮调用刷新、刷新中转圈；没接刷新时没有按钮；返回：打开和离开时开关原生回调，全屏时先退全屏，有对话框先关对话框，平常退出直播间；换房间时旧页面不会关掉新页面的回调。
- K90：TASKS 第 5 节 5.1 第 5、14 条。

## 风险和性能

- 没有常驻任务；原生改动无（通道已有）。
- 原生接管后，直播间页面上的返回不再有系统的预测返回动画（v3 也是这样，换来全屏、面板的返回不出错）。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
| 2026-10-02 | 写功能对比；`liveStreamId` 已在 `live_core`，c1 不改平台层 |
| 2026-10-02 | 开发完成（c1～c3），待 K90 验证 |

## 结果

- 提交：代码 `df6e2cf2a`（`feat(live_play): portrait hint, Kuaishou app link, switcher refresh, back, player standby (F.1b-F.1d)`），合并 `d53df6d71`（2026-10-02）；登记表写的 `7b37e6f5f` 是记录的提交。逐条见 [record.md](record.md)。
- c1～c3 都做到，没有偏差。原生没有改（通道、`onBackPressed`、`PRIORITY_OVERLAY` 注册在 I01.1 时就在 `MainActivity.kt` 里）。
- 现在的位置（`apps/pure_live/lib/` 下）：c1 在 `features/live_play/buttons/room_menu_button.dart:55-83`（`externalRoomTarget` 的快手分支、`kuaishouStreamId`、`kuaishouAppLink`）；c2 当时在 `dialogs/room_switcher.dart`，A07.13 把切换直播间改成面板后，刷新在 `features/live_play/switch_room/room_switch_panel.dart` 的 `FollowsRefresher`（:22）、`RoomSwitchPanel.follows`（:110）、`_RefreshButton`（:409，另显示上次刷新时间和失败数，B05），`app/app.dart:86` 接到关注的 `refreshAll(visible: false)`；c3 在 `features/live_play/logic/predictive_back.dart` 和 `live_play_page.dart:262`（持有）、`:451`（放开）、`:646`（`_nativeBack`）。
- 记录里“换房间时新页面先打开、旧页面后关闭”的情况：A07.13 之后换房间在同一个页面里进行，持有者不变；从别处（例如通知）打开另一个直播间时仍是新页面先持有、旧页面后放开，`release` 只放自己持有的，照样成立。
- 测试：`apps/pure_live/test/features/live_play/room_extras_test.dart` 的“F.1c”组 4 个（记录写 5 个，其中刷新按钮的部分后来随 A07.13 搬进 `room_switch_test.dart`）。

## 验证

- 自动测试：`room_extras_test.dart`“F.1c”组；`room_switch_test.dart` 的刷新按钮用例。
- 真机：S02.3（2026-10-02，K90）看过“返回逐级退出：先关菜单和面板，再离开直播间，回到上一页”，通过（见 [S02.3 记录](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md)）。**没有结果的**：快手直播间“在快手打开”跳到 App、切换直播间点刷新、HyperOS 的返回键（`onBackPressed` 路径）。归 C01.3 真机第 4、5 步；返回键在 O06.1 一起看。

## 留下的问题

- 上面没看的真机项，归 C01.3。
- `_nativeBack` 没有 3.x `_handlingBack` 那样的防重入（`live_play_page.dart:646-658`），很快连按两次返回可能连退两层；读代码得出，没复现。在 O06.1 的真机步骤里看。
- 上游 pure_live `a424399e6` 在 ColorOS 14 上关掉了预测返回（GetX 路由卡死）；4.x 是否受影响由 O06.1 验证。
