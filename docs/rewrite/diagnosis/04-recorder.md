# 录制模块第 0 阶段诊断（master@49ceccb0，只读）

## ① 规模与结构

`lib/recorder` 共 55 个文件、14,241 行。引用它的测试有 89 个文件、2.18 万行，`tool/probes` 下另有约 20 个录制和 HLS 的真实网络探针。

| 层 | 主要文件（行数） | 合计 | 职责 |
|---|---|---|---|
| 控制器、模型、策略 | recorder_controller(1763)、live_record_task(616)、stream_resolver_service(455)、recorder_continuation_policy(113) | 3161 | 任务生命周期、轮询、重连、租期、持久化 |
| FFmpeg 核心 | ffmpeg_service(889)、ffmpeg_flv_input_relay(351)、ffmpeg_scheduler(276)、ffmpeg_command_builder(250)、tls_trust_store(112) | 2011 | FFmpegKit 会话、参数、并发、FLV 输入桥 |
| HLS 输入 | ffmpeg_hls_input_relay(990)、13 个 hls_*、cancellable_http_connections | 4392 | 回环中继、整片暂存、预取保留窗口、LL-HLS |
| 自有输入 | niconico/bigo/fc2_hls_input、owned_record_input、binding | 728 | 会话型输入 |
| 收尾 | video_processor_service(476)、recording_segment_clock(153)、recording_output_metrics(213) | 869 | TS 转 MP4、时钟清单、进度 |
| 界面与设置 | recorder_page(842)、record_settings_page(622)+controller(348)、recorder_config(297) | 2349 | |
| 其它 | cache_service(280)、recording_danmaku_service(241)、recorder_background_service(160) | 731 | |

| 步骤 | 位置 | 要点 |
|---|---|---|
| 入口 | recorder_controller.dart:693；record_action_button.dart:173,181 | “立即录制”不看卡片状态，由严格解析判定（:701-704） |
| 用户启动 | :715-768 | 先等上一次停止、崩溃恢复、收尾完成，再清零计数 |
| 入队 | :774-818 → ffmpeg_scheduler.dart:124-150 | 先拿后台租约；并发上限默认 3；全局启动间隔 5 s（:9） |
| 一次尝试 | :820-1011 | 解析流地址，或用预取凭据（:862-879）；**每次尝试新建“平台/主播/日期/时分秒”目录**（cache_service.dart:262-279）；请求头与播放共用 |
| 录制参数 | ffmpeg_command_builder.dart:86-176 | 5 MB 探测、`+genpts+discardcorrupt`、只对 5xx 内部重连（:182-210）、`-c copy`、segment→mpegts、子 TS `flush_packets…output_ts_offset=1.4`（:161）、CSV 段表、默认每 300 s 一段（recorder_config.dart:12） |
| 输入替换 | ffmpeg_service.dart:364-444 | HLS→HLS 中继；.flv→FLV 输入桥；Bigo/FC2/niconico→OwnedRecordInput；段表占用锁；`ca_file` |
| 执行与事件 | :446-685 | 日志用于完整性和缺口判定，统计用于进度，结束时按日志分类出 failure_kind 和 retryable |
| 结束处理 | recorder_controller.dart:169-312,415-519 | 本次 TS 记入 pendingAttempts；能重连就先重连（:457-466），用户停止或放弃时才合并 |
| 合并 | video_processor_service.dart:59-345 | clock-v1 CSV 生成 ffconcat → `-xerror -f concat -c copy +faststart` → 写 .partial 后原子改名 → 删除 TS；有损坏则保留源文件 |
| 进度 | recorder_controller.dart:325-407 | 每秒统计 TS 文件大小；时长取墙钟与 FFmpeg 的较大值；码率按文件增长计算；跨尝试累计 |
| 持久化与恢复 | live_record_task.dart:324-378；controller:622-661,1470-1595 | Hive `recorder_tasks`（schema 9），2 s 防抖、进度 10 s 节流；签名 URL 不落盘；启动时把活跃态改为停止并合并残留 TS |

合并进度事件 VideoProcessEvent 没有任何订阅者，界面只能显示“处理中”。

## ② 依赖与耦合

FFmpegKit 只在 ffmpeg_service.dart:9 被导入一次。逐项评估如下：

| 能力 | 现位置 | v4 做法 | 需要的 FFmpeg |
|---|---|---|---|
| 拉流并写 TS 分段 | ffmpeg_service.dart:446-685 | FLV 由 Dart 中继按 tag 直写；HLS 由录制器自己拉整片、写归档 | 不需要 |
| 统计和日志回调 | :514-556、:58-146、:851-880 | 写入端自己统计字节和 tag 时间戳；错误改为类型化 | 不需要 |
| 多段 TS 拼接成 MP4 | video_processor_service.dart:244-270 | 单个 FLV/TS/HLS 归档 stream copy 转 MP4 | 见下方说明 |
| HTTPS CA 注入 | ffmpeg_tls_trust_store.dart:90 | 删除，TLS 由 Dart 或 live_net 处理 | — |
| 纯音频本地输出 | ffmpeg_command_builder.dart:29-62 | 生产代码无调用、只有测试引用，删除 | — |
| 探测、截图 | 无 | — | — |

转 MP4 需要的库：
- libavformat：解复用 flv、mpegts、hls、mov；复用 mp4；协议 file、crypto；concat 只在迁移时用。
- libavcodec：只要 parser 和 bsf（h264、hevc、aac、av1 的 parser，aac_adtstoasc 等），不需要解码器。
- libavutil。
- 不需要 swscale、swresample、avfilter、avdevice。

| 平台或机制 | 位置 | 行为 |
|---|---|---|
| 严格房间接口（B 站、斗鱼、虎牙、抖音、快手、CC、Twitch、SOOP、YY 等） | stream_resolver_service.dart:133-157 | 元数据失败按网络错误重试，不当成下播 |
| 线路游标（斗鱼、虎牙） | :190-280 | 每次只签名一条线路；顺序为同画质下一线路 → 下一画质 → 回绕；续签优先原线路 |
| 租期元数据（斗鱼、虎牙、酷狗、猫耳、YouTube） | :377-388 | 斗鱼 expire 前 45 s 续签（douyu_site.dart:34,58-64）；虎牙网页 FLV/HLS 按 100/125 s（huya_site.dart:57-58） |
| 虎牙 WUP 原生 FLV（ctype=huya_pc_exe&t=100） | huya_transport_policy.dart:71；controller:1075-1078,1148-1157 | 只预取下一凭据，不主动断开；维护间隔 30 s |
| 请求头 | ffmpeg_header_factory.dart:4 → playback_header_resolver.dart:53-146 | 与播放共用 UA、Origin、Referer、Cookie；日志脱敏（ffmpeg_service.dart:809-820） |
| HLS 查询 token 策略 | hls_source_query_policy.dart | 唯一生产者 ttinglive 已在 1495f56b 下线，目前没有生产者 |
| Bigo、FC2、niconico | live_input_recording_binding.dart:27-107 | WebSocket 座位、Cookie、选定视频加伴随音频 |
| Twitch | — | 没有专门逻辑；广告 DATERANGE 只保留、不剔除 [待确认是否需要剔除] |
| codec 12 HEVC | — | 录制不经过 FlvLegacyHevcRelay，靠 FFmpeg 9 自己识别 |

| 耦合 | 现状 | 位置 |
|---|---|---|
| 反向依赖 | player 引用 recorder 的 FlvInputFramer、HLS 中继和三个自有输入；直播间直接 `Get.find<RecorderController>` | flv_splice_relay.dart:8；playback_source_transport.dart:5；live_play_controller.dart:59 |
| GetX | GetxService + RxList + ever 监听；设置有 16 个 `.obs`；调度器从 Get 读并发上限；服务层直接调用 Toast 和 i18n | controller:82,128-131,297,971；ffmpeg_scheduler.dart:26-28 |
| 界面性能 | 一个 Obx 包住整张列表，任务对象可变且每秒替换，导致整表重建、重排；弹幕同步每秒遍历全部任务 | recorder_page.dart:88-90；controller:130 |
| Android 后台 | 独立 dataSync 前台服务，绑定 AudioService 保住 Dart 引擎，加 CPU/WiFi 锁；Android 15 起 24 h 内限 6 h，超时后有界收尾并标失败 | AndroidManifest.xml:120-123；RecorderBackgroundPlugin.kt:291-300,419；RecorderForegroundService.kt:188-197；controller:1038-1057 |
| Windows | 没有后台保障；退出时直接销毁窗口，不排空录制；下次启动靠恢复合并 | plugins/utils.dart:20-75；controller:1569 |
| 冷启动 | Android 必须提前初始化 FFmpegKit，否则首次录制 I/O 失败 | initialized.dart:119-123,138-146 |

## ③ 技术债（按风险×收益排序）

| # | 问题 | 证据 | 风险/收益 |
|---|---|---|---|
| 1 | 续期等于新开一次尝试。斗鱼带 expire 的链接从 31982153 起每约 255 s 主动轮换，虎牙网页 FLV/HLS 约 100 s 一次。每次都是新前缀、新目录、新 MP4，中间有缺口（排空 ≤3 s + 重连 2 s + 解析 + 探测 ≤5 s） | controller:1080-1085,883-887；recorder_continuation_policy.dart:58-71 | 高/高 |
| 2 | FFmpegKit 取消会截断输出，由此衍生出 FLV 输入桥、AVC 边界等待、HLS 整片暂存/预取/ENDLIST、日志完整性判定等补丁，仅 HLS 就 4.4k 行 | docs/HUYA_RECORDER_LEASE_AUDIT_2026_09_05.md §2 | 高/高 |
| 3 | TS 分段加 concat 在每个边界产生约 90 ms 时钟阶跃，靠 clock-v1 段表修正 | docs/RECORDING_CONCAT_CLOCK_DRIFT_2026_09_10.md | 中/高 |
| 4 | 重连期间释放调度槽，排队任务可能抢占；全局 5 s 启动间隔还会叠加 [代码推断，待真机确认] | ffmpeg_scheduler.dart:9,164-170 | 中/中 |
| 5 | 错误靠日志字符串分类，两份致命错误清单不一致 | ffmpeg_service.dart:58-146；recorder_continuation_policy.dart:15-40 | 中/中 |
| 6 | 控制器 1763 行、约 20 个状态表、任务对象可变 | controller:80-107 | 中/中 |
| 7 | 弹幕时间基取尝试开始（在解析之前），早于首个媒体包 [待确认偏差量]；Windows 退出不排空 | recording_danmaku_service.dart:193；controller:832 | 低/中 |
| 8 | 死代码：合并进度事件、纯音频中继参数、RecordFileItem/recordHistory、heartbeat、initInIsolate、isStalled、HLS 查询策略 | recorder_config.dart:224-239 等 | 低/低 |

## ④ 处置建议

| 部分 | 处置 | 改用 FlvSpliceRelay 后可删的位置 |
|---|---|---|
| 租期预取、轮换、待用凭据 | 删除，交给中继的 renewer | controller:90-94,1059-1188；policy:85-112；ffmpeg_service.dart:172-174,725-731 |
| 多尝试合并、累计进度 | 删除；一次会话就是一个连续文件 | live_record_task.dart:55-60,254-299；controller:529-591；output_metrics:16-28 |
| TS 分段、clock-v1、concat | 删除，只保留一次性迁移 | recording_segment_clock.dart；video_processor:147-187,357-383 |
| FLV 输入桥和 AVC 等待 | 删除；分帧器移到 live_media | ffmpeg_flv_input_relay.dart。FLV 转 MP4 是否还会出现无画面尾包 [待确认] |
| FFmpegService、Manager、Scheduler、CommandBuilder、TLS | 删除 | lib/recorder/ffmpeg/* 等 |
| HLS 预取、保留窗口、暂存 | 改写为录制器自带的 HLS 下载器 | hls_prefetch_*、hls_retained_*、hls_media_spool |
| 解析游标、严格房间、轮询退避、开机恢复、缓存保护、后台租约、弹幕 XML | 行为写进规格，实现重写 | — |

## ⑤ 必须继承的行为与坑

| 现象 | 根因 | 正确做法 | 提交/测试 |
|---|---|---|---|
| 虎牙 WUP 录到约 270 s 被切断，尾部损坏 | 定时轮换取消了健康连接；该凭据只限制新建连接 | 只预取下一凭据，真正 EOF 时才使用 | f66cff51；recorder_lease_lifecycle_test.dart:173,196,218 |
| 斗鱼每 5 分钟断一次 | expire=300，CDN 按签发时刻断开；新旧连接时间戳在同一时间线 | 提前 45 s 续签，在新连接首个未送达的关键帧处拼接；时间线不同时平移 | 31982153；tool/probes/douyu_splice_probe_test.dart |
| 流结束被当成下播 | 直播没有自然的 EOF | code 0 或 AVERROR_EOF 快速重连（2→15 s），不进入慢轮询 | 7c3275b4；continuation_policy_test:94,127 |
| 403/404 反复重试旧签名 | FFmpeg 内部重连 | 只有 5xx 在内部重连，4xx 交上层重新解析 | cf35dcf9 |
| 首个 URL 启动时已过期 | 启动前签名了所有画质×线路 | 按游标只签名本次要用的一条 | 065427ed；owned_record_input_test:33,61 |
| 元数据失败被当成下播 | 界面加载器保留旧卡片状态 | 用严格房间接口，状态未知按网络错误处理 | 233d858d |
| 重连被 MP4 合并阻塞 10–20 s | 先合并后重连 | 先重连，会话结束后再收尾 | db7d0df3；controller:457-466 |
| 停止后 TS 尾部损坏，但转 MP4 仍返回 0 | 取消同时中断了输出 IO；stream copy 不解码 | 先让输入自然结束；用 `-xerror` 加日志判定；有损坏就保留源 | 263e458a、a65638bd、9a588f4b；video_processor_lifecycle_test:152 |
| 尾部只剩 SEI、没有画面 | 完整 tag 不等于完整访问单元 | 停止时等到下一个完整画面（3 s 预算） | 1abbff9a、26de4378；ffmpeg_flv_access_unit_stop_test |
| 分段边界约 90 ms 阶跃 | concat 按文件时长累加 | 用 CSV 起点差加 inpoint 0 | f46ebe56、608c1d5d；recording_segment_clock_test:53-76 |
| 时长显示 596523:14:08 | 首个统计时间是 INT32_MAX 哨兵值 | 以墙钟封顶；持久化值超过 1 年归零 | e9d11a09；ffmpeg_service.dart:29-37 |
| 码率显示偏低 | FFmpeg 用源时间戳做分母 | 按文件增长的时间窗计算 | ff0119b0 |
| 签名 URL、Cookie 泄漏 | currentUrl 被持久化 | 只存画质 ID 和线路索引；日志脱敏 | cf35dcf9；persistence_test:124-182 |
| 重试混入旧分片、同秒覆盖 | 文件名只精确到秒 | 毫秒前缀、.partial 原子提交、不覆盖已有文件 | video_processor_lifecycle_test:284 |
| 清理缓存删掉正在写的文件 | 没有活跃保护 | 只管理 PureLiveRecords 子目录，活跃目录引用计数 | cf35dcf9、f07d1861；storage_policy_test:145-186 |
| 旧会话的迟到回调覆盖新任务 | 事件没有代次 | 用 sessionId 加任务身份做栅栏 | output_lifecycle_test:163-286；poll_lifecycle_test:68-196 |
| 停止、启动、恢复竞态 | 用户意图没有串行化 | 按顺序等待上一步完成 | e7670220；user_intent_test:116-243 |
| 锁屏或关闭界面后中断 | 引擎随 Activity 一起销毁 | 独立前台服务 + 保活引擎 + 锁；被系统中断后只允许用户手动重试 | 9a512919、f4d40174；background_service_test |
| HLS 交给 FFmpeg 半个分片 | 流式转发 | 整片收完再发布；停止时冻结播放列表并追加 ENDLIST | 6415d42e、29caea0b |
| HLS 子请求证书失败 | FFmpeg 不把 ca_file 传给子请求 | TLS 在 Dart 侧处理 | e35247d0 |
| 录制不走应用代理 | FFmpeg 直连 | 上游统一走代理策略 | 17a192f1 |
| 开机恢复时弹出权限框 | 不是用户手势 | 不请求权限，保持停止状态 | 723b4452；user_intent_test:243 |
| Windows 弹幕文件被锁 | 没有等关闭完成 | 等待 close 结束 | 8c5fb87e |

## ⑥ 对 v4 live_record 的建议

| 模块 | 设计 |
|---|---|
| 来源 | 按“租期类型”选择：会断开连接的用拼接（斗鱼）；只限新建连接的只在 EOF 时续接（虎牙 WUP）；没有租期的 EOF 后续接。FlvSpliceSession 在旧流先结束时会直接退出（flv_splice_relay.dart:146-147），需要外层循环 |
| FLV 写入 | FLV 头和脚本 tag 只写一次；时间戳保持单调；断流后重新定基准，缺口写入 gaps.json；编解码配置变化或按时间、大小切分时，在关键帧处开新分段；codec 12 改写为 Enhanced FLV；写入必须有背压（现在 :413-421 没有） |
| HLS 写入 | 录制器自己轮询、整片下载，按序号去重，序号跳变记为缺口；保存为本地 VOD 归档（原始分片 + 本地化的 KEY/MAP + ENDLIST） |
| 转封装 | 以 FFmpeg `doc/examples/remux.c` 为蓝本写一个 C 垫片，链接共享的 libavformat；可中断，按字节报进度，在后台 isolate 运行；失败时保留源文件 |
| 状态 | 任务状态不可变；进度流按任务分开推送；错误类型化；数据存 drift |
| 后台 | 保留 Android 独立前台服务；评估改为 specialUse 以避开 6 h 上限 [待确认]；Windows 退出前提示，关闭文件即可（FLV 没有尾部） |
| 共用连接 | 可选：播放中继把 tag 分流给写入器（前提是画质、线路相同） |

去掉 FFmpegKit 的实施步骤：
1. **规格与样本**：把 ⑤ 表写入 `spec/modules/record.md`。准备样本：斗鱼两次续签、虎牙 WUP、B 站 fMP4 HLS、Twitch、niconico 分离音频、Kilakila SEI 尾、codec 12。
2. **live_media**：抽出分帧器和拼接会话，消除 player 对 recorder 的反向依赖，并加上背压和分流。
3. **live_record 写入**：实现 FLV 写入器、外层会话循环和缺口日志，用 FlvTagReader 假源做确定性测试。
4. **HLS**：实现下载器，接入 Bigo、FC2、niconico。
5. **原生**：libmpv 构建配方改为共享 FFmpeg，同时产出 C 垫片。Windows 的 libmpv 目前可能不是自编的 [待确认]。退路是单独附带精简版转封装 FFmpeg（约 2–4 MB [待确认]）。
6. **接入旧应用**：以开关方式接入 3.3.x，FFmpegKit 保留一个版本作为回退。门禁：
   - 斗鱼录 30 min，DTS 最大间隔 ≤1 帧；
   - 虎牙录 60 min 无断开；
   - 各 HLS 平台全解码 stderr 为空；
   - 杀进程后能恢复。
7. **迁移**：Hive 数据迁到 drift；遗留的 clock-v1 TS 用 concat 一次性收尾。
8. **删除**：`ffmpeg_kit_extended_flutter`（pubspec.yaml:77-80,291-300）、FFmpegKit 预热代码和 minSdk 注释（build.gradle.kts:50-53）；体积门禁 −29 MB。
