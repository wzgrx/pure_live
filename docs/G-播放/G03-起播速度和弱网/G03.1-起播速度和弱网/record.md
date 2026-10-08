# G03.1 起播速度和弱网：记录

- 日期：2026-10-08
- 执行者：Claude（Opus 5.5）
- 分支和提交：本机工作区；阶段 1 c1 打点一个提交（`[G03.1]`）；阶段 3 三个提交（`9e89c8f22` 探测开关、`8432f9910` 快手、`ee41f6c7c` 打点单调时钟）
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 进度

| 阶段 | 编号 | 状态 |
|---|---|---|
| 1 测量现状 | c1 打点 | 做完（本记录） |
| 1 测量现状 | c2 K90 测量 | 做完（Wi-Fi 冷进房、复用进房；换房、弱网没测，见“阶段 1 c2”） |
| 1 测量现状 | c3 3.x 基线（可选） | 没做 |
| 2 找出慢的环节 | c4 最慢的段、c5 探测 A/B（电脑上 ffmpeg）、c6 结论 | 做完（见“阶段 2”）；K90 上的探测 A/B 放进阶段 4 |
| 3 改进 | 快手取详情少一个请求；探测参数的构建期开关；打点改用单调时钟 | 做完；c7、c8、c9、c10（改默认值）、c11、c12 不做或等阶段 4 的数字 |
| 4 真机对比 | c13 | 等维护者在 K90 上测 |

## c1 打点：做了什么

打点只读时钟（`package:clock` 的 `clock.now()`，测试里可以换），一次打开最多写一行；没有在打开的会话不做任何事。打点不改变任何播放行为（回调抛异常也被吞掉）。

直播间（`apps/pure_live/lib/features/live_play/logic/room_controller.dart`）：

| 点 | 在哪里记 |
|---|---|
| T0 进房 | `:203` `_startup = StartupMarks()`：控制器创建时。进房时控制器在页面 `initState` 里建（`live_play_page.dart` 的 `_newRuntime`）；上下滑换房、切换面板选房时在 `_switchRoom`（`live_play_page.dart:377`）里建，也就是松手那一刻 |
| T1 详情回来 | `:487` `load` 里 `getRoomDetail` 返回后 |
| T2 画质回来 | `:531` `_startStream` 里 `scope.discover` 返回后（选默认档、查网络类型算在 `urls` 段） |
| T3 地址回来 | `:588` `_openQuality` 里 `resolvePlayUrls` 返回后（只记进房那一次，不记用户换档） |
| 交给会话 | `:622` `_takeStartup(epoch)`，随 `PlaybackRequest(startup:, onTiming:)` 交给 `session.open` |
| 写日志 | `:364` `_logTiming`：应用日志 info（标签 `playback`）+ `debugPrint` |

只计“进房”的那一次打开：第一次 `load` 的打开。刷新直播间、出错后重试、换清晰度、换线路都不写；第一次 `load` 没有开出流（取详情失败 `:481`、未开播 `:493`、无法播放 `:558`）时丢掉这组点。

会话（`packages/live_player/lib/src/session.dart`，计时对象在新文件 `packages/live_player/lib/src/timing.dart`）：

| 点 | 在哪里记 |
|---|---|
| 开始计时 | `:354` `open` 里，请求带 `onTiming` 时才建 `OpenTiming` |
| T4 引擎就绪 | `:654` `_openSource` 里 `_engineNow()` 返回后；`engine=reused` 表示调用前会话已有引擎（`PlayerStandby` 交来的或上一个房间留下的） |
| T5 输入打开 | `:671` `MediaOpener.open` 返回、交给引擎前，同时记路线（`direct`/`flvSplice`/`flvRewrite`/`hlsRelay`/`owned`） |
| T6 引擎打开返回 | `:673` `engine.open` 返回后 |
| T7 首帧画面参数 | `:755` 第一个 `EngineVideoSize` |
| T8 首次播放 | `:319` `_reportTiming`：第一次发出 `PlaybackStatus.playing` 时结束计时并回调 |
| 出错 | 同上：第一次发出 `PlaybackStatus.error` 时结束，`result=error:<代码>` |
| 被取代 | `:570` 新一代（新的 `open`、换线路、重试、`stop`、`dispose`）直接丢掉，不写 |

每个点只记第一次：打开过程中的恢复（刷新地址、换线路）不覆盖已有的点，耗时算进后面的段。一个点比后面的点来得晚（例如首帧参数在 `playing` 之后才到）就不记，写 `-`，那一段的时间算进下一段，所以各段不会是负数，加起来等于 `total`（每段向下取整到毫秒，差几毫秒）。

## 日志格式

```text
playback-timing site=bilibili room=1a2b3c route=direct engine=new result=playing detail=312 qualities=0 urls=405 engineReady=180 input=2 load=96 firstFrame=640 playing=702 total=1697
```

- 和任务书 c1 的格式一致：`room` 是 `平台:房间号` 的 32 位 FNV-1a 哈希的前 6 位十六进制（`LiveRoomController.roomTag`），不写房间号、地址、请求头、Cookie。
- 各段是相邻两点的差（毫秒）：`detail` T0→T1、`qualities` T1→T2、`urls` T2→T3、`engineReady` T3→T4、`input` T4→T5、`load` T5→T6、`firstFrame` T6→T7、`playing` T7→T8；`total` 是 T0→结束（T8 或出错）。没到的点写 `-`。
- 应用日志里这一行在标签后面（`[INFO] playback: playback-timing site=…`），logcat 里是 `I/flutter: playback-timing site=…`，两处的正文相同，脚本按 `playback-timing ` 后面的字段解析即可。
- 被新打开取代的打开不写（和任务书“写 `result=superseded`”不同：按 README“验证”一节，取代的不写）。

## 怎么收集（c2 用）

1. 装 profile 包（`flutter build apk --profile`，测试包 `com.mystyle.purelive.v4dev`），设置 → 数据 → 日志管理打开“启用本地日志”（应用日志页也能看、能导出）。
2. 电脑上：`adb -s 192.168.1.2:5555 logcat -c`，然后 `adb -s 192.168.1.2:5555 logcat -s flutter | grep playback-timing > timing.txt`（即 `adb logcat -s flutter | grep playback-timing`）。
3. 按 README“真机验证”的矩阵进房、换房；每次进房一行。
4. 中位数和 P90：每格按 `total` 和各段分别排序，中位数取中间值（偶数个取中间两个的平均），P90 取第 ⌈0.9n⌉ 个（50 个样本取第 45 个）。`tools/perf/playback_timing.py` 还没写，测完需要时再加。

要留意的：

- 换房的 `detail` 段包含等旧房间释放的时间（`_switchRoom` 等 `old.dispose` 完才 `controller.start()`，见 README“换房”一行），这正是 c9 要改的。
- 复用引擎时 `mpv_engine.dart` 的 `open` 返回前会补发播放器当时的状态；如果出现 `engine=reused` 且 `firstFrame`、`playing` 接近 0，可能是补发了上一路流留下的状态，记下来，阶段 2 分析时单独看。
- 浮窗回到直播间（`FloatingRoom.claim`）不重新打开，不写行。多画面、不经过直播间的打开不计时（没有接，范围外）。

## 测试

- `packages/live_player/test/session_test.dart` 新增 5 个（组 `G03.1 timing`）：
  - `timing: one line per open, each mark once`：带房间的点，假引擎依次建引擎、打开、两次画面尺寸、播放，每步 1 秒；整行逐字对比（各段 1000、`input=0`、`total=7000`），之后的尺寸、出错恢复、再次播放不再回调。
  - `timing: an open without a room times from the session open`：没有房间的点时 `detail` 等写 `-`。
  - `timing: a superseded open writes nothing`：打开中再 `open`，第一次不写；打开中换线路、`stop` 也不写。
  - `timing: a reused engine says reused`：`stop` 后 10 秒内再 `open`，第二行 `engine=reused`。
  - `timing: an error reports its code`：空计划 `error:no_source`（`route=-`、`engine=-`）；打不开的来源 `error:source_open_timeout`。
- `apps/pure_live/test/features/live_play/live_play_controller_test.dart` 新增 1 个：`G03.1: entering the room leaves one timing line, its marks in order`：假平台的详情和取地址各等 1 秒，应用日志里正好一行，字段顺序固定，`detail`≥1000、`qualities`<1000、`urls`≥1000（T0～T3 顺序对、各点在各自那一步之后），各段相加等于 `total`；之后换清晰度、刷新直播间不再写。
- 结果：`live_player` 全部测试通过；`apps/pure_live` 全部 `flutter test` 通过；`dart analyze --fatal-infos`、`flutter analyze --fatal-infos`、格式检查通过。

## 跟进：结束点改成“在播并且有画面”（2026-10-08）

- K90 上第一行：`playback-timing site=bilibili … load=2 firstFrame=- playing=0 total=472`。mpv 加载完马上报“在播”（`MpvEngine.open` 末尾补发，G02.3 记过），计时在第一帧之前就结束了，`total` 偏小、`firstFrame` 总是空。
- 改成：在播且已有第一帧（`EngineVideoSize`）时结束；先来画面、后报在播时照旧在“在播”时结束；没有画面的源（纯音频）在播放位置第一次前进时结束；出错照旧立即结束。
- 测试：`session_test` 改了 3 条（补发画面）、新增 1 条（纯音频按位置前进结束）；`live_play_controller_test` 的打点用例补发画面并检查 `firstFrame`。`live_player` 55 个、`test/features/live_play` 325 个全过。

## 阶段 1 c2：K90 测量（2026-10-08，master d24c6757b，Wi-Fi，profile 包）

原始行在 `data/2026-10-08-warm.txt`、`data/2026-10-08-cold.txt`（房间是 6 位哈希，不含地址）。

| 情况 | 样本 | 中位数 | P90 | 目标 |
|---|---|---|---|---|
| 复用播放器（热门连续点，每平台 2 房间 × 3 次） | 27 | 1033 ms | 1526 ms | 中位数 ≤1.2 秒 ✓ |
| 冷进房（杀进程，每平台 2 次） | 10 | 1406 ms | 2868 ms | 中位数 ≤1.5 秒 ✓；P90 ≤2.5 秒 ✗ |

各平台中位数（复用 / 冷）：哔哩哔哩 1285 / 3113、斗鱼 918 / 1204、虎牙 998 / 1355、抖音 950 / 1167、快手 971 / 1828（毫秒）。

各段中位数（复用；冷）：取详情 285；325，取地址 91；78，建引擎 1；44，打开输入 0，加载 13；5，**加载到第一帧 565；634**。

最慢的环节：

1. **加载到第一帧**（mpv 探测和等关键帧）：多数 0.4～0.9 秒；哔哩哔哩个别房间 1.0～1.7 秒（复用）、2.5～2.9 秒（冷进房），冷进房的 P90 全是它。下一步 c5：mpv 探测参数 A/B（2 MiB/2 秒、1 MiB/1 秒、512 KiB/0.5 秒），先在电脑上用 ffmpeg 对同一地址测“拿到第一帧”的时间，确认是探测还是等关键帧。
2. **快手取详情** 1.0～1.35 秒（别的平台 0.05～0.6 秒）：看 `kuaishou_site.dart` 的取详情是不是串行发了几个请求。
3. 建引擎（冷进房 33～52 ms）、打开输入、加载都很小，c7（预建引擎）收益不大。

没测：上下滑换房、弱网（K90 上没有不影响别的应用的限速办法，`OEM_DENY_3` 只能断网）。

## 阶段 2：找出慢的环节（2026-10-08，电脑 WSL，直连，ffmpeg 9.0.2）

做法：用适配器（`live_cli` 的站点表，游客、`优先 H.264` 开）取每个平台首页推荐里在播的房间，按应用的默认档（`原画`，没有就第一档，HEVC 让给 H.264）取第一条线路的地址和请求头（临时脚本，不提交，地址不进仓库）。哔哩哔哩 5 个房间，其余平台各 3 个，每个房间 5 轮，每轮依次：

- `flv`：Python 直接读 FLV 标签，不探测：记首字节、第一个关键帧、第一个音频包到达的时间，以及开始后 0.5 / 1 / 2 秒内收到了多少秒的流（看 CDN 是一次推完缓存的 GOP 还是按实时速度给）。
- `ffmpeg`：`-probesize/-analyzeduration` 三组（A = 2 MiB / 2 秒，应用现值，`mpv_options.dart` 的 `demuxer-lavf-probesize`/`demuxer-lavf-analyzeduration`；B = 1 MiB / 1 秒；C = 512 KiB / 0.5 秒），`-frames:v 1 -f null -`：`probe` 是打印 `Input #0`（探测结束）的时间，`firstFrame` 是解出第一帧退出的时间，同时记有没有找到音轨、画面参数是否一样。

原始数据（房间是 6 位哈希，不含地址）：`data/2026-10-08-pc-probe.txt`。中位数取中间值，P90 取第 ⌈0.9n⌉ 个。

### 探测参数：到第一帧（毫秒）

| 平台 | 组 | 样本 | 探测结束中位数 | 第一帧中位数 | 第一帧 P90 | 没找到音轨 |
|---|---|---|---|---|---|---|
| 哔哩哔哩 | A 2 MiB/2 s | 24 | 838 | **948** | 1777 | 0 |
| 哔哩哔哩 | B 1 MiB/1 s | 24 | 410 | **627** | 1336 | 0 |
| 哔哩哔哩 | C 512 KiB/0.5 s | 24 | 498 | **704** | 1067 | 0 |
| 斗鱼 | A | 10 | 248 | 350 | 500 | 0 |
| 斗鱼 | B | 15 | 224 | 335 | 461 | 0 |
| 斗鱼 | C | 15 | 225 | 335 | 484 | 0 |
| 虎牙 | A | 12 | 519 | 682 | 1082 | 0 |
| 虎牙 | B | 14 | 498 | 674 | 982 | 0 |
| 虎牙 | C | 13 | 504 | 674 | 1347 | 0 |
| 虎牙 HEVC（`优先 H.264` 关） | A | 15 | 522 | 854 | 3225 | 0 |
| 虎牙 HEVC | B | 15 | 553 | 824 | 1049 | 0 |
| 虎牙 HEVC | C | 15 | 509 | 808 | 1229 | 0 |
| 抖音 | A | 15 | 325 | 422 | 697 | 0 |
| 抖音 | B | 15 | 285 | 395 | 586 | 0 |
| 抖音 | C | 15 | 247 | 340 | 499 | 0 |
| 快手 | A | 15 | 330 | **791** | 1052 | 0 |
| 快手 | B | 15 | 326 | **531** | 1066 | 0 |
| 快手 | C | 15 | 280 | **439** | 771 | 0 |

- 失败的样本（不计入）：斗鱼的直接读 FLV 13 次、A 5 次是 HTTP 403（每轮的顺序是读 FLV、A、B、C，同一个带签名的地址反复请求时 CDN 时拒时不拒，原因没查；斗鱼本身不慢，不影响结论）；虎牙 A 3 次、B 1 次、C 2 次是流本身断了（同一轮三组都受影响）；哔哩哔哩一个房间有一轮三组都只读到 `h264, none`（主播那一刻推流异常）。
- 副作用：三组读出的画面参数（编码、分辨率、帧率、色彩）和音轨（AAC、采样率、声道）逐房间完全一致，没有一次 B 或 C 找不到音轨；HEVC 也一样。纯音频、HLS 的源这次没测。

### 不探测时：首字节和关键帧（毫秒，中位数）

| 平台 | 样本 | 首字节 | 第一个关键帧 | 第一个音频 | 0.5 秒内收到的流 | 1 秒内 | 2 秒内 |
|---|---|---|---|---|---|---|---|
| 哔哩哔哩 | 24 | 486 | 532 | 532 | 0 | 1834 | 2700 |
| 斗鱼 | 2 | 158 | 305 | 305 | 6133 | 6616 | 7633 |
| 虎牙 | 12 | 301 | 401 | 401 | 1462 | 7000 | 8120 |
| 抖音 | 15 | 141 | 192 | 200 | 3600 | 4160 | 5120 |
| 快手 | 15 | 409 | 499 | 499 | 1033 | 7125 | 8358 |

### 结论（c4、c6）

1. **哔哩哔哩慢在探测，不在等关键帧**：关键帧紧跟首字节（相差约 50 毫秒，CDN 从关键帧开始给），但它的 CDN 只先推 1～2 秒的缓存，之后按实时速度给（1 秒内 1.8 秒的流，2 秒内 2.7 秒）；别的平台第一秒就推来 4～7 秒。`analyzeduration` 2 秒要读满 2 秒的流才结束探测，在哔哩哔哩上就得等实时的流慢慢来：A 比 B 多 0.3 秒（中位数），个别房间（推得少的）多 1～1.3 秒。K90 冷进房的 2.5～2.9 秒就是这一段被放大（手机上首字节更慢、硬解初始化也在这一段）。另外哔哩哔哩的首字节本身最慢（0.49 秒，抖音 0.14 秒），这是 CDN 的，客户端改不了。
2. **快手**也受探测参数影响（第一帧 A 791、B 531、C 439），但三组的探测结束时间差不多，差在探测结束到第一帧之间；它的 CDN 推得快，不是等实时流，具体原因没细查，以 K90 上的 A/B 为准。
3. 斗鱼、虎牙、抖音三组差别在噪声以内：CDN 一下推来几秒的数据，探测参数不起作用。
4. **决定**：B（1 MiB / 1 秒）在电脑上对哔哩哔哩、快手明显更快、对别的平台无害、没有发现音画副作用；C 没有比 B 更好（哔哩哔哩反而慢一点）、余量更小。但电脑上量的是 ffmpeg 命令行，不是 K90 上的 mpv 和硬解，任务书要求 A/B 在手机上逐次确认音画正常才改默认值（c10），所以**默认值不改**，加构建期开关（`MPV_PROBESIZE`、`MPV_ANALYZEDURATION`），阶段 4 在 K90 上比 A 和 B（需要时再加 C）后再定。
5. **快手取详情**（c4 第二慢）：见下节。
6. **c8**（`start` 里读屏蔽表和 `load` 并行）不做：两张小表的本地读取，K90 上斗鱼复用进房的 `detail` 最小 47 毫秒（含网络请求），能省的不到几毫秒，不值得改顺序带来的竞态（过滤器要在第一条弹幕前就绪）。
7. **c7**（预建引擎）不做：冷进房建引擎 33～52 毫秒（阶段 1）。**c9**（换房）、**c11**（弱网）、**c12**（中继预热）：没有换房、弱网数字，斗鱼的 `flvSplice` 打开输入是 0 毫秒，不做。

## 阶段 3：改了什么

### 快手取详情（`8432f9910`）

原因：第一次进快手房间（没有游客会话、或会话超过 30 分钟）要串行发三个请求：不带 Cookie 访问房间页拿 `Set-Cookie`（会话），等 `misc2` 上报设备号，再带会话 Cookie 把同一个房间页取一遍。电脑上一次是 `GET 房间页 350～1000 ms → POST 上报 45～220 ms → GET 房间页 220～450 ms`，和 K90 上第一次 1040～1351 毫秒、之后 333～512 毫秒（会话已有，只剩一个请求）对得上。不是重试、不是某个接口慢，是多发了一遍房间页。

改法（`packages/live_core/lib/src/sites/kuaishou/kuaishou_site.dart`）：建会话时访问的就是房间页本身（录下来的 `S09-room-live` 正是一次不带 Cookie 的访问，`Set-Cookie` 和在播房间、`playUrls` 都在里面；3.x 的关注刷新也是不带会话直接读房间页），所以先读它：读得出房间就直接用，弹幕拿会话 Cookie（和以前一样），设备上报在后台照发不等；读不出（风控页、改版）就照旧等上报完、带会话再取一遍，被拒照旧换新会话重试一次。预计第一次进房的 `detail` 从 1.0～1.35 秒降到和之后一样的 0.3～0.5 秒（省一个房间页请求和上报的等待）。

真实网络的复核没做完：测试时连续开新会话把本机出口 IP 触发了快手的“请求过快”（`errorType 2`，半小时后仍在），之后的请求全是风控页（这时改后的代码照旧退回取第二遍，和改前行为一样）。K90 和电脑同一出口，阶段 4 测快手前先在浏览器里确认快手能正常打开房间。

测试（`packages/live_core/test/sites/kuaishou_site_test.dart`，改前 6 个失败）：进房只有 `GET 房间页`、`POST 上报` 两个请求；上报卡住时房间已经回来（新增）；访问页读不出时等上报完再带会话取（新增）；30 分钟会话、被拒换会话重试、刷新被拒重试、上报失败四条的请求序列跟着改。

### 探测参数的构建期开关（`9e89c8f22`）

`packages/live_player/lib/src/mpv_options.dart` 的 `mpvProbeValues()`：默认 3.x 的 2 MiB / 2 秒；构建时 `--dart-define=MPV_PROBESIZE=<字节>`、`--dart-define=MPV_ANALYZEDURATION=<秒>` 换掉（mpv 不接受的值，例如非数字、小于 32 字节、不大于 0 或超过 3600 秒，回到默认）。用了开关的包建引擎时在 logcat 打一行 `mpv probe override: probesize=… analyzeduration=…`，便于确认装的是哪个包。测试：`options_test.dart` 新增 1 个（改前编译失败）。

### 打点改用单调时钟（`ee41f6c7c`，维护者在 K90 上发现的矛盾行）

现象：`playback-timing site=kilakila room=f25921 route=direct engine=reused result=playing detail=869 qualities=0 urls=2 engineReady=0 input=0 load=19 firstFrame=475 playing=0 total=13`，各段加起来 1.37 秒，`total` 却是 13 毫秒。

原因：各段和 `total` 在 `OpenTiming.finish` 里用同一个起点（直播间的 T0）算，各段是相邻两点的差，加起来就是“最后一个点 − T0”，而 `total` 是“结束时刻 − T0”，最后一个点（T8）就在结束前一刻记下。只要时间不倒退，`total` 不可能小于各段之和；和 `_takeStartup`、复用引擎补发的旧状态都无关（那些只会让某一段变短或变长，不会让和超过 `total`）。所以是记点用的时钟倒退了约 1.35 秒：打点用的是 `clock.now()`，即墙上时间，手机自动对时（网络时间）会把它往回拨。

改法（`packages/live_player/lib/src/timing.dart`）：打点改读 `timingNow()`：进程内一个 `Stopwatch` 的单调时间（测试里的 `withClock`/fake_async 时钟照旧生效）。测试：`session_test.dart` 新增“打开过程中墙上时间往回拨 3 秒，行里各段之和仍等于 `total`”（改前 `total` 是 −1 秒，失败）。同一次的 IPTV 行（`firstFrame=17385 total=17423`，中间一次 `buffering_stall_timeout` 恢复）是正常的。

## 阶段 4 要在 K90 上做的

1. 装改后的包（含快手改动、单调时钟），按阶段 1 的矩阵再测冷进房、复用进房；快手看第一次进房的 `detail`。
2. 探测 A/B：同一批房间（重点哔哩哔哩、快手，其余平台各 1 个房间看有没有副作用）冷进房各 5 次，逐次确认有声音、画面正常：
   - A（默认）：`flutter build apk --profile`
   - B：`flutter build apk --profile --dart-define=MPV_PROBESIZE=1048576 --dart-define=MPV_ANALYZEDURATION=1`
   - C（B 明显有效时再试）：`--dart-define=MPV_PROBESIZE=524288 --dart-define=MPV_ANALYZEDURATION=0.5`
   比较 `firstFrame` 的中位数和 P90；B 比 A 快且没有一次无声或花屏，就把默认值改成 B（`mpv_options.dart` 一处，`options_test.dart` 的断言跟着改）。

## 阶段 4：K90 探测参数 A/B 和决定（2026-10-08，master 3c1306b61）

冷进房（杀进程），每次记 `playback-timing` 和测试包是否有音轨在播（`audio=1`）。原始行：`data/2026-10-08-k90-probe-A.txt`、`…-B.txt`。

| 组 | 哔哩哔哩 加载到第一帧（5 次） | 中位数 | 哔哩哔哩 total 中位数 | 有声音 | 其他平台（斗鱼、虎牙、抖音 各 1 次 total） |
|---|---|---|---|---|---|
| A 2 MiB / 2 s（3.x） | 2654、2596、974、615、1802 | 1802 ms | 2295 ms | 5/5 | 1587、1373、808 |
| B 1 MiB / 1 s | 875、493、812、708、595 | 708 ms | 1179 ms | 5/5 | 1485、1270、937 |

- 决定：默认改成 B（`mpv_options.dart` 的 `mpvProbeDefaults`），A 留作构建开关（`--dart-define=MPV_PROBESIZE=2097152 --dart-define=MPV_ANALYZEDURATION=2`）。B 每次都有声音、画面正常；斗鱼、虎牙、抖音不受影响（和电脑上的结论一样）。
- 加上阶段 1 的其他平台，冷进房的 P90 已在 2.5 秒以内（原来超出的全是哔哩哔哩）。
- C（512 KiB / 0.5 s）没在手机上试：B 已经达标，C 在电脑上对哔哩哔哩没有更快（704 vs 627 ms）。
- 快手：这一轮 3 次里只有 1 次开出来（`detail=2485`），另外两次没有计时行——电脑上量快手时触发了同一出口的“请求过快”风控，K90 也受影响。快手第一次进房省掉第二次取房间页（`8432f9910`）的效果要等风控过去再看。
- 没测：上下滑换房、弱网（K90 上没有只限测试包的限速办法）。
