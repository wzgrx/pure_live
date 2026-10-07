# G01 引擎

播放的“下半截”：mpv 引擎本身（media_kit 分支、libmpv 和 FFmpeg 原生包、mpv 属性、软硬解），以及把平台给的一条线路变成“交给 mpv 的地址”的取流管线（选源、选路、本地中继、配方输入、错误分类）。

## 范围

- 包括：
  - `packages/live_media`（纯 Dart）：`PlaybackPlan` 选源和“优先 H.264”排序、`MediaRoute` 选路、`MediaOpener` 开源、`PlaybackTransport` 事务、`LineFallback` 和 `DecoderFallback`、`NativeDiagnostic` 错误分类、`SourceEventFence` 事件分代、`engineProxyUrl`、`relay/` 下的本地中继（FLV 续签拼接、codec 12 HEVC 改写、HLS 列表改写和续签、会话 Cookie、证书放行表）、`inputs/recipes.dart` 的 Bigo、FC2、niconico 配方打开器。
  - `packages/live_player` 里和引擎有关的部分：`MpvEngine`（属性、打开、事件转发、纯音频、帧率探测）、`MpvEngineConfig`（3.x 的硬解、兼容模式、自定义输出、RTX 超分设置换成 mpv 属性）、`NativeDiagnosticGate`、`mpvEngineProfile()`、`probeFrameRate`。
  - `third_party/media_kit`、`third_party/media_kit_video`（补丁分支）和原生包清单 `third_party/media_kit/hook/native_bundles.json`。
  - “优先 H.264”默认值的评估（G01.2）。
- 不包括（归哪里）：
  - 会话怎么用这些东西（打开顺序、看门狗、恢复、预取）→ [G02](../G02-会话和恢复/README.md)；探测和缓冲参数为了起播速度怎么调 → [G03](../G03-起播速度和弱网/README.md)（改的仍是本子分类的 `mpv_options.dart`，由 G03 的任务做）。
  - 线路从哪来、带什么请求头、编码标记、租期、画质名 → E 组（E05 管 `LivePlayLine` 模型）。
  - 设置页上“硬件解码”“优先 H.264 编码”“播放器内核”等行的样子 → A11.3；设置的存储 → J 组。
  - 录制复用 `LoopbackRelay`、`HlsRoute`、配方打开器，以及只给录制用的 HLS 预取窗口 `relay/hls_window.dart` → [H01](../../H-录制/H01-录制核心/README.md)。
  - 播放代理的设置 → [Q02](../../Q-网络和代理/Q02-代理和镜像/README.md)；本子分类只调用 `ProxyPolicy`。

## 现状：做到哪、怎么工作的

- 用户看得到的：进直播间出画面（国内平台在 K90 冒烟中正常）；清晰度菜单里 HEVC 档带标记，“优先 H.264 编码”开着时（默认）HEVC 线路排在后面；硬解失败的房间自动改软解继续播；斗鱼的签名地址到期时画面不断（中继在关键帧处换上新连接）；Bigo、FC2、niconico 这些没有直接地址的平台由本地中继播放。
- 内部怎么工作（一次打开）：
  1. 直播间 `room_controller.dart:515` 的 `_plan` 调 `PlaybackPlan.of(resolution, preferH264:, onDemand:)`（`source.dart:156-177`）：有配方的变成一个 `RecipeSource`；否则 `normalized()` 后的线路按“优先 H.264”把 `codec == 'hevc'` 的排到最后，变成 `LineSource` 列表。
  2. 会话把选中的源交给 `MediaOpener.open`（`input.dart:112`），它按 `MediaRoute.of`（`source.dart:111-127`）选路：FLV 且租期切断连接且能续签 → `flvSplice`（斗鱼）；FLV 可能是 codec 12 HEVC 且引擎读不了 → `flvRewrite`（现在只有 FFmpeg 版本未知的包会走）；HLS 有令牌传递策略或租期切断连接 → `hlsRelay`（CHZZK、PandaTV、YouTube 等）；其余 `direct`，mpv 自己连 CDN。配方走 `RecipeOpener`（`inputs/recipes.dart:71`、`:93`、`:145`）。
  3. 需要中继时按需启动一个共用的 `LoopbackRelay`（`relay/loopback_relay.dart:37`，只绑 127.0.0.1，每个输入一个随机路径，关掉即 404）。
  4. 结果是 `MediaInput`（地址、请求头、mpv 的 `http-proxy`、点播起点、`isUsable`、`close`），由 `PlaybackTransport`（`transport.dart:20`）在引擎接受后才释放旧输入。
  5. `MpvEngine.open`（`mpv_engine.dart:162-193`）每次设 `hwdec`（硬解时 `auto-safe`，软解回退 `no`）和 `http-proxy`，带请求头 `player.open`；打开后补发当前的缓冲、播放状态，并在 2 秒后读 `container-fps`、`estimated-vf-fps`（`frame_rate.dart:16-36`）给 R02。
  6. mpv 的错误日志经 `NativeDiagnosticGate`（`diagnostics.dart:19`）按 3.x 的前缀和分类变成 `EngineError`；解码类错误由会话交给 `DecoderFallback`（`fallback.dart:73`）改软解。
- 引擎配置：播放器建好后按 3.x 顺序设一次直播属性（`mpv_options.dart:133-158`：`demuxer-lavf-probesize` 2 MiB、`demuxer-lavf-analyzeduration` 2 秒、`cache-secs` 6、`demuxer-max-bytes` 32 MiB、`demuxer-max-back-bytes` 4 MiB、`demuxer-readahead-secs` 2、`network-timeout` 15、`hwdec-software-fallback` 1、Android 的 `ao=audiotrack,aaudio,opensles,`）。设置来自直播间 `live_play_page.dart:399`、多画面 `multiview_page.dart:141`、电视 `tv/room/tv_live_play_page.dart:32` 各自的 `_engineConfig`（读 `enableCodec`、`customPlayerOutput`、`videoOutputDriver`、`videoHardwareDecoder`、`audioOutputDriver`、`playerCompatMode`、`enableRtxVsr`）。
- 原生包（`native_bundles.json`、`engine_profile.dart:15-28`）：Android arm64、armeabi-v7a、x86_64 和 Linux x64 是本仓库 Releases 的自建包（mpv 0.41.0 + FFmpeg 9.0.2），能直接读 codec 12 的 HEVC FLV，不改写；Windows 是 Predidit 的开发版（FFmpeg master）；Android x86、Linux arm64、iOS、macOS 是 Predidit 的包、FFmpeg 版本没写，`mpvEngineProfile()` 对它们打开改写。
- 完成度（和 3.x 对照）：
  - 一致：错误分类的顺序、关键词和代码；事件分代；事务规则；mpv 属性的值和顺序；配方每次打开各取各的授权；codec 12 → Enhanced FLV 的改写逐字节同 3.x。
  - 确认过的改动（G01.1、G02.1 的“有意差异”）：只用 mpv；引擎降级 → 硬解改软解；请求头跟线路走；HLS 中继纯 Dart；租期切断连接的 HLS 也续签；一个中继服务所有输入；证书放行表只放百度两类主机。
  - 修掉的 3.x 问题 18 个（G01.1 10 个、G02.1 8 个，见两个任务的说明）。
  - 还缺：“优先 H.264”默认值没有真机依据（G01.2）；Steam 分档画质没有真的限定变体（见“已知问题”）。

## 代码地图

`packages/live_media/lib/src/`：

| 文件 | 职责 |
|---|---|
| `source.dart`（208 行） | `PlaybackSource`（`:8`）、`LineSource`（`:20`）、`RecipeSource`（`:46`）、`EngineProfile`（`:65`，`rewriteLegacyHevcFlv`、`legacyHevcHosts` 默认 `.17app.co`）、`MediaRoute`（`:88`，`of` `:111`）、`PlaybackPlan`（`:139`，`of` `:156` 的“优先 H.264”排序、`queryPolicyFor` `:204`） |
| `input.dart`（256） | `MediaInput`（`:14`）、`OwnedInput`（`:55`）、`RecipeOpener`（`:69`）、`MediaOpener`（`:80`，按需起共用中继 `:105`，`open` `:112`）、直连和中继两种输入 |
| `transport.dart`（143） | `PlaybackTransport`（`:20`）：新输入被引擎接受后才释放旧输入，晚到结果释放并报 `StateError` |
| `fallback.dart`（133） | `lineKey`（`:6`，按 `lineId`）、`LineFallback`（`:16`）、`DecoderMode`（`:59`）、`DecoderFallback`（`:73`，`shouldFallback` `:93`） |
| `errors.dart`（265） | `PlayerErrorType`（`:6`）、`PlayerException`（`:35`）、`NativeDiagnostic.classify`（`:79`，3.x 原样）、`SourceFailureKind`（`:236`）、`classifySourceFailure`（`:256`） |
| `fence.dart`（80） | `SourceEventFence`（`:11`）：每次打开一代，打开期间的事件只记标志 |
| `proxy.dart`（16） | `engineProxyUrl`（`:10`）：本地输入不走代理，其余按平台的 `ProxyPolicy` 给 mpv 的 `http-proxy` |
| `relay/loopback_relay.dart`（326） | `LoopbackRelay`（`:37`）：一个 127.0.0.1 服务，`openFlv`、`openHls`，每个输入随机路径 |
| `relay/flv_splicer.dart`（536） | `FlvSplicer`（`:159`）、`SpliceTimings`（`:16`）：续签后在新连接第一个没送出的关键帧处拼接，旧流在关键帧前最多等 10 秒 |
| `relay/flv.dart`（227） | `FlvTag`、`FlvFramer`（`:109`）、`FlvLegacyHevcRewriter`（`:186`） |
| `relay/hls_relay.dart`（543） | `HlsRelayRecipe`（`:18`）、`IoHlsUpstream`（`:80`）、`HlsRoute`（`:151`）：改写主列表、媒体列表、分片、map、key，只代理出现过的地址；`prefetch` 只给录制 |
| `relay/hls_cookies.dart`（139）、`relay/upstream.dart`（196） | 会话 Cookie 罐（TwitCasting 的 `lvhls_ssid_*`）；FLV 上游连接、`MediaTlsExemptions`（`:19`，百度两类主机） |
| `relay/hls_window.dart`（487） | HLS 预取和保留窗口，只给录制（H01），播放不用 |
| `inputs/recipes.dart`（185） | `bigoRelayRecipe`（`:14`，分片前 376 字节解扰）、niconico 主列表只留选中变体（`:25-47`）、`BigoRecipeOpener`（`:71`）、`Fc2RecipeOpener`（`:93`，`adopt` 接手已开的控制连接）、`NiconicoRecipeOpener`（`:145`） |

`packages/live_player/lib/src/`（引擎部分）：

| 文件 | 职责 |
|---|---|
| `mpv_engine.dart`（283） | `mpvPlatformOf`（`:13`）、`displaySizeOf`（`:25`）、`MpvEngine`（`:47`）：`create`（`:54`，设直播属性、建 `VideoController`）、`reportsFrames` 只有 Windows（`:100`）、`_bind` 转发 media_kit 事件（`:106-154`）、`open`（`:162-193`）、帧率探测（`:196`）、纯音频（`:230-258`）、`mpvEngineFactory`（`:282`） |
| `mpv_options.dart`（159） | `MpvPlatform`（`:4`）、`MpvEngineConfig`（`:26`）：`preferredHardwareDecoder`（`:88`）、`hwdecFor`（`:99`）、`videoOutput`（`:102`）、`audioOutput`（`:114`）、`liveProperties`（`:133-158`） |
| `diagnostics.dart`（174） | `NativeDiagnosticGate`（`:19`）：只看 3.x 认的日志前缀，可恢复错误等 1.2 秒，同一解码器出画面就取消 |
| `engine_profile.dart`（48） | `nativeBundleFfmpeg`（`:15`）、`mpvEngineProfile`（`:38`）：FFmpeg ≥8.0 或 master 不改写 HEVC FLV |
| `frame_rate.dart`（36） | `parseFrameRate`（`:5`）、`probeFrameRate`（`:16`，`container-fps` 优先，读不到时等 `estimated-vf-fps` 稳定） |
| `engine.dart`（198） | `EngineMedia`（`:9`）、`EngineEvent` 一族（`:59-159`）、`PlayerEngine` 接口（`:165`）、`EngineFactory`（`:198`） |

其他：`third_party/media_kit/lib/src/player/native/player/real.dart`（缓冲、播放状态从 mpv 属性来：`START_FILE` `:1374-1388`、`core-idle` `:1402-1420`、`paused-for-cache` `:1421-1427`）；`third_party/media_kit_video/PURELIVE_PATCH.md`（补丁清单）；`third_party/media_kit/hook/native_bundles.json`（原生包地址和 SHA-256）。

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_media/test/errors_test.dart`（9） | 错误分类（移植 3.x）、取流失败分类、事件分代 |
| `packages/live_media/test/plan_test.dart`（14） | 线路回退（越界、续签后失败记录）、解码降级、“优先 H.264”排序、配方计划、选路、直连输入和引擎代理 |
| `packages/live_media/test/flv_splicer_test.dart`（4） | 续签拼接无缝、旧连接提前断、续签失败重试、无后继时结束（`fake_async`） |
| `packages/live_media/test/relay_test.dart`（8） | 本机回环上的 TwitCasting 会话 Cookie、Bigo 解扰、令牌传递、HLS 续签换地址、HEVC 改写、关闭后 404、niconico 变体选择、Cookie 规则 |
| `packages/live_media/test/transport_test.dart`（3）、`hls_window_test.dart`（2，录制） | 事务；录制的预取窗口 |
| `packages/live_player/test/options_test.dart`（5）、`diagnostics_test.dart`（4）、`frame_rate_test.dart`（5） | 直播属性、解码和输出选择、按原生包决定改写、显示尺寸和旋转；诊断门；帧率读取 |

## 3.x 基线

文件都在 `git show v3.2.11:lib/player/` 下：

- 适配器 `adapters/media_kit_adapter.dart`（1266 行）：直播属性逐个 `setProperty`（`:84` 探测 2 MiB、`:89` 分析 2 秒、`:98` `network-timeout` 15），缓冲策略 `utils/live_buffer_policy.dart`（`cache-secs`、`demuxer-max-bytes`、`demuxer-readahead-secs` 2）；读全局设置（`:106-127`、`:266-303`）。
- 多引擎：`adapters/fijk_adapter.dart`、`video_player_adapter.dart`、`fvp_adapter.dart`，`core/engine_fallback_manager.dart`（73 行）按引擎降级；4.x 只留 mpv，降级改成解码方式。
- 取流：`core/playback_source_transport.dart`（303，事务）、`core/line_fallback_manager.dart`（38，`:11` 越界、`:23` 按完整 URL 记失败）、`core/player_error_classifier.dart`（188）、`core/source_event_fence.dart`（83）、`core/playback_proxy_policy.dart`（29）、`core/playback_header_resolver.dart`（211，按平台写请求头）。
- 中继：`core/flv_splice_relay.dart`（538，斗鱼续签拼接，`_handover` 推迟一个 GOP）、`core/flv_legacy_hevc_relay.dart`（189，`:76` 只认 `.17app.co`）、HLS 借用录制的 `recorder/services/ffmpeg_hls_input_relay.dart`；配方 `core/bigo_playback_input.dart`、`fc2_playback_input.dart`、`niconico_playback_input.dart`。
- media_kit 分支在 3.x 的 `third_party/`（`d13fc22b`，FFmpeg 7.1，读不了 codec 12）；`third_party/fvp`。
- 3.x 没有“优先 H.264”，HEVC 档和 H.264 档按平台给的顺序。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| “优先 H.264”默认开没有真机依据：升级的统一原则写着“在高通真机上验证硬解后再评估”，G01.1、G02.1、S02.3 都没做 | `packages/live_store/lib/src/settings/settings.dart:293` | 默认看不到 HEVC 档（同码率画质更好、更省流量）；也不知道 K90 硬解 HEVC 稳不稳 | G01.2 |
| **映客默认播 HEVC**：映客开着“优先 H.264”时画质是 `[FLV, 原画]`（`inke_site.dart:347`），但默认清晰度按名字找“原画”（`apps/pure_live/lib/shared/rooms/play_quality.dart:7-10`，设置 `preferResolution` 默认“原画”，`settings.dart:270-273`），而映客的“原画”只有即构的 HEVC 线路（`inke_api.dart:165-169`），所以默认就落在 HEVC 档，“优先 H.264”对它不起作用 | `play_quality.dart:9`；`packages/live_core/lib/src/sites/inke/inke_site.dart:340-348` | 和设置“优先 H.264 编码”的说明不符；K90 上 HEVC 硬解不稳时映客会先失败再软解 | 先由 G01.2 测映客 HEVC；不管结论如何，“按名字选原画”和“优先 H.264”谁优先要定（建议：开着“优先 H.264”时名字匹配跳过 `codec == 'hevc'` 的档），需要维护者开任务（E02.5 或 C01） |
| **Steam 选“720p”实际仍是自适应**：每个变体档的 `resolvePlayUrlsRaw` 返回的都是同一个主列表地址（`steambroadcast_site.dart:440-448` 的 `_resolution`），`SteamBroadcastVariant.selectIn`（`steambroadcast_api.dart:82`）只在平台包里定义，播放管线没有任何地方用它限定变体；mpv 拿到完整主列表按带宽自己选。UPGRADES 27-7 写“完成（G01.1）：各档是普通 HLS 线路，播放核心无需改动”不对 | `packages/live_core/lib/src/sites/steambroadcast/steambroadcast_site.dart:440-448`；`packages/live_media/lib/src/source.dart:111-127`（没有“按变体改写主列表”的路线） | 用户选 720p 仍可能播 1080p60（流量、发热），清晰度菜单显示的档和实际不符 | 需要开任务：线路带上变体选择（例如 `LivePlayUrlResolution` 加主列表筛选，`MediaRoute.of` 遇到它走 `hlsRelay`，中继像 niconico 那样只留选中变体，参考 `inputs/recipes.dart:25-47`）；UPGRADES 27-7 改回“部分完成” |
| HEVC FLV 改写只在 FFmpeg 版本未知的包上打开；Android x86、Linux arm64、iOS、macOS 的包是否真的读不了 codec 12 没验证 | `engine_profile.dart:15-28` | 这些平台多一层中继（性能略差），或者本来能读 | 做到这些客户端时验证（X 组） |
| YouTube、PandaTV 两个平台各自写了宽松的 HLS 主列表解析，没有合并 | `packages/live_core` 的两个平台适配器 | 重复代码；中继本身按行改写，不受影响 | 没有任务（E 组） |
| LiveMe、TikTok 的租期按“不切断连接”处理，只预取 | 平台层的 `PlayLease.cutsConnection` | 如果实际会断，到点会断流后再恢复 | 两个平台都受阻（D01.18、D01.19、E 组），看到断开再改标记 |
| FC2 画质探测时开的控制连接不交给播放，播放再开一条 | `inputs/recipes.dart:93`（`adopt` 已有），应用没接 | 多开一次连接，起播慢一点 | E06.2（阶段“FC2”，暂停） |
| 斗鱼续签拼接、HEVC FLV、Bigo、FC2、niconico 配方没有真机记录 | G01.1 记录“验证” | 这些路线只在本机回环测试里跑过 | 建议并入 S02.6（国内）、S02.4（海外，开代理） |
| 原生包不进 git、构建时下载：网络断时 `flutter build` 失败在 media_kit 的构建钩子（R01.1 记录遇到过 `archive.zip.partial`） | `third_party/media_kit/hook/` | 新工作区第一次构建可能失败 | 不做代码改动；从主仓库的 `.dart_tool` 缓存拷同一个包（按哈希命名）或重试（Z 组工具链说明） |
| 代码注释里还用旧编号（M7.1、M7.2、U.2i） | `source.dart:70-72`、`engine_profile.dart:34`、`mpv_engine.dart:195` 等 | 找文档要先查 MAPPING | Z 组统一替换 |

## 相关决定和规范

- D-001（照 3.x 逐块重构）：错误分类、事务、mpv 属性照 3.x。
- D-017：中继测试在回环上跑真实 HTTP 服务、不访问真实平台；拼接测试用 `fake_async`。
- D-018：3.x 的播放设置键名和含义不变；`preferH264` 是 4.x 新加的，改默认值不违反。
- [specs/ENGINEERING.md](../../specs/ENGINEERING.md) 第 4 节：`live_media` 纯 Dart，只依赖 `live_core`、`live_net`（`tools/gate/check_deps.py` 检查）；第 5 节：上游 media_core 只借鉴修复思路，不照搬架构。
- [specs/UPGRADES.md](../../specs/UPGRADES.md)：统一原则“默认编码”（G01.2）；6-1、8-8、11-1、14-5、22-2、22-3、26-2、27-7、29-8、30-2、33-2。

## 测试和验证

- 自动测试：`cd packages/live_media && dart test`（40 个，中继测试在本机回环上起服务）；`cd packages/live_player && flutter test`（引擎部分 14 个，不需要 libmpv 运行；构建钩子会下载 Linux x64 包到 `packages/live_player/build/`）。缺的：没有真实 mpv 的集成测试（属性是否被接受、HEVC 改写后 mpv 能否解）；Steam 变体限定没有用例（功能本身没做）。
- 真机：[S02 的真机清单](../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 1 节第 1、2 条（各平台出画面、切清晰度和线路）在 S02.2、S02.3 部分看过；第 3 条（断网重连）没结果；高通 HEVC 硬解在 G01.2 测。

## 路线

1. G01.2：K90 上逐平台测 HEVC 硬解（含映客），定“优先 H.264”的默认值并写进 DECISIONS；顺带给出“按名字选原画”和“优先 H.264”谁优先的建议。
2. 请维护者为 Steam 变体限定开任务（规模小到中：模型加筛选、选路、中继改写主列表、测试），同时把 UPGRADES 27-7 改回“部分完成”。
3. G03.1 测量后如果要调探测和缓冲参数，改的是 `mpv_options.dart`；按 G03.1 的数字做，不在本子分类单独开任务。
4. 以后：做到 Windows、Linux、苹果平台时核对各自原生包的 FFmpeg 和 HEVC 改写（X 组）；跟进 media_kit 上游时按 `PURELIVE_PATCH.md` 保留补丁。新想法写进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [G 播放](../README.md)。

- 代码：`packages/live_media`、`third_party/media_kit`
- 进度：`██████████░░░░░░░░░░` 50%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| G01.1 | 播放核心：media_kit 分支和取流管线 | 功能 | 完成 | 2026-10-01 | b4fb966e8 | [设计或说明](G01.1-播放核心/README.md)、[记录](G01.1-播放核心/record.md) |
| G01.2 | 高通硬解评估：在 K90 上看 HEVC 硬解，定“优先 H.264”的默认值（UPGRADES 22-3） | 验证 | 未开始 | — | — | [设计或说明](G01.2-高通硬解评估/README.md)、[任务书](G01.2-高通硬解评估/brief.md) |

## 还没完成的

- **G01.2 高通硬解评估：在 K90 上看 HEVC 硬解，定“优先 H.264”的默认值（UPGRADES 22-3）**（未开始，第二档，规模 中）
  - 阶段：K90 上逐平台测 HEVC 硬解 → 定默认值并写进 DECISIONS
  - 来源：UPGRADES 统一原则“默认编码”、22-3（V03.3 核对：S02.3 没有做这一项）

<!-- docs:生成结束 -->
