# C01.5 后台时未开播的房间开播后不自动出声，后台播放补出媒体通知

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：[C01 说明](../README.md)“已知问题”第 1、2 条（读代码得出，2026-10-07 docs v2 C、O 组核对）。这两条原来归 [C01.3](../C01.3-直播间功能余项/README.md) 第 3 阶段，C01.3 按 D-029 改“不做”后没有去处
- 相关：决定 D-001（3.x 是基线）、D-017（测试定时器）、D-029；后台规则 [C02](../../C02-小窗、画中画、后台播放/README.md)、[O01](../../../O-Android系统集成/O01-通知和前台服务/README.md)（前台服务和媒体通知）；刷新（B-24）在 [C01.1](../C01.1-直播间主要流程/README.md)；媒体通知只在后台播放或助眠时显示是 [C01.2](../C01.2-直播间第二部分/README.md) 确认的改动；同文件的任务 [C01.4](../C01.4-直播间清晰度显示实际档/README.md)、[C01.6](../C01.6-主播换场后弹幕参数变了要重连/README.md)
- 任务书：[brief.md](brief.md)

## 目标

两种情况，用户现在会被吓一跳或停不下来：

1. **没开“后台播放”**：在一个未开播的直播间里按 Home 或锁屏，过一会儿主播开播，手机突然出声（不在前台、没有画面），通知栏也没有能停的东西，只能回到应用或划掉应用。
2. **开着“后台播放”**：后台听着的时候主播断流、过一会儿又开播（或者离开应用时房间本来就没在播），声音会在后台重新响起，但通知栏的媒体通知已经没了（暂停、停止按钮、锁屏控制都没有），系统还可能因为没有前台服务把进程收掉。

做完以后：

- 离开应用时**没在播**的直播间（未开播、出错、受限），在后台发现开播**不自动开始播放**，只更新状态；回到应用（或进画中画）时立刻开始播放。和 3.x 一样：3.x 没有定时刷新，后台根本不会开播。
- 离开应用时**在播**、并且允许后台继续（后台播放或助眠）的直播间，后台断流重载、下播又开播时照旧自动接上（B-24），媒体通知一直在，状态从“播放”变“暂停”再变回“播放”，不会消失。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`，文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 未开播的房间什么时候开始播 | 进房时一次；之后只有用户点“刷新”或重新进房（没有定时刷新，`lib/modules/live_play/controllers/live_play_controller.dart` 没有周期计时器） | 每 60 秒 `refreshDetail`（`apps/pure_live/lib/features/live_play/logic/room_controller.dart:325-327`），不在播而现在能播就 `load()`（`:775-777`），**不管应用在不在前台** | 前台、画中画：照现在（开播后 60 秒内自动开始，A07.7 的“开播后会自动开始播放”）；后台：只更新状态，回前台时再 `load()` |
| 离开应用时的规则 | `lib/player/core/playback_lifecycle_coordinator.dart:109-143`：离开 1.5 秒后，没有后台播放就 `pauseForLifecycle`，回来恢复 | `logic/background_playback.dart:472-491` `onHidden`：1.5 秒后**只判断一次**，那时会话是 `paused`/`idle`/`stopped` 就直接返回（`:485`），之后才开始的播放没人管；`onResumed`（`:493-506`）只恢复“我们暂停的” | 离开时记下“离开时在不在播”；后台期间开始的播放不再漏掉 |
| 后台发现下播又开播 | 不会自动接（没有定时刷新） | `refreshDetail` 里“播放出错且平台说已下播”→ `load()`（`:779-781`）→ 未开播时 `_stopStream` 把会话停掉（`:387-391`、`:399-405`）；之后开播再 `load()` | 允许后台继续时照旧自动接上 |
| 媒体通知 | 每次开播都 `LiveAudioService.start`（`lib/player/core/player_manager.dart:333`），一直显示 | 只在后台播放或助眠、并且在前台时才第一次显示（`_syncNotification`，`background_playback.dart:431-459`，`:438` `if (_hidden) return`）；会话停了（不是 `opening`）就 `hide`（`:455-458`）；后台里再开播也不会再显示 | 后台期间不隐藏：会话因为重载、下播停下时通知改成“暂停”样子，重新播放时改回“播放”；只在离开直播间、或用户关掉后台播放时隐藏 |
| 后台每 60 秒请求详情 | 没有 | 照跑（`:325`） | 不变（后台也要知道开播，回来时状态是新的）；流量很小，记在“留下的问题” |

## 方案

- **c1 离开时记下在不在播**（`logic/background_playback.dart`）：`onHidden` 时记 `_playingWhenHidden = 会话是 playing/buffering/opening`；`RoomBackgroundPolicy` 对外给一个只读的 `mayStartInBackground`：在前台、或者在画中画（Flutter 报 `inactive`，不进 `onHidden`）为真；在后台时 = `_playingWhenHidden && _continues`。
- **c2 控制器不在后台自动开播**（`logic/room_controller.dart`）：`LiveRoomController` 加一个可选的回调 `bool Function()? mayAutoStart`（`RoomRuntime` 建好后由页面接到 `RoomBackgroundPolicy.mayStartInBackground`；测试里直接给）。`refreshDetail` 的两处 `load()`（`:775-777` 未开播变能播、`:779-781` 出错且已下播）在 `mayAutoStart` 为假时不调 `load()`：更新 `_room`（标题、状态）后记 `_startWhenBack = true`、`_notify()`。`RoomBackgroundPolicy.onResumed` 看到 `controller.takeStartWhenBack()` 为真就 `unawaited(controller.load())`。不加新设置、不加新文字（画面上照旧是未开播的样子；回来后马上进“加载中”）。
- **c3 后台期间保住媒体通知**（`background_playback.dart:431-459`）：`_syncNotification` 在 `_hidden` 时，已经显示过（`_notified`）的通知不再因为会话停了而 `hide`，改成 `RoomMediaNotification.update(playing: false)`；会话重新 `playing`/`buffering` 时 `update(playing: true)`。真正隐藏只在：离开直播间（`dispose`）、回到前台后会话仍然不播且不允许后台、用户在设置里关掉后台播放（`_continues` 变假）。
- **c4 后台里从没显示过通知时不硬起**：离开时没在播（c1 不会让它在后台开播），所以“后台里第一次显示”不再发生；保留 `:438` 的判断，并在注释里写明原因（Android 12 起不允许应用在后台启动前台服务）。
- 不改：60 秒刷新、`shouldContinueInBackground`（`packages/live_player/lib/src/policies.dart:7`）、通知内容和按钮、画中画里的行为、多画面。

## 验证

- 自动测试：`apps/pure_live/test/features/live_play/live_play_more_test.dart` 加两个用例（离开时未开播，后台刷新发现开播不打开引擎、回前台后打开；后台播放中下播又开播，通知没有被隐藏、状态先暂停后播放），`live_play_controller_test.dart:178` 的“刷新后自动开播”照旧通过（前台）。通知要能在测试里看到：给 `RoomMediaNotification` 加一个 `@visibleForTesting` 的记录口子（见任务书）。
- 真机：K90 上三种情况各走一遍（任务书“真机验证”）；没做之前是“未开始”。

## 留下的问题

- 后台每 60 秒请求一次详情（C01 说明“已知问题”第 2 条）：这次不改，后台知道开播才能在回来时马上播；如果 R05.1（耗电）测出明显耗电，再改成后台降频。
- 多画面在后台的行为不在本任务（N01；多画面没有定时刷新，不会在后台开播）。
- 用户在后台想知道“主播开播了”属于开播提醒（新功能提议 [V01.1](../../../V-需求和反馈/V01-新功能提议/V01.1-开播提醒/README.md)），本任务不发通知。
