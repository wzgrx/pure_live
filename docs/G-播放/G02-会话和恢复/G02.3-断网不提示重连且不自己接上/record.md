# G02.3 断网时播放器不提示重连、报“解码失败”、恢复后不自己接上：记录

- 日期：2026-10-08
- 执行者：Claude（Opus 5.5）
- 分支和提交：本机工作区，`bd6ab89d6`（代码和测试）；本记录和登记表另一个提交
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 “正在重连”没出现 | 做了 | 会话改为按播放位置判断直播流（不看 mpv 的标志）：走过之后停 4 秒就是第 1 次重连，停 12 秒算失败 |
| c2 失败原因 | 做了 | 刷新地址也连不上 = 网络断了：不再换线路、不再换软解，最后发“网络已断开，恢复后会自动重连”；诊断分类忽略 URL |
| c3 网络恢复后自动接上 | 做了 | 用“放弃前一直在看网络”的办法（每 2 秒问一次平台），没有接 `connectivity_plus`：只断测试包时系统网络状态不变，靠它收不到恢复 |
| 先写失败的测试 | 做了 | 5 个会话测试、2 个诊断测试在改代码前失败（见“测试”） |

验收：

| 验收 | 结果 |
|---|---|
| 1. 断网 10 秒内“正在重连（第 1 次）”和“换线路”，之后递增 | 自动测试过：最后一次前进后 4 秒出第 1 次；之后每看一次网络加 1。界面（A07.10）没改，“换线路”照旧在多线路时出现。待真机 |
| 2. 一直连不上时原因是网络 | 自动测试过：网络断后 20 秒发 `network_lost`，失败页原因“网络已断开，恢复后会自动重连”。按 K90 那种请求挂住不回的情况，断网后约 45～50 秒出失败页。待真机 |
| 3. 恢复后 10 秒内自己接上 | 自动测试过：失败页期间每 2 秒问一次（每次最多等 5 秒），一回答就重开，画面走起来才算接上。待真机 |
| 4. 真正的解码失败仍报“解码失败” | 自动测试过：网络正常时两种解码都失败，仍发 `codec`，文字“当前播放器解码失败” |
| 5. 暂停、换清晰度、刷新不出“正在重连” | 自动测试过：暂停期间不看；继续播放、新打开的源要先走起来，之后停住才算 |

## 3.x 基线

- `v3.2.11:lib/player/core/player_manager.dart:2610-2638`：同样是“一次连续缓冲一个 12 秒期限”，缓冲结束就取消；重试轮次 0.75 秒、2 秒（`:305`）；之后报错停下。
- 3.x 的播放器没有监听网络恢复（全仓库没有 `onConnectivityChanged`，`Connectivity` 只用于移动网络提示），放弃后也要手动重试。本任务在这点上比 3.x 多做了一步（README 的目标）。

## 根因

K90 上没抓日志；下面是读代码和用假引擎复现得出的，每条都有失败的测试。

1. 只有转圈、没有“正在重连”（c1）：
   - 会话的卡住判定只看 mpv 的缓冲标志：`_onBuffering(false)` 取消 12 秒期限（原 `packages/live_player/lib/src/session.dart:652`），`_onPlaying(true)` 也取消（原 `:620`），下次缓冲再从头算（原 `:687-701`）。media_kit 的缓冲标志由 mpv 的 `core-idle` 和 `paused-for-cache` 两个属性一起改（`third_party/media_kit/lib/src/player/native/player/real.dart:1402-1427`），断网等数据时会来回翻，期限就一直往后推，画面停在“转圈、没字”（原画面还在，所以是 `pictureBuffering`）。测试“flipping flags do not postpone it”改前在第一处断言就失败：翻一次之后状态变回“播放中”，没有恢复。
   - 就算恢复开始了，重开后 mpv 一开始加载就说“在播”（`pause=no`，`MpvEngine.open` 末尾补发 `state.playing`，`packages/live_player/lib/src/mpv_engine.dart:190-191`），会话把它当成接上了：发“播放中、recovery 0”（原 `session.dart:624`），还把这条线路记成可用（原 `:613`）。假引擎复现的时间线：15 秒“第 1 次”→ 27 秒换线路 2 后立刻“播放中、0”→ 然后是没有“正在重连”的“正在连接直播流…”。
2. 报“解码失败”（c2）：
   - 诊断分类先查解码器关键词再查打开失败（原 `packages/live_media/lib/src/errors.dart:115-118`），而且是在整行里找，包括 mpv 写在行里的 URL（原 `:93`）；URL 里常有 `codec`、`decode` 这类字（虎牙的 `codec=264`），一行“打开某某地址失败”就成了解码失败。
   - 恢复步骤对“源/卡住”类失败也走软解（原 `session.dart:915-929`），而解码类失败不走刷新、线路和重试轮次，直接发出去（原 `:932-933`）：断网时只要中间混进一条被认成解码的诊断，很快就以“当前播放器解码失败”结束，线路停在 2。
3. 恢复网络后不自己接上（c3）：发出错误（原 `session.dart:1004-1010`）以后会话什么也不做，也没有任何地方看网络回来没有；重试轮次只有 0.75 秒、2 秒两次。
4. 顺带：发出错误后引擎再报“没在播”，`_onPlaying(false)` 会把失败页改成“暂停”（原 `session.dart:633`），失败页可能自己消失。

## 改了哪些文件

- `packages/live_player/lib/src/session.dart`：
  - 直播流按位置判断：`_onPosition`（`:782`）、`_armMoveWatchdog`（`:886`，一个定时器、按剩余时间重排，标志变化不推迟也不结束）、`_noticeStall`（`:919`，停 4 秒先显示第 1 次，`_recover` 不再重复加 1）；
  - 恢复中重开的源要走起来才算接上（`:695` 起，`_awaitingMove`）；
  - 网络断了：`_tryRefresh` 里刷新因为没人回答而失败就进入断网（`:1131`），`_enterOffline`、`_probe`（`:1228`，每次一个尝试；一回答就带新预算重开）、`_publishOffline`（`:1279`，发 `network_lost` 后继续看）；暂停、重开、停止都会结束断网状态；
  - `_onPlaying(false)` 不再把失败改成暂停；
  - `SessionTimings` 新增 `stallNotice`（4 秒）、`offlineGrace`（20 秒）、`networkProbe`（2 秒）、`networkProbeTimeout`（5 秒）。
- `packages/live_player/lib/src/state.dart`：`recovery` 的说明。
- `packages/live_media/lib/src/errors.dart`：`classify` 去掉 URL 再判断（`:153`），传输类加上 “connection aborted / software caused connection abort / broken pipe / no route to host”；新增 `isNetworkFailure`（`:290`）和 `networkLostCode`（`:284`）。
- `apps/pure_live/lib/shared/rooms/room_texts.dart:178`：`network_lost` 的文字。
- `apps/pure_live/lib/features/live_play/logic/reconnect_watch.dart`：只改说明（逻辑不用改：会话自己报恢复）。
- 翻译：`playback_network_lost`（zh、en）。

## 新设置、翻译键、门禁基线

- 新翻译键 `playback_network_lost`：“网络已断开，恢复后会自动重连” / “Network lost; playback resumes by itself when it is back”。
- 没有新设置，没有改门禁基线。

## 测试

- `packages/live_player/test/session_test.dart` 新增 5 个（G02.3 组）：卡住时 4 秒内显示第 1 次、标志来回翻不推迟、重开后“在播”不算接上；断网时次数递增、不换线路和解码、失败原因是网络、恢复后自己播放；刷新请求挂住不回也算断网、一分钟内出失败页；网络正常时的解码失败仍是解码失败；暂停、等待中的继续播放、换线路不算重连。改前 3 个失败（另 2 个守住原有行为）。
- `packages/live_media/test/errors_test.dart` 新增 3 个：URL 里的字不算数（改前失败）、被系统断开的连接算传输失败（改前失败）、`isNetworkFailure`。
- `apps/pure_live/test/features/live_play/`：`live_play_room_test.dart` 新增 1 个（会话 + `ReconnectWatch`：重连次数、失败文字、恢复后播放），`live_play_states_test.dart` 加了 `network_lost` 和解码失败的文字断言。
- 假引擎加了“位置前进”（两个测试支持文件）。
- 全部通过：`live_media` 43、`live_player` 41、`live_record` 43、`apps/pure_live` 893；`dart format`、`dart analyze --fatal-infos`、`check_ui_structure.py`、`docs.py --check` 通过。

## 真机上要看的

K90，测试包 `com.mystyle.purelive.v4dev`，哔哩哔哩房间（多线路）播放中：

1. `adb shell cmd connectivity set-chain3-enabled true`；`adb shell cmd connectivity set-package-networking-enabled false com.mystyle.purelive.v4dev`。
2. 10 秒内：画面变暗，“正在重连（第 1 次）”和“换线路”。
3. 继续断 60 秒：次数递增（每几秒加 1）；大约 45～50 秒时变成“播放已中断 · 网络已断开，恢复后会自动重连”，不是“解码失败”，线路不乱换。
4. 恢复：`adb shell cmd connectivity set-package-networking-enabled true com.mystyle.purelive.v4dev`；10 秒内出“正在重连（第 N 次）”后自己播放，提示消失，不用点“重试”。
5. 再断一次再恢复（S02.5 1A-06 的第二次）：仍然正常。
6. 暂停 20 秒再继续、换清晰度、刷新：没有“正在重连”（1A-05）。
7. 弱网时（可选）：几秒的卡顿只转圈；超过 4 秒会显示“正在重连（第 1 次）”，画面一走就消失。
8. 最后 `adb shell cmd connectivity set-chain3-enabled false`。

如果第 2 步没有出“正在重连”：抓 `adb logcat` 里 mpv 的 `time-pos` 是否还在变（本修复假设 Android 上 mpv 卡住时位置不前进）。

## 和其他任务的关系

- [G02.2](../G02.2-缓冲状态对账/README.md)（缓冲状态对账，未开始）：本任务已经让会话读直播的位置事件（`_onPosition`），G02.2 的“位置在走时补回播放中”可以接在这里做。
- 并行的 C01.5（后台播放）、G01.3（映客画质）：本任务没改 `room_controller.dart` 和后台播放；后台不允许播放时直播间会调 `session.pause()`，暂停会结束断网状态，回到前台 `resume()` 走重试，和原来一样。

## 留下的问题

- 没有接系统网络变化（`connectivity_plus`）：真断 Wi-Fi 时也是靠每 2 秒问一次平台发现恢复，最多慢几秒。
- 没有刷新器的播放（回放、网络电视的回看）不进入断网状态，仍按原来的步骤结束。

## K90 复查（2026-10-08，master 820129343）

- 注意：K90 的单应用断网（`OEM_DENY_3`）只挡新连接，已经连着的视频流照样在走；只断网、不动画面时画面会一直播，弹幕连接断开（显示“多次重连失败”）。所以先断网、再换到线路 2 制造新连接：
  - 4 秒“正在重连（第 3 次）”+“换线路”，之后次数一直加 ✓；
  - 约 20 秒变成“播放已中断 · 网络已断开，恢复后会自动重连” ✓（不是“解码失败”）；
  - 恢复网络后约 2 秒自己接上，画面在走，弹幕也重新连上 ✓。
- 次数涨得比较快（12 秒到第 9 次），看着像在狂试；能用，先不改。
- 暂停、换清晰度时不出“正在重连”只有自动测试。
