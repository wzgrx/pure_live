# G03.1 起播速度和弱网：任务书

## 背景

- 来源：PLAN 原则 4“速度（起播、滑动、响应）优先”，第一档列有本任务；[specs/UI.md](../../../specs/UI.md) 第 9.4 节的指标“点击直播间到画面出现：不超过 v3 的 70%”。2026-10-02 文档整理时登记（旧编号 T04c.1），一直没有人测过。
- 现象：点进直播间到出画面“几秒”，没有数字；用户感觉 4.x 进房不够快、上下滑换房要等；网络差时反复出现“正在重连（第 N 次）”。没有数字就不知道该改哪一段。
- 为什么现在做：第一档；起播是每次看直播都要经过的路径。前置是 G02.2（会话对账和恢复原因日志）：没有它，测量里会混进“缓冲标志卡住”造成的假重连，也数不清弱网下重连的原因。
- 已经做过的：G01.1（取流管线）、G02.1（会话）、C02.1（`PlayerStandby`：关闭直播间 45 秒内进下一个房间复用播放器）、R01.1（界面帧的基准，不含视频）。

## 目标和验收

阶段 1（测量现状）：

1. 打点代码合并进 master：每次打开写一行 `playback-timing …`（格式见“方案”c1），进应用日志（info，日志页能看、能导出）并 `debugPrint`（`adb logcat -s flutter` 能看）；被新打开取代、出错的打开写 `result=superseded` / `result=error:<代码>`；打点本身不改变任何行为。
2. `record.md` 有“现状”表：五大平台 × 冷进房 / 复用进房，每格是 5×2 个样本的中位数和 P90，以及各段（detail、qualities、urls、engineReady、input、load、firstFrame）的中位数；换房 10 次；弱网 3 个平台各 5 次和 10 分钟连续播放的重连次数。每行写日期、时间段、房间号、网络。
3. （可选）3.x 基线：同样的房间在 `com.mystyle.purelive.v3bench`（改了包名的 v3.2.11 构建）上录屏数帧的结果；做不了时写明原因，验收改用绝对目标。

阶段 2（找出慢的环节）：

4. `record.md` 的“分析”一节：最慢的两三段和占比；mpv 探测参数的 A/B 结果（三组参数 × 五平台 × 5 次，同时记音轨和画面是否正常）；每个要做的改动写清预期收益和风险；有用户可见取舍的列出来请维护者确认（登记表 `next` 写明等确认）。

阶段 3（改进）：

5. 只做阶段 2 选定的改动，每个改动单独提交、单独有测试；默认行为对用户的变化写进 `record.md` 的前后对比表。

阶段 4（真机对比）：

6. 同样的矩阵再测一遍，`record.md` 有改前改后对比表；目标：Wi-Fi 冷进房中位数 ≤1.5 秒、P90 ≤2.5 秒，复用进房中位数 ≤1.2 秒，换房中位数 ≤1.5 秒，会话部分（T3→T7）中位数 ≤0.8 秒；弱网冷进房中位数 ≤5 秒且 10 次里 0 次 `source_open_timeout`，弱网连续 10 分钟（流码率低于限速时）0 次重连；有 3.x 基线时另加“≤3.x 的 70%”。达不到的写原因（例如平台接口本身要 1 秒以上），交给 E 组开任务。
7. 每个阶段测试和门禁通过。

## 现状（读代码得出，写文件:行）

进房路径（一次冷进房，按顺序）：

1. `apps/pure_live/lib/features/live_play/live_play_page.dart:196-262` `initState`：读设置、`_engineConfig`（`:399`），`standby.take(config:)` 或 `playbackSessionFactoryProvider` 新建会话（`:228`）；`_newRuntime` 建 `LiveRoomController`（`:274`）；`unawaited(controller.start())`（`:259`）。页面转场和后面的请求同时进行。
2. `apps/pure_live/lib/features/live_play/logic/room_controller.dart:304-328` `start`：订阅；**`await _reloadFilter()`（`:316`，读屏蔽词、屏蔽用户两张表，`:340-357`）**；**`await store.meta.get(showGiftsKey)`（`:317-319`）**；然后才 `await load()`（`:328`）。
3. `load`（`:360-404`）：`site.getRoomDetail`（`:370`，网络）；开播才 `_startStream`。
4. `_startStream`（`:413-444`）：`scope.discover(site, _room)` 取画质（有的平台要请求）；`_preferredQuality`（`:407-411`，`connectivity_plus` 查网络类型）；`defaultQualityIndex`；`_openQuality`；之后才连弹幕（`:442`）。
5. `_openQuality`（`:462-513`）：`site.resolvePlayUrls`（`:466-468`，网络；用户手动换档时走 `resolvePlayUrlsForRecovery`）；`ensureLocalNetworkFor`（局域网地址才弹权限）；`session.open(PlaybackRequest(...))`（`:503-512`）。
6. 会话 `packages/live_player/lib/src/session.dart`：`open`（`:195-231`）→ `_openSource`（`:444-538`）：`_engineNow`（`:406-431`，第一次才 `MpvEngine.create`）→ `_transport.open(MediaOpener.open, engine.open)`，整体 18 秒期限（`:492-502`）→ `_settle`。
7. 引擎 `packages/live_player/lib/src/mpv_engine.dart`：`create`（`:54-75`：`MediaKit.ensureInitialized`、`Player(...)`、逐个 `await native.setProperty` 设 13 个直播属性 `:59-62`、建 `VideoController`）；`open`（`:162-193`：设 `hwdec`、`http-proxy`，`player.open(Media(...))`，补发状态，2 秒后探测帧率）。
8. 取流 `packages/live_media/lib/src/input.dart`：`MediaOpener.open`（`:112`）按 `MediaRoute.of`（`source.dart:111-127`）：`direct` 只拼地址；`flvSplice`、`hlsRelay` 先 `_relayNow()`（`:105`，第一次要中继时才 `LoopbackRelay.start`）再由中继发首个上游请求；配方（Bigo、FC2、niconico）每次都要向平台取授权。
9. mpv 属性 `packages/live_player/lib/src/mpv_options.dart:133-158`：`demuxer-lavf-probesize` 2097152、`demuxer-lavf-analyzeduration` 2、`cache-secs` 6、`demuxer-max-bytes` 32 MiB、`demuxer-max-back-bytes` 4 MiB、`demuxer-readahead-secs` 2、`network-timeout` 15、`hwdec-software-fallback` 1。
10. 状态事件：首帧画面参数 → `EngineVideoSize`（`mpv_engine.dart:127-133`）；缓冲结束 → `EngineBuffering(false)` → 会话 `playing`（`session.dart:642-659`、`:609-628`）。

换房：`live_play_page.dart:359-395` `_switchRoom`：新 runtime 用旧会话；`release()` 等 `old.dispose(keep:)`（停会话、关输入），`handover.whenComplete` 之后才 `runtime.controller.start()`（`:393`）——新房间的取详情、取画质、取地址全排在旧房间释放之后。

弱网相关：`SessionTimings`（`session.dart:41-88`）打开 18 秒、刷新 12 秒、缓冲 12 秒、意外暂停 0.35 + 5 秒、两轮重试 0.75 秒和 2 秒；mpv `network-timeout` 15 秒。

已有的计时工具：`clock`（会话已依赖，测试可替换）；应用日志 `apps/pure_live/lib/app/app_log.dart:256`（`AppLog.instance.info`）。没有任何起播打点。

## 3.x 基线

- 3.x 进房：`git show v3.2.11:lib/modules/live_play/controllers/live_play_controller.dart:249`（取详情、合并卡片信息、`:753` 更新关注快照）→ `lib/modules/live_play/controllers/player_controller.dart:594`、`:613`（默认清晰度）→ `lib/player/core/player_manager.dart` 的 `playSource`（打开期限 `:297`、`:2296-2301`）。播放器是全局编排器（`lib/player/global_player_service.dart`，`main.dart:91` 初始化），原生解码器第一次播放时才建。
- mpv 属性和 4.x 相同：`lib/player/adapters/media_kit_adapter.dart:84`、`:89`、`:98`；`lib/player/utils/live_buffer_policy.dart`。
- 3.x 没有起播打点；换房同样先关后开。
- 3.x 安装在 K90 上的是用户的正式包 `com.mystyle.purelive`，**不能用来测**（不碰 3.x 安装和数据，D-019）。要 3.x 基线只能自己构建一个改包名的 v3.2.11：在独立工作区 `git worktree add <路径> v3.2.11`，把 `android/app/build.gradle` 的 `applicationId` 改成 `com.mystyle.purelive.v3bench`、应用名改成“纯粹直播 v3bench”，本机构建 profile 包装到 K90；测完卸载。这一步可选。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 3.3 节阶段、第 5 节分阶段、第 8 节合并审查、第 10 节真机、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`（第 4 节分层：`live_player` 的会话不引 Flutter，`live_media` 纯 Dart）；`docs/specs/UI.md` 第 9.2、9.4 节。
3. 本文件夹的 `README.md`；`docs/G-播放/G03-起播速度和弱网/README.md`（起播路径和已知问题）；`docs/G-播放/G02-会话和恢复/README.md`；`docs/G-播放/G01-引擎/README.md`；`docs/G-播放/G02-会话和恢复/G02.2-缓冲状态对账/record.md`（前置任务做了什么）；`docs/C-直播间/C02-小窗、画中画、后台播放/README.md` 里 C02.1 的 `PlayerStandby`；`docs/V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md` 第 4.3 节（手机上怎么测）。
4. 代码：上面“现状”列出的每个文件和行。

## 范围

- 可以改：
  - `packages/live_player/lib/src/`：`session.dart`（打点、`prepare()`、时限的使用方式）、`mpv_engine.dart`（打点、属性设置方式）、`mpv_options.dart`（只在阶段 2 的 A/B 证明后改探测和缓存值）、`state.dart`（只添加）；`packages/live_player/test/`。
  - `packages/live_media/lib/src/input.dart`、`relay/loopback_relay.dart`（只为中继预热和打点）；`packages/live_media/test/`。
  - `apps/pure_live/lib/features/live_play/logic/room_controller.dart`（打点、`start` 的并行）、`live_play_page.dart`（`initState` 的预建引擎、`_switchRoom` 的并行）；`apps/pure_live/lib/app/bootstrap.dart`（只为中继预热，阶段 3 c12）；`apps/pure_live/test/features/live_play/`。
  - 可以新建 `tools/perf/playback_timing.py`（把导出的日志或 logcat 汇总成中位数、P90 表；只读文件、不访问网络）。
  - 本文件夹的 `record.md`。
- 不能改：
  - 平台适配器（`packages/live_core/lib/src/sites/`）：平台接口慢的只记数字，交给 E 组。
  - 恢复顺序和 3.x 的会话规则（用户暂停不被恢复、缓冲看门狗不被重复通知重置、新输入被接受后才释放旧输入）；`PlaybackState` 现有字段的含义。
  - 加载时的界面（A07.7）；设置项（不加“起播模式”之类的设置）；3.x 的设置键名和含义。
  - `third_party/media_kit`（要改分支另开任务）；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 测量现状 | c1 打点：直播间记 `T0`（`initState`）、`T1` 详情回来、`T2` 画质回来、`T3` 地址回来，交给会话（`PlaybackRequest` 加可选的 `startedAt`、或会话加 `markRoom(...)`，只添加）；会话记 `T4` 引擎就绪、`T5` 输入打开、`T6` `engine.open` 返回、`T7` 第一个 `EngineVideoSize`、`T8` 第一次 `playing`；一次打开结束时写一行日志。c2 K90 测量（下表）。c3（可选）3.x 基线 | `session.dart`、`state.dart`（如需）、`mpv_engine.dart`（如需）、`room_controller.dart`、`live_play_page.dart`；测试；可选 `tools/perf/playback_timing.py`；`record.md` | 验收第 1～3 条 |
| 2 找出慢的环节 | c4 排出最慢的段；c5 mpv 探测 A/B：A = 2 MiB / 2 秒（现值）、B = 1 MiB / 1 秒、C = 512 KiB / 0.5 秒，用本机临时构建（`--dart-define` 只在实验包里加，不合并）各平台各 5 次，记 `load`、`firstFrame` 和音画是否正常；c6 写结论 | `record.md` | 验收第 4 条；需要确认的取舍等维护者回复 |
| 3 改进 | 按 c6 选做：c7 进房即预建引擎（`PlaybackSession.prepare()`：只建引擎、不开输入，`initState` 里在 `controller.start()` 前调用，和网络并行）；c8 `start` 里读屏蔽表、meta 和 `load()` 并行（过滤器在第一条弹幕前就绪即可）；c9 换房：新房间的 `load` 先跑，`_openQuality` 里 `session.open` 前等旧房间释放（`_handover` 的 Future 交给控制器）；c10 探测参数（A/B 证明更快且无副作用时）；c11 弱网时限（例如缓冲期限期间 mpv 的 `demuxer-cache-time` 在增长就顺延，最多到 30 秒；只在弱网测试证明反复重连时）；c12 应用启动后 5 秒空闲时预热本地中继（只在 `flvSplice`/`hlsRelay` 首个输入明显慢时） | 见“范围”可以改的文件 | 每个改动有测试（下节），门禁通过，单独合并 |
| 4 真机对比 | c13 同样的矩阵再测 | `record.md` | 验收第 6 条 |

每个阶段都要能单独合并（门禁通过、不留半截功能）。阶段 2 不改代码，阶段 3 的每个 c 编号单独一个提交。

日志格式（c1，一行，字段固定，便于脚本汇总；不带地址、请求头、Cookie）：

```text
playback-timing site=bilibili room=<房间号的哈希前 6 位> route=direct engine=new|reused result=playing|superseded|error:<代码> detail=312 qualities=0 urls=405 engineReady=180 input=2 load=96 firstFrame=640 playing=702 total=1697
```

各字段是相邻两点的差（毫秒），`total` 是 T0→T8；没有经过直播间的打开（多画面、网络电视）`detail`、`qualities`、`urls` 写 `-`。

## 测试

- 阶段 1：
  - `packages/live_player/test/session_test.dart`：`timing: one line per open, each mark once`（假引擎依次发尺寸、播放；断言回调收到一次，`engineReady`、`input`、`load`、`firstFrame`、`playing` 都有、非负）；`timing: a superseded open reports superseded`（打开中再 `open`，第一次的结果是 `superseded`）；`timing: a reused engine says reused`（`stop` 后 45 秒内再 `open`）；`timing: an error reports its code`。用 `fake_async` 和 `clock` 控制时间，定时器至少 1 秒。
  - `apps/pure_live/test/features/live_play/live_play_room_test.dart`：`timing line of a room open`（假平台、假引擎，进房后应用日志里有一行 `playback-timing site=<假平台>`，`detail`、`urls` 有值）。
- 阶段 3（各自的用例，改之前会失败的写明）：
  - c7：`prepare builds the engine once; open adopts it`（`prepare()` 后 `engineFactory` 调用 1 次，`open` 不再调）；直播间 `the engine is prepared while the detail loads`（假平台的详情用 `Completer` 卡住，断言引擎已建）。
  - c8：`the detail request does not wait for the block lists`（假存储的屏蔽表读取卡住，断言 `getRoomDetail` 已被调用）——改之前会失败。
  - c9：`a swipe starts the next room's detail before the previous room is released`（旧会话的 `stop` 卡住，断言新房间的 `getRoomDetail` 已调用、`session.open` 还没调）——改之前会失败。
  - c10：`packages/live_player/test/options_test.dart` 的直播属性断言跟着改。
  - c11：`buffering that grows its cache is not judged stalled`（假引擎报缓存时间在涨，12 秒后不恢复；不涨时照旧恢复）。
- 改过的包跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`（`live_media` 用 `dart analyze`）、测试；`apps/pure_live` 跑全部 `flutter test`。不访问真实平台。

## 真机验证（维护者在 K90 上做）

准备：

- 装阶段 1 合并后的 profile 包（`com.mystyle.purelive.v4dev`，`flutter build apk --profile` 本机构建）；屏幕常亮；设置 → 数据 → 日志管理打开“启用本地日志”；`adb -s 192.168.1.2:5555 logcat -c` 后 `adb -s 192.168.1.2:5555 logcat -s flutter | grep playback-timing > timing.txt`。
- 进房用分享入口，便于重复：`adb -s 192.168.1.2:5555 shell am start -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT "https://live.bilibili.com/<房间号>" com.mystyle.purelive.v4dev`（O03.2 的分享接收直接进房）。冷进房：先 `adb shell am force-stop com.mystyle.purelive.v4dev`；复用进房：在直播间按返回回到首页，10 秒内再发下一次。
- 弱网：电脑上开 Clash（局域网端口 7897，允许局域网连接），K90 的设置 → 网络 → 应用代理和播放代理都指向电脑的局域网地址:7897（Android 17 会先要“本地网络”权限，见 O04.1）；电脑上用 Clumsy（Windows，按端口过滤 `tcp.DstPort == 7897 or tcp.SrcPort == 7897`）加 Lag 100 ms（往返约 200 ms）、Throttle 到约 2 Mbps、Drop 1%。先在无限速时确认代理通，再打开限速。

| 步骤 | 期望 |
|---|---|
| 1. Wi-Fi 直连，五大平台各 2 个热门房间，每个冷进房 5 次 | `timing.txt` 每次一行 `result=playing`；50 行 |
| 2. 同样的房间各复用进房 5 次 | 行里 `engine=reused`；50 行 |
| 3. 竖屏全屏（抖音或哔哩哔哩竖屏房间列表）上下滑换房 10 次，每次等出画面 | 10 行；没有 `result=error` |
| 4. 弱网：哔哩哔哩、斗鱼、虎牙各冷进房 5 次（选“超清”或默认档） | 记录 `total` 和有没有 `source_open_timeout` |
| 5. 弱网：选一个码率低于 2 Mbps 的档连续播 10 分钟 | 数应用日志里的 `playback: recovering`（G02.2）；期望 0 次 |
| 6. 阶段 4：改动合并后的包重复 1～5 | 改前改后的表；没有新出现的音画问题（无声、花屏、只有声音） |
| 7. 阶段 2 的 A/B（实验包，不合并）：三组探测参数各在五平台冷进房 5 次 | 记 `load`、`firstFrame`；逐次确认有声音、画面正常 |

用 `python3 tools/perf/playback_timing.py timing.txt`（如果写了）出中位数和 P90 表；没写脚本时在 `record.md` 里写明计算方法。

## 风险和注意

- **平台数据随时段变化**：热门房间的码率、CDN 不同时段差很多；改前改后尽量同一时段、同一批房间，写清时间。每组至少 5 次，取中位数，不看单次。
- **探测参数调小的副作用**：探测不够时 mpv 可能认不出音轨（只有画面没声音）或把 HEVC 流信息读错；3.x 选 2 MiB / 2 秒是有原因的。A/B 时逐次确认音画正常，有一次异常就不采用那一组。
- **预建引擎的代价**：`prepare()` 会在用户点进房间、但房间没开播时也建引擎（多占几十 MB）；离开直播间时照旧 `stop` → 45 秒释放，不常驻。
- **并行的竞态**：c8、c9 改了顺序，要保证过滤器在第一条弹幕前就绪、换房时旧会话停完之前新房间不 `session.open`（`_handover` 的注释“a stop still running would stop what the next room opens”）。
- **打点的开销**：热路径只记 `clock.now()`，一次打开只写一行日志；不要每帧、每个位置事件记。
- **和其他任务冲突的文件**：`session.dart`（G02.2 先合并，G01.2 也加诊断）、`room_controller.dart`（C01.4、E06.2）、`live_play_page.dart`（A 组直播间界面任务、A03.3 暂停中的拖动手感）、`mpv_options.dart`（G01.2 不改它）。开工前先合并最新 master。
- 只点测试包（D-019）；v3bench 包测完卸载；不碰用户的 3.x 和正式包。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/G03.1` 或本机工作区；提交信息以 `[G03.1]` 开头（英文）；不推 master。阶段 2 的实验包改动只留在本机，不提交。
- 提交前：改过的包跑 `dart format --output=none --set-exit-if-changed .`、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；根目录 `python3 tools/gate/check_ui_structure.py`、`python3 tools/gate/check_deps.py`、`python3 tools/docs/docs.py --check`。
- 构建 profile 包时不要同时跑门禁（PROCESS 第 8 节第 5 条）；构建完 `./gradlew --stop`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（哪个阶段、测到哪个平台、表里哪些格子还空、阶段 3 做了哪几个 c）、更新登记表的 `done`、`next`、`branch`。测量数据（`timing.txt`）不进仓库，汇总表写进 `record.md`。

## 报告（中文，简洁）

每个阶段做到没有；现状表和改后表（中位数、P90、各段）；最慢的环节和原因；mpv 参数 A/B 的结论；做了哪些改动（c 编号）、各自省了多少；没达到的目标和原因；交给 E 组的平台（哪个接口慢、多慢）；测试数量（改之前失败几个）；改了哪些文件；要在真机上再看的；需要维护者决定的；可能冲突的文件。
