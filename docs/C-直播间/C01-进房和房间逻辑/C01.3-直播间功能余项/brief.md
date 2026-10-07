# C01.3 直播间功能余项：任务书

> 任务书 v2（2026-10-03）。自包含：读完这一页和“先读”里的文件就能开工。

## 背景

- **来源**：功能清点 `docs/inventory/FEATURES.md` 第 8 节。登记时照抄了清点第 1 版（2026-10-02）统计表里直播间一行的“6 项缺失、1 项有问题”：缺失的是 F-ROOM-21（退出时销毁播放器）、F-RT-05（快手 App 跳转）、F-RT-07（切换直播间里的刷新）、F-PORT-05（小窗跟随竖屏源比例）、F-PORT-06（竖屏诊断）、F-MINI-04（小窗弹幕预览），有问题的是 F-ROOM-13（屏幕常亮关不掉）；另有 F-ROOM-25（媒体键）部分、F-RT-01（投屏）没验证。
- **已经做过的**：这 7 项的代码在登记前后已经由别的任务做完：C02.1（F-ROOM-21、F-PORT-05、F-PORT-06、F-MINI-04、F-ROOM-25，合并 `d53df6d71`）、C03.1（F-RT-05、F-RT-07，同一合并）、O05.1（F-ROOM-13，合并 `1071b4e25`）。它们在登记表里是“完成”，但记录里“要在 K90 上看的”都**没有真机结果**；清点表第 8 节的统计行和几处“依据”也没跟着改。
- **读代码新发现的问题**：在未开播的直播间里离开应用（按 Home 或锁屏），过一阵主播开播，手机会在后台直接出声，通知栏没有媒体通知可以停。3.x 没有定时刷新，所以 3.x 没有这个问题；是 4.x 的 B-24（每 60 秒刷新、开播自动播放）带出来的。没在真机上确认过。
- **为什么现在做**：第二档。直播间是最常用的页面，清点表错了会误导后面所有人；后台突然出声是用户能明显感觉到的问题。和 O02.1（画中画复验）、S02.5 第一阶段放在同一次真机里做最省事。
- 相关决定：D-012（暂停后单击只显示控制层）、D-017（测试定时器至少 1 秒）、D-018（3.x 设置键不变）。

## 目标和验收

1. `docs/inventory/FEATURES.md` 第 8 节 46 行和第 8 节对应的统计行与代码一致：下面“现状”表里 9 行的“v4 现状”“依据”“备注”按现在的文件和任务写；F-ROOM-25 两列不再填反；统计表第 8 行和合计行重新数；第 2 节 F-AND-08 的依据改成现在的写法。`python3 tools/docs/docs.py --check` 没有新问题。
2. 9 个功能点在 K90 上逐条看过，结果和截图写进本文件夹的 `verify.md`（照 `docs/templates/verify.md`）；不通过的在 `verify.md` 写现象和根因线索，并告诉维护者开到哪个组（例如投屏开到 N02）。
3. 离开应用以后，未开播的房间开播时**不出声**；回到前台后自动开始播放。有一个改之前会失败的测试。
4. 前台时“开播自动播放”（B-24）、“离开应用 1.5 秒暂停、回来继续”、“开着后台播放时离开继续播”这三条已有行为不变，已有测试全部通过。

## 现状（读代码得出，写文件:行）

`apps/pure_live/lib/features/live_play/` 下的文件省略这个前缀。

| 编号 | 现在的实现 | 测试 |
|---|---|---|
| F-ROOM-13 屏幕常亮 | `packages/live_player/lib/src/screen_wake.dart`（`ScreenWake` 全应用一个计数）、`video_view.dart:79`（播放或缓冲且 `keepScreenOn` 时持有）；直播间 `player/player_view.dart:503-516`、应用内小窗 `mini/floating_window.dart:187` 传 `Settings.enableScreenKeepOn` | `packages/live_player/test/frame_rate_test.dart` 两个；`apps/pure_live/test/features/live_play/live_play_page_test.dart` 一个 |
| F-ROOM-21 播放器留给下一个房间 | `logic/player_standby.dart`；`live_play_page.dart:228`（`standby.take(config:)`）、`:491-496`（离开时 `runtime.dispose(keep:)`）；会话自己 45 秒后释放引擎 | `test/features/live_play/room_extras_test.dart` “c1: 播放器强制销毁 off keeps the player…” |
| F-ROOM-25 媒体键 | `live_play_page.dart:750-753`（`mediaPlay`、`mediaPause`、`mediaPlayPause`） | `room_extras_test.dart` “c6” |
| F-RT-05 快手 App | `buttons/room_menu_button.dart:55-58`（`externalRoomTarget` 的快手分支）、`:66`（`kuaishouStreamId`：详情的 `KuaishouRoomData.liveStreamId`，再看弹幕参数）、`:78`（`kuaishouAppLink`） | `room_extras_test.dart` “c1: Kuaishou opens its app…” |
| F-RT-07 切换直播间刷新 | `switch_room/room_switch_panel.dart:22`（`FollowsRefresher`）、`:110`（`RoomSwitchPanel.follows`）、`:409`（`_RefreshButton`）；`app/app.dart:86` 接到关注的 `refreshAll(visible: false)` | `room_extras_test.dart` “c2”、`room_switch_test.dart` |
| F-PORT-05 小窗比例 | `logic/mini_window.dart:83`（`miniPictureSize`：竖屏且不跟随时 9:16）；画中画 `mini/room_mini_window.dart:106-114`，自动画中画 `:270`，应用内小窗 `mini/floating_window.dart:125`、`:140` | `room_extras_test.dart` “c2” 两个 |
| F-PORT-06 竖屏诊断 | `player/portrait_diagnostics.dart`（`PortraitDiagnosticsBadge`）；`player/player_view.dart:557`、`:711` | `room_extras_test.dart` “c3” 两个 |
| F-MINI-04 小窗弹幕预览 | `apps/pure_live/lib/features/settings/playback_tiles.dart:690`（`PipDanmakuPreviewBinding`）、`packages/live_ui/lib/src/widgets/pip_danmaku_preview.dart` | `apps/pure_live/test/features/settings/settings_playback_test.dart` “phone: the preview above the rows…”、`packages/live_ui/test/settings_playback_widgets_test.dart` |
| F-RT-01 投屏 | `dialogs/stream_dialogs.dart:27`（`showStreamPanel`）、`:290`（`CastDevices`，每次搜索先申请本地网络权限 `:335`）；协议在 `packages/live_cast` | `live_play_more_page_test.dart` 投屏两个 |

清点表里过时的地方（第 1 阶段要改的）：

- 第 8 节 F-ROOM-13、F-ROOM-21、F-RT-05、F-RT-07、F-PORT-05、F-PORT-06 的“依据”还写“没人读”“没有快手分支”“`room_switcher.dart` 没有刷新”；F-ROOM-13 的备注“关掉设置后仍常亮”。
- F-ROOM-21 的备注“要不要保留这个开关需要用户定”：已定（C02.1 的 X1 = A，保留开关）。
- F-ROOM-25：“Android”列是“完成（2026-10-02，C02.1，记录）”，“v4 现状”列是“部分”，两列填反；依据还写“媒体键没有”。
- F-RT-06 的依据 `features/live_play/dialogs/room_switcher.dart` 已不存在，现在是 `features/live_play/switch_room/room_switch_panel.dart`（A07.13）。
- 统计表第 8 行“46 / 35 / 1 / 6 / 1 / 2 / 1”和合计行没跟着各行改；第 2 节 F-AND-08 的依据“Dart 侧没有调用”已过时（C03.1 的 `logic/predictive_back.dart`）。

后台出声的根因线索：

- `logic/room_controller.dart:325-327`：`start()` 里 `Timer.periodic(refreshInterval, …refreshDetail)`，页面在后台不会被销毁，定时器照跑。
- `:758-786` `refreshDetail`：`!playing && _stage != unplayable && fetched.isPlayableNow` 时直接 `await load()`（`:775-777`），`load` → `_startStream` → `session.open`，不看前后台。
- `logic/background_playback.dart:472-490` `RoomBackgroundPolicy.onHidden`：只在离开的那一刻起 1.5 秒计时，到时如果状态是 paused、idle、stopped 就什么也不做（未开播的房间正是 idle）；之后会话再开始播放，没有任何地方暂停它。
- `:431-438` `_syncNotification`：后台时不启动媒体通知（Android 不允许应用在后台启动前台服务），所以出声后通知栏也没有可以停的通知。
- `packages/live_player` 的 `setPresentationVisible(visible: false)` 只影响卡住检测（`session.dart:737`、`:743`），不阻止打开。

## 3.x 基线

- 3.x 没有定时刷新详情（4.x 的 B-24 是已批准的升级），未开播的房间不会自己开始，所以没有后台出声的问题。离开应用的规则在 `lib/player/core/playback_lifecycle_coordinator.dart`（1.5 秒，`:34`）：只暂停离开时在播的，回来恢复它暂停的。
- 各功能点的 3.x 位置见本文件夹 [README.md](README.md) 的对照表。要保留的行为：屏幕常亮的设置键 `enableScreenKeepOn`（默认开）、`useHardStopOnExit`（默认关）、`portraitPipFollowSource`（默认开）、`showPortraitDiagnostics`（默认关）键名和含义不变（D-018）；快手的 App 地址参数照 3.x（`room_external_opener.dart:193-200`）。

## 先读

1. `AGENTS.md`；`docs/PROCESS.md` 第 5 节（分阶段、停下）、第 8 节（合并审查）、第 10 节（真机）、第 14 节（规则）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 附录 A 第 8、10、12、16 条。
3. 本文件夹 [README.md](README.md)；[C02.1 的说明](../../C02-小窗、画中画、后台播放/C02.1-冷门的播放设置/README.md)和[记录](../../C02-小窗、画中画、后台播放/C02.1-冷门的播放设置/record.md)；[C03.1 的说明](../../C03-直播间工具/C03.1-直播间小项/README.md)和[记录](../../C03-直播间工具/C03.1-直播间小项/record.md)；[O05.1 的记录](../../../O-Android系统集成/O05-方向、刷新率、常亮/O05.1-屏幕常亮跟随设置/record.md)。
4. `docs/inventory/FEATURES.md` 的“怎么读”、统计表、第 2 节、第 8 节；[S02 的 CHECKLIST.md](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节。
5. 代码：`apps/pure_live/lib/features/live_play/logic/room_controller.dart`（`start`、`load`、`refreshDetail`）、`logic/background_playback.dart`（`RoomBackgroundPolicy`）；测试 `apps/pure_live/test/features/live_play/live_play_more_test.dart`（“leaving the app pauses unless background play is on”，:219）、`live_play_controller_test.dart`（“an offline room … starts by itself when the refresh finds it live (B-24)”，:178）。

## 范围

- 可以改：
  - `docs/inventory/FEATURES.md`（第 2 节 F-AND-08 一行；第 8 节；统计表第 8 行和合计行）。
  - 本文件夹：`README.md`（补“结果”）、`verify.md`（新建）、`record.md`（新建）。
  - `apps/pure_live/lib/features/live_play/logic/background_playback.dart`（方案 A）；选方案 B 时还有 `logic/room_controller.dart` 和 `live_play_page.dart` 的 `_newRuntime`。
  - `apps/pure_live/test/features/live_play/live_play_more_test.dart`（新用例）。
- 不能改：其他组的界面和逻辑；`packages/live_player`（会话的打开和暂停不改）；`MainActivity.kt`；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义；不加新设置；`docs/tasks.toml` 只在停下时按第 5.2 节改本任务那一段。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 清点表更正：逐行核对第 8 节 46 行，改“现状”里列的地方，重数统计 | `docs/inventory/FEATURES.md` | 9 行和统计行与代码一致；`python3 tools/docs/docs.py --check` 通过 |
| 2 | c2 真机核对（维护者在 K90 上做）：下面“真机验证”第 1～9 步 | 本文件夹 `verify.md` | 每步有结果和截图；不通过的列出现象和建议的去向 |
| 3 | c3 后台不自动出声：先写失败的测试，再按维护者选的方案改（建议 A：`RoomBackgroundPolicy` 记住离开时是否在播，离开后才开始打开或播放的立即 `pause()` 并记为 `_pausedByUs`，回到前台时 `resume()`；开着后台播放也一样） | `logic/background_playback.dart`、`test/features/live_play/live_play_more_test.dart` | 新测试改前失败、改后通过；`live_play_more_test.dart`、`live_play_controller_test.dart`、`live_play_mini_window_test.dart` 全部通过；真机第 10 步 |

第 1 阶段只改文档，可以先合并；第 3 阶段开工前请维护者在 A、B 里选一个（README“方案”c3）。

## 测试

- 修 bug 先写失败的测试（第 3 阶段），在 `live_play_more_test.dart` 里加：`'a room that comes on air while the app is away stays quiet until the app is back'`
  - 用文件里现成的 `controllerFor(FakeSite(...))`，`FakeSite` 先返回未开播的房间；`controller.start()` 后 `stage == RoomStage.offline`。
  - 建 `RoomBackgroundPolicy(controller:, settings: store.settings)`，调 `onHidden()`。
  - `FakeSite` 改成开播，**直接调 `controller.refreshDetail()`**（不要等 60 秒的定时器；需要计时的地方至少 1 秒，D-017）。
  - 断言：会话不是 `PlaybackStatus.playing`（方案 A 是 `paused`，方案 B 是没有打开）；`onResumed()` 后变成 `playing`。
  - 再测一遍开着 `Settings.enableBackgroundPlay` 的情况，结果相同。
- 回归：已有的“leaving the app pauses unless background play is on; coming back resumes”（`:219`）和 B-24 的“an offline room does not play; it starts by itself when the refresh finds it live”（`live_play_controller_test.dart:178`）不改断言、仍然通过。
- 第 1 阶段只有文档，跑 `python3 tools/docs/docs.py --check`。
- 不访问真实平台；用 `live_play_support.dart` 的 `FakeSite`、`FakeEngine`、`FakeDanmaku`。

## 真机验证（维护者在 K90 上做）

设备 Redmi K90 Pro Max（Android 17，HyperOS），测试包 `com.mystyle.purelive.v4dev`；每次点按前确认前台是测试包（本机用 `~/tools/pl-adb.sh`）；不碰 3.x 和正式包。截图缩到宽 540，放本文件夹 `verify/`。

| 步骤 | 期望 |
|---|---|
| 1. F-ROOM-13：系统设置里把自动锁屏改成 30 秒。应用 设置 → 视频 → 播放行为设置 →“屏幕常亮”开，进一个哔哩哔哩直播间播放，不碰手机 2 分钟；再把“屏幕常亮”关掉，同样等 | 开：一直亮；关：约 30 秒后灭屏。暂停状态下开着也会按系统超时灭屏（O05.1 和 3.x 的差别，属预期）。看完把自动锁屏改回 |
| 2. F-ROOM-21：设置 → 播放器内核 → 内核 →“播放器强制销毁”关（默认）。进直播间 A 等出画面 → 返回 → 5 秒内进直播间 B；再打开“播放器强制销毁”重复一次。另外离开直播间后用 `adb shell dumpsys meminfo com.mystyle.purelive.v4dev` 每 15 秒看一次总内存，看 1 分钟 | 关时 B 起播不比开时慢（主观或录屏对比）；离开后约 45 秒内存回落一截；开时离开即回落 |
| 3. F-ROOM-25：直播间播放中 `adb shell input keyevent 127`（暂停）、`126`（播放）、`85`（播放/暂停） | 分别暂停、继续、切换；暂停时控制层常显（D-012） |
| 4. F-RT-05：K90 装了快手时，进一个正在播的快手直播间 → 右上角菜单 →“在快手打开” | 跳到快手 App 的这个直播间；没装快手时提示“无法打开APP，将使用浏览器打开”并打开网页。未开播的快手房间只开网页 |
| 5. F-RT-07：任一直播间 → 菜单 →“切换直播间” → 面板标题行的刷新按钮 | 按钮变成转圈、不能再点；结束后“已开播”分组更新，显示上次刷新时间 |
| 6. F-PORT-05：设置 → 视频 → 竖屏直播适配 → 全屏、小窗与弹幕 →“小窗跟随真实画面比例”开，进一个抖音竖屏主播 → 画面上栏的小窗按钮进画中画；回来，关掉这个开关再进一次画中画；再打开 设置 → 视频 → 小窗 →“离开直播间时小窗播放”，返回首页看应用内小窗，开关两种各一次 | 开：画中画和应用内小窗按真实比例；关：竖屏画面固定 9:16；横屏主播两种都按真实比例 |
| 7. F-PORT-06：设置 → 视频 → 竖屏直播适配 → 诊断与恢复 →“显示识别状态”开，进抖音竖屏主播 | 画面左上角一块半透明文字：宽×高、比例、方向、手动覆盖；第二行起播时“平台预判”，出画面后变“解码尺寸”。关掉后消失 |
| 8. F-MINI-04：设置 → 小窗弹幕，改字号、速度、透明度 | 页顶的预览即时跟着变 |
| 9. F-RT-01：同一 Wi-Fi 下有电视或盒子时：直播间菜单 →“投屏” → 选清晰度、线路 → 设备列表点一台 | 列表里出现设备；点了转圈后打勾，电视上开始播放。没有设备就写“跳过：没有接收设备” |
| 10. 第 3 阶段合并后：找一个快开播的关注（看主播的开播习惯），开播前进它的直播间（显示未开播）→ 按 Home 或锁屏，等它开播后再等 2 分钟 → 回到应用 | 后台期间不出声；回到应用后自动开始播放。当天找不到快开播的房间就写“跳过：靠自动测试”，留到下一次 |

## 风险和注意

- 第 3 阶段动的是后台策略，和画中画、自动画中画、应用内小窗、助眠都有关：画中画时 Flutter 报 `inactive`（不触发 `onHidden`），不能把画中画当后台；自动助眠和后台播放打开时“离开时在播”的照常继续。改完跑 `live_play_mini_window_test.dart`。
- 方案 A 会先打开流再暂停，后台多一次连接；方案 B 不开流，但控制器要知道前后台（`LiveRoomController` 现在不依赖 `RoomBackgroundPolicy`，反过来是策略依赖控制器）。
- 和其他任务的冲突：A07.14、A07.15、G02.2 也可能改 `features/live_play/`；`docs/inventory/FEATURES.md` 别的任务也会改各自的行，只改上面列的行。
- 真机第 2 步的“起播更快”是主观的，看不出差别不算失败，以内存回落为准。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter 3.47.5；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/C01.3` 或本机工作区；提交信息以 `[C01.3]` 开头（英文），例如 `[C01.3] docs: correct the live room rows of the feature inventory`；不推 master。
- 提交前：`cd apps/pure_live && dart format --output=none --set-exit-if-changed . && flutter analyze && flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支；在本文件夹 `record.md` 写“停在哪”（做完的阶段、正在做的阶段做到哪、下一步）；更新登记表本任务的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；清点表改了哪些行；真机每步的结果（通过、不通过的现象）；第 3 阶段选了哪个方案、根因（文件:行）、测试数量；改了哪些文件；要在真机上补看的；需要维护者决定的（登记表标题、C02.1/C03.1/O05.1 的状态）；可能冲突的文件。
