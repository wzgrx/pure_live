# A07.20 语音直播（猫耳FM、克拉克拉）画面换成房间封面：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（从 master `d24c6757b` 开始）
- 设计或说明：[README.md](README.md)

## 根因

- 封面层只看纯音频模式：`apps/pure_live/lib/features/live_play/player/player_view.dart:722-737`（改前）`_room.audioOnly` 为真才叠 `AudioOnlyCover`；小窗 `features/live_play/mini/mini_player.dart:219-223`（改前）同样只看 `audioOnly`。
- 猫耳FM 的流里是一路 16×16 的占位视频（`packages/live_core/lib/src/sites/missevan/missevan_api.dart:70-72` 不标纯音频，播放器照轨道来），克拉克拉是一路纯色或背景图；播放器把它当真画面拉满。没有任何地方判断“这不是真画面”。
- 附带：小窗按画面尺寸定比例（`features/live_play/logic/mini_window.dart` `expectedPictureSize`），16×16 会让小窗变成正方形。

## 做了什么

- c1：`features/live_play/logic/room_status.dart` 新增纯函数 `pictureIsPlaceholder(playback, voiceLive:)`：已知尺寸短边 ≤ 32（`placeholderPictureSide`）算占位；语音平台在尺寸报上来或开始播放（含暂停）后算没有真画面；尺寸未知且还在打开时不算（那时是加载状态）。
- 平台能力标记：`packages/live_core/lib/src/sites.dart` `SiteIds.voiceLive = {missevan, kilakila}`，`live_site.dart` `LiveSite.isVoiceLive`（和 `hasSuperChats` 同样的做法），界面不写平台名单。
- c2：直播间画面区的封面层改成“纯音频模式或没有真画面”（`player_view.dart`），没有真画面时 `AudioOnlyCover(voiceLive: true)` 写“语音直播”（新键 `live_play_voice_live`：zh“语音直播”、en“Voice live”），暂停时播放标下面也写“语音直播”；小窗（`mini_player.dart` `_MiniAudioCover`）同样处理，芯片写“语音直播”。纯音频模式优先（用户自己开的就照旧写“纯音频播放中”）。
- 封面为空时（猫耳会把占位封面去掉）用主播头像代替（`player_status.dart` `AudioOnlyCover`）。
- c3：封面外包 `IgnorePointer`，手势照旧落在画面的 `GestureDetector`；视频组件不动，照常解码，帧看门狗不受影响。
- 小窗比例：`expectedPictureSize` 不把占位尺寸当画面尺寸（回到声明尺寸或 16:9）。

## 测试

- `live_play_room_test.dart`：
  - `A07.20 c1: a short side of 32 or less is a placeholder…`（16×16、32×32、1920×32、144×256、33×33、未知；语音平台 1280×720、未知但在播、未知且在打开）。
  - `A07.20: a placeholder picture gets the room cover…`：16×16 时有封面和“语音直播”，换成 1280×720 后封面消失。
  - `A07.20: a voice platform gets the room cover over a full-size picture`：克拉克拉 1280×720 也有封面。
- `live_play_mini_window_test.dart`：浮窗里 16×16 时有封面和“语音直播”，1920×1080 时没有。
- 改之前：小窗用例失败（找不到“语音直播”）；直播间两个用例和判定函数（函数不存在）同样失败。改后 `live_core` 全部、`apps/pure_live` 全部通过。

## 真机

待 K90（README“验证”）：

1. 进一个猫耳FM 直播间：画面是房间封面（没有封面时是主播头像）、中间耳机和“语音直播”，有声音；点画面照常出控制层，暂停后播放标下面写“语音直播”。
2. 进一个克拉克拉直播间：同上。
3. 回到桌面开小窗（应用内小窗）：小窗是 16:9，封面上写“语音直播”。
4. 切到哔哩哔哩直播间：画面正常，没有封面。

## K90 复查（2026-10-08，master 660b488b7）

- 猫耳FM“登峰·寻光”：画面位置是房间封面加耳机图标和“语音直播”，测试包有一路音频在播 ✓。
- 克拉克拉“瑜唐”：同样是封面和“语音直播” ✓。
- 哔哩哔哩、虎牙等视频直播间照常显示画面（同一轮的其他检查里看过）✓。应用内小窗的比例没看。
