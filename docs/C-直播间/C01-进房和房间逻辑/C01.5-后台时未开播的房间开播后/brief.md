# C01.5 后台时未开播的房间开播后不自动出声，后台播放补出媒体通知：任务书

## 背景

- 来源：[C01 说明](../README.md)“已知问题”第 1、2 条（2026-10-07 docs v2 C、O 组读代码发现，未在真机确认）。原来归 C01.3 第 3 阶段，C01.3 按 D-029 改“不做”后没有去处，维护者 2026-10-07 登记为本任务。
- 现象（读代码推出）：
  1. 没开“后台播放”：进一个未开播的关注 → 按 Home → 主播开播后不超过 60 秒，手机在后台开始出声；通知栏没有媒体通知，没法停。
  2. 开着“后台播放”：后台听着时主播断流（平台说已下播），过一会儿又开播 → 声音自己回来，但通知栏的媒体通知在断流那一刻就消失了，之后不会再出现（锁屏也没有控制）。
- 为什么现在做：第二档；规模小（两个阶段各约 1 小时）。3.x 没有定时刷新，不会出现这两种情况，现在是 4.x 加了 B-24（未开播自动开始）带来的退步。
- 已经做过的：B-24 的定时刷新（C01.1，`room_controller.dart:758`）；后台规则（C01.2，`background_playback.dart` 的 `RoomBackgroundPolicy`）；媒体通知只在后台播放或助眠时显示（C01.2 确认的改动）。

## 目标和验收

1. 没开后台播放：未开播的直播间里离开应用，主播在后台开播 → 不打开播放器（引擎没有 `open`），没有声音；回到应用后 1 秒内开始加载并播放。
2. 开着后台播放，离开时房间**没在播**（未开播、出错、受限）：同第 1 条，后台不自动开播，回来再开始（离开时没在播，用户没期待声音，而且 Android 不允许从后台第一次启动媒体通知的前台服务）。
3. 开着后台播放，离开时**在播**：后台断流、平台说已下播、之后又开播 → 照旧自动接上（B-24）；整个过程媒体通知不消失：断流时按钮变成“播放”（暂停的样子），重新播放时变回“暂停”。
4. 进画中画（不是后台）时，未开播房间开播照旧自动开始（画中画里能看到画面）。
5. 前台时行为不变：`live_play_controller_test.dart:178` 的“an offline room … starts by itself when the refresh finds it live (B-24)”照样通过。
6. 离开直播间（返回、关掉小窗）时通知照旧消失；回到前台后房间不播又不允许后台时，通知照旧消失。
7. 测试和门禁通过；没有新设置、没有新文字。

## 现状（读代码得出，写文件:行）

- 定时刷新：`apps/pure_live/lib/features/live_play/logic/room_controller.dart`：`refreshInterval` 默认 60 秒（`:99`），`start()` 里 `Timer.periodic`（`:325-327`）；`refreshDetail`（`:758-787`）：状态待定不动（`:771`）；`!playing && _stage != RoomStage.unplayable && fetched.isPlayableNow` → `await load()`（`:775-777`）；`playing && !fetched.isPlayableNow && session.state.status == PlaybackStatus.error` → `await load()`（`:779-781`）。控制器不知道应用在不在前台。
- `load()`（`:360-393`）：未开播时 `_stage = offline`，`_stopStream()`（`:399-405`）把会话 `stop()`；能播时 `_startStream` → `session.open`。
- 后台规则：`apps/pure_live/lib/features/live_play/logic/background_playback.dart`：
  - `RoomBackgroundPolicy`（`:393` 起）：`_continues`（`:415-418`，`shouldContinueInBackground(backgroundPlaybackEnabled:, sleepSessionActive:)`）；`start()`（`:421-427`）听会话状态和控制器，都走 `_syncNotification`。
  - `_syncNotification`（`:431-459`）：`wanted = (playing || buffering || paused) && _continues`；第一次显示必须在前台（`:437-438` `if (_hidden) return;`）；`!wanted && _notified && status != opening` → `hide`（`:455-458`）。会话被 `stop()` 后状态是 `stopped`，通知就被藏掉，之后在后台再 `playing` 也不会再显示。
  - `didChangeAppLifecycleState`（`:459-468`）：`hidden`/`paused`/`detached` → `onHidden`，`resumed` → `onResumed`，`inactive`（画中画、下拉通知栏）不管。
  - `onHidden`（`:472-491`）：不允许后台时 1.5 秒后判断一次，会话是 `paused`/`idle`/`stopped` 就返回（`:485`），否则暂停并记 `_pausedByUs`；允许后台时只开唤醒锁（`:477-480`）。
  - `onResumed`（`:493-506`）：恢复 `_pausedByUs` 的，`_syncNotification()`。
- 媒体通知：`RoomMediaNotification`（`:299` 起）：`available` 只看 `Platform.isAndroid`（`:304`），**没有测试口子**；`show`（`:326`）、`update`（`:355`）、`hide`（`:373`）。`AudioServiceConfig`（`:310-317`）`androidNotificationOngoing: true`（暂停时降为普通通知，`audio_service` 要求同时 `androidStopForegroundOnPause`）。
- 组装：`live_play_page.dart:266` `_newRuntime`：先建 `LiveRoomController`（`:274-286`），再建 `RoomBackgroundPolicy(controller:, settings:)..start()`（`:292`）。应用内小窗接手同一个 `RoomRuntime`（`logic/room_runtime.dart` 的 `FloatingRoom`），策略跟着走。
- 测试：`apps/pure_live/test/features/live_play/live_play_more_test.dart:219` “leaving the app pauses unless background play is on; coming back resumes”（`onHidden`/`onResumed` 直接调，`hiddenPauseDelay` 传短值）；`live_play_controller_test.dart:178`（前台刷新后自动开播、弹幕结束后重连）；假引擎 `engine.opens`、假会话在 `live_play_support.dart`。

## 3.x 基线

- `git show v3.2.11:lib/player/core/playback_lifecycle_coordinator.dart`：`_enterHiddenState`（`:109`）、`_applyHiddenPause`（`:131`）、`_enterResumedState`（`:145`）：离开 1.5 秒后按后台策略暂停，回来恢复；没有“后台里才开始的播放”这种情况，因为 3.x 直播间没有定时刷新（`lib/modules/live_play/controllers/live_play_controller.dart` 里只有醒目留言、弹幕批量、礼物特效的计时器，`:349`、`:512`、`:597`）。
- `lib/player/core/player_manager.dart:333`：每次开播 `LiveAudioService.start`（媒体通知一直显示，4.x 改成只在后台播放或助眠时，C01.2）。
- 要保留：后台播放、助眠的规则和键名（`enableBackgroundPlay`、`enableAsmrSleepMode`，D-018）；离开 1.5 秒才算离开（转屏、进画中画的短暂 hidden）；回来恢复“我们暂停的”。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/DECISIONS.md` 的 D-017、D-029。
3. 本文件夹的 `README.md`；`docs/C-直播间/C01-进房和房间逻辑/README.md`（“现状”的刷新、“已知问题”）；`docs/C-直播间/C02-小窗、画中画、后台播放/README.md`；`docs/O-Android系统集成/O01-通知和前台服务/README.md`（媒体通知、前台服务）；`docs/C-直播间/C01-进房和房间逻辑/C01.2-直播间第二部分/README.md`（媒体通知的确认改动）。

## 范围

- 可以改：`apps/pure_live/lib/features/live_play/logic/room_controller.dart`（`refreshDetail` 和一个回调、一个“回来再开播”的标记）、`logic/background_playback.dart`（`RoomBackgroundPolicy`、`RoomMediaNotification` 加测试口子）、`live_play_page.dart`（`_newRuntime` 里接线）；测试 `live_play_more_test.dart`、`live_play_controller_test.dart`、`live_play_support.dart`；本文件夹。
- 不能改：60 秒刷新间隔；`shouldContinueInBackground`（`packages/live_player`）；通知的内容、按钮、渠道和图标（A14.1、O01）；画中画的进入和退出（C02）；多画面；设置键名和含义（D-018）；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 离开时没在播的房间，后台开播不自动播放，回到应用再开始 | c1：`RoomBackgroundPolicy` 在 `onHidden` 记 `_playingWhenHidden`（会话 `opening`/`buffering`/`playing`），给 `bool get mayStartInBackground => !_hidden \|\| (_playingWhenHidden && _continues)`。c2：`LiveRoomController` 加 `bool Function()? mayAutoStart`（可写字段，默认 null = 允许）和私有 `_startWhenBack`；`refreshDetail` 两处 `load()` 前先判断，不允许时 `_room = _room.mergeFrom(fetched)…`、`_startWhenBack = true`、`_notify()` 后返回；加 `bool takeStartWhenBack()`（读出并清掉）。`onResumed` 里 `if (controller.takeStartWhenBack()) unawaited(controller.load())`。`_newRuntime` 里建好策略后 `controller.mayAutoStart = policy.mayStartInBackground`（注意：小窗接手时策略是同一个） | `room_controller.dart`、`background_playback.dart`、`live_play_page.dart`、测试 | 验收 1、2、4、5；新测试改之前失败 |
| 2 后台播放中重新加载时保住媒体通知 | c3：`_syncNotification` 在 `_hidden && _notified` 时，会话 `stopped`/`idle`/`error`/`opening` 不 `hide`，改 `update(playing: false)`；回到 `playing`/`buffering` 时 `update(playing: true)`；`_continues` 变假（用户关了后台播放）时照旧 `hide`。c4：`:438` 加注释说明为什么后台里不第一次显示。`RoomMediaNotification` 加 `@visibleForTesting static void Function(String action, bool? playing)? debugLog`（`show`/`update`/`hide` 时记一笔，`available` 为假也记），让测试看得见 | `background_playback.dart`、测试 | 验收 3、6；新测试改之前失败 |

每个阶段都要能单独合并（门禁通过、不留半截功能）。

## 测试

- 阶段 1（改之前会失败）：`live_play_more_test.dart` 加 “an offline room that comes on air while the app is away waits until the app is back (C01.5)”：`FakeSite(liveRoom(status: LiveStatus.offline))`，`controller.start()`，建 `RoomBackgroundPolicy` 并接上 `controller.mayAutoStart = policy.mayStartInBackground`，`policy.onHidden()`；`site.room = liveRoom()`；`await controller.refreshDetail()` → `engine.opens` 仍为空、`controller.stage` 仍是 `offline`；`policy.onResumed()` 后 `await until(() => controller.stage == RoomStage.playing)`，`engine.opens` 有一次。再开后台播放重复一遍（离开时没在播），结果相同。
- 阶段 1：同文件加 “a room playing when the app left may restart in the background when background play is on”：后台播放开，播放中 `onHidden`，平台变下播且会话 `error` → `refreshDetail` → `offline`；平台再变开播 → `refreshDetail` 后 `engine.opens` 加一（不用等回来）。
- 阶段 2（改之前会失败）：同一个场景里用 `RoomMediaNotification.debugLog` 记录：离开前显示（`show`），后台下播 → 只有 `update(false)`、没有 `hide`；重新播放 → `update(true)`；`policy.dispose()` → `hide`。另一个用例：后台里把 `Settings.enableBackgroundPlay` 关掉 → `hide`。
- 前台不变：`live_play_controller_test.dart:178` 不改照样通过。
- 测试里的定时器至少 1 秒（D-017）：新用例里 `hiddenPauseDelay` 用 1 秒以上，或不依赖它（离开时没在播的分支本来就不起计时器）。不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 设置 → 视频“后台播放”关。找一个关注里马上要开播的主播（或用测试账号自己开播），进它的直播间（显示未开播），按 Home 等它开播后 2 分钟 | 手机一直没有声音；`adb shell dumpsys media_session` 里没有本应用的播放状态 |
| 2. 回到应用 | 1 秒内开始加载，随后播放 |
| 3. “后台播放”开，重复第 1、2 步 | 后台同样没有声音；回来开始播放 |
| 4. “后台播放”开，进一个在播的直播间，等通知栏出现媒体通知后按 Home；让主播下播（或断网 1 分钟让播放出错、平台说已下播），再开播 | 通知一直在：断流时按钮变“播放”，重新开播后自动出声、按钮变回“暂停”；锁屏控制同样 |
| 5. 第 4 步的后台播放中，从通知栏下拉进设置关掉“后台播放”（或回应用关掉再离开） | 通知消失，离开 1.5 秒后暂停 |
| 6. 进一个未开播的直播间，按画中画按钮进系统画中画，等主播开播 | 画中画里自动开始播放（和现在一样） |

## 风险和注意

- `refreshDetail` 里不 `load()` 时要照样把新的标题、人数、状态合进 `_room`（`mergeFrom`），否则回来时画面上还是旧的“未开播”文字。
- `_startWhenBack` 和用户点“刷新”交错：回来时用户正好点了刷新，会 `load()` 两次；`load()` 有 `_epoch` 丢弃旧回答（`:362`、`:396`），可以接受，但测试里别依赖次数。
- 画中画：Android 进画中画时 Flutter 报 `inactive`，偶尔会先报一次很短的 `hidden`；`mayStartInBackground` 只看 `_hidden`，而 `onHidden` 的 1.5 秒去抖只管暂停。要确认进画中画时 `_hidden` 不会长时间为真（看 `PictureInPicture.active`，必要时 `mayStartInBackground` 在画中画时直接为真）。
- `audio_service` 在暂停时把前台服务降级（`androidNotificationOngoing: true`）；后台里从暂停回到播放时它会再请求前台，Android 12+ 可能拒绝（`ForegroundServiceStartNotAllowedException`）。拒绝时通知仍在、按钮能用，唤醒锁（`BackgroundKeepAlive`）仍持有；在 K90 上用 `adb logcat | grep -i ForegroundService` 看一次，结果写进记录。真的被系统收掉进程时，改成后台断流期间把通知保持在“播放中”的样子（不降级），写进记录再定。
- 可能冲突的文件：`room_controller.dart`（C01.4、C01.6、E05.4 都改它，先后做）；`background_playback.dart`（G05.1 的音频焦点可能放在旁边）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/C01.5` 或本机工作区；提交信息以 `[C01.5]` 开头（英文）；不推 master。
- 提交前：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；测试数量（改之前失败几个）；改了哪些文件；画中画时 `_hidden` 的实际情况；后台从暂停回到播放时前台服务有没有被拒（logcat）；要在真机上看的；可能冲突的文件。
