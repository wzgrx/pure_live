# live_record

Pure Live v4 的录制层（纯 Dart）：FLV 写入器、带租期拼接的录制会话、任务管理器、崩溃恢复、FLV → MP4 转封装。行为依据 [spec/modules/record.md](../../spec/modules/record.md)（文中 §编号指它），方案依据 [ADR 0005](../../docs/adr/0005-recording-without-ffmpegkit.md)，实现上的选择见 [ADR 0021](../../docs/adr/0021-recording.md)。依赖 `live_media`（`FlvSplicer`、`FlvFramer`、`openHttpFlv`）、`live_core`、`live_net`。

## 应用怎么用

```dart
final manager = RecordManager(
  rooms: SiteRecordRooms((platform) => adapters[platform]),   // 各平台适配器（RoomSource + StreamSource）
  store: myLiveStoreTaskStore,                                 // RecordTaskStore；内置 MemoryRecordTaskStore、JsonFileRecordTaskStore
  root: RecordRoot.resolve(defaultRoot: '$dataDir/RECORDS', chosen: settings.recordDirectory),
  settings: RecordSettings(maxConcurrent: 3, polling: true, danmaku: true),   // 由应用的 record.* 设置映射
  opener: httpRecordOpener(proxy: proxyPolicy, readTimeout: const Duration(seconds: 15)),
  remuxer: const IsolateRemuxer(FlvToMp4Remuxer()),           // 可选：纯 Dart 转封装，在后台 isolate 运行；不给则保留 FLV
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
manager.activeCountChanges;             // 有活跃会话时 Android 前台服务保持运行（§16.1）
await manager.interruptAll();           // Android onTimeout：有界收尾，标“后台时间用尽”失败
await manager.stopAll();                // 桌面退出：10 s 内收尾（不转封装），下次启动可开机恢复
await manager.dispose();
```

`RecordTask` 是不可变快照：`state`（`queued`、`resolving`、`recording`、`reconnecting`、`finalizing`、`waitingLive`、`completed`、`failed`、`stopped`）、`failure`（`RecordErrorKind` + 阶段 + 脱敏文本）、`stopCause`（`user` / `pollingOff` / `appRestart`）、`retrying`（重连或轮询中的最近错误）、`nextCheckAt`、`session`（目录、前缀、分段、MP4、字节、媒体时长、缺口数、连接数、拼接数）、`bitsPerSecond`、`remuxProgress`。

## 文件放在哪里

```
<根>/<平台>/<主播>/<yyyy-MM-dd>/
  20260927_101530_123_001.flv        分段（写入中是 .flv.part，关闭时改名）
  20260927_101530_123_001.xml        弹幕（开 record.danmaku 时，与分段同名）
  20260927_101530_123_001.mp4        转封装结果（写入中是 .mp4.partial）
  20260927_101530_123.gaps.json      缺口记录（没有缺口也写空数组）
```

- 根目录按 §15：默认应用数据目录的 `RECORDS`；用户选的目录只当父目录，写进 `<选定目录>/PureLiveRecords/`，放 `.pure_live_recording_root` 标记。`RecordRoot.prepare` 写探针验证可写。
- 路径组件按 §9 清洗；`transliterate` 参数可接拼音转换（`record.pinyinFolders`）。
- 一次会话一个写入器：重连、续期都写同一个文件；只有编解码配置变化、`record.splitMinutes`、`record.splitMegabytes` 才开新分段，在关键帧处切，每个分段的时间戳从 0 开始、都能独立播放。

## 接转封装和弹幕

- **转封装**：实现 `Remuxer.remux(RemuxJob job)`：把 `job.input` 以 stream copy（`+faststart`，不解码）写到 `job.output`（`.partial` 路径），通过 `job.onProgress(已读字节)` 报进度，`job.cancelled` 完成后尽快返回；任何解复用或复用错误都要抛 `RemuxException`（退出码 0 不能说明输入完整，REG-RECORD-008）。提交、改名、删源、60 s 无进度看门狗、失败保留源都由本包处理。本包自带实现 `FlvToMp4Remuxer`（见下文“转封装”），应用用 `IsolateRemuxer` 把它放到后台 isolate；`tools/live_cli` 里的 `FfmpegProcessRemuxer` 调用 `ffmpeg` 可执行文件，只用来对照。
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

## 转封装（`FlvToMp4Remuxer`）

纯 Dart 把录好的 FLV 分段复制成 faststart MP4（`ftyp`、`moov`、`mdat`，`moov` 在前），不解码，Android、Windows 同一份代码（[ADR 0021](../../docs/adr/0021-recording.md) 补充决定，取代 ADR 0005 §4 的原生垫片）。代码在 `lib/src/remux/`：

- **两遍读、一遍写**：第一遍逐 tag 解复用、建样本表；据此排好 `moov`；第二遍再解复用一次，按第一遍定好的块顺序把负载写进 `mdat`。不写临时文件，磁盘只多占一份输出。第二遍核对每个样本的大小和块的位置，输入在两遍之间变了就报错。
- **内存有界**：样本表用 64 KiB 分块的 `Uint32List`，每个样本约 4 字节（大小），`stts`/`ctts` 游程编码，`stss` 只记关键帧，`stsc` 只记变化。6 小时 60 fps 视频 + 48 kHz AAC（230 万样本）的表约 28 MiB（单元测试）；2.1 GiB、1 小时 51 分的 1440p60 文件进程峰值 RSS 88 MiB。第二遍每条轨最多缓存一个块（半秒媒体，最多 4 MiB）。
- **解复用**：复用 `live_media` 的 `FlvFramer`。视频：旧式 AVC（codec 7）、HEVC（codec 12）和 Enhanced FLV `avc1`/`hvc1`（SequenceStart、CodedFrames、CodedFramesX；跳过命令帧、元数据和序列结束）。序列头是 Annex B 起始码而不是配置记录时（虎牙 `codec=265` 就是这样，写入器改写成 `hvc1` 后负载不变），由 VPS/SPS/PPS 重建 `avcC`/`hvcC`，样本改为 4 字节长度前缀。音频：AAC raw 帧；ADTS 包装的剥掉头，没有 AudioSpecificConfig 时由 ADTS 头生成。只读第一个脚本 tag 的 `onMetaData`（SPS 读不出尺寸时用它的宽高）。
- **封装**：`ftyp`（isom、iso2、avc1 或 hvc1、mp41）；每条轨 `tkhd`、`mdhd`（视频 90 kHz，音频按采样率）、`hdlr`、`vmhd`/`smhd`、`dinf`、`stsd`（`avc1`+`avcC`（非方形像素加 `pasp`）、`hvc1`+`hvcC`、`mp4a`+`esds`）、`stts`、`ctts`（有非零偏移时；有负偏移用 version 1）、`stss`、`stsz`、`stsc`、`stco`（超过 4 GiB 换 `co64`，`mdat` 用 64 位长度）。音视频每 500 ms 交错成块。
- **时间戳**：视频毫秒 ×90 原样换算，显示时间（DTS + CTS）不变；重复的 DTS 往后挪 1 tick（CTS 相应减小，可为负）；回退超过 1 s 报错。音频每帧按 1024（或 960）个采样累加，只有时间戳偏离一帧以上（缺口、时钟漂移）才跟随时间戳，避免 FLV 毫秒取整造成逐帧抖动。最后一个样本的时长取最近 64 个的中位数。影片从最早显示的样本开始（与 `ffmpeg -c copy` 相同），晚开始的轨和 B 帧造成的首帧延迟用 `elst`（空编辑 + 媒体编辑）表达。
- **报错**（`RemuxException`，源文件保留，未完成的输出删除）：不是 FLV、tag 类型不对、末尾 tag 不完整、加密 tag、不支持的编码（MP3、VP6、AV1…）、多轨 Enhanced FLV、配置记录损坏、NAL 长度越界、文件中途配置变化（参数集相同的重复序列头可以）、没有配置的媒体、时间戳回退超过 1 s、没有音视频、取消。
- **进度与取消**：进度是已读输入字节（两遍各算一半），每读 1 MiB 报一次；每个 tag 之间检查取消。`IsolateRemuxer` 用 `Isolate.run` 运行任意可发送的 `Remuxer`，进度和取消跨 isolate 传递。

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

- HLS 下载器（§7）、HTTP 连续 TS（§8）：首批 5 个平台都有 FLV 线路，录制器只选 FLV；某画质只有 HLS 时跳到下一画质，全部没有 FLV 时报 `unsupportedProtocol`。
- 桌面退出提示（§16.2，应用层）、旧版 TS 遗留合并（§14.3）。
- 任务持久化接 `live_store` 的 `record_tasks` 表（应用目前用 `JsonFileRecordTaskStore` 写 `<数据根>/DB/record_tasks.json`）。
- 转封装只接受 FLV 里的 H.264、H.265 和 AAC；HLS 本地归档、旧 TS 的转封装在录制器产出它们时再加；文件中途编解码配置变化时报错（写入器本来就会在配置变化处切分段）。

## 测试

`dart test`：写入器（分段结构、时间戳、重定基准、按时长/大小/配置切分、codec 12、SEI 尾、`.part` 与重名、背压与磁盘卡住、磁盘满、刷盘、弹幕锚点、gaps.json）、恢复（扫描截断、改名、XML 补尾、crash 缺口）、重试与游标、命名与根目录、错误分类与脱敏、会话（斗鱼两次续期无缝、EOF 续接、下播、断网有界退避、4xx、5xx、全部线路失败、停止、磁盘满、关闭自动重连、画质偏好、HLS 跳过、预取、弹幕 XML）、管理器（开始/停止/持久化不含密钥、并发与间隔、强制开始、容量上限清理、备份导入、等待开播轮询、REG-RECORD-033、轮询开关、迟到结果、意图串行、崩溃恢复、开机恢复、退出与后台中断、转封装失败与重试、进度、写入合并、删除、弹幕重连、JSON 存储）、容量上限（`storage_test.dart`：从旧到新删除、受保护目录、被占用的文件、空目录清理、真实磁盘）、转封装（`test/remux/`：两个 ffmpeg testsrc 生成的小 FLV 夹具（x264 带 B 帧、x265 Enhanced FLV）的黄金字节；逐样本比对负载、显示时间、同步样本；盒子结构；`stts`/`ctts` 游程、`stss`、`stsc` 分块、`co64` 切换；负 CTS 与重复时间戳；纯音频、纯视频；旧式 codec 12 与 Annex B（H.264、H.265）；ADTS；配置变化与各种损坏输入；取消、进度、两遍之间输入变化；`remuxFiles` 集成；写入器输出再转封装；6 小时 60 fps 样本表的内存；`IsolateRemuxer`）。除 `IsolateRemuxer` 用临时目录外，全部在 `fake_async` 和内存文件系统上运行，事件顺序与真实上游一致。

真实网络：`dart run tools/live_cli/bin/live_cli.dart record douyu <房间> --duration 600 --remux --out <目录>`（默认用 `FlvToMp4Remuxer`，`--remuxer ffmpeg` 换成 ffmpeg 对照），录完用 `lease` 同一套规则检查每个 FLV 的时间戳，用 ffprobe 检查 FLV 和 MP4 的视频 DTS 与盒子顺序，并读 `gaps.json`。已有的 FLV 用 `live_cli remux <文件>…` 转换并检查（包数、DTS、时长、完整解码、负载 MD5、`moov` 在 `mdat` 前）。

2026-09-27 斗鱼 9999 房间（匿名，1080p30 H.264 + AAC，`expire=300`）录制 600 s：

| 项目 | 结果 |
|---|---|
| 续期 | 2 次（257 s、512 s），都在拼接器内完成，外层连接 1 次 |
| 文件 | 1 个分段 169.3 MiB，时间戳 0 → 603067 ms，18093 个视频 tag、28269 个音频 tag、1 个脚本 tag |
| 最大间隔 | 视频 34 ms（一帧，30 fps 取整），音频 22 ms；没有回退 |
| ffprobe | FLV 与转出的 MP4 都是 18093 个视频包，DTS 最大间隔 34 ms，无回退；`ffmpeg -v error -i …mp4 -f null -` 无输出 |
| gaps.json | 0 条 |
| 结果 | PASS |
