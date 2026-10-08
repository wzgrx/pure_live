# C01.5 后台时未开播的房间开播后不自动出声，后台播放补出媒体通知：记录

- 日期：2026-10-08
- 执行者：Claude（Opus 5.5）
- 分支和提交：本机工作区，`f357fd38d`（两个阶段一个提交）
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 | 做了 | `RoomBackgroundPolicy.onHidden` 记 `_playingWhenHidden`（`opening`/`buffering`/`playing`）；`mayStartInBackground = !_hidden \|\| PictureInPicture.active.value \|\| (_playingWhenHidden && _continues)`：画中画时直接为真（任务书“风险”里说的短暂 `hidden`） |
| c2 | 做了 | `LiveRoomController.mayAutoStart`、`takeStartWhenBack()`；`refreshDetail` 两处 `load()` 不允许时只 `mergeFrom` 更新房间、记 `_startWhenBack`；`load()` 清掉这个标记（回来时用户正好点刷新不会多载一次）。**接线放在 `RoomBackgroundPolicy.start()` 里**（`dispose` 时解开），不在 `live_play_page.dart`：直播间和电视直播间（`tv_live_play_page.dart:151`）都用这个策略，一处接好两处都生效 |
| c3 | 做了 | `_syncNotification`：后台、已显示、允许后台继续时，会话停了（`stopped`/`idle`/`error`/`opening`）不 `hide`，改 `update(playing: false)`；回到 `playing`/`buffering` 时 `update(playing: true)`；同样的状态不重复发。新听 `enableBackgroundPlay` 的变化：后台里关掉 → `hide` |
| c4 | 做了 | 后台里第一次不显示的判断保留，注释写明原因（Android 12 起不能从后台启动前台服务；离开时没在播的房间也不会在后台开播） |
| 验收 1、2 | 做到 | |
| 验收 3 | 做到 | 测试里用“重新加载发现下播”模拟断流（假引擎做不出 `error` 而不触发重试计时器）；`error` 那一支和“未开播变能播”走同一个判断 |
| 验收 4 | 做到 | 画中画时 `mayStartInBackground` 为真 |
| 验收 5、6、7 | 做到 | `live_play_controller_test.dart` 的 B-24 用例没改照样通过 |

## 根因

- `refreshDetail`（`room_controller.dart` 原 `:775-781`）不知道应用在不在前台，60 秒刷新一发现能播就 `load()`；后台策略 `onHidden` 只在离开 1.5 秒时判断一次（原 `background_playback.dart:485`），之后才开始的播放没人管。
- `_syncNotification`（原 `:455-458`）只要会话不在播就 `hide`；后台里断流重载时会话被 `stop()`，通知被藏掉，而第一次显示又必须在前台（`:438`），所以后台再开播时通知回不来。

## 改了哪些文件

- `apps/pure_live/lib/features/live_play/logic/room_controller.dart`：`mayAutoStart`、`_startWhenBack`、`takeStartWhenBack`、`refreshDetail`、`load()` 清标记。
- `apps/pure_live/lib/features/live_play/logic/background_playback.dart`：`RoomMediaNotification.debugLog`（测试口子，`show`/`update`/`hide` 都记，`available` 为假也记；`show` 里内部发状态不再重复记）；`RoomBackgroundPolicy` 的 `mayStartInBackground`、`_playingWhenHidden`、接线、`onResumed` 里 `load()`、`_syncNotification`、听后台播放设置。

## 新设置、翻译键、门禁基线

- 无。

## 测试

- 新增 6 个（`apps/pure_live/test/features/live_play/live_play_more_test.dart` 的“C01.5: a room the app left”一组）：离开时未开播、后台开播不开引擎、回来后播放（后台播放关、开各一个）；画中画里照旧自动开播；后台播放中重新加载下播又开播，通知 `show true` → `update false` → `update true`，离开直播间 `hide`；后台里关掉后台播放 → `hide`；回到前台房间不播 → `hide`（同以前）。
- 改之前：6 个全部失败（编译不过）；阶段 1 的代码加上后，阶段 2 的 3 个仍失败（通知被 `hide`、重复 `update`）。
- 全部通过：`apps/pure_live` 908 个；`dart analyze --fatal-infos` 无问题。新用例的 `hiddenPauseDelay` 是 1 秒。

## 真机上要看的

- 任务书“真机验证”1～6 步。
- 第 4 步额外看：`adb logcat | grep -i ForegroundService`，后台从“暂停的样子”回到播放时，前台服务有没有被拒（`ForegroundServiceStartNotAllowedException`）；被拒时通知应该还在、按钮能用；如果进程被系统收掉，改成断流期间通知保持“播放中”的样子（不降级），再定。
- 第 6 步顺便看：进画中画时 Flutter 有没有报 `hidden`（`_hidden` 为真）。代码里画中画时直接允许开播，不依赖这一点；没在真机上确认过。

## 留下的问题

- 后台照样每 60 秒请求一次详情（README“留下的问题”），R05.1 测耗电后再定。

## K90 复查（2026-10-08）

- 进直播间后按 Home：通知栏有媒体通知（封面、主播名、停止/暂停按钮）✓。后台时未开播房间开播后不出声没测（要等开播）。
