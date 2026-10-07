# G01.1 播放核心：media_kit 分支和取流管线

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（模块重构）
- 来源：4.x 逐块重构计划（D-001）的播放第一块：把 3.x `lib/player/core/` 里不依赖 Flutter 和具体引擎的部分、`lib/player/models/`，以及播放借用的录制中继，搬进纯 Dart 包 `packages/live_media`
- 旧编号：M7.1、T04a.1
- 相关：决定 D-001、D-017；后续 [G02.1](../../G02-会话和恢复/G02.1-播放器/README.md)（引擎绑定、会话）；录制复用中继 H01.1；线路自带请求头 E05.1；设置“优先 H.264” J02.1；记录 [record.md](record.md)

## 目标

- 播放层不再依赖 Flutter、全局单例和录制层：取流、选路、中继、事务、回退、错误分类都在一个能用 `dart test` 测、也能给命令行工具用的纯 Dart 包里。
- 行为照 3.x（事务规则、错误分类、回退规则、codec 12 改写逐字节），同时修掉审查发现的 10 个 3.x 问题（线路回退越界、续签后失败记录丢失、拼接推迟一个 GOP 等）。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`，文件:行） | 现在（文件:行） | 结果 |
|---|---|---|---|
| 播放源 | `lib/player/core/playback_source.dart`（`UrlPlaybackSource`、`OwnedPlaybackSource`） | `packages/live_media/lib/src/source.dart:8-63`（`LineSource` 带请求头、格式、租期；`RecipeSource`） | 同 3.x，线路信息更全 |
| 事务 | `playback_source_transport.dart`（303 行） | `transport.dart:20-133` | 规则不变：新输入被引擎接受后才释放旧输入 |
| 请求头 | `playback_header_resolver.dart:56,75,206` 按平台写在播放器里 | 删除；线路自带请求头（E05.1） | 有意差异 |
| 线路回退 | `line_fallback_manager.dart:11`（越界）、`:23`（按完整 URL 记） | `fallback.dart:16-56`（按 `lineId` 记、游标重新定位） | 修了两处 |
| 引擎降级 | `engine_fallback_manager.dart:35,54`（多引擎） | `fallback.dart:59-133`（硬解 → 软解） | 有意差异（只用 mpv） |
| 错误分类 | `player_error_classifier.dart`（188 行） | `errors.dart:79-235` | 不变 |
| FLV 续签拼接 | `flv_splice_relay.dart` `_handover`（约 200～260 行）常推迟一个 GOP | `relay/flv_splicer.dart`（归档 v4 的拼接器：旧流在关键帧前等新连接，最多 10 秒） | 修了 |
| codec 12 HEVC | `flv_legacy_hevc_relay.dart:76` 只认 `.17app.co` | `relay/flv.dart:186` + `source.dart:111-130`（线路标了 `hevc` 就算；按引擎能力开关） | 修了；Android arm64 默认不改写 |
| HLS 令牌和续签 | 借用录制的 FFmpeg 中继（`recorder/services/ffmpeg_hls_input_relay.dart`） | `relay/hls_relay.dart:151`（纯 Dart 改写列表、转发分片；租期切断的 CHZZK、PandaTV 也续签） | 有意差异 |
| 配方输入 | `bigo_playback_input.dart`、`fc2_playback_input.dart`、`niconico_playback_input.dart`（195 行，放在录制层） | `inputs/recipes.dart:71-185` | 每次打开各取授权；录制反过来依赖它 |
| 本地服务器 | 每个 FLV 中继各开一个（`flv_splice_relay.dart:359`、`flv_legacy_hevc_relay.dart:106`） | `relay/loopback_relay.dart:37`（一个服务，每个输入一个随机路径） | 修了 |
| 播放代理 | `playback_proxy_policy.dart:11` 只看全局设置 | `proxy.dart:10`（和平台请求共用 `ProxyPolicy`） | 修了 |

## 结果

- 改动（提交 `b4fb966e8`，2026-10-01，“feat(live_media): playback core”）：
  - c1 选源：`PlaybackPlan.of(resolution, preferH264:, onDemand:, start:)`，“优先 H.264”时 `hevc` 线路排后。
  - c2 定路：`MediaRoute.of`：`flvSplice`、`flvRewrite`、`hlsRelay`、`owned`、`direct`。
  - c3 开源：`MediaOpener.open` 返回 `MediaInput`；共用 `LoopbackRelay` 按需启动一次。
  - c4 HLS 中继：主列表、媒体列表、分片、map、key 全改写成本地地址，只代理列表里出现过的地址；会话 Cookie 按来源和路径回传。
  - c5 事务：`PlaybackTransport`。
  - c6 回退和错误：`LineFallback`、`DecoderFallback`、`NativeDiagnostic.classify`、`classifySourceFailure`、`SourceEventFence`。
  - c7 证书放行表：只对百度 `flv-live.bdstatic.com`（证书和主机不符）、`*.liveshow.lss-user.baidubce.com`（证书链不完整）放行（`relay/upstream.dart:19`）。
- 修掉的 3.x 问题：10 个（记录“审查发现的 v3 问题”表）。
- 依赖：新包 `live_media`（`live_core`、`live_net`、`meta`、`clock`；测试用 `fake_async`）。
- 偏差：“HEVC FLV 改写”默认关（4.x 原生包的 FFmpeg 9.0.2 能读），由 G02.1 的 `mpvEngineProfile()` 按包开关；`live_stream_geometry_hint`（抖音画面比例）留给 G02.1，后来由 [G04.1](../../G04-画面/G04.1-竖屏流的画面比例预判/README.md) 做完。
- 测试：38 个（`errors_test` 9、`plan_test` 14、`flv_splicer_test` 4、`relay_test` 8、`transport_test` 3）。

## 验证

- 自动测试：`cd packages/live_media && dart test`；中继测试在本机回环上起真实的 HTTP 服务。
- 真机：没有单独的 verify.md。播放管线在 K90 冒烟（[S02.2](../../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md)，2026-10-02）和主流程（[S02.3](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md)）里随哔哩哔哩等平台的播放一起看过；斗鱼续签拼接、HEVC FLV、Bigo、FC2、niconico 的配方输入没有单独在真机上记录结果。

## 留下的问题

- YouTube、PandaTV 的宽松 HLS 主列表读法合并：在 `live_core` 的平台适配器里，没有任务（建议 E 组登记）。
- LiveMe、TikTok 的租期是否切断连接：现在按不切断只预取，没有任务（真机看到断开再改平台层标记）。
- FC2 画质探测交出控制连接、哔哩哔哩轮播从 `play_time` 播：在 E06.2（暂停）。
- “优先 H.264”默认值：等高通真机硬解验证，没有任务（见 [G01 已知问题](../README.md#已知问题和限制)）。
