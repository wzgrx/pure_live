# G03.1 起播速度和弱网：记录

- 日期：2026-10-08
- 执行者：Claude（Opus 5.5）
- 分支和提交：本机工作区；阶段 1 c1 打点一个提交（`[G03.1]`）
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 进度

| 阶段 | 编号 | 状态 |
|---|---|---|
| 1 测量现状 | c1 打点 | 做完（本记录） |
| 1 测量现状 | c2 K90 测量 | 等维护者在 K90 上测（见“怎么收集”） |
| 1 测量现状 | c3 3.x 基线（可选） | 没做 |
| 2～4 | c4～c13 | 没开始；阶段 2 等 c2 的数字 |

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
