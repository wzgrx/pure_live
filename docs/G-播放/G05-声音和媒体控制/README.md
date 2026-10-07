# G05 声音和媒体控制

直播的声音这一侧：纯音频（只听不看）、播放器音量和每个房间记住的音量、全局静音、系统媒体会话（通知栏和锁屏的播放控制、耳机按键）、音频焦点（来电、别的应用出声、拔耳机）。

## 范围

- 包括：
  - 纯音频的播放部分：`PlaybackSession.setAudioOnly`（`packages/live_player/lib/src/session.dart:309-314`，不重开）、`MpvEngine._applyAudioOnly`（`mpv_engine.dart:230-258`：Android 关掉控制器的视频输出、桌面 `vid=no`，切回视频等出画面最多 2.8 秒）、纯音频时不做画面停住检测（`session.dart:312`、`:735`）。
  - 音量规则：`packages/live_player/lib/src/policies.dart` 的 `roomVolumeKey`（`:12`，3.x 键名）、`roomVolume`（`:17-32`）；直播间 `room_controller.dart` 的 `_volume`（`:551-568`）、`setVolume`、`saveVolume`（`:575-588`）；设置 `globalVolumeMute`（`settings.dart:649`）、`roomVolumes`（`:652`）、`defaultMobileVolume`、`defaultDesktopVolume`（`:631`、`:640`）。
  - 系统媒体会话：`features/live_play/logic/background_playback.dart` 的 `RoomMediaNotification`（audio_service，`:299` 起）、`mediaControls`（中文按钮标签）、`_RoomAudioHandler`（通知的播放、暂停、停止接到直播间）。
  - 音频焦点（来电、通知音、导航语音时暂停或压低；拔耳机、蓝牙断开时暂停）——**4.x 还没有**，G05.1。
  - 后台继续播放的规则 `shouldContinueInBackground`（`policies.dart:7`）。
- 不包括（归哪里）：
  - 纯音频封面、音量面板、静音按钮的样子 → A07（A07.10 的“纯音频已暂停”、A07.6 的面板）；画面上下滑调音量和亮度的手势 → C01.2（`player_gestures.dart`）、`DeviceControls`（媒体音量和窗口亮度的原生通道）。
  - 后台、助眠、定时关闭什么时候暂停和恢复（`RoomBackgroundPolicy`）、唤醒锁 → C01.2、O03；通知权限和电池优化的申请 → O03.2；通知栏图标 → A14。
  - 多画面里每格的声音（只有选中格出声）→ N01。

## 现状：做到哪、怎么工作的

- 用户看得到的：
  - 上栏耳机按钮切纯音频：画面换成封面和“纯音频播放中”，流不断；切回视频时等第一帧画面再揭开（不露黑底）。开“自动助眠”时进房即纯音频并开始定时（`room_controller.dart:320-324`），切回视频结束助眠。
  - 手机上播放器音量固定 1（`room_controller.dart:555`），音量由系统媒体音量决定：画面右侧上下滑、音量面板、音量键改的都是系统媒体音量（A07 的确认改动）；电脑上用播放器音量，每个房间记住（键 `room_vol_<平台>_<房间号>`，存在 `roomVolumes`）。全局静音开时进房音量 0。
  - 开着后台播放或助眠时，离开应用后继续有声音，通知栏有直播间标题、主播名、封面，“暂停”“停止”两个按钮（中文，读屏读中文，U.14 c6）；耳机按键和锁屏控制走同一个媒体会话；外接键盘的媒体键也能播放暂停（C02.1 c6）。
  - 来电时：**声音不会自动停**（见“已知问题”）。
- 内部怎么工作：
  - 纯音频：直播间 `setAudioOnly`（`room_controller.dart:591-601`）→ 会话 `setAudioOnly`（发状态、取消画面看门狗）→ 引擎 `_applyAudioOnly`；打开时如果是纯音频，`EngineMedia.audioOnly` 让引擎打开后立即关视频（`mpv_engine.dart:181-185`）。
  - 音量：打开时 `PlaybackRequest.volume = _volume()`；会话在引擎创建后和每次打开时设音量（`session.dart:228`、`:418`）。
  - 媒体会话：`RoomMediaNotification.show`（`background_playback.dart` 第 156 行起的方法）第一次调用时 `AudioService.init`（通道 `com.mystyle.purelive.audio`、图标 `drawable/ic_stat_playback`），把直播间的 `play`、`pause`、`stop` 接到处理器；`update` 按播放状态换按钮；`hide` 在离开直播间时清掉。只在后台播放或助眠打开时显示（C01.2 确认的改动；3.x 一直显示）。
- 完成度（和 3.x 对照）：
  - 一致：纯音频不重开、切回等画面；每房间音量键名和规则；全局静音；后台继续的规则；通知内容和按钮。
  - 确认过的改动：手机上音量面板改系统媒体音量（A07）；媒体通知只在后台播放或助眠时显示（C01.2）；按钮文字中文（U.14 c6）；状态栏图标单色（U.14 c2）。
  - 还缺：音频焦点（3.x 有，4.x 没接）→ G05.1。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_player/lib/src/session.dart` | `setAudioOnly`（`:309-314`）、`setVolume`（`:332-337`）；打开时设音量（`:228`）、新引擎设音量（`:418`）；纯音频时不开画面看门狗（`:735`） |
| `packages/live_player/lib/src/mpv_engine.dart` | `setVolume`（`:225`，0～1 换成 mpv 的 0～100）、`setAudioOnly` / `_applyAudioOnly`（`:228-258`）、打开时按 `media.audioOnly` 关视频（`:181-185`）；Android 的 `ao=audiotrack,aaudio,opensles,`（`mpv_options.dart:114-126`） |
| `packages/live_player/lib/src/policies.dart`（32 行） | `shouldContinueInBackground`（`:7`）、`roomVolumeKey`（`:12`）、`roomVolume`（`:17`） |
| `apps/pure_live/lib/features/live_play/logic/room_controller.dart` | 助眠进房即纯音频（`:320-324`）、`_volume`（`:551`，手机固定 1）、`setVolume`、`saveVolume`（`:575-588`）、`setAudioOnly`（`:591`）、`setSleepTimer` |
| `apps/pure_live/lib/features/live_play/logic/background_playback.dart`（517） | `DeviceControls`（媒体音量、窗口亮度，`pure_live/device_controls`）、`BackgroundKeepAlive`（唤醒锁和 Wi-Fi 锁）、`_RoomAudioHandler`、`mediaControls`、`RoomMediaNotification`、`RoomBackgroundPolicy`（离开应用 1.5 秒后暂停，除非后台播放或助眠） |
| `apps/pure_live/lib/features/live_play/dialogs/room_dialogs.dart` | `RoomVolumePanel`（`:275`，手机上是系统媒体音量，电脑上是房间音量） |
| `apps/pure_live/lib/features/multiview/logic/multiview_controller.dart:766-780` | 多画面每格的音量（用 `defaultMobileVolume`） |
| `apps/pure_live/pubspec.yaml:20` | `audio_service ^0.18.19`（没有 `audio_session`） |

测试：`packages/live_player/test/options_test.dart`（后台规则和房间音量，移植 3.x 用例）、`session_test.dart`（纯音频时不判画面停住）；`apps/pure_live/test/features/live_play/` 的纯音频、音量面板、媒体通知按钮（`mediaControls`）用例。

## 3.x 基线

- `git show v3.2.11:lib/player/core/live_audio_handler.dart`：`_initSession`（`:98-176`）用 `audio_session` 配成音乐（`:100`）；`interruptionEventStream`（`:103`）：开始时“暂停”类中断（来电）暂停并记下要恢复、“压低”类（通知、导航）把音量降到 20%，结束时恢复播放或音量；`becomingNoisyEventStream`（`:163`）：拔耳机、蓝牙断开时暂停。`pubspec.yaml:74-76`：`audio_service`、`audio_service_win`、`audio_session`。
- `lib/player/core/live_audio_service.dart`：媒体通知一直显示（4.x 改为后台播放或助眠时）。
- `lib/player/core/live_room_volume_manager.dart:12-23`：每房间音量、手机默认 `defaultMobileVolume`（0.5）；`lib/player/adapters/media_kit_adapter.dart:615-620`：打开后手机强制音量 1.0、电脑用房间音量。
- 纯音频：`lib/modules/live_play/widgets/video_player/video_controller.dart:1246`（F-ROOM-19）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| **没有音频焦点**：来电、别的应用播放声音时直播不暂停也不压低；拔耳机、蓝牙耳机断开时继续从扬声器外放。3.x 用 `audio_session` 做了这三件事（`live_audio_handler.dart:98-176`），4.x 没有引 `audio_session`，`_RoomAudioHandler` 只接了通知按钮。功能清点（`inventory/FEATURES.md`）里没有这一项，G02.1 的“留下的问题”提过 | `apps/pure_live/lib/features/live_play/logic/background_playback.dart:251-271`、`apps/pure_live/pubspec.yaml:20` | 比 3.x 少：通勤拔耳机时外放、来电时直播声音和通话叠在一起（Android 会给通话自动降低媒体音量，但不暂停） | [G05.1](G05.1-音频焦点/README.md)（2026-10-07 登记，第二档，中）；功能清点已补 F-MINI-05（缺失） |
| `defaultMobileVolume` 在直播间不起作用：手机上播放器音量固定 1（照 3.x 适配器），这个设置只被多画面读 | `room_controller.dart:555`、`multiview_controller.dart:778` | 设置页的“手机默认音量”只影响多画面，用户可能以为影响直播间 | 照 3.x（3.x 也是这样）；设置说明文字是否要写清，交给 A11.3 |
| 纯音频时 mpv 仍在解码视频（Android 只关输出，`setVideoOutputEnabled(false)`） | `mpv_engine.dart:232-233` | 纯音频省电不如 `vid=no`；但切回视频不用重开、更快（3.x 的取舍） | 照 3.x；R05.1 测耗电时一起看纯音频 |
| 媒体通知只在后台播放或助眠时显示，前台播放时耳机按键依赖 Flutter 的媒体键（C02.1 c6） | `background_playback.dart:393` 起 | 前台时蓝牙耳机按键能不能暂停要看系统把按键给谁 | 没有 K90 记录；建议并入 S02.6 |
| 纯音频切换、媒体通知暂停和停止的真机结果：S02.2 看过通知内容和按钮（通过），纯音频（CHECKLIST 第 1 节第 9 条）没结果 | [CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 9、10 条 | — | 并入 S02.6 |

## 相关决定和规范

- D-001：音量键名、后台规则、纯音频行为照 3.x。
- D-012：暂停状态的界面（纯音频已暂停）。
- D-018：`room_vol_*`、`globalVolumeMute`、`defaultMobileVolume`、`defaultDesktopVolume`、`enableBackgroundPlay` 键名和含义不变。
- [specs/UI.md](../../specs/UI.md) 附录 A（返回链、手势）；U.14（媒体通知中文按钮、单色图标，见 A14）。

## 测试和验证

- 自动测试：`cd packages/live_player && flutter test test/options_test.dart test/session_test.dart`；`cd apps/pure_live && flutter test test/features/live_play/`。缺的：音频焦点（功能没做）；媒体会话只测了按钮列表，没测处理器的回调（要 audio_service 的平台通道）。
- 真机：[S02 的真机清单](../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 1 节第 9 条（纯音频、定时关闭、自动助眠）、第 10 条（后台播放和通知，S02.2 通过）、第 15 条（房间音量记住）；音频焦点做了以后加一条“播放中来电、拔耳机”。

## 路线

1. [G05.1](G05.1-音频焦点/README.md)（第二档，中，两个阶段）：音频焦点——来电暂停和恢复、提示音压低、拔耳机暂停（3.x 有、用户每天会碰到拔耳机）。
2. 纯音频和前台耳机按键的真机结果随 S02.6 补。
3. 以后：纯音频的耗电（R05.1 一起测）；Windows 的系统媒体控制（3.x 有 `audio_service_win`，X01）。新想法写进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [G 播放](../README.md)。

- 代码：`packages/live_player`、`logic/background_playback.dart`
- 进度：`░░░░░░░░░░░░░░░░░░░░` 0%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| G05.1 | 音频焦点：来电时暂停、拔耳机时暂停（3.x 用 audio_session） | 功能 | 未开始 | — | — | [设计或说明](G05.1-音频焦点/README.md)、[任务书](G05.1-音频焦点/brief.md) |

## 还没完成的

- **G05.1 音频焦点：来电时暂停、拔耳机时暂停（3.x 用 audio_session）**（未开始，第二档，规模 中）
  - 阶段：来电和别的应用：拿焦点、暂停和恢复、压低音量 → 拔耳机和蓝牙断开时暂停；多画面出声的那一格
  - 来源：docs v2 G 组核对（G05 说明“已知问题”；功能清点补 F-MINI-05）

<!-- docs:生成结束 -->
