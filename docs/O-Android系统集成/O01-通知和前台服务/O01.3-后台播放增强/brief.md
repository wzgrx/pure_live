# O01.3 后台播放增强：任务书

## 背景

- 来源：用户 2026-10-09：“4.设置-后台播放 这个功能需要增强，适配各种rom，小米、oppo等手机系统，确保功能全面强大、稳定没有bug”。随 4.1.0 发布，第一档。
- 现象：开着“后台播放”切到后台或锁屏，过一会儿直播停了（网络抖动、主播重推流、来电之后最明显），回到应用才继续；各家手机还要在系统里打开自启动、省电无限制等，用户不知道。
- 已经做过的：C01.2（媒体通知只在后台播放时显示）、C01.5（后台时未开播的房间开播后）、G05.1（音频焦点）、O04（通知和电池优化权限）、S02.2（K90 上看过媒体通知和权限流程）。

## 目标和验收

1. 先做根因审查，每条写进 `record.md`（文件:行）：现在的后台机制、各家系统和 Android 版本的限制、哪里会坏。
2. 后台播放时重连、重新加载、等开播、来电都不丢 `mediaPlayback` 前台服务；用户自己暂停才放掉前台服务、唤醒锁和 Wi-Fi 锁。
3. 后台断流按退避自动重试（有上限），网络回来立刻试；前台行为不变（用户点“重试”）。
4. 新的“后台播放设置”页：识别品牌和系统（`Build.MANUFACTURER`、MIUI/HyperOS/ColorOS/OriginOS 等属性），读得到的状态（通知、媒体通知类别、电池优化、后台限制、流量节省）显示出来；各家的项说明怎么改、跳到对应系统页，找不到就打开应用信息。
5. 新开关默认保持现在的行为（D-040）；3.x 的键不变（D-018）；翻译键不删（D-024）。
6. 回到前台：状态恢复，没有两份声音。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`、`docs/specs/UI.md`、`docs/DECISIONS.md`。
2. `docs/O-Android系统集成/README.md`、`O01`、`O04` 的说明；`docs/G-播放/README.md`、`G05.1`。
3. `apps/pure_live/lib/features/live_play/logic/background_playback.dart`、`audio_focus.dart`、`room_controller.dart`、`packages/live_player/lib/src/session.dart`。
4. `apps/pure_live/android/app/src/main/AndroidManifest.xml`、`MainActivity.kt`、`PermissionsPlugin.kt`；audio_service 0.18.19 的 `AudioService.java`。

## 范围

- 可以改：`features/live_play/logic/`、`features/settings/`（自成一体的子页面，不动设置页的滚动）、`platform/`、`android/app/src/main/kotlin/`、`packages/live_store` 的设置、`packages/live_ui` 的 `AppIcons`、翻译、文档。
- 不能改：菜单和弹窗的样子（A07.23）、滚动恢复（A11.6）；版本号、`assets/version.json`、`assets/releases.json`；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么 | 怎么算做完 |
|---|---|---|
| 1 | 根因审查 | `record.md` 第一部分 |
| 2 | 后台保活：`BackgroundKeeper`；通知、锁跟着它；重试和网络；Wi-Fi 锁；来电 | 测试（假时钟） |
| 3 | 后台播放设置页、原生通道、三个开关、一次提示 | 测试（假通道） |
| 4 | 真机：K90；其他品牌 | `verify.md` |

## 测试

- 单元：keeper（假时钟）、品牌识别和步骤、通道（假平台通道）、音频焦点。
- 组件：设置页（各家步骤、找不到页面的提示、开关、一次提示）、后台规则（真控制器和 session）。
- 测试里的定时器至少 1 秒；不访问真实平台。

## 真机验证

见 [verify.md](verify.md)。K90 上看 HyperOS；别的品牌写在 record.md“要别的手机看的”。

## 风险和注意

- 各家系统页的组件名会随版本变：每个列表最后都是应用信息。
- 离开应用后等开播、来电时通知显示“在播”（锁屏上是暂停按钮），这是为了保持前台服务（README S1）。
- 冲突文件：`settings_catalog.dart`、`settings_model.dart`（A11.6 也在改设置）、`background_playback.dart`、`live_play_page.dart`、翻译文件。

## 报告（中文，简洁）

每条做到没有；根因；测试数量；改了哪些文件；新设置和翻译键；要在真机上看的；需要维护者决定的；可能冲突的文件。
