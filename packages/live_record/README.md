# live_record

Pure Live v4 的录制层（纯 Dart）：FLV 写入器、带租期拼接的录制会话、HLS 下载器与写入器、单条 HTTP 流与连续 MPEG-TS（IPTV）、任务管理器、崩溃恢复、FLV / MPEG-TS / fMP4 → MP4 转封装。行为依据 [spec/modules/record.md](../../spec/modules/record.md)（文中 §编号指它），方案依据 [ADR 0005](../../docs/adr/0005-recording-without-ffmpegkit.md)，实现上的选择见 [ADR 0021](../../docs/adr/0021-recording.md) 和 [ADR 0035](../../docs/adr/0035-hls-record.md)（HLS 录制；末尾的修订是 IPTV 连续 TS）。依赖 `live_media`（`FlvSplicer`、`FlvFramer`、`openHttpFlv`）、`live_core`、`live_net`。

## 应用怎么用

```dart
final manager = RecordManager(
  rooms: SiteRecordRooms((platform) => adapters[platform]),   // 各平台适配器（RoomSource + StreamSource）
  store: myLiveStoreTaskStore,                                 // RecordTaskStore；内置 MemoryRecordTaskStore、JsonFileRecordTaskStore
  root: RecordRoot.resolve(defaultRoot: '$dataDir/RECORDS', chosen: settings.recordDirectory),
  settings: RecordSettings(maxConcurrent: 3, polling: true, danmaku: true),   // 由应用的 record.* 设置映射
  opener: httpRecordOpener(proxy: proxyPolicy, readTimeout: const Duration(seconds: 15)),   // FLV 连接、HLS 请求和单条 HTTP 流都走代理
  remuxer: const IsolateRemuxer(Mp4Remuxer()),                // 可选：纯 Dart 转封装（FLV、TS、fMP4），在后台 isolate 运行；不给则保留源文件
  chat: danmakuChatSource,                                     // 可选：RecordChatSource（live_danmaku 适配）
);
await manager.init();                  // 读取任务；后台做崩溃恢复（每次启动）和开机恢复（record.resumeOnLaunch）

await manager.add(roomDetail);                    // 添加并立即录制（“立即录制”由严格检查决定是否开播）
await manager.add(roomDetail, start: false);      // 只添加：轮询开 → 等待开播；轮询关 → 已停止（原因：轮询已关闭）
await manager.start(key);                         // key = RoomRef.key，例如 'douyu:9999'；终态任务即“重新录制”
await manager.forceStart(key);                    // 强制开始：排队中或等待开播的任务不等并发槽和启动间隔（§2）
await manager.stop(key);                          // 用户停止：收尾（含转封装）完成后返回
await manager.remove(key);                        // 先按用户停止收尾，再删任务；文件保留
await manager.checkNow(key);                      // 手动检查等待中的房间
await manager.retryRemux(key);                    // 转封装失败后重试
await manager.updateSettings(newSettings);        // 轮询开关、并发数、容量上限等立即生效
await manager.sweepStorage();                     // 立即按容量上限清理录制目录（开关打开时每分钟自动做，§15）
await manager.importTasks(tasksFromBackup);       // 恢复备份：替换空闲任务，活跃任务不动（store.md §7.2）

manager.tasks;                          // 按添加顺序的快照列表（顺序稳定）
manager.listChanges;                    // 增删任务时发出整个列表
manager.watch(key);                     // 单个任务的快照流：状态立即推送，进度每秒最多一次
manager.activeCountChanges;             // 有活跃会话时 Android 前台服务保持运行（§16.1，应用的 RecordKeepAlive）
await manager.flush();                  // 立即落盘；Android 保活在活跃数归零后先等它再停服务
await manager.interruptAll();           // Android onTimeout：有界收尾，标“后台时间用尽”失败
await manager.stopAll();                // 桌面退出：10 s 内收尾（不转封装），下次启动可开机恢复
await manager.dispose();
```

`RecordTask` 是不可变快照：`state`（`queued`、`resolving`、`recording`、`reconnecting`、`finalizing`、`waitingLive`、`completed`、`failed`、`stopped`）、`failure`（`RecordErrorKind` + 阶段 + 脱敏文本）、`stopCause`（`user` / `pollingOff` / `appRestart`）、`retrying`（重连或轮询中的最近错误）、`nextCheckAt`、`session`（目录、前缀、分段、MP4、字节、媒体时长、缺口数、连接数、拼接数）、`bitsPerSecond`、`remuxProgress`。

## 文件放在哪里

```
<根>/<平台>/<主播>/<yyyy-MM-dd>/
  20260927_101530_123_001.flv        FLV 分段（写入中是 .flv.part，关闭时改名）
  20260927_101530_123_002.ts         HLS（MPEG-TS）分段：分片按序整片相接；fMP4 为 .m4s（初始化段 + 分片）
  20260927_101530_123_001.xml        弹幕（开 record.danmaku 时，与分段同名）
  20260927_101530_123_001.mp4        转封装结果（写入中是 .mp4.partial）
  20260927_101530_123.gaps.json      缺口记录（没有缺口也写空数组）
```

- 根目录按 §15：默认应用数据目录的 `RECORDS`；用户选的目录只当父目录，写进 `<选定目录>/PureLiveRecords/`，放 `.pure_live_recording_root` 标记。`RecordRoot.prepare` 写探针验证可写。
- 路径组件按 §9 清洗；`transliterate` 参数可接拼音转换（`record.pinyinFolders`）。
- 一次会话一个写入器：重连、续期都写同一个文件；只有编解码配置变化、`record.splitMinutes`、`record.splitMegabytes` 才开新分段，在关键帧处切，每个分段都能独立播放（FLV 的时间戳从 0 开始；TS、fMP4 保留上游时间戳，转封装时连成一条）。会话在 FLV 与 HLS 线路之间切换时关旧文件、开新文件，编号接着往后。

## 接转封装和弹幕

- **转封装**：本包自带 `Mp4Remuxer`（FLV、MPEG-TS、fMP4 都能转，按内容分派），应用用 `IsolateRemuxer(Mp4Remuxer())`。自己实现时照 `Remuxer.remux(RemuxJob job)`：把 `job.input` 以 stream copy（`+faststart`，不解码）写到 `job.output`（`.partial` 路径），通过 `job.onProgress(已读字节)` 报进度，`job.cancelled` 完成后尽快返回；任何解复用或复用错误都要抛 `RemuxException`（退出码 0 不能说明输入完整，REG-RECORD-008）。提交、改名、删源、60 s 无进度看门狗、失败保留源都由本包处理。`tools/live_cli` 里的 `FfmpegProcessRemuxer` 调用 `ffmpeg` 可执行文件，只用来对照。
- **弹幕**：实现 `RecordChatSource.connect(RoomDetail room)`，返回 `Stream<RecordChatMessage>`（id、userId、userName、text、color、sentAt）。用 `live_danmaku` 按 `room.danmakuKeys` 连接，只转普通聊天。流出错或结束时录制器 30 s 后重连；弹幕失败不影响视频。时间按写入器的“墙钟 ↔ 文件时间”锚点换算（§17）。

## 设计要点

- **会话（`RecordSession`，§5.4）**：严格房间检查 → 按游标解析一个画质（只签这一个，§4.3）→ 连接。每条 FLV 连接都经过 `FlvSplicer`：斗鱼 `expire` 租期到 `refreshAt` 续签并在第一个未送达的关键帧处无缝拼接；不断开连接的租期只在 `refreshAt` 前 5 s 预取，EOF 时直接用（§5.2）；没有租期的线路 EOF 后立即续接，最多跳过一个 GOP 并记缺口。拼接器放弃后外层循环按错误类型重试：
  - EOF（已录到媒体）：2 s 起翻倍到 15 s，不限次数，每次先严格检查，确认下播才结束；
  - 4xx：第一次立即续签原线路，第二次换下一线路，第三次起常规退避；从不重试旧签名；
  - 5xx：同址 1、2、4 s，然后常规退避；
  - 连接前失败：立即换下一线路，全部失败记 `allLinesFailed` 常规退避；
  - 网络、解析失败：常规退避（`retryDelay`，开 `backoff` 时翻倍到 `maxCheckInterval`），`maxRetries` 用尽即结束——轮询开转等待开播，轮询关标失败（不会 2 s 无限重试，REG-RECORD-034；不会停在等待开播，REG-RECORD-033）；
  - 连续录到 10 s 媒体后计数清零。
- **写入器（`FlvSessionWriter`，§6）**：分段开头依次是头、首个连接的脚本 tag、视频配置、音频配置、关键帧；时间戳单调；新连接与已写位置相差 60 s 内且在其后就沿用时间线，否则平移到“已写末尾 + 1 帧”（中位帧间隔），缺口写 `gaps.json`；旧式 codec 12 HEVC 改写为 Enhanced FLV `hvc1`；只含 SEI/SPS/PPS/AUD 的视频 tag 先扣住，等到画面再写，停止时最多等 3 s，否则丢掉，文件不会以它结尾；写入队列超过 8 MiB 时读上游暂停；至少每秒刷盘一次；单次写入卡住 30 s 或写入出错按磁盘错误致命失败（`diskFull`、`permissionDenied`、`readOnly`、`pathInvalid`、`diskStalled`）。
- **容量上限（`enforceStorageLimit`，§15）**：`RecordSettings.storageLimitMegabytes`（应用的 `record.cacheLimitEnabled` + `record.cacheLimitMB`）大于 0 时，管理器每分钟扫描一次根目录：总量（标记文件除外）超过上限就按修改时间从旧到新删除，解析、录制、重连、收尾中的会话目录只计入不删除，删不掉的文件跳过；删了文件后从深到浅清理空目录。
- **管理器（`RecordManager`，§2、§3、§11–§14）**：每个房间一个任务；同一任务的意图串行；过期代次的结果丢弃；并发槽先进先出，新会话之间至少 5 s，重连期间不释放槽；状态变化 2 s 合并写入、进度最多 10 s 写一次、终态立即写；崩溃恢复每次启动都在后台做，用户这时点开始会等它完成；等待开播只在轮询打开时存在，关闭轮询时转为“已停止（轮询已关闭）”，再打开时回到等待并立刻检查。

## HLS 录制（§7）

同一画质先用 FLV 线路，没有或都在录到媒体前失败时用 HLS 线路（SOOP、Twitch、TwitCasting、PandaTV 只有 HLS；B 站、虎牙等 FLV 之外还有 HLS）。一条 HLS 连接是一个 `HlsFeed`，写进会话的 `HlsSessionWriter`。

- **列表**：`M3u8Playlist.parse` 解析 master 和媒体列表：隐式 BYTERANGE 在解析时算成绝对范围；EXT-X-KEY 按格式分开，`identity` 的 AES-128 可录，SAMPLE-AES 和 DRM 格式标为不支持；EXT-X-MAP 记住当时的密钥；LL-HLS 的 PART / PRELOAD-HINT 不算分片；含 EXT-X-SKIP 的增量列表直接报错。master 取带宽最高的变体，之后直接轮询变体地址；AUDIO 组带独立地址（音视频分离）暂不支持。
- **节奏**：首次立即请求；列表全文变了等 1 个 TARGETDURATION，没变等半个，从请求开始计时，同一时间只有一个列表请求。第一个列表从倒数第 3 个分片开始录。4xx 经适配器续签一次再试；5xx、网络、解析失败连续 3 次结束连接；`max(readTimeout, 4 × TARGETDURATION)` 没有新分片结束连接；ENDLIST 写完即结束。
- **分片**：在内存里整片下载（核对 `Content-Length`，上限 64 MiB），AES-128 在内存解密（key 按地址缓存，不落盘），按序号顺序写；最多 2 个在下载或等写，写入器的 8 MiB 队列满时不再开始新下载。失败的分片重试 2 次后记缺口，连续 3 个失败结束连接。
- **序号**：`HlsFeedState` 跨重连保留最后处理的序号：重连后列表仍含下一片时无缝接上；跳号记 `sequenceJump`（fromSeq、toSeq、片数 × TARGETDURATION）；序号回退或跳得远超离开的时间视为重新编号，从新直播边缘接着录，记 `reset`（换地址引起的记 `lease`）。
- **租期**：线路带租期时在 refreshAt 续签同画质同格式的线路，下一次轮询换地址（master 重新选变体）。
- **Cookie**：`IoHlsClient` 按源站（scheme、主机、端口）在内存里保存 Set-Cookie 并回传（TwitCasting 的 `lvhls_ssid_*`），每个源站最多 64 条 / 16 KiB；请求都走代理策略，TLS 照常校验。
- **写文件**：TS 分片整片相接写成 `.ts`（去掉末尾不足 188 字节的残余），fMP4 写成 `.m4s`（初始化段 + 分片）；编码配置（PMT 流类型、SPS/PPS/VPS、AAC 配置、初始化段）变化、TS 与 fMP4 交替、按时长或大小切分时开新文件。文件从关键帧开始：分片不以关键帧开头（Amazon IVS）时在分片内第一个关键帧处切开，新文件带上该分片的 PAT/PMT。文件时间是已写分片的 EXTINF 之和（缺口 `atMs`、进度、弹幕时间都用它）。
- **停止**：不再请求列表和开始新下载，在途分片最多等 1 个 TARGETDURATION（≤10 s）写完，剩下的记一条 `stop` 缺口。
- **崩溃恢复**：`.ts.part` 截到整包并去掉最后一个分片（崩溃可能写了一半），`.m4s.part` 截到最后一个完整 moof + mdat；没有媒体的删除。

2026-09-28 真实录制（`live_cli record <平台> <房间> --duration 60 --remux`，本包的写入器和转封装；“包数”是 ffprobe 读到的视频 / 音频包，`.ts`、`.m4s` 和 MP4 都用 `ffmpeg -v error -i … -f null -` 全解码）：

| 平台 | 线路 | 编码 | 源文件 | 包数（源 = MP4） | 缺口 | 解码错误 | 备注 |
|---|---|---|---|---|---|---|---|
| SOOP devil0108 | HLS TS（gcp_cdn） | H.264 1080p60，AAC 48 kHz | 54.5 MiB `.ts` | 3600 / 2813 | 0 | 0 | 转封装解码画面、音频逐帧相同 |
| Twitch caedrel（代理 127.0.0.1:7897） | HLS TS（usher 变体） | H.264 1080p60，AAC 48 kHz | 45.8 MiB `.ts` | 3600 / 2813 | 0 | 0 | 访问单元跨 PES（REG-RECORD-042）；画面逐帧相同，最后一个 AAC 帧按容器末尾截断（ffmpeg 自己的 `-c copy` 也一样） |
| TwitCasting nabo66game | HLS fMP4（会话 Cookie） | H.264，AAC | 35.4 MiB `.m4s` | 3857 / 3014 | 0 | 0 | 负载 MD5 与源相同 |
| B 站 22603245 | HLS fMP4（`--line fmp4`） | H.264，AAC | 13.7 MiB `.m4s` | 1840 / 2875 | 0 | 0 | |
| B 站 22603245 | HLS TS（`--line '\|ts\|'`） | H.264，AAC | 12.6 MiB `.ts` | 1875 / 2930 | 0 | 0 | |
| PandaTV moonmerry1225 | Amazon IVS HLS TS，`--renew-after 20`（90 s 内续签 3 次） | H.264 1080p60，AAC | 70.2 MiB `.ts` | 5520 / 4313 | 0 | 0 | master 一次性令牌，每次续签重新选变体，序号连续无缝 |
| CHZZK 458f6ec2… | HLS fMP4 | H.264 1080p60，AAC | 52.7 MiB `.m4s` | 3240 / 2532 | 0 | 0 | |
| SHOWROOM 538344 | HLS TS | H.264，AAC | 7.8 MiB `.ts` | 1801 / 2813 | 0 | 0 | |

转封装速度（WSL）：SOOP 51 MiB 0.59 s（86 MiB/s），Twitch 46 MiB 0.64 s，TwitCasting 35 MiB 0.38 s。

## 单条 HTTP 流与连续 TS（§8）

线路格式 `StreamFormat.other` 是一条 HTTP 响应就是整条流（IPTV 的 `.ts`、udpxy `/udp/…`、没有扩展名的地址；IPTV 按路径判断，见 spec/modules/iptv.md §5）。录制器用 `RecordOpener.stream`（`httpRecordOpener` 里是 `openHttpStream`：代理路由、线路请求头、`record.readTimeout` 读空闲超时、4 MiB 背压）打开，先读开头的字节（`sniffStream`，最多 64 KiB）：

- `FLV` → FLV 路径（`FlvByteSource` 把已读的字节和后面的流交给 `FlvFramer`，拼接器续接时再嗅探一次）；
- 前 188 字节里某处起 5 个对齐的 `0x47` → 连续 TS：`TsFeed` 写进 `HlsSessionWriter` 的 `.ts`（`TsSink`）；
- `#EXTM3U` → HLS 路径（没有 `.m3u8` 扩展名的列表地址）；
- 其它 → `unsupportedProtocol`，换下一条线路。

游标里 FLV 和 other 线路按原顺序在前，HLS 在后。

**`TsFeed`（一条连接）**：包按收到的顺序原样写，每个 PES 和 PAT/PMT 段整个写或整个不写（只丢整包，不改写包）。

- 对齐：找 5 个对齐的同步字节，之前的字节丢掉；中途失去同步就重新找，按损坏处理。
- 单元完整：节目里的音视频流（PMT 列出的）和 PAT/PMT 跟踪到单元完整：视频 PES 到下一个视频 PES 开头，声明长度的 PES 到收满；排在未完成单元后面的包一起等着，写入落后读取约一帧。其它 PID（SDT、EIT、字幕、空包）不等，照原样跟着写。
- 起点：连接开始（以及每次截断之后）找第一个视频关键帧：H.264 IDR 或恢复点、H.265 IRAP（都要带 SPS），MPEG-1/2 序列头，其它编码看 `random_access_indicator`（300 帧都没有这个标志就每帧都算）；纯音频节目从第一个音频 PES 开始。关键帧前写一份最近收到的 PAT、PMT，其它流从关键帧之后各自的第一个 PES 开始。30 s（`TsTimings.keyframeWait`）找不到关键帧：这条连接还没写过媒体就报 `unsupportedProtocol`（加扰或读不懂的内容），写过就结束连接由会话重连。
- 截断（`_cut`）：已完成的单元写出，没完成的丢掉，然后等下一个关键帧。连接结束、停止（先等正在收的帧收完，最多 3 s）、视频丢包（连续计数器跳变，`discontinuity_indicator` 和逐字节重复的包除外；记 `damaged` 缺口）、失去同步、PMT 变化（流或 PID）、AAC 配置变化都走这里；音频等其它流丢包只丢那个 PES。
- 开新文件：关键帧处问写入器 `wantsFile`（没有文件、流类型或参数集或 AAC 配置变了、`splitMinutes` / `splitMegabytes` 到了）；关键帧之前开始、之后结束的其它流的 PES 先写进旧文件，再开新文件。
- 时间：文件时间按视频 DTS（纯音频按 PTS）累加，差在 (0, 60 s] 内照加，否则按一帧（与转封装的时间线规则一致），断流的空档只在接着写同一文件时计入；33 位回绕按模 2^33 算差。重连后第一个关键帧处记缺口（`TsStreamState` 跨连接保留上一个单元的时间）：60 s 内按 DTS 差减一帧，否则按墙钟，超过一帧才记。
- 转封装：TS 解复用器对跨 PES 的 ADTS 帧加了一条：文件开头或缺口处接不上的半帧丢掉而不是报错（断流、切分处会遇到）。

**崩溃恢复**：`.ts.part` 有多个 PAT 时，最后一个 PAT 在视频单元边界上（HLS 分片）从它截掉；夹在帧中间（连续 TS）就从最后一个视频 PES 开头截掉。

2026-09-28 实测（`live_cli record url <地址> --duration 60 --remux`；包数是 ffprobe 读到的视频 / 音频包，`.ts` 与 MP4 相同；“解码”是 `ffmpeg -v error -i … -f null -` 的输出，`.ts` 和 MP4 都为空；`live_cli remux` 另外比对了解码后的逐帧 MD5，全部相同）：

| 来源 | 编码 | 情形 | 源文件 | 包数（源 = MP4） | 缺口 | MP4 |
|---|---|---|---|---|---|---|
| 本地模拟 udpxy（ffmpeg 实时编码 testsrc2 + sine，1316 字节一块，连接从流中间加入） | H.264 640×360 25 fps（GOP 2 s），AAC 48 kHz | 第 9 s 服务端断开所有连接，上游不断 | 9.4 MiB `.ts` | 1389 / 2608 | 1 条 `eof` 3640 ms | 最大 DTS 步长 3680 ms（空档保留），无回退 |
| 同上 | 同上 | 第 19 s 源重启（时间戳从头开始），第 39 s 丢 3 个视频包 | 9.2 MiB | 1359 / 2544 | `eof` 3564 ms（按墙钟）、`damaged` 1560 ms | 55.9 s，最大步长 1600 ms，无回退（两段接上） |
| 同上，`-output_ts_offset 95420` | 同上 | 第 8 s PTS 越过 2^33 回绕，第 30 s 断开 | 9.3 MiB | 1368 / 2568 | 1 条 `eof` 3680 ms | 最大步长 3720 ms，无回退 |
| Euronews Georgia（iptv-org 列表里的 Flussonic `/mpegts`） | H.264 1080p，AAC 44.1 kHz 立体声 | 公网 60 s | 34.9 MiB | 1625 / 2799 | 0 | 最大步长 41 ms |
| Sport TV（白俄罗斯，iptv-org） | MPEG-2 576i，AAC + MP2 | 公网 30 s | 21.7 MiB | 714 视频包，解码无错 | 0 | 转封装失败（不支持 MPEG-2 视频），`.ts` 保留，任务 `remuxFailed` |

## 转封装（`Mp4Remuxer`）

纯 Dart 把录好的分段复制成 faststart MP4（`ftyp`、`moov`、`mdat`，`moov` 在前），不解码，Android、Windows 同一份代码（[ADR 0021](../../docs/adr/0021-recording.md) 补充决定，取代 ADR 0005 §4 的原生垫片）。`Mp4Remuxer` 按文件内容分派：FLV → `remuxFlvToMp4`，MPEG-TS → `remuxTsToMp4`，fMP4 → `remuxFmp4ToMp4`。代码在 `lib/src/remux/`。下面先写 FLV，TS 和 fMP4 在本节末尾：

- **两遍读、一遍写**：第一遍逐 tag 解复用、建样本表；据此排好 `moov`；第二遍再解复用一次，按第一遍定好的块顺序把负载写进 `mdat`。不写临时文件，磁盘只多占一份输出。第二遍核对每个样本的大小和块的位置，输入在两遍之间变了就报错。
- **内存有界**：样本表用 64 KiB 分块的 `Uint32List`，每个样本约 4 字节（大小），`stts`/`ctts` 游程编码，`stss` 只记关键帧，`stsc` 只记变化。6 小时 60 fps 视频 + 48 kHz AAC（230 万样本）的表约 28 MiB（单元测试）；2.1 GiB、1 小时 51 分的 1440p60 文件进程峰值 RSS 88 MiB。第二遍每条轨最多缓存一个块（半秒媒体，最多 4 MiB）。
- **解复用**：复用 `live_media` 的 `FlvFramer`。视频：旧式 AVC（codec 7）、HEVC（codec 12）和 Enhanced FLV `avc1`/`hvc1`（SequenceStart、CodedFrames、CodedFramesX；跳过命令帧、元数据和序列结束）。序列头是 Annex B 起始码而不是配置记录时（虎牙 `codec=265` 就是这样，写入器改写成 `hvc1` 后负载不变），由 VPS/SPS/PPS 重建 `avcC`/`hvcC`，样本改为 4 字节长度前缀。音频：AAC raw 帧；ADTS 包装的剥掉头，没有 AudioSpecificConfig 时由 ADTS 头生成。只读第一个脚本 tag 的 `onMetaData`（SPS 读不出尺寸时用它的宽高）。
- **封装**：`ftyp`（isom、iso2、avc1 或 hvc1、mp41）；每条轨 `tkhd`、`mdhd`（视频 90 kHz，音频按采样率）、`hdlr`、`vmhd`/`smhd`、`dinf`、`stsd`（`avc1`+`avcC`（非方形像素加 `pasp`）、`hvc1`+`hvcC`、`mp4a`+`esds`）、`stts`、`ctts`（有非零偏移时；有负偏移用 version 1）、`stss`、`stsz`、`stsc`、`stco`（超过 4 GiB 换 `co64`，`mdat` 用 64 位长度）。音视频每 500 ms 交错成块。
- **时间戳**：视频毫秒 ×90 原样换算，显示时间（DTS + CTS）不变；重复的 DTS 往后挪 1 tick（CTS 相应减小，可为负）；回退超过 1 s 报错。音频每帧按 1024（或 960）个采样累加，只有时间戳偏离一帧以上（缺口、时钟漂移）才跟随时间戳，避免 FLV 毫秒取整造成逐帧抖动。最后一个样本的时长取最近 64 个的中位数。影片从最早显示的样本开始（与 `ffmpeg -c copy` 相同），晚开始的轨和 B 帧造成的首帧延迟用 `elst`（空编辑 + 媒体编辑）表达。
- **报错**（`RemuxException`，源文件保留，未完成的输出删除）：不是 FLV、tag 类型不对、末尾 tag 不完整、加密 tag、不支持的编码（MP3、VP6、AV1…）、多轨 Enhanced FLV、配置记录损坏、NAL 长度越界、文件中途配置变化（参数集相同的重复序列头可以）、没有配置的媒体、时间戳回退超过 1 s、没有音视频、取消。
- **进度与取消**：进度是已读输入字节（两遍各算一半），每读 1 MiB 报一次；每个 tag 之间检查取消。`IsolateRemuxer` 用 `Isolate.run` 运行任意可发送的 `Remuxer`，进度和取消跨 isolate 传递。

**MPEG-TS 与 fMP4**（`ts_demux.dart`、`ts_to_mp4.dart`、`fmp4_to_mp4.dart`，共用 `mp4_remux.dart` 的两遍驱动和 FLV 的 MP4 写入部分）：

- TS：PAT/PMT 选第一个 H.264（0x1B）/ H.265（0x24）视频和第一个 ADTS AAC（0x0F）音频，跟随 PMT 变化；没有可复制的同类流时其它音视频（MP3、AC-3、MPEG-2…）报错，ID3、SCTE-35 忽略。一个 PES 是一个访问单元，PES 开头在第一个起始码之前的字节接回上一个单元（Twitch / Amazon IVS）；起始码改为 4 字节长度，与 `avcC`/`hvcC` 相同的参数集从样本里去掉，AUD、SEI 保留；ADTS 帧逐帧拆开去头，跨 PES 的帧接起来。连续计数器断在单元中间、PES 长度不符、失去同步、截断的包都报错；文件末尾被截断的最后一个音频 PES 丢弃。重复包只认逐字节相同的包（拼接的分片会把计数器从头开始）。
- fMP4：初始化段里每条音视频轨的样本描述原样复制（`Mp4RawCodec`），样本表按 `tfhd`/`tfdt`/`trun`（含 default-base-is-moof、多个 trun）重建；读完一个 moof 后一次读出它引用的数据。加密轨、第二个初始化段、引用到文件外的数据、截断的盒子都报错。
- 时间线（`TimelineJoiner`）：TS 的 33 位时间戳先展开回绕；某条轨时间戳后退超过 1 s 或前进超过 60 s 就是新的一段，接在已写的所有轨之后，另一条轨跳到同一段时跟着接上；更小的前跳保留（漏掉的分片在文件时间里是空档）。视频 DTS 严格递增（重复的往后挪 1 tick），音频按帧长累加、偏离一帧以上才跟随时间戳。
- 夹具（`test/fixtures/remux/`、`test/fixtures/hls/`）：ffmpeg 生成的 x264 / x265 + AAC 的 TS、HLS TS 分片和 fMP4 分片；测试把输出与 `ffmpeg -c copy` 的 MP4 逐样本比对（NAL 单元、同步样本、显示时间），并用 ffprobe 和 ffmpeg 全解码检查。

2026-09-28 真实录制（`live_cli record` 录约 60 s FLV，`live_cli remux` 转换并用 ffprobe、ffmpeg 检查；“时长”是 ffprobe 的容器时长，`ffmpeg -c copy` 转出的 MP4 与本实现相同）：

| 平台 | 编码 | FLV | 包数 FLV = MP4（视频/音频） | 时长 FLV → MP4 | DTS 回退 | 解码错误 | 负载 |
|---|---|---|---|---|---|---|---|
| 斗鱼 36252 | H.264 High 1080p30，AAC 44.1 kHz | 3.0 MiB | 1898 / 2723 | 63.234 → 63.346 s | 0 | 0 | MD5 相同 |
| 斗鱼 252140（`record --remux` 端到端，管理器调用本实现） | H.264 High 1080p30，AAC 48 kHz | 13.7 MiB | 1910 / 2985 | 63.661 → 63.764 s | 0 | 0 | MD5 相同 |
| 虎牙 998 | H.264 High 1440p60，AAC 44.1 kHz | 21.6 MiB | 4013 / 2874 | 66.722 → 66.772 s | 0 | 0 | MD5 相同 |
| B 站 6732538 | H.264 High 720p30，AAC 48 kHz | 10.3 MiB | 1804 / 2812 | 59.982 → 60.120 s | 0 | 0 | MD5 相同 |
| 虎牙 998（`codec=265`，写入器改写为 `hvc1`，Annex B 负载） | H.265 Main 1440p60，AAC 44.1 kHz | 36.6 MiB | 3944 / 2825 | 65.589 → 65.651 s | 0 | 0 | 音频 MD5 相同，视频解码画面逐帧相同 |
| 虎牙 998（CDN 原始 codec 12 FLV，未经写入器） | H.265 Main 1440p60，AAC 44.1 kHz | 8.4 MiB | 898 / 643 | 15.0 s | 0 | 0 | 同上 |

- 解码检查用 `ffmpeg -v error -i x -map 0:v? -map 0:a? -fps_mode passthrough -enc_time_base demux -f null -`。照原样的 `ffmpeg -v error -i x -f null -` 在虎牙和 B 站上会打印几行 “non monotonically increasing dts to muxer”，那是 null 输出按帧率取整时间基后相邻帧撞在一起，FLV 源文件和 `ffmpeg -c copy` 的 MP4 打印的行数完全一样，与转封装无关。
- 音频时间与 FLV 相差不超过 1 ms（毫秒取整），视频显示时间完全相同；B 站当时没有 FLV 的 HEVC（匿名请求 `codec=0,1` 只给 AVC），抖音、快手推荐房间也只有 AVC 的 FLV，H.265 用虎牙 `codec=265` 验证。
- 速度（WSL，tmpfs）：2.1 GiB 的 1440p60 文件（68.9 万个样本）10.8 s，约 200 MiB/s（两遍读、一遍写），峰值 RSS 88 MiB；同一文件 `ffmpeg -c copy -movflags +faststart` 6.1 s、115 MiB。

## 还没做

- HLS：SAMPLE-AES、音视频分离的 master、packed audio 分片报 `unsupportedProtocol` 并换线路；会话型输入（Bigo、FC2、niconico，§7.9）未做。
- 连续 TS：rtsp、udp、rtp 等非 HTTP 地址不录；MPEG-2 视频、MP2 / AC-3 音频能录成 `.ts` 但转不了 MP4（任务以 `remuxFailed` 结束，源文件保留）；只跟踪 PAT 里的第一个节目（多节目流里其它节目的包照写）。
- 桌面退出提示（§16.2，应用层）、旧版 TS 遗留合并（§14.3）。
- 任务持久化接 `live_store` 的 `record_tasks` 表（应用目前用 `JsonFileRecordTaskStore` 写 `<数据根>/DB/record_tasks.json`）。
- 转封装只复制 H.264、H.265 和 AAC（fMP4 的样本描述原样复制，不限编码）；文件中途编解码配置变化时报错（写入器本来就会在配置变化处切分段）；旧 TS 遗留合并（§14.3）不走这里。

## 测试

`dart test`（304 个）：连续 TS（`test/ts/`：嗅探 FLV / TS / HLS / 其它与读多少字节、`FlvByteSource`、`openHttpStream` 的请求头、非 200 和读空闲超时；`TsFeed` 在模拟的广播式交错流上（音视频包交错、PAT/PMT 夹在帧中间、连续计数器贯穿整条流）：从中间加入从关键帧开始、原样包序、错位开头和任意分块、断在帧中间只留整单元、重连接着写并记缺口、源重启、视频丢包丢到关键帧、音频丢包只丢一个 PES、失去同步、按时长切分且旧文件的 PES 完整、SPS / AAC 配置 / PMT 变化、停止、没有关键帧、33 位回绕、纯音频、MPEG-2、跨 PES 的 AAC 帧；会话里 other 线路的 TS / FLV / HLS / 不支持的内容、404、线路顺序；管理器端到端转 MP4；崩溃恢复截到最后一个视频 PES）、HLS（`test/hls/`：列表解析、AES-128 与 NIST 向量 / live_core / openssl 对照、刷新节奏与慢响应、起点、并发与背压、分片重试与缺口、跳号、重连无缝、重新编号、EXT-X-GAP、ENDLIST、卡住、AES-128 两种 IV、SAMPLE-AES、BYTERANGE、fMP4 初始化段、LL-HLS、master 与分离音频、4xx 续签、连续失败、租期换地址、停止、Cookie；写入器的连续文件、切分、配置变化、关键帧切开、残余字节、缺口、弹幕时间、背压、磁盘满；崩溃恢复；会话里 FLV 与 HLS 的顺序和切换、重连、下播、不支持的线路、密钥不落盘；管理器端到端和崩溃恢复后转封装）、TS / fMP4 转封装（`test/remux/ts_to_mp4_test.dart`、`fmp4_to_mp4_test.dart`：与 ffmpeg 逐样本比对、时间线连接、33 位回绕、跨 PES 的访问单元与 ADTS 帧、分片计数器重置、各种损坏输入）、写入器（分段结构、时间戳、重定基准、按时长/大小/配置切分、codec 12、SEI 尾、`.part` 与重名、背压与磁盘卡住、磁盘满、刷盘、弹幕锚点、gaps.json）、恢复（扫描截断、改名、XML 补尾、crash 缺口）、重试与游标、命名与根目录、错误分类与脱敏、会话（斗鱼两次续期无缝、EOF 续接、下播、断网有界退避、4xx、5xx、全部线路失败、停止、磁盘满、关闭自动重连、画质偏好、HLS 跳过、预取、弹幕 XML）、管理器（开始/停止/持久化不含密钥、并发与间隔、强制开始、容量上限清理、备份导入、等待开播轮询、REG-RECORD-033、轮询开关、迟到结果、意图串行、崩溃恢复、开机恢复、退出与后台中断、转封装失败与重试、进度、写入合并、删除、弹幕重连、JSON 存储）、容量上限（`storage_test.dart`：从旧到新删除、受保护目录、被占用的文件、空目录清理、真实磁盘）、转封装（`test/remux/`：两个 ffmpeg testsrc 生成的小 FLV 夹具（x264 带 B 帧、x265 Enhanced FLV）的黄金字节；逐样本比对负载、显示时间、同步样本；盒子结构；`stts`/`ctts` 游程、`stss`、`stsc` 分块、`co64` 切换；负 CTS 与重复时间戳；纯音频、纯视频；旧式 codec 12 与 Annex B（H.264、H.265）；ADTS；配置变化与各种损坏输入；取消、进度、两遍之间输入变化；`remuxFiles` 集成；写入器输出再转封装；6 小时 60 fps 样本表的内存；`IsolateRemuxer`）。除 `IsolateRemuxer` 用临时目录外，全部在 `fake_async` 和内存文件系统上运行，事件顺序与真实上游一致。

真实网络：`dart run tools/live_cli/bin/live_cli.dart record douyu <房间> --duration 600 --remux --out <目录>`（默认用 `Mp4Remuxer`，`--remuxer ffmpeg` 换成 ffmpeg 对照；`--format hls|flv|other`、`--line <线路 id 片段>` 只给录制器某些线路，`--renew-after <秒>` 让线路按间隔续签，用来验证 HLS 换地址；`record url <地址>` 录一个流地址，格式按 IPTV 的规则判断，`--user-agent` 给请求头，`--max-gaps` 允许的缺口数），录完用 `lease` 同一套规则检查每个 FLV 的时间戳，用 ffprobe 检查 FLV 和 MP4 的视频 DTS 与盒子顺序，并读 `gaps.json`。已有的录制文件（FLV、TS、fMP4）用 `live_cli remux <文件>…` 转换并检查（包数、DTS、时长、完整解码、负载 MD5 或解码后的逐帧 MD5、`moov` 在 `mdat` 前）。HLS 分段（`.ts`、`.m4s`）在 `record` 报告里用 ffprobe 数包并全解码。

2026-09-27 斗鱼 9999 房间（匿名，1080p30 H.264 + AAC，`expire=300`）录制 600 s：

| 项目 | 结果 |
|---|---|
| 续期 | 2 次（257 s、512 s），都在拼接器内完成，外层连接 1 次 |
| 文件 | 1 个分段 169.3 MiB，时间戳 0 → 603067 ms，18093 个视频 tag、28269 个音频 tag、1 个脚本 tag |
| 最大间隔 | 视频 34 ms（一帧，30 fps 取整），音频 22 ms；没有回退 |
| ffprobe | FLV 与转出的 MP4 都是 18093 个视频包，DTS 最大间隔 34 ms，无回退；`ffmpeg -v error -i …mp4 -f null -` 无输出 |
| gaps.json | 0 条 |
| 结果 | PASS |
