# T04a.1 播放核心

- 日期：2026-10-01
- 目标包：`packages/live_media`（纯 Dart，依赖 `live_core`、`live_net`、`meta`、`clock`；测试另用 `fake_async`）
- 范围：v3 `lib/player/core/` 里不依赖 Flutter 和具体引擎的部分、`lib/player/models/`，以及播放用到的 `recorder/services/*_hls_input.dart`、`hls_session_cookies` 的中继部分。引擎绑定（media_kit 分支、Flutter、`PlayerManager` 的会话和恢复状态机）是 T04b.1。
- 参考：归档 v4 `packages/live_media`（中继、FLV 拼接、HLS 改写，借鉴处在代码注释里注明）、`spec/modules/playback.md`。

## 做法

把 live_core 给出的东西变成“交给引擎的东西”：

1. **选源**：`PlaybackPlan.of(LivePlayUrlResolution, preferH264:, onDemand:, start:)` 把一个画质的回答变成有序的 `PlaybackSource` 列表——普通线路是 `LineSource(LivePlayLine)`，没有地址的平台是 `RecipeSource(LiveInputRecipe)`（Bigo、FC2、niconico）。“优先 H.264”打开时 `hevc` 线路排到后面。
2. **定路**：`MediaRoute.of(line, engine:, canRenew:, queryPolicy:)` 按顺序判断：
   - FLV 且租期会切断连接（斗鱼 `expire`）且能续签 → `flvSplice`，本地中继在 `refreshAt` 取新地址，在新连接第一个没送出的关键帧处无缝拼接；
   - FLV 可能是 codec 12 的 HEVC，且引擎读不了 → `flvRewrite`，逐标签改写成 Enhanced FLV；
   - HLS 带令牌传递策略，或租期会切断连接且能续签（CHZZK、PandaTV）→ `hlsRelay`；
   - 其余 → `direct`，引擎自己连 CDN，带线路的请求头和本平台的代理。
3. **开源**：`MediaOpener.open(source, site:, renew:, ...)` 返回 `MediaInput`（地址、请求头、是否本地、mpv 的 `http-proxy`、点播与起点、`isUsable`、`close`）。本地中继按需启动一次（`LoopbackRelay`，只绑 127.0.0.1，每个输入一个随机路径，关掉即 404）。配方由 `RecipeOpener` 打开：
   - `BigoRecipeOpener`：每次开都向工作室要新令牌（`BigoSite.resolveInput`），中继把每个分片前 376 字节解扰（`bigoRelayRecipe`）；
   - `Fc2RecipeOpener`：每次开一条自己的控制连接（`Fc2LiveSite.openControl`，按配方的档位），连接断了输入就不可用；`adopt` 可以接手画质探测时已经开好的控制连接；
   - `NiconicoRecipeOpener`：每次读观看页、开自己的座位，每个请求带该路径当时的 Cookie；指定分辨率时主列表只留那一个变体（`niconicoRelayRecipe`）；座位结束或主列表换了地址，输入不可用。
4. **HLS 中继**（`HlsRoute`）：主列表、媒体列表、分片、map、key 全改写成本地地址，只代理列表里出现过的地址（不是开放代理）；每个上游请求带线路请求头、配方的 Cookie、上游 `Set-Cookie` 下发的会话 Cookie（按来源和路径，TwitCasting 的 `lvhls_ssid_{movie}`）；令牌按 `HlsSourceQueryPolicy` 传给子请求；租期切断连接的线路到点续签，引擎已经拿到的子列表按位置指向新地址。
5. **事务**：`PlaybackTransport`（v3 的 `PlaybackSourceTransport`）一个播放器一个，新输入被引擎接受后才释放旧输入，晚到的结果不会变成当前输入。
6. **回退和错误**：`LineFallback`（线路）、`DecoderFallback`（硬解 → 软解，替代 v3 的多引擎降级）、`NativeDiagnostic.classify`（mpv 日志分类，v3 原样）、`classifySourceFailure`（取流、开源失败：终止 / 可重试 / 已取消）、`SourceEventFence`（v3 原样）。

## 对照

| v3 文件 | 行数 | 重构后 | 说明 |
|---|---|---|---|
| `player/models/player_engine.dart` | 1 | `fallback.dart` 的 `DecoderMode` | v4 只用 mpv，多引擎换成解码方式 |
| `player/models/player_error_type.dart`、`player_exception.dart` | 23 | `errors.dart` | 不变（`PlayerException` 改为不可变） |
| `player/models/player_state.dart` | 14 | 留给 T04b.1 | 会话状态 |
| `player/core/playback_source.dart` | 41 | `source.dart` | `UrlPlaybackSource` → `LineSource`（带请求头、格式、租期），`OwnedPlaybackSource` → `RecipeSource` |
| `player/core/playback_source_transport.dart` | 303 | `transport.dart`、`input.dart` | 事务规则不变；选路移到 `MediaRoute`，中继移到 `LoopbackRelay` |
| `player/core/playback_header_resolver.dart` | 211 | 删除 | 请求头已经跟着线路走（T02g.1、T02.x），播放器不再按平台写请求头 |
| `player/core/line_fallback_manager.dart` | 38 | `fallback.dart` `LineFallback` | 修两处问题（见下） |
| `player/core/engine_fallback_manager.dart` | 73 | `fallback.dart` `DecoderFallback` | 规则不变，对象换成解码方式 |
| `player/core/player_error_classifier.dart` | 188 | `errors.dart` `NativeDiagnostic` | 不变 |
| `player/core/source_event_fence.dart` | 83 | `fence.dart` | 不变 |
| `player/core/playback_proxy_policy.dart` | 29 | `proxy.dart` `engineProxyUrl` | 按平台选路（同 API 请求） |
| `player/core/flv_splice_relay.dart` | 538 | `relay/flv_splicer.dart`、`relay/loopback_relay.dart`、`relay/upstream.dart`、`relay/flv.dart` | 用归档 v4 的拼接器（多了“旧流在关键帧前等新连接”） |
| `player/core/flv_legacy_hevc_relay.dart` | 189 | `relay/flv.dart` `FlvLegacyHevcRewriter`、`LoopbackRelay.openFlv(rewriteLegacyHevc:)` | 改写规则不变 |
| `player/core/bigo_playback_input.dart`、`fc2_playback_input.dart`、`niconico_playback_input.dart`、`live_input_playback_binding.dart` | 195 | `inputs/recipes.dart` | 每次开都取自己的授权，不共享 |
| `recorder/services/hls_session_cookies.dart`（`core/common`） | 115 | `relay/hls_cookies.dart` | 不变 |
| `recorder/services/ffmpeg_hls_input_relay.dart` 的播放用法 | — | `relay/hls_relay.dart` | 纯 Dart 改写列表和转发；预取、保留窗口等录制专用部分留给 T08a.1 |
| `player/core/live_stream_geometry_hint.dart` | 345 | 留给 T04b.1 | 依赖抖音原始流数据，v4 的抖音数据还没有宽高 |
| `background_playback_*`、`live_audio_*`、`live_room_volume_manager.dart`、`linux_mpv_runtime.dart`、`playback_lifecycle_coordinator.dart`、`portrait_stream_support.dart`、`player_manager.dart` | — | 留给 T04b.1 | 依赖 Flutter、系统服务或引擎 |

v3 调用方（`git grep` v3.2.11 `lib`）：`player_manager.dart`（26 处：选源、事务、线路和引擎回退、续签拼接）、`modules/live_play/controllers/player_controller.dart`（配方绑定、请求头）、`modules/multiview/cells/multiview_cell_player.dart`（每格一个事务、代理）、`player/adapters/media_kit_adapter.dart`（错误分类、事件栅栏、代理）、`recorder/services/ffmpeg_header_factory.dart`（请求头）。T04b.1/M13 换成：`PlaybackPlan.of` → `MediaOpener.open` → `PlaybackTransport.open(create, engineOpen)`，引擎用 `MediaInput` 的 `uri`、`headers`、`proxyUrl`。

## 审查发现的 v3 问题

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 刷新后线路变少时取线路越界（`RangeError`） | `line_fallback_manager.dart:11` | 游标是上一个列表的下标，换了列表不重新定位 | 游标记“上次给出的线路”，在新列表里重新找 |
| 2 | 签名地址续签后，失败过的线路又被当成没试过 | `line_fallback_manager.dart:23` | 失败按完整 URL 记 | 按 `lineId`（CDN 代号）记，没有才用 URL |
| 3 | 播放层依赖录制层，HLS 中继和三个配方输入都在 `recorder/services` | `playback_source_transport.dart:5`、`bigo_playback_input.dart:3` 等 | 中继最早为录制写，播放直接借用 | 中继和配方输入放进 `live_media`，录制（T08a.1）反过来依赖它 |
| 4 | 播放核心引 Flutter，不能用 `dart test` 跑、不能给命令行用 | `flv_splice_relay.dart:7`、`live_stream_geometry_hint.dart:3` | 用了 `debugPrint`、`@immutable` | 纯 Dart（`meta`），拼接事件交给调用方记日志 |
| 5 | 请求头按平台写在播放器里，读全局单例和可变静态量 | `playback_header_resolver.dart:56,75,206` | 线路不带请求头 | live_core 的线路自带请求头（T02g.1、T02.x），本模块删掉这层 |
| 6 | 每个 FLV 中继各开一个本地服务器 | `flv_splice_relay.dart:359`、`flv_legacy_hevc_relay.dart:106` | 中继各自实现 | 一个 `LoopbackRelay` 服务所有输入，每个输入一个随机路径 |
| 7 | codec 12 HEVC 只认 `.17app.co` 主机，快手、映客的 HEVC FLV 漏掉 | `flv_legacy_hevc_relay.dart:76` | 线路没有编码信息，只能猜主机 | 线路标了 `hevc` 就算，主机表保留作补充；改不改写由引擎能力决定 |
| 8 | 续签拼接时旧连接常先送出两边共有的关键帧，切换推迟一个 GOP 甚至错过断开点 | `flv_splice_relay.dart` `_handover`（约 200～260 行） | 两条连接都在直播边缘，只等新连接找关键帧 | 用归档 v4 的拼接器：新连接开始找关键帧后，旧流在下一个关键帧前停住等它（最多 10 秒） |
| 9 | 播放代理只看全局设置 | `playback_proxy_policy.dart:11` | 早于按平台选路 | 和平台请求共用 `ProxyPolicy`（T03a.1） |
| 10 | 引擎降级是 async 却不等待任何东西，日志带表情符号 | `engine_fallback_manager.dart:35,54` | — | 改为同步，不写日志 |

## 保留的 v3 行为

- 错误分类的顺序、关键词和代码（`transport`、`source_open`、`video_decoder_init`…），音视频解码分开。
- 事件栅栏：本地路径只作诊断，不作放行条件。
- 事务：新输入被引擎接受后才释放旧输入；晚到、被取消、被关闭的结果一律释放并报 `StateError`；关闭是幂等的。
- 降级规则：只有 codec、native、texture、initialization、source 降级；默认一次就换；都失败后重抛并重置。
- 配方：不保存地址、座位、授权；每次打开各取各的（播放、录制、画质探测互不共享）。
- 本地输入不走代理；中继对外只绑 127.0.0.1。
- 会话 Cookie 只回给同一来源，路径匹配，长路径优先，大小和数量有上限。
- codec 12 → Enhanced FLV 的改写逐字节照 v3。

## 有意差异

1. **多引擎 → 解码方式**：v4 全平台只用 mpv（PLAN §4），`fijk`、`exo`、`fvp` 不再存在，引擎降级改成硬解 → 软解（`DecoderFallback`）。
2. **HEVC FLV 改写默认关**：v3 的 libmpv 带 FFmpeg 7.1，不认 codec 12；v4 原生包是 FFmpeg 9.0.2，认得。`EngineProfile.rewriteLegacyHevcFlv` 留给 T04b.1 在某个构建的 FFmpeg 低于 8.0 时打开。
3. **HLS 中继改成纯 Dart**：v3 播放带令牌的 HLS 时借用录制的 FFmpeg 中继；现在由 `HlsRoute` 改写列表、转发分片。
4. **租期切断连接的 HLS 也续签**（CHZZK、PandaTV 的线路在 live_core 已标 `cutsConnection`）：v3 没有，靠出错后恢复。
5. **请求头不再由播放器按平台生成**（见问题 5）。v3 用户在设置里填的哔哩哔哩、虎牙等 Cookie 由平台层放进线路（T09b.1 接设置时传给适配器），播放器只照线路发。
6. **证书放行表**：中继走 `dart:io` 会校验证书，而百度 `flv-live.bdstatic.com` 证书和主机不符、`*.liveshow.lss-user.baidubce.com` 的证书链不完整（T02b.11），所以 `MediaTlsExemptions.known` 只对这两类主机放行；其他主机照常校验。引擎直连时 mpv 本来就不校验媒体证书，行为同 v3。
7. **`PlaybackSource` 相等**：`LineSource` 按地址相等，`RecipeSource` 按对象身份（同 v3：重建的配方不继承旧状态）。

## 待办的处理（m13_notes 的 T04 条目）

| 待办 | 处理 |
|---|---|
| YouTube、PandaTV 的宽松 HLS 主列表读法合并成一个 | 未做：两个解析器在 live_core 的平台适配器里，本模块不改其他包。中继本身不解析主列表，只按行改写，任何合法列表都能过。留给 live_core 的后续一轮 |
| niconico 座位和分路径 Cookie | 完成：`NiconicoRecipeOpener`、`niconicoRelayRecipe` |
| BIGO 前 376 字节解扰 | 完成：`bigoRelayRecipe` |
| TwitCasting `lvhls_ssid` Cookie | 完成：直连时 FFmpeg 自己回传；走中继时 `HlsSessionCookies` 回传 |
| `PlayLease` 到期是否断开（CHZZK、LiveMe、TikTok） | CHZZK 在 live_core 已标会断开，本模块按此续签；LiveMe、TikTok 仍按不断开处理（只在 `refreshAt` 预取），等 T04b.1 实机看到断开再在平台层改标记 |
| 百度 FLV 要 Referer、`flv-live.bdstatic.com` 证书不符 | Referer 已在线路请求头里（T02b.11）；证书见有意差异 6 |
| FC2 控制连接与播放共用 | 部分：`Fc2RecipeOpener.adopt` 能接手已开的控制连接；live_core 的画质探测目前用完就关，要交出连接需要平台层加接口，留给后续 |
| H.265 FLV（codec 12）要中转 | 完成：`flvRewrite` 路线，按引擎能力开关（有意差异 2） |
| 哔哩哔哩轮播从 `play_time` 开始播 | 部分：`PlaybackPlan.start` 带起点给引擎；取 `getRoundPlayVideo` 和普通视频地址是平台层的事，留给 live_core |
| 虎牙回放播点播地址 | 部分：`PlaybackPlan.onDemand` 标出点播；“结束不算失败、可以拖动”由 T04b.1 会话处理 |
| “优先 H.264”设置 | 完成核心部分：`PlaybackPlan.of(preferH264: true)`；设置项在 T09b.1，界面在 M13 |

升级条目（UPGRADES 模块列含 T04 的 12 条）的状态已逐条更新：26-2 的播放部分、27-7 完成，其余写明 T04a.1 做了什么、还剩哪个模块。

## 放到其他模块的部分

- **T04b.1**：media_kit 绑定；`PlayerManager` 拆出的会话状态机（打开、刷新、换线、重建、看门狗、恢复轮次、后台、多画面调度）；在 `refreshAt` 预取不断开的租期；点播结束和拖动；画面比例提示（`live_stream_geometry_hint`，需要 live_core 抖音数据带宽高）；“优先 H.264”默认值在高通真机硬解验证后再定；`EngineProfile` 按构建的 FFmpeg 版本填。
- **T08a.1**：录制复用 `LoopbackRelay`、`HlsRoute` 和配方打开器；v3 HLS 中继里录制专用的预取、保留窗口、低延迟部分。
- **live_core 后续**：YouTube、PandaTV 主列表读法合并；FC2 画质探测交出控制连接；哔哩哔哩轮播取地址；LiveMe、TikTok 的租期是否断开。
- **T09b.1**：“优先 H.264”设置项；平台 Cookie 传给适配器。

## 依赖变化

- 新包 `live_media` 加入根 `pubspec.yaml` 的 workspace，依赖方向按 `tools/gate/check_deps.py`（`live_core`、`live_net`）。
- 新增第三方包：`clock` 1.1.3（拼接器的时钟，测试可替换）、`fake_async` 1.3.3（只用于测试），都是 Dart 官方包的最新稳定版。

## 测试

38 个用例（`dart test`）：
- `errors_test.dart`（9）：错误分类（移植 v3 的主要用例）、取流失败分类、事件栅栏；
- `plan_test.dart`（14）：线路回退（含问题 1、2）、解码降级（移植 v3）、“优先 H.264”排序、配方计划、选路、直连输入和引擎代理；
- `flv_splicer_test.dart`（4）：续签拼接无缝、旧连接提前断、续签失败重试、无后继时结束（移植归档 v4，`fake_async`）；
- `relay_test.dart`（8）：真实回环上的 TwitCasting 会话 Cookie、Bigo 解扰、令牌传递、HLS 续签换地址、HEVC 改写、关闭后 404、niconico 变体选择、Cookie 罐规则；
- `transport_test.dart`（3）：事务的提交、晚到结果、失败和关闭释放。
