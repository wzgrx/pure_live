# G05.1 音频焦点：来电时暂停、拔耳机时暂停（3.x 用 audio_session）：任务书

## 背景

- 来源：2026-10-07 docs v2 G 组核对：4.x 没有音频焦点（[G05 说明](../README.md)“已知问题”），3.x 用 `audio_session` 处理来电、提示音和拔耳机（`lib/player/core/live_audio_handler.dart:98-176`）。维护者登记为本任务，并在功能清点补 F-MINI-05。
- 现象：
  1. 看直播时来电：接通后直播声音还在（系统把媒体音量压低一些），挂断后也没变化；3.x 会暂停、挂断后继续。
  2. 开着导航，导航播报时直播声音不降低（视系统而定）。
  3. 戴有线或蓝牙耳机看直播，耳机拔掉或断开：直接从扬声器外放；3.x 会暂停。
- 为什么现在做：第二档；比 3.x 少的功能，日常通勤会碰到。规模中（两个阶段各约 1.5 小时）。
- 已经做过的：媒体通知和按钮（C01.2、A14.1）；后台规则（C01.2）；多画面只让一格出声（N01.1）。

## 目标和验收

1. 直播间播放中来电（或别的应用要独占声音）：1 秒内暂停；通话结束（系统发中断结束）后自动继续播放，只恢复因为来电暂停的那次。
2. 中断期间用户自己点了暂停或播放：中断结束后不自动操作。
3. 提示音（导航、通知，可以压低的中断）：音量降到当前的 20%，结束后恢复到原来的音量（手机上是播放器音量 1，桌面是房间音量）。
4. 拔有线耳机、蓝牙耳机断开：暂停，不自动恢复。
5. 进房开播时请求焦点（别的音乐应用会停下）；离开直播间释放（别的应用能继续）。应用内小窗、后台播放、画中画里同样生效（同一个运行时）。
6. 没有新设置、没有新文字；媒体通知的显示规则不变；测试和门禁通过。
7. （第二阶段，可选）多画面在播时同样处理：来电暂停所有格子、结束后恢复。

## 现状（读代码得出，写文件:行）

- 依赖：`apps/pure_live/pubspec.yaml:20` `audio_service: ^0.18.19`；`pubspec.lock:84-91` `audio_session 0.2.4`（间接）；全仓库没有 `AudioSession`、`AudioFocus`、`ACTION_AUDIO_BECOMING_NOISY` 的代码（Kotlin 也没有）。
- 会话：`packages/live_player/lib/src/session.dart`：`pause`（`:266`）、`resume`（`:280`）、`setVolume`（`:332-337`）、状态流 `states`。
- 直播间：`apps/pure_live/lib/features/live_play/logic/room_controller.dart`：`_volume`（`:551-556`，手机固定 1，桌面房间音量）、`setVolume`（`:575`）；`apps/pure_live/lib/features/live_play/logic/background_playback.dart`：`RoomBackgroundPolicy`（`:393`，离开应用 1.5 秒后暂停、`_pausedByUs` 回来恢复，同样的“只恢复自己暂停的”写法可以参考）、`_RoomAudioHandler`（`:251-271`，通知按钮）、`RoomMediaNotification`（`:299`）。
- 运行时：`logic/room_runtime.dart:19` `RoomRuntime`（`controller`、`session`、`reconnect`、`background`、`orientation`、`playerConfig`；`dispose(keep:)` `:63`）；`live_play_page.dart:266-295` `_newRuntime`。应用内小窗 `FloatingRoom` 接手同一个运行时。
- 多画面：`apps/pure_live/lib/features/multiview/logic/multiview_controller.dart:766-798`（`_applyVolumes`、`setAudioFocus` 只改音量）。

## 3.x 基线

- `git show v3.2.11:lib/player/core/live_audio_handler.dart`：`_initSession`（`:98`）：`configure(const AudioSessionConfiguration.music())`（`:100`）；`interruptionEventStream`（`:103`）：开始 `pause` → `pauseForInterruption` 拿令牌（没有时直接暂停并记下原来在不在播），`duck` → 音量 × 0.2；结束 `pause` → 用令牌 `resumeFromInterruption`（或原来在播就播），`duck` → 恢复音量（`:131-158`）；`becomingNoisyEventStream`（`:163`）：清掉令牌、调暂停命令。所有事件排队按顺序执行（`_enqueueAudioEvent`，`:86-95`）。
- `lib/player/core/live_audio_service.dart:142`：开播 `start` 时 `activateSession`（失败只记日志，不影响播放，`:143-149`）。
- `lib/player/core/player_manager.dart:494-530`：`pauseForAudioInterruption` / `resumeFromAudioInterruption`（令牌：期间用户操作过就作废）。
- `pubspec.yaml:76` `audio_session: ^0.2.3`。
- 要保留：三种事件的处理和 20% 的压低比例；只恢复自己暂停的；激活失败不影响播放。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`（加依赖的规则：第 4 节；`tools/check_latest` 的依赖检查）。
3. 本文件夹的 `README.md`；`docs/G-播放/G05-声音和媒体控制/README.md`；`docs/C-直播间/C02-小窗、画中画、后台播放/README.md`；`docs/C-直播间/C01-进房和房间逻辑/C01.5-后台时未开播的房间开播后/brief.md`（同在 `background_playback.dart` 附近）。

## 范围

- 可以改：`apps/pure_live/pubspec.yaml`（加 `audio_session`）、`pubspec.lock`（只因加直接依赖变动，版本不变）；新文件 `apps/pure_live/lib/features/live_play/logic/audio_focus.dart`；`logic/room_runtime.dart`、`live_play_page.dart`（接线）；（第二阶段）`features/multiview/logic/multiview_controller.dart`；测试；`docs/inventory/FEATURES.md` 的 F-MINI-05（完成后改状态）；本文件夹。
- 不能改：媒体通知的显示规则、按钮和渠道（C01.2、A14.1、O01）；`RoomBackgroundPolicy` 的规则；音量规则（手机用系统媒体音量，A07）；`audio_service` 的版本和配置；设置；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 来电和别的应用：拿焦点、暂停和恢复、压低音量 | c1 依赖；c2 `RoomAudioFocus` + `AudioFocusPort`（真实实现包 `AudioSession.instance`，`configure(music())` 只做一次；事件按顺序处理）；会话 `playing` 时 `activate(true)`（失败只记日志）；中断 `pause`/`duck` 两类；c3 接到 `RoomRuntime`，`dispose` 时 `activate(false)` | `pubspec.yaml`、`audio_focus.dart`、`room_runtime.dart`、`live_play_page.dart`、`audio_focus_test.dart` | 验收 1、2、3、5、6 |
| 2 拔耳机和蓝牙断开时暂停；多画面出声的那一格 | `becomingNoisy` → 暂停、清掉记录；（可选，维护者开工前定）c4 多画面 | `audio_focus.dart`、（可选）`multiview_controller.dart`、测试；FEATURES F-MINI-05 | 验收 4、（7） |

每个阶段都要能单独合并（门禁通过、不留半截功能）。

## 测试

- 新文件 `apps/pure_live/test/features/live_play/audio_focus_test.dart`（假 `AudioFocusPort`：两个 `StreamController` 发 `AudioInterruptionEvent`、`becomingNoisy`，记录 `activate` 调用；用 `live_play_support.dart` 的假会话）：
  - 阶段 1：“an interruption that pauses pauses the room and resumes it when it ends”；“the user paused during the interruption: nothing resumes”；“a duck lowers the volume to 20 % and restores it”；“focus is asked for when playing starts and given back when the room is left”；“activation failing does not stop playback”。
  - 阶段 2：“unplugged headphones pause, and nothing resumes later”；（可选）多画面的对应用例放 `multiview_controller_test.dart`。
- 这些用例在改之前不存在（新功能）；不访问真实平台；测试里的定时器至少 1 秒（D-017），事件用流直接发，不靠计时器。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 进一个在播的直播间；用另一部手机给 K90 打电话 | 响铃时直播暂停 |
| 2. 挂断 | 1～2 秒内直播继续播放 |
| 3. 再来电，响铃时在直播间里点播放（或暂停）一下，再挂断 | 挂断后不自动改变（停在用户最后的状态） |
| 4. 打开地图导航，让它播一句（或用别的应用播一段通知音），同时开着直播 | 播报时直播声音明显变小，播完恢复 |
| 5. 戴有线耳机（或连蓝牙耳机）看直播，拔掉 / 关掉耳机 | 直播暂停，扬声器没有外放；之后不会自己继续 |
| 6. 开着网易云音乐等播放，进直播间 | 音乐停下（直播拿到焦点）；离开直播间后音乐应用可以继续（是否自动继续看该应用） |
| 7. 开“后台播放”，按 Home 后重复第 1、2 步 | 同第 1、2 步 |

## 风险和注意

- `audio_session` 的 Android 实现会自己 `requestAudioFocus`；和 `audio_service` 同时用时，3.x 是同样的组合，没有冲突记录；确认 `audio_service` 0.18 不会自己再请求一次（它不请求焦点）。
- 暂停和恢复要走会话（`session.pause` / `resume`），不要直接调引擎，否则状态和控制层不同步；恢复时会话可能已经因为断流在重连，判断状态再恢复。
- 压低音量期间用户拖音量条：恢复时用控制器当前算出的音量（`_volume()`），不是记下的旧值。
- 来电时 Android 也会把应用放到后台（通话界面盖上来）：和 `RoomBackgroundPolicy` 的 1.5 秒暂停可能同时发生，两边都只恢复自己暂停的，回到前台后不要恢复两次（测试里覆盖“先焦点暂停、再后台暂停”的顺序）。
- 可能冲突的文件：`room_runtime.dart`、`live_play_page.dart`（C01.5 也接线）；`background_playback.dart`（C01.5）；`multiview_controller.dart`（N01.2、E05.4）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/G05.1` 或本机工作区；提交信息以 `[G05.1]` 开头（英文）；不推 master。
- 提交前：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`；加了依赖跑一次 `flutter build apk --debug --target-platform android-arm64` 确认原生部分能编译。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；加的依赖和版本；测试数量；改了哪些文件；和后台规则同时触发时的处理；多画面做没做；要在真机上看的；FEATURES F-MINI-05 的新状态；可能冲突的文件。
