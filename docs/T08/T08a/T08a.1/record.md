# T08a.1 录制内核

- 日期：2026-10-01
- 目标包：`packages/live_record`（纯 Dart，依赖 `live_core`、`live_media`、`live_net`、`clock`、`meta`、`path`、`pinyindart`）
- 范围：v3 `lib/recorder/` 里不属于页面的部分：任务模型、设置、调度、选流、FFmpeg 调用和事件、分段和命名、合并成 MP4、重试和开播检测、租期续签、持久化和恢复，以及 `pages/recorder/recorder_controller.dart` 里的内核逻辑（这个 1763 行的 GetxService 放在页面目录，实际是录制内核）。页面、设置页、权限申请、打开文件夹是 M13；FFmpeg 插件、Android 前台服务、CA 证书文件是 T07a.1。
- 参考：归档 v4 `packages/live_record`、`spec/modules/record.md`（归档版走纯 Dart 转封装、不用 FFmpeg，与 v3 不同，只借了“注入接口、事件类型化”的思路，没搬代码）；`docs/T04/T04a/T04a.1/record.md`（中继和配方）。

## 做法

1. **任务**（`task.dart`）：`RecordTask` 就是 v3 的 `LiveRecordTask`（同样可变、同样的字段），JSON 照 v3 的 schema 9，3.x 存下的任务原样读入（T09b.1 搬进新存储）。`RecordStatus` 的值顺序是 3.x 存的下标，不动。
2. **选流**（`resolver.dart`）：`RecordStreamResolver.resolve` 照 v3 `StreamResolverService`：严格的房间详情（`LiveSiteRecordRoomResolver`）→ 画质按平台排序再把最接近“默认画质”的一档放到最前 → 只解析这次需要的那一档：续签时同画质同线路，失败后同画质下一条线路，再往后的画质，最后回到上一档的第一条线路（新签名）。线路按 scheme/host/path 去重（签名参数每次都变）。租期取自线路本身（`LivePlayLine.lease`），不再查 `LivePlayLeaseMetadata`。
3. **开输入**（`input.dart`）：`RecordInputOpener` 复用 `live_media` 的 `LoopbackRelay` 和 `MediaOpener`：
   - 租期会切断连接的 FLV（斗鱼）→ 中继拼接续签，HLS（CHZZK、PandaTV）→ 中继续签；
   - 带令牌策略的 HLS → 中继改写；
   - 配方（Bigo、FC2、niconico）→ 每次录制各开各的授权；
   - 其余 HTTP(S) 的 FLV、HLS 也走中继（同 v3：v3 录制时所有直播输入都套本地中继，见下“有意差异”2）；
   - RTMP、RTSP、文件等其他协议直接交给 FFmpeg，带线路请求头和本平台代理（`-http_proxy`）。
4. **FFmpeg**（`ffmpeg.dart`）：`FfmpegRunner`/`FfmpegExecution` 是注入接口（日志行、统计、返回码、取消），T07a.1 用 v3 的 FFmpegKit 插件或桌面的 `ffmpeg` 进程实现。`FfmpegCommand.record` 和 `merge` 生成参数列表，选项逐条照 v3 `FFmpegCommandBuilder`、`VideoProcessorService`（clock-v1 分段、`-segment_list` CSV、`flush_packets=1:...:output_ts_offset=1.4`、只对网络错误和 5xx 重连、`-xerror` 合并）。失败分类（`classifyFfmpegFailure`）、介质损坏判定（`FfmpegMediaIntegrity`）、统计时间纠偏（`normalizeLiveRecordedSeconds`）照 v3。
5. **一次录制**（`capture.dart`）：`RecordCapture` 照 v3 `FFmpegService` 的单次会话：类型化事件（`CaptureAcknowledged`、`CaptureStarted`、`CaptureProgress`、`CaptureCoverageGap`、`CaptureEnded`）。直播录制没有“正常结束”：返回 0 或 EOF 当作 CDN 断开，静默、可重试；只有用户停止算完成。停止时先关输入（中继关闭 → FFmpeg 读到结尾 → 写完最后一个分段），5 秒没结束再取消；直连输入直接取消。日志保留最后 120 行/12000 字符，并去掉地址、Cookie、签名。
6. **分段和命名**（`segments.dart`、`naming.dart`、`storage.dart`）：目录 `<根>/<平台>/<主播>/<yyyy-MM-dd>/<HH-mm-ss>/`（可选拼音），文件 `<yyyyMMdd_HHmmss_SSS>_%06d.clock-v1.ts` 和同名 `.clock-v1.csv`，合并成 `<前缀>.mp4`（重名加 `-N`）。`SegmentClock` 校验日志后生成 concat 清单（时长取下一段的起点，不猜末尾）；`SegmentReservation` 防止同一前缀被两个写入者使用。`RecordStorage` 照 v3 `CacheService`：用户选的目录只是父目录，实际写进带标记文件的 `PureLiveRecords`；在用的目录受保护，不被清理。
7. **合并**（`merge.dart`）：`RecordMerger.merge` 照 v3：有损坏标记的尝试直接拒绝（保留源文件）；写 `.partial`，FFmpeg 正常退出、日志无损坏、文件非空才改名提交，然后删分段和日志；超时按大小和时长算（30 秒～1 小时）。
8. **调度**（`scheduler.dart`）：`RecordScheduler` 照 v3 `FFmpegScheduler`：先进先出，并发上限每次读设置，两次启动至少隔 5 秒，取消等待最多 20 秒。
9. **内核**（`recorder.dart`）：`Recorder` 是 v3 `RecorderController` 去掉界面后的部分：
   - 对外：`addTask(room, startImmediately:)`、`startTask`、`stopTask`、`removeTask`（v3 `unRecorder`）、`refreshTaskStatus`、`restore(json)`、`settingsChanged()`、`keepAliveInterrupted(reason)`、`flush`、`dispose`；状态从 `changes`（每次变化后的任务列表）、`notices`（v3 的提示）读；
   - 一次尝试：选流 → 建目录 → 预留前缀 → 开输入 → 启动 FFmpeg → 每秒读分段文件算大小和码率（v3：分段封装器不报大小）；
   - 结束时：把这次的分段记为“待合并”；要重连就先重连（CDN 断开 2 秒、最多 15 秒；普通失败按设置的重试间隔和退避），会话结束（用户停止、重试用完、失败）才合并；
   - 未开播 → 等待开播，开了“挂机轮询”就按间隔（可退避）检测，开播即开始；
   - 租期不切断连接的线路：在 `refreshAt` 前 5 秒预取新地址，连接断了快速重连时直接用（未过期才用），之后按下一个租期继续预取；
   - 持久化 2 秒合并写一次，进度最多 10 秒写一次；恢复时把录制中被杀掉的任务的分段合并掉，开了“开机自启”就三路并发重新检测等待中的任务；
   - 每分钟检查一次缓存上限（开了才查），删最旧的未保护文件。

## 对照

| v3 文件 | 行数 | 重构后 | 说明 |
|---|---|---|---|
| `models/live_record_task.dart` | 616 | `task.dart` `RecordTask`、`PendingRecordingAttempt` | JSON 兼容 schema 9；`isStalled` 改为 `isStalledAt(now)` |
| `models/record_status.dart` | 83 | `task.dart` `RecordStatus` | 文字标签（`i18n`）留给 M13 |
| `models/recorder_task_ordering.dart` | 25 | `RecordTask.forDisplay` | 不变 |
| `models/record_file_item.dart` | 78 | 不搬 | 录制历史只有设置页用，M13 决定 |
| `consts/recorder_config.dart`、`recorder_keys.dart` | 358 | `settings.dart` `RecordSettings` | 默认值、范围、规整照 v3；读写（Hive 键）留给 T09b.1 |
| `ffmpeg/ffmpeg_command_builder.dart` | 250 | `ffmpeg.dart` `FfmpegCommand` | 选项不变；加 `-http_proxy`（直连输入）和 `-ca_file`（原在 `ffmpeg_tls_trust_store.dart`） |
| `ffmpeg/ffmpeg_event.dart`、`ffmpeg_types.dart` | 22 | `capture.dart` 的事件类 | Map 负载改成类型 |
| `ffmpeg/ffmpeg_manager.dart` | 100 | 删除 | 单例转发层 |
| `ffmpeg/ffmpeg_scheduler.dart` | 276 | `scheduler.dart` | 并发上限改为注入（问题 4） |
| `services/ffmpeg_service.dart` | 889 | `capture.dart`、`ffmpeg.dart` | FFmpegKit 换成注入的 `FfmpegRunner` |
| `services/stream_resolver_service.dart` | 455 | `resolver.dart` | 游标规则不变；平台错误按类型分（`NotFound`、`NeedsLogin`），加 `restricted` |
| `services/recording_segment_clock.dart` | 153 | `segments.dart` | 不变 |
| `services/video_processor_service.dart` | 476 | `merge.dart`、`segments.dart` | 不变；进度事件不搬（见“留给后续”） |
| `services/cache_service.dart`、`path_helper.dart` | 319 | `storage.dart`、`naming.dart` | 不变 |
| `services/recorder_continuation_policy.dart` | 113 | `policy.dart` | 不变 |
| `services/recording_output_metrics.dart`、`recording_bitrate_window.dart` | 240 | `metrics.dart` | 不变 |
| `services/recorder_diagnostics.dart` | 28 | `diagnostics.dart` | 不变 |
| `services/ffmpeg_flv_input_relay.dart`、`ffmpeg_hls_input_relay.dart`、`hls_upstream_client.dart`、`hls_session_cookies.dart`、`cancellable_http_connections.dart`、`hls_body_reader.dart`、`hls_http_body_metadata.dart` | 约 1900 | `input.dart` + `live_media` 中继 | 录制复用 T04a.1 的中继 |
| `services/bigo_hls_input.dart`、`fc2_hls_input.dart`、`niconico_hls_input.dart`、`owned_record_input.dart`、`live_input_recording_binding.dart` | 728 | `live_media` 的 `RecipeOpener` | 每次录制各取各的授权 |
| `services/ffmpeg_header_factory.dart` | 11 | 删除 | 线路自带请求头（T04a.1 问题 5） |
| `services/recorder_proxy_routing.dart` | 11 | `RecordInputOpener.proxy` | 和平台请求共用 `ProxyPolicy` |
| `services/ffmpeg_tls_trust_store.dart` | 112 | `Recorder.caFile`（路径由 T07a.1 给） | 证书包本身是应用资源 |
| `services/hls_prefetch_*`、`hls_retained_*`、`hls_relay_prefetch.dart`、`hls_low_latency.dart`、`hls_date_range.dart`、`hls_media_spool.dart`、`hls_relay_diagnostics.dart` | 约 2900 | 未搬 | 录制专用的 HLS 预取和保留窗口，见“留给后续” |
| `services/recording_danmaku_service.dart` | 241 | 未搬 | 见“留给后续” |
| `services/recorder_background_service.dart` | 160 | `RecordKeepAlive` 接口 | Android 前台服务由 T07a.1 实现 |
| `pages/recorder/recorder_controller.dart` 的内核部分 | 约 1500 | `recorder.dart` `Recorder` | GetX、Toast、权限、打开目录去掉 |

v3 调用方（`git grep` v3.2.11 `lib`）：`common/global/initial_services.dart`（注册 `RecorderController`，开机自启时读 `recorder_tasks` 预热）、`modules/live_play/widgets/button/record_action_button.dart`（`tasks` 查找、`addTask(startImmediately:)`、`forceStartTask`、`stopTask`、`unRecorder`）、`modules/live_play/controllers/live_play_controller.dart`（持有控制器）、`modules/home/home_page.dart` 和 `recorder/pages/*`（录制中心、设置页）、`routes/app_pages.dart`。T07a.1/M13 换成：一个 `Recorder` 实例（provider），`tasks`/`changes` 代替 `RxList`，`startTask` 代替 `forceStartTask`，`removeTask` 代替 `unRecorder`，`notices` 代替 Toast，`restore(存下的 JSON)` 代替 `restoreAndAutoPoll`。

## 审查发现的 v3 问题

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 签名地址续期时录制出现缺口，每次续期多一个 MP4 | `recorder_controller.dart:1059-1086`（`_scheduleRecorderLeaseRefresh` 到点 `ffmpeg.refreshLease`） | FFmpeg 直连 CDN，换地址只能结束这次 FFmpeg 再开一次（重新探测 5 秒） | 会切断连接的租期在中继里续签（FLV 拼接、HLS 续签），FFmpeg 不知道换了地址；不切断的只预取，断线时快速重连 |
| 2 | 为绕过 FFmpegKit 取消会截断输出，自写了 FLV、HLS 两套录制中继（约 1900 行），和播放的中继各写一份 | `ffmpeg_flv_input_relay.dart:50-55`、`ffmpeg_hls_input_relay.dart:41-49` | 停止只能取消 FFmpeg，取消会打断输出 IO | 复用 `live_media` 的中继：关闭输入即正常结束，FFmpeg 写完再退出；超时才取消 |
| 3 | 录制内核依赖 Flutter、GetX 和全局单例，不能单测、不能给命令行用 | `ffmpeg_service.dart:9-10,314`、`video_processor_service.dart:14,21`、`cache_service.dart:19,25`、`stream_resolver_service.dart:79` | `.to` 单例和 `Get.find` | 纯 Dart，全部注入 |
| 4 | 应用后台启动时并发上限可能变成 1 | `ffmpeg_scheduler.dart:24-31` | 上限从 `Get.find<RecordSettingsController>` 读，没注册就退回 1 | 上限由构造时注入的函数读设置 |
| 5 | 付费、私密、会员房间按普通失败重试到上限，用户不知道原因 | `stream_resolver_service.dart:120-131` | 房间没有受限信息，取不到地址只能当网络错误 | 取流失败且房间带受限标记时报 `restricted`（不重试，带受限类型），M13 显示原因（升级 22-1） |
| 6 | 内核里直接弹提示、拼中文文字 | `recorder_controller.dart:291-293,960`、`ffmpeg_service.dart:780-807` | 服务层用 `ToastUtil`、`i18n` | 内核给类型（`RecordNotice`、`FfmpegFailureKind`、`RecordStreamErrorType`），文字由 M13 多语言给 |
| 7 | FFmpeg 事件是字符串键的 Map，键名拼错不会报错 | `ffmpeg_event.dart`、`recorder_controller.dart:210-300` | 跨 isolate 时代的格式 | 密封类事件 |
| 8 | 卡住判定读系统时间，不能注入 | `live_record_task.dart:205-209` | `DateTime.now()` | `isStalledAt(now)`，内核统一用 `clock` |
| 9 | 只有虎牙原生 FLV 走“预取不轮换”，其他不切断连接的租期也被强制轮换 | `recorder_controller.dart:1077` | 平台特判 `HuyaTransportPolicy` | 由线路的 `cutsConnection` 决定，不按平台写 |

## 保留的 v3 行为

- 任务 JSON（schema 9）：枚举优先按名字读，数字漂移容错，INT32_MAX 时长哨兵清零，签名地址不写，诊断再次脱敏，未知阶段丢弃，待合并尝试去重且损坏标记只增不减。
- 选流游标、画质排序（平台 rank、五档偏好按位置换算）、线路去重。
- FFmpeg 参数逐条一致；失败分类关键词和顺序一致；直播 EOF 静默快速重连，不进入慢速轮询；只有用户停止算完成。
- 重试：CDN 断开 2 秒起、最多 15 秒；普通失败按设置；`retryCount` 录满 10 秒清零；重试用完转为等待开播。
- 一个会话里多次尝试的时长、大小累计；合并后用 MP4 实际大小替换这次分段的大小。
- 分段日志（clock-v1）的校验和 concat 清单；只合并本次尝试的文件，3.x 旧格式只在崩溃恢复时允许。
- 合并：损坏的尝试保留源文件；`.partial` 改名才算提交；有删不掉的分段时保留日志。
- 目录：用户目录下建 `PureLiveRecords` 和标记文件；Android 私有目录不能选；在用目录不清理。
- 调度：先进先出，同一任务只排一次，两次启动隔 5 秒。
- 恢复：录制中被杀的任务合并分段后标为停止；开机自启三路并发检测。

## 有意差异

1. **FFmpeg 由应用注入**：v3 直接调用 `ffmpeg_kit_extended_flutter`；纯 Dart 包不能依赖 Flutter 插件，所以定义 `FfmpegRunner`，T07a.1 用同一个插件实现（桌面也可以用进程）。
2. **所有 HTTP(S) 的 FLV、HLS 都套中继**：与 v3 相同的做法（v3 用自己的两套中继），改用 `live_media` 的中继；好处是停止时能正常结束，HLS 子请求由 Dart 校验证书。RTMP 等其他协议直连，停止时直接取消（没有可以“关掉”的输入，v3 在这里会白等排空超时）。
3. **续期不再新开一次 FFmpeg**（问题 1）：会切断连接的租期在中继里无缝续签，录制只有一个 MP4；不切断的租期只预取。v3 对非虎牙原生 FLV 的租期到点强制轮换，现在不轮换。
4. **录制专用 HLS 预取和保留窗口没搬**：v3 为了让 FFmpeg 慢读时不漏分段，自己并行下载并保留一段窗口（约 2900 行）。现在 FFmpeg 按需经中继取分段；漏段仍会被 FFmpeg 报告并标“有缺口”（`inputCoverageIncomplete`）。是否补做见“留给后续”。
5. **错误文字由界面给**：内核只给类型和脱敏的诊断；任务上存的 `lastError` 是英文诊断或 FFmpeg 日志末行，M13 按 `lastErrorStage` 显示本地化文字。
6. **代理**：v3 录制的代理是全局回调；现在中继和直连输入都按平台用 `ProxyPolicy`（同播放、同平台请求）。
7. **断线预取通用化**：v3 只对虎牙原生 FLV 持续预取下一个签名；现在凡是不切断连接的租期都这样（问题 9）。

## 升级条目

| 编号 | 处理 | 状态 |
|---|---|---|
| 22-1 TikTok 私密、订阅、付费直播 | 录制时房间受限又取不到流，报 `restricted`（带受限类型，不重试）；界面文字在 M13 | T08a.1 部分完成，余下 M13 |
| 26-2 FC2 三档画质 | 录制按所选档位经 `Fc2RecipeOpener` 开自己的控制连接（复用 T04a.1） | T08a.1 部分完成，余下 T07a.1 把打开器传给 `RecordInputOpener(recipes:)` |

## 待办的处理（m13_notes 的 T08a.1 条目）

| 待办 | 处理 |
|---|---|
| 百度 FLV 要 Referer、`flv-live.bdstatic.com` 证书不符（T04/M8） | Referer 在线路请求头里；录制的 FLV 走中继，中继用 `MediaTlsExemptions.known` 放行这两类主机（T04a.1），其他主机照常校验 |
| `PlayLease` 到期是否断开（CHZZK、LiveMe、TikTok） | 按线路的 `cutsConnection`：CHZZK 在中继里续签；LiveMe、TikTok 按不断开处理（只预取） |
| 配方输入（niconico、BIGO、TwitCasting Cookie） | 复用 T04a.1 的配方打开器和中继 Cookie |

## 留给其他模块的部分

- **T07a.1**：`FfmpegRunner` 的实现（FFmpegKit 插件；FFmpeg 9 的 OpenSSL 在 Android/Linux 需要的 CA 包路径给 `Recorder.caFile`）；`RecordKeepAlive`（Android 前台服务，被系统停掉时调 `keepAliveInterrupted`；用户手动开始时允许重试的逻辑 `allowUserRetry`）；存储权限（`storageAccess`）；默认录制目录；`Recorder` 的 provider 和启动时 `restore`。
- **T09b.1**：录制设置的读写（3.x Hive 键 `segmentTime`、`maxTaskCount`…，见 `recorder_keys.dart`）和 `recorder_tasks`、`record_history` 的迁移；设置变化后调 `settingsChanged()`。录制设置已进 live_store 的设置注册表和备份（T08a.2）。
- **M13**：录制中心和设置页；状态、阶段、失败类型、受限类型的文字；合并进度条（v3 `VideoProcessEvent`）。
- **留给后续（T08a.1 补做）**：
  - ~~录制弹幕（v3 `recording_danmaku_service.dart`，按尝试写 B 站 XML）~~：完成（T08a.2，`chat.dart` 的连接器接口和 XML 写入器，应用接 `live_danmaku`，见 `T08a.2-record-more.md`）；
  - ~~HLS 录制专用预取和保留窗口（有意差异 4）~~：完成（T08a.2，live_media 的 `HlsMediaWindow`，录制的中继默认打开）；
  - 合并进度事件（`mergeProgress`）。

## 依赖变化

- 新包 `live_record` 加入根 `pubspec.yaml` 的 workspace，依赖方向按 `tools/gate/check_deps.py`（`live_media`、`live_core`、`live_net`）。
- 新增第三方包：`pinyindart` 0.0.1（v3 同款，文件夹拼音；带入 `archive` 4.3.0、`posix` 6.5.2）。`clock`、`meta`、`path` 已在锁文件里。

## 测试

27 个用例（`dart test`）：
- `task_test.dart`（7）：3.x JSON 读写（枚举名、数字漂移、哨兵、不存签名地址、诊断脱敏、损坏标记）、会话与尝试、排序、设置规整、路径名和拼音；
- `ffmpeg_test.dart`（8）：录制参数（移植 v3 主要用例）、协议选项、失败分类、时间纠偏、分段日志、只合并本次尝试、前缀预留、重试和租期时间；
- `recorder_test.dart`（12）：选流（画质排序、换线路和续签、离线和网络错误、受限房间 22-1、租期随线路）、FLV/HLS 走中继而 RTMP 直连、录制→停止→合并 MP4、直播 EOF 快速重连后两段都合并、未开播转等待、损坏尝试保留源文件、恢复时合并被杀的录制并丢掉不支持的平台、并发上限排队。
