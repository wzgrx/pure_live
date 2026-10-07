# G05.1 音频焦点：来电时暂停、拔耳机时暂停（3.x 用 audio_session）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：2026-10-07 docs v2 G 组核对（[G05 说明](../README.md)“已知问题”第 1 条：4.x 没有音频焦点，3.x 有；G02.1 的“留下的问题”也提过）。功能清点原来没有这一项，随本任务补 F-MINI-05（[inventory/FEATURES.md](../../../inventory/FEATURES.md) 第 8.4 节）
- 相关：媒体通知和后台规则 [C01.2](../../../C-直播间/C01-进房和房间逻辑/C01.2-直播间第二部分/README.md)、[C01.5](../../../C-直播间/C01-进房和房间逻辑/C01.5-后台时未开播的房间开播后/README.md)；播放会话 [G02](../../G02-会话和恢复/README.md)；多画面出声的格子 [N01](../../../N-多画面和投屏/N01-多画面/README.md)；Android 通知和前台服务 [O01](../../../O-Android系统集成/O01-通知和前台服务/README.md)；决定 D-001（3.x 是基线）、D-017
- 任务书：[brief.md](brief.md)

## 目标

和 3.x 一样，直播的声音懂得让路：

1. **来电**（以及闹钟、别的应用开始放音乐或视频这类“要独占声音”的情况）：直播暂停；通话结束、对方让出声音后自动继续（只恢复我们因为来电暂停的）。
2. **短暂的提示音**（导航语音、通知音这类“可以压低”的情况）：直播音量降到 20%，提示结束后恢复。
3. **拔耳机、蓝牙耳机断开**：直播暂停（不会突然从扬声器外放），不自动恢复，用户自己点播放。

现在 4.x 这三件事都不做：来电时直播声音和通话叠在一起（系统只帮忙压低媒体音量，不暂停）；通勤时耳机掉了直接外放。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`，文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 依赖 | `pubspec.yaml:74-76`：`audio_service`、`audio_service_win`、`audio_session` | `apps/pure_live/pubspec.yaml:20` 只有 `audio_service ^0.18.19`；`audio_session 0.2.4` 只是它带进来的间接依赖（`pubspec.lock:84-91`） | 应用直接依赖 `audio_session`（版本跟锁文件，不升级） |
| 配置和拿焦点 | `lib/player/core/live_audio_handler.dart:98-100` `_initSession`：`configure(AudioSessionConfiguration.music())`；开播时 `activateSession`（`lib/player/core/live_audio_service.dart:132-150` 的 `start`） | 没有；mpv 的 `ao=audiotrack,…`（`packages/live_player/lib/src/mpv_options.dart:114-126`）不请求焦点 | 进房开播时 `setActive(true)`，离开直播间 `setActive(false)` |
| 中断（来电、独占） | `live_audio_handler.dart:103-160`：`interruptionEventStream`，开始且类型 `pause` → 暂停并记下令牌，结束 → 用令牌恢复 | 没有 | 同 3.x：只恢复自己暂停的；用户在中断期间手动操作过就不自动恢复 |
| 中断（可以压低） | 同上，类型 `duck` → 音量 × 0.2，结束恢复 | 没有；手机上播放器音量固定 1（`apps/pure_live/lib/features/live_play/logic/room_controller.dart:551-556`），桌面用房间音量 | 压低到当前音量的 20%，结束恢复原音量 |
| 拔耳机 | `live_audio_handler.dart:163-175` `becomingNoisyEventStream` → 暂停（走通知的暂停命令） | 没有 | 同 3.x |
| 媒体通知 | 一直显示 | 只在后台播放或助眠时（C01.2），`_RoomAudioHandler`（`features/live_play/logic/background_playback.dart:251-271`）只接通知按钮 | 不变（音频焦点和通知分开，没有通知时也处理焦点） |
| 多画面 | `lib/modules/multiview/multiview_controller.dart` 不处理焦点 | 只有选中的一格出声（`features/multiview/logic/multiview_controller.dart:792-798` `setAudioFocus`，名字叫焦点，实际只是音量） | 第二阶段：多画面在播时也拿焦点，来电暂停全部格子、结束后恢复（3.x 没有，可选，见任务书） |

## 方案

- c1 依赖：`apps/pure_live/pubspec.yaml` 加 `audio_session: ^0.2.4`（锁文件版本不变）。
- c2 新类 `RoomAudioFocus`（`apps/pure_live/lib/features/live_play/logic/audio_focus.dart`）：构造时拿直播间的会话和控制器；依赖一个小接口 `AudioFocusPort`（`activate(bool)`、`interruptions` 流、`becomingNoisy` 流），真实实现包 `AudioSession.instance`（配置一次 `AudioSessionConfiguration.music()`），测试给假的。规则照 3.x：会话进入 `playing` 时 `activate(true)`；中断开始（`pause`）且在播 → `session.pause()`、记 `_pausedByFocus`；结束 → 有记录且期间用户没动过 → `session.resume()`；`duck` → `session.setVolume(当前 × 0.2)`，结束 → 恢复 `controller` 算出的音量；`becomingNoisy` → 暂停、清掉记录；离开直播间 `activate(false)`。
- c3 接线：`RoomRuntime`（`logic/room_runtime.dart:19`）多一个 `audioFocus`，`live_play_page.dart:266` 的 `_newRuntime` 建，`dispose` 释放；应用内小窗接手同一个运行时，自然跟着走。
- c4（第二阶段，可选）多画面：`MultiviewController` 在任一格在播时拿焦点，来电暂停全部格子、结束恢复（N 组的文件，开工前请维护者确认做不做）。
- c5 功能清点：F-MINI-05 本任务完成后改“完成”或“没验证”（看真机）。
- 不改：媒体通知的显示规则和按钮（C01.2）；后台规则（`RoomBackgroundPolicy`）；手机上音量由系统媒体音量决定的规则（A07）；设置（不加开关，3.x 也没有）。

## 验证

- 自动测试：新文件 `apps/pure_live/test/features/live_play/audio_focus_test.dart`（假的 `AudioFocusPort`：来电暂停和恢复、用户期间手动暂停后不恢复、压低和恢复、拔耳机暂停不恢复、离开直播间释放焦点）。
- 真机：K90 上来电（用另一部手机打）、导航语音（或别的应用播一段声音）、拔有线或断开蓝牙耳机（任务书“真机验证”）；做之前“未开始”。

## 留下的问题

- 电视、Windows、Linux 的音频焦点不在本任务（`audio_session` 在这些平台基本是空实现；X 组做到时再看）。
- 录制不受影响（不出声）。
