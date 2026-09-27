# 0035 录制 HLS：连续文件、内存解密、纯 Dart 的 TS / fMP4 转封装

- 状态：已接受（修订 ADR 0021 决定 8、ADR 0005 决定 3）
- 日期：2026-09-28

## 背景

ADR 0021 决定 8 让录制器只选 FLV 线路，某画质只有 HLS 时跳过，全部没有 FLV 时报 `unsupportedProtocol`。首批 5 个平台都有 FLV，这样够用；第二、三批平台里 SOOP、Twitch、TwitCasting、PandaTV、CHZZK、Picarto、SHOWROOM 只有 HLS，B 站的部分高画质也只在 fMP4 HLS 里，这些房间现在都录不了。

ADR 0005 决定 3 和规格 §7.5 原来要把 HLS 存成本地 VOD 归档：`<前缀>.hls/` 目录里每个分片一个文件、本地 `index.m3u8`、本地 key 文件和初始化段。按这个做会有三个问题：

- 2 秒分片一小时就是 1800 个文件，录制目录、容量清理、备份都要处理大量小文件；
- AES-128 的 key 要写进录制目录，与 §13“HLS key 绝不落盘”冲突（规格里两处互相矛盾）；
- 转封装要先按本地列表把分片拼起来，再解一遍 HLS，比直接转一个连续文件多一层。

实现时还在真实网络上碰到三种与规格无关、但决定写法的上游行为：Twitch / Amazon IVS 把一帧拆到两个 PES（下一个 PES 以上一帧末尾的字节开头）；拼起来的分片把每个 PID 的连续计数器从 0 重新开始；IVS 列表里较早的分片不以关键帧开头。

## 决定

1. **线路顺序**：同一画质先用 FLV 线路（拼接无缝，ADR 0021 决定 1），没有或都在录到媒体前失败时用 HLS 线路；游标的线路序号按“FLV 在前、HLS 在后”编。`unsupportedProtocol` 只剩真正录不了的情况：rtmp 等协议，以及连上后才发现的 SAMPLE-AES、DRM 密钥格式、音视频分离的 master、packed audio——这种线路立即换下一条，所有画质的所有线路都这样才失败。
2. **下载器 `HlsFeed`**（纯 Dart，`live_record`）：RFC 8216 §6.3.4 的刷新节奏，从请求开始计时、不重叠；第一个列表从倒数第 3 片开始录；按媒体序号去重，序号状态跨重连保留（重连后列表还含下一片时无缝），跳号、重新编号、放弃的分片都记进 `gaps.json`；分片在内存里整片下载、核对长度、AES-128 在内存解密，最多 2 个在下载或等写；LL-HLS 只取完整父分片，增量列表按失败处理；4xx 经适配器续签一次，租期到 refreshAt 续签同格式线路并在下一次轮询换地址；停止时在途分片等一个目标时长。网络走 `IoHlsClient`：应用的代理策略按请求地址选路，TLS 照常校验，会话 Cookie 按源站只存在内存（TwitCasting 的分片要回传列表下发的 Cookie）。
3. **连续文件取代本地 VOD 归档**：MPEG-TS 分片整片相接写成 `<前缀>_<NNN>.ts`，fMP4 写成 `<前缀>_<NNN>.m4s`（初始化段 + 分片），与 FLV 分段共用 `.part`、写入队列、背压、刷盘和编号（`SegmentFiles`）。编码配置变化、TS 与 fMP4 交替、按时长或大小切分时开新文件；文件从关键帧开始，分片不以关键帧开头时在分片内第一个关键帧处切开。字节原样写（解密后），不改写时间戳；key 不落盘。
4. **转封装**：`Mp4Remuxer` 按内容分派 FLV、MPEG-TS、fMP4，TS 和 fMP4 共用 FLV 转封装的两遍写法和 MP4 写入部分。TS 按 PES 取访问单元，PES 开头在起始码之前的字节接回上一帧；只有逐字节相同的包才算重复包；参数集放进 `avcC`/`hvcC`，ADTS 头去掉。fMP4 原样复制样本描述，按 `trun` 重建样本表。上游的多段时间戳（DISCONTINUITY、重新编号、广告）在转封装时连成一条：后退超过 1 s 或前进超过 60 s 算新的一段，接在已写内容之后，与 FLV 写入器的重定基准规则一致（规格 §6.3）。
5. **崩溃恢复**：`.ts.part` 截到整包并去掉最后一个分片（最后一个 PAT 起，可能只写了一半），`.m4s.part` 截到最后一个完整 moof + mdat。
6. **应用接入**：`httpRecordOpener` 现在同时给 FLV 和 HLS 的访问（`RecordOpener` 由函数类型改为接口），应用不用改；转封装要把 `IsolateRemuxer(FlvToMp4Remuxer())` 换成 `IsolateRemuxer(Mp4Remuxer())`，否则 HLS 分段转封装失败、源文件保留。

2026-09-28 真实网络各录约 60 s（`live_cli record … --remux`）：SOOP、Twitch（代理）、TwitCasting（fMP4 + 会话 Cookie）、B 站 fMP4 和 TS、PandaTV（IVS，90 s 内强制续签 3 次）、CHZZK（fMP4）、SHOWROOM，全部 0 缺口，`.ts` / `.m4s` 和转出的 MP4 用 ffmpeg 全解码无错误；转封装后的画面和音频与源逐帧相同（fMP4 负载 MD5 相同）。细节见 `packages/live_record/README.md`。

## 备选方案与放弃理由

- **本地 VOD 归档（原 ADR 0005 决定 3）**：见背景的三个问题；它唯一的好处是能保留 DATERANGE 和 PROGRAM-DATE-TIME，而这两者目前没有用处（广告照录，§23 第 4 项）。
- **把 key 写进录制目录、保留加密分片**：违反 §13，还要求播放器支持本地 key；在内存解密后写明文没有额外代价。
- **写入时改写 TS 时间戳，让 `.ts` 本身连续**（像 FLV 写入器那样重定基准）：要解析、改写每个 PES 头和 PCR，写入路径变复杂也更容易出错；转封装时连接时间线结果相同，`.ts` 源文件默认在转封装成功后删除。
- **每个 DISCONTINUITY 开新文件**：Twitch 广告前后各有一个，一场直播会切出很多文件；只有编码配置真的变了才需要新文件。
- **按 PES 切帧、不接回开头的残余字节**：Twitch 转出的 MP4 有四分之一的帧被截短，花屏。
- **用 FFmpeg 转 TS / fMP4**：与 ADR 0021 补充决定相同，不再链接 libavformat。
- **音视频分离的 master 和 SAMPLE-AES 现在就做**：前者要两路下载、两条时间线对齐，只有 niconico（v4 还没有适配器）用；后者要按样本解密并改写 NAL，目前的平台都没有。先报 `unsupportedProtocol` 换线路，接入需要它们的平台时再做。

## 影响

- `spec/modules/record.md` §1、§4.3、§7、§8、§9、§10、§14.1、§16.2、§19、§21–§24 按上述改写；§7.5 的本地归档作废。
- ADR 0021 决定 8 和补充决定里“HLS 本地归档的转封装以后再加”由本决定取代；ADR 0005 决定 3 的“保存为本地 VOD 归档”由决定 3 取代。
- 应用侧：`apps/pure_live/lib/core/recording.dart` 换成 `Mp4Remuxer`；`recording_page.dart` 里 `unsupportedProtocol` 的文案“这个直播间只有暂不支持录制的 HLS 流”要改；录制设置里“转成 MP4 后保留原始 FLV”改为“原始文件”。
- 真实网络验证：`live_cli record` 新增 `--format`、`--line`、`--renew-after`；`live_cli remux` 接受 TS 和 fMP4。

## 修订（IPTV 连续 TS，2026-09-28）

### 背景

IPTV 的线路除了 HLS，还有 `.ts`、udpxy 的 `/udp/…`、没有扩展名的地址，它们是一条 HTTP 响应里的连续流。`live_core` 只有 flv / hls 两种格式，IPTV 把非 HLS 的线路都标成 flv（ADR 0024），录制按 FLV 解析，一连上就失败（REG-RECORD-045）。应用里 IPTV 有录制入口（直播间录制按钮、节目预约录制 F-IPTV-10），这是真实缺口。规格 §8 原来只写了“按字节原样写 `.ts`，关闭时截到 188 的整数倍”，断流后的时间戳处理标为待确认。

### 决定

1. **线路格式 `StreamFormat.other`**：一条 HTTP(S) 响应就是整条流，容器由开头的字节决定。IPTV 的规则：路径 `.m3u8` / `.m3u` → hls，`.flv` → flv，其它 http(s) → other；rtmp、rtsp、udp、rtp 仍标 flv（播放直连，录制跳过）。播放层对 other 直连（`PipelineMode.of` 的“其它”）。
2. **按内容嗅探**（每次连接，最多 64 KiB）：`FLV` 签名走 FLV 路径（拼接器照常续接，续接时再嗅探一次）；前 188 字节里某个位置起连续 5 个包的同步字节对齐 → 连续 TS；`#EXTM3U` → 按 HLS 录（没有 `.m3u8` 扩展名的 IPTV 列表地址）；其它 → `unsupportedProtocol`，换下一条线路。游标里 FLV 和 other 线路按原顺序排在 HLS 前面。
3. **连续 TS 写进 HLS 写入器的 `.ts`**（`TsFeed` → `HlsSessionWriter` 作为 `TsSink`）：与 HLS 的 TS 分段同一种文件、同一套编号、`.part`、背压、刷盘、转封装和崩溃恢复。包按收到的顺序原样写，但每个 PES 和 PSI 段要么整个写、要么整个不写（只丢整包，从不改写包）：单元收完才写，写入落后读取约一帧。文件和每次断流后都从视频关键帧开始，前面补一份最近的 PAT/PMT，其它流从各自的下一个 PES 开头开始；断流、停止（先等正在收的帧收完，最多 3 s）时没收完的单元丢掉；视频丢包或失去同步按断流处理，丢到下一个关键帧并记 `damaged` 缺口，其它流丢包只丢那个 PES；按时长/大小切分和编码配置变化在关键帧处开新文件，关键帧之前开始的其它流的 PES 整个留在旧文件。
4. **不改写时间戳**（原规格 §8 待确认的结论）：文件时间按 DTS 累加，断流后第一个关键帧处记缺口（60 s 窗口内按 DTS 差，否则按墙钟），时间线由转封装连接（§10 的规则：60 s 内的前跳保留为空档，更大的跳变或回退接在已写内容之后）。实测三种情况 `.ts` 和 MP4 都完整解码无错：上游不断只是连接断了（时间戳前进断流时长）、源重启（时间戳从头开始）、33 位回绕。
5. **崩溃恢复**：`.ts.part` 有多个 PAT 时，最后一个 PAT 在视频单元边界上（HLS 分片）照旧从它截掉；PAT 夹在帧中间（连续 TS）则从最后一个视频 PES 开头截掉。
6. **应用接入**：`RecordOpener` 加 `stream(platform)`，`httpRecordOpener` 用同一个代理路由和读空闲超时打开这种流，应用不用改；`live_cli record url <地址>` 录任意一个地址，用来实测。

### 备选方案与放弃理由

- **按字节原样写，只在关闭时截到 188 的整数倍**（原规格 §8）：断流处留下半个 PES，新连接从 PES 中间开始，连续计数器断在单元中间；严格的转封装按 REG-RECORD-008 的规则判失败，ffmpeg 解码也报错。udpxy 转发的组播本身会丢包，同样的问题更常见。
- **把连续字节按 188 对齐切块、每块当一个 HLS 分片交给 `addMedia`**：HLS 写入器按分片判断编码配置和关键帧，要求每块自带 PAT/PMT；连续流里 PAT/PMT 大约 100 ms 一次、夹在帧中间，块内判断不了，按分片切开新文件也会切断其它流的 PES。所以复用写入器的文件、切分和签名比较，分块与单元完整由 `TsFeed` 负责。
- **写入时重定时间戳**：与本 ADR 原决定相同的理由（要改写每个 PES 头和 PCR），转封装连接时间线的结果相同。
- **按 PES 重新排包（每个 PES 连续写）**：改变了包的交错，已不是原样；单元完整只需要在边界处丢包。

### 影响

- `spec/modules/record.md` §1、§4.3、§6.4（`damaged`）、§7.1、§8（重写）、§14.1、§19、§21–§24；`spec/modules/iptv.md` §5、§9；`spec/modules/playback.md` SRC-2。
- ADR 0024 里“非 HLS 线路暂标 flv”由决定 1 取代。
- 转封装只复制 H.264、H.265、AAC：MPEG-2 视频、MP2 / AC-3 音频的 IPTV 频道能录成 `.ts`，转 MP4 失败并保留源文件。
