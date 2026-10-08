# G05.1 音频焦点：记录

- 日期：2026-10-08
- 执行者：Claude（Opus 5.5）
- 分支和提交：本机工作区；代码、测试和本记录一个提交（`[G05.1]`），两个阶段一起合并
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 依赖 | 做了 | `apps/pure_live/pubspec.yaml` 加 `audio_session: ^0.2.4`；锁文件不变（0.2.4，原来就是 `audio_service` 带进来的） |
| c2 `RoomAudioFocus` + `AudioFocusPort` | 做了 | 另加两条：别的应用永久拿走焦点（Android 的 `AUDIOFOCUS_LOSS`，`audio_session` 报 `unknown`）时暂停、不自动恢复，再播放时重新拿焦点（3.x 忽略 `unknown`，于是网易云一开直播照样出声，和 README 目标 1 不符）；中断结束时如果直播间现在不能播（后台且没开后台播放），等回到前台再恢复 |
| c3 接线 | 做了 | `RoomRuntime.audioFocus`（可空），`live_play_page.dart` 的 `_newRuntime` 只在 Android 建；`dispose` 时释放焦点；应用内小窗接手同一个运行时 |
| c4 多画面 | 没做 | 任务书写明“开工前请维护者确认”，没有确认，留着 |
| c5 F-MINI-05 | 做了 | “缺失”→“没验证”（等 K90） |

验收：

| 验收 | 结果 |
|---|---|
| 1. 来电暂停，结束后只恢复这次暂停的 | 自动测试过；待真机 |
| 2. 中断期间用户点了播放或暂停，结束后不动 | 自动测试过（用户期间点播放再暂停；用户来电前已暂停） |
| 3. 提示音压低到 20%，结束恢复 | 自动测试过：恢复到压低前的音量；压低期间用户改了音量就留着用户的 |
| 4. 拔耳机暂停、不自动恢复 | 自动测试过（拔耳机清掉来电的恢复记录）；待真机 |
| 5. 开播拿焦点、离开释放；小窗、后台、画中画同样生效 | 自动测试过拿和放；同一个运行时所以小窗、画中画跟着走；待真机 |
| 6. 没有新设置、新文字，通知规则不变 | 是 |
| 7. 多画面 | 没做（可选，等维护者决定） |

## 3.x 基线

- `v3.2.11:lib/player/core/live_audio_handler.dart:98-176`：`configure(music())`；中断开始 `pause` → 暂停并记令牌，`duck` → 音量 × 0.2；结束 `pause` → 用令牌恢复，`duck` → 恢复音量；`unknown` 什么也不做；`becomingNoisy` → 清令牌、暂停；事件排队按顺序执行（`:84-95`）。
- `lib/player/core/live_audio_service.dart:142`：开播时激活，失败只记日志。
- `lib/player/core/player_manager.dart:494-530`：令牌在用户期间操作过就作废。
- 保留了：三种事件、20% 比例、只恢复自己暂停的、激活失败不影响播放、按顺序处理。

## 根因（缺口）

- 4.x 没有任何音频焦点代码：全仓库没有 `AudioSession`、`requestAudioFocus`、`ACTION_AUDIO_BECOMING_NOISY`（Kotlin 也没有）；`audio_session` 只是 `audio_service` 的间接依赖（`pubspec.lock:84-91`）；`audio_service` 0.18 自己不请求焦点；mpv 的 `ao=audiotrack`（`packages/live_player/lib/src/mpv_options.dart`）也不请求。所以系统从不通知直播间来电、提示音或拔耳机。

## 改了哪些文件

- `apps/pure_live/lib/features/live_play/logic/audio_focus.dart`（新）：
  - `AudioFocusPort`（`activate`、`interruptions`、`becomingNoisy`）；
  - `SystemAudioFocus`：包 `AudioSession.instance`，`configure(music())` 只做一次；`available` 只在 Android 为真（测试在主机上跑，不碰插件）；
  - `RoomAudioFocus`：会话进入 `playing` 且没拿着焦点时拿（失败只记日志）；`pause` 类中断在出声时暂停并记下，结束时仍是暂停就恢复（不能播就等回前台）；`unknown` 暂停不恢复、下次播放重新拿；`duck` 压低、结束恢复；拔耳机暂停并清掉记录；状态离开“暂停”就作废记录（用户点了播放、换了房间、失败）；事件排队顺序执行；`dispose` 释放焦点。
- `apps/pure_live/lib/features/live_play/logic/room_runtime.dart`：`audioFocus` 字段，`dispose` 时释放。
- `apps/pure_live/lib/features/live_play/live_play_page.dart`：`_newRuntime` 建 `RoomAudioFocus`；“现在能不能播”= 后台规则的 `mayStartInBackground` 或者开了后台播放/助眠（`shouldContinueInBackground`），没改 `RoomBackgroundPolicy`。
- `apps/pure_live/pubspec.yaml`：`audio_session: ^0.2.4`。
- `docs/inventory/FEATURES.md`：F-MINI-05 和统计。

## 和后台规则同时触发时

- 先焦点暂停、再进后台：后台规则 1.5 秒后看到已经暂停，不记“自己暂停的”；来电结束时如果允许后台播放就直接恢复，不允许就等回前台由焦点恢复一次（测试“the call ends while the room may not play in the background …”）。
- 先进后台被后台规则暂停、再来电：焦点看到已经暂停，不记，结束时不动；回前台由后台规则恢复。两边各恢复自己的，不会恢复两次。

## 新设置、翻译键、门禁基线

- 没有新设置、没有新翻译键、没有改门禁基线。
- 新依赖 `audio_session ^0.2.4`（理由：3.x 用它处理来电、提示音、拔耳机；版本和锁文件里原有的间接依赖一致，不引入新包）；`tools/gate/check_deps.py` 通过。
- 没有跑 `flutter build apk`（这次不构建 APK）；`audio_session` 的原生部分原来就随 `audio_service` 编进包里（锁文件没变），风险小，维护者构建 profile 包时会编到。

## 测试

- 新文件 `apps/pure_live/test/features/live_play/audio_focus_test.dart`，9 个：开播拿焦点、暂停再播不重复拿、离开释放；来电暂停并恢复；中断期间用户点了播放和暂停不恢复；用户先暂停的不被来电结束启动；压低到 20% 并恢复、期间用户改的音量保留；激活失败照常播放；别的应用永久拿走焦点暂停不恢复、再播放重新拿；拔耳机暂停、之后不恢复；来电结束时不能播则回前台恢复一次。功能是新的，改前这些用例不存在（文件编译失败）。
- 全部通过：`apps/pure_live` 929；`dart format`、`dart analyze --fatal-infos`、`check_ui_structure.py`、`check_deps.py`、`docs.py --check` 通过。

## 真机上要看的

K90，测试包 `com.mystyle.purelive.v4dev`，任务书“真机验证”的 7 步：

1. 在播的直播间，用另一部手机打 K90：响铃时直播暂停。
2. 挂断：1～2 秒内继续播放。
3. 再来电，响铃时点一下播放（或暂停），挂断：停在最后的状态，不自动改。
4. 地图导航播一句（或别的应用放通知音）：播报时直播声音明显变小，播完恢复。
5. 戴有线或蓝牙耳机，拔掉或关掉：暂停，扬声器不外放，之后不自己继续。
6. 开着网易云音乐进直播间：音乐停下；离开直播间后音乐应用能继续。反过来在直播时打开音乐播放：直播暂停（本任务新加的，3.x 没有）。
7. 开“后台播放”，按 Home 后重复 1、2 步：同 1、2。没开后台播放时，挂断后直播停着，回到应用再继续。
