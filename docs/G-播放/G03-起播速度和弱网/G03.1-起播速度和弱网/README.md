# G03.1 起播速度和弱网：测首帧时间，找出慢的环节，改进后真机对比

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：性能
- 来源：PLAN 原则 4“速度（起播、滑动、响应）优先”和第一档；[specs/UI.md](../../../specs/UI.md) 第 9.4 节的指标“点击直播间到画面出现：不超过 v3 的 70%”；2026-10-02 整理文档时从播放组的余项登记（旧编号 T04c.1）。
- 旧编号：T04c.1
- 相关：前置 [G02.2](../../G02-会话和恢复/G02.2-缓冲状态对账/README.md)（会话对账和恢复原因日志，先合并）；[G01.2](../../G01-引擎/G01.2-高通硬解评估/README.md)（HEVC 和 H.264 的首帧对比用本任务的打点）；C01（直播间编排，`room_controller.dart`）、C02.1（`PlayerStandby` 复用播放器）、A07.7（加载时画面上显示什么）、A07.13（切换直播间面板）、R04.1（冷启动，同一套打点思路）；E 组（平台接口慢的部分）；任务书 [brief.md](brief.md)

## 目标

- 有数字：K90 上从“点进直播间”到“第一帧画面”的时间，按平台、按冷进房 / 复用播放器、按网络条件拆成几段（取详情、取画质、取地址、建引擎、开输入、mpv 加载到首帧），知道慢在哪。
- 变快：按数字改最慢的两三段，目标是国内五大平台在 Wi-Fi 下中位数 ≤1.5 秒、P90 ≤2.5 秒（能测到 3.x 时再加上“≤3.x 的 70%”）。
- 弱网撑得住：200 毫秒延迟、2 Mbps、1% 丢包下能起播（中位数 ≤5 秒），播放中不因为短暂的低速反复“正在重连”。
- 用户感觉到：点进去画面来得更快；上下滑换房更快；网差时少见“正在重连”。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`，文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 起播打点 | 没有 | 没有 | 每次打开一行分段计时日志，测完保留（以后回归用） |
| 进房编排 | `modules/live_play/controllers/live_play_controller.dart:249` 取详情，`player_controller.dart:594` 选清晰度，`player/core/player_manager.dart` 的 `playSource` | `features/live_play/live_play_page.dart:196-262` → `logic/room_controller.dart:304`（先 `await` 读屏蔽表和 meta `:316-319`）→ `load` `:360` → `_startStream` `:413` → `_openQuality` `:462` → `session.open` `:503` | 取详情前不等本地读库；能并行的并行 |
| 引擎创建 | 全局播放器，原生解码器第一次播放时才建 | 第一次 `_openSource` 才建（`packages/live_player/lib/src/session.dart:473` → `_engineNow` `:406` → `MpvEngine.create`，`mpv_engine.dart:54-75`）；关闭直播间 45 秒内进下一个房间可复用（`player_standby.dart:15`） | 冷进房时建引擎和网络请求并行（数字证明值得时） |
| mpv 探测和缓存 | `media_kit_adapter.dart:84`、`:89`：2 MiB / 2 秒；`live_buffer_policy.dart` | `mpv_options.dart:136-138`：同 3.x；`cache-secs` 6、预读 2 秒 | 用 A/B 数字决定是否调小 |
| 换房 | `switchRoom` 先关旧的再开新的 | `live_play_page.dart:359-395`：等旧房间 `dispose` 完才 `controller.start()` | 新房间的网络请求不等旧房间释放（只有 `session.open` 等） |
| 弱网时限 | 打开 18 秒、缓冲 12 秒、`network-timeout` 15 | `session.dart:44-48`、`mpv_options.dart:149`：同 3.x | 按弱网测试的数字决定要不要调 |

## 方案

按登记表的四个阶段：

- 阶段 1 测量现状：
  - c1 打点（代码，测完保留）：直播间记 `T0`（`initState`）、`T1` 详情回来、`T2` 画质回来、`T3` 地址回来；会话记 `T4` 引擎就绪（新建或复用）、`T5` 输入打开（`MediaOpener.open` 返回，带路线 `direct`/`flvSplice`/`hlsRelay`/`owned`）、`T6` `engine.open` 返回、`T7` 第一个 `EngineVideoSize`（首帧画面参数）、`T8` 第一次 `playing`。每次打开结束（首次 `playing`、出错或被新打开取代）时写一行：`playback-timing site=<平台> route=<路线> engine=<new|reused> detail=<ms> qualities=<ms> urls=<ms> engineReady=<ms> input=<ms> load=<ms> firstFrame=<ms> playing=<ms> total=<ms>`，进应用日志（info）并 `debugPrint`。
  - c2 K90 测量：国内五大平台（哔哩哔哩、斗鱼、虎牙、抖音、快手）各选 2 个热门房间，每个房间冷进房 5 次（杀进程或等 45 秒让引擎释放）、复用进房 5 次（从首页连续点）；上下滑换房 10 次；弱网（见任务书的做法）对哔哩哔哩、斗鱼、虎牙各 5 次，外加 10 分钟连续播放数重连。
  - c3（可选）3.x 基线：另装一个把包名改成 `com.mystyle.purelive.v3bench` 的 v3.2.11 构建（不碰用户的 3.x），用录屏数帧测同样的房间。
- 阶段 2 找出慢的环节：c4 按分段数字排出最慢的段；c5 对 mpv 参数做 A/B（探测 2 MiB / 2 秒 vs 1 MiB / 1 秒 vs 512 KiB / 0.5 秒，各平台各 5 次，同时看音轨和画面是否正常）；c6 写结论和要做的改动，有用户可见取舍的列给维护者确认。
- 阶段 3 改进（候选，按阶段 2 的结论选做）：c7 进房即预建引擎（会话加 `prepare()`，`initState` 时调用，和取详情并行）；c8 `start` 里读屏蔽表、meta 和 `load` 并行；c9 换房时新房间先取详情和地址，只有 `session.open` 等旧房间释放；c10 调 mpv 探测参数（只在 A/B 证明更快且没有副作用时）；c11 弱网时限（例如缓冲期限按“有数据在进”延长，而不是一刀切 12 秒；只在弱网测试证明反复重连时）；c12 应用启动后空闲时预热本地中继（只在 `flvSplice`/`hlsRelay` 平台的首个输入明显慢时）。
- 阶段 4 真机对比：c13 同样的矩阵再测一遍，表格写改前改后。

## 性能任务：测量

| 指标 | 改之前 | 目标或结果 | 怎么测 |
|---|---|---|---|
| Wi-Fi 冷进房 `total`（T0→首次 playing），五大平台中位数 | 待测（阶段 1） | ≤1.5 秒；能测 3.x 时同时 ≤3.x 的 70% | `playback-timing` 日志，每平台 2 房间 × 5 次 |
| Wi-Fi 冷进房 `total` 的 P90 | 待测 | ≤2.5 秒 | 同上（50 个样本取第 45 个） |
| Wi-Fi 复用播放器进房 `total` 中位数 | 待测 | ≤1.2 秒 | 同上，从首页连续点 |
| 会话部分（`session.open`→首帧，T3→T7）中位数 | 待测 | ≤0.8 秒 | 同上 |
| 换房（上下滑松手→首帧）中位数 | 待测 | ≤1.5 秒 | 同上，竖屏全屏滑动 10 次 |
| 弱网（200 ms、2 Mbps、1% 丢包）冷进房中位数 | 待测 | ≤5 秒，10 次里 0 次 `source_open_timeout` | 同上 + 应用日志的恢复原因（G02.2） |
| 弱网连续播放 10 分钟的“正在重连”次数（流码率低于带宽时） | 待测 | 0 次 | G02.2 的 `playback: recovering` 日志 |

## 验证

- 自动测试：打点（`packages/live_player/test/session_test.dart` 新用例：一次打开各段只记一次、被新打开取代时不写、复用引擎时 `engine=reused`；`apps/pure_live/test/features/live_play/` 新用例：直播间的 T0～T3 顺序对、写出一行日志）；阶段 3 的每个编排改动各有用例（见任务书）。
- 真机：任务书“真机验证”一节的矩阵；结果和改前改后对比写进 `record.md`。

## 留下的问题

- 平台接口慢的（取详情、取地址要几个请求）只给数字，交给 E 组按平台开任务。
- 弱网自动降清晰度、加载时显示缓冲百分比是新行为，先进 V01 提议（D-026）。
- 多画面 4 路同时起播的时间在 N01 看。
