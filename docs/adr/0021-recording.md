# 0021 录制层的实现方式：进程内拼接、`.part` 分段、任务状态与可注入的转封装

- 状态：已接受
- 日期：2026-09-27

## 背景

`live_record`（纯 Dart）按 ADR 0005 和 `spec/modules/record.md` 实现。规格写了行为，但有几处实现方式需要固定下来：录制怎样复用播放的拼接能力、文件在写入过程中叫什么、“等待开播”在轮询关闭时的去向、转封装和弹幕怎样接入而不让本包依赖 FFmpeg 和 `live_danmaku`，以及 HLS 录制的范围。

## 决定

1. **进程内拼接，不经回环 HTTP。** 每条 FLV 连接都交给 `live_media` 的 `FlvSplicer`（与 `LoopbackRelay` 用的是同一个类），输出直接进 `FlvSessionWriter`，不经过 127.0.0.1 的 HTTP 转发。斗鱼 `expire` 租期在拼接器里无缝续上；没有租期或租期不断开连接的线路，旧连接 EOF 时拼接器立刻续接（有有效预取就用预取，§5.2），最多跳过一个 GOP 并记缺口；拼接器放弃后才交给外层会话循环按 §11.4 快速重连。背压：拼接器读上游前先等写入器的 `ready`（队列超过 8 MiB 时暂停），套接字因此停读，TCP 背压生效。

   2026-09-27 实测：斗鱼 9999 房间录制 600 s，跨过两次 300 s 租期，拼接 2 次，一个文件，视频最大间隔 34 ms（一帧），音频 22 ms，没有回退，`gaps.json` 为空；转出的 MP4 DTS 同样连续、完整解码无错误（`packages/live_record/README.md`）。

2. **写入中的文件带 `.part` 后缀。** FLV 分段写成 `<前缀>_<NNN>.flv.part`，弹幕写成 `<前缀>_<NNN>.xml.part`，关闭时改名；转封装输出写 `<名字>.mp4.partial`。名字冲突时依次加 `-1`、`-2`，`.part` 和 `.partial` 也算占用。崩溃恢复（每次启动都做）按 tag 扫描截掉残余字节后改名，没有媒体的分段直接删除，XML 补 `</i>`，`gaps.json` 补一条 `crash`。

3. **等待开播只在轮询打开时存在。** 任务进入 `waitingLive` 时一定有定时检查在排队；关闭轮询时，等待中的任务转为“已停止（原因：轮询已关闭）”，重新打开轮询时它们回到等待并立刻检查。轮询关闭时重试用尽直接标失败（`retriesExhausted`），确认下播标完成（REG-RECORD-033）。停止原因（`StopCause`）另有“用户停止”（用户意图锁存）和“应用退出”（`stopAll` 或崩溃恢复后）；开机恢复只看后者，不开开机恢复时下次启动清掉这个原因。

4. **错误全部类型化**（`RecordErrorKind`，每种带重试类别）：`upstreamEof` 走快速重连、`http4xx` 立即重新解析（第一次续签原线路、第二次换线路、第三次起常规退避）、`http5xx` 同址 1/2/4 s 后常规退避、网络与解析错误常规退避并受 `maxRetries` 约束；连接前失败的线路立即换下一条，全部失败记 `allLinesFailed` 并常规退避。在 §21 的清单外补了 `regionBlocked` 和 `retriesExhausted`。

5. **转封装通过注入的 `Remuxer`。** 本包只定义接口和提交流程（`.partial`、成功才改名、失败删 `.partial` 保留源、60 s 无进度看门狗、进度单调且最高 0.99、默认删源）。应用按 ADR 0005 §4 提供链接 libmpv 那份 libavformat 的原生垫片；`tools/live_cli` 用 `ffmpeg` 可执行文件（`FfmpegProcessRemuxer`），只用于桌面工具。（2026-09-28 起实现改为本包内的纯 Dart 转封装，见补充决定。）

6. **弹幕由 `RecordChatSource` 提供。** 接口只有 `connect(RoomDetail) → Stream<RecordChatMessage>`，应用用 `live_danmaku` 实现（本包不依赖它）。管理器在会话解析、录制、重连时订阅，出错或结束 30 s 后重连；消息按写入器的“墙钟 ↔ 文件时间”锚点写进与分段同名的 B 站格式 XML。

7. **任务持久化通过 `RecordTaskStore` 接口**（`load` / `save` / `remove`），内置内存和单个 JSON 文件两种实现；应用以后用 `live_store` 的 `record_tasks` 表实现。快照只含 `RecordTask.toJson` 的字段：房间、展示信息、画质偏好、游标（画质 id + 线路序号）、状态、脱敏后的失败、会话信息，没有 URL、请求头和 Cookie。

8. **HLS 录制暂不实现。** 首批 5 个平台每个画质都有 FLV 线路（B 站只有部分高画质或 HEVC 仅在 fMP4 HLS 中提供），录制器只选 FLV 线路；某个画质只有 HLS 时跳到下一画质，全部没有 FLV 时报 `unsupportedProtocol`。§7 的 HLS 下载器在接入 Bigo、FC2、niconico 或 B 站 fMP4 画质时再做。

## 备选方案与放弃理由

- 录制经 `LoopbackRelay` 的回环 HTTP 读取：多一次本机 HTTP 转发，`HttpResponse.add` 没有背压，拼接事件也拿不到（缺口记账需要）。拼接逻辑本身相同，所以直接用拼接器。
- FLV 直接写最终文件名：进程被杀后文件看起来完整，其它程序（包括转封装和清理）可能拿走半个文件；`.part` 让“未收尾”一目了然，恢复时改名即可。
- 轮询关闭时让任务停在“等待开播”：正是 3.x 的缺陷，任务看似在等却永远不检查。
- 本包直接依赖 `live_danmaku`：两个包并行开发，而且录制只需要普通聊天的四个字段；推模式的 sink 则要应用自己管理重连，拉模式由录制器统一处理 §17 的超时和重连。

## 补充决定（2026-09-28，主会话）

- **回放不录**：平台返回回放（轮播、重播）时按下播处理，会话结束、监控任务回到等待开播。轮播是旧内容，旧版照常录制会占满空间并让任务一直停在录制中（spec/modules/record.md §4.1）。
- **转封装用纯 Dart 实现，取代 ADR 0005 §4 的原生垫片**：`FlvToMp4Remuxer`（`packages/live_record/lib/src/remux/`）自己解复用 FLV（复用 `live_media` 的 `FlvFramer`）并写 faststart MP4：第一遍逐 tag 建紧凑样本表（每样本约 4 字节，`stts`/`ctts` 游程编码），据此排好 `moov`；第二遍再解复用一次，把负载按计划的块顺序写进 `mdat`，不写临时文件，内存与文件大小无关。不再需要把 libavformat 链接进来，也不用为此改 libmpv 的构建配方；Android 与 Windows 同一份代码，能在 `dart test` 里测。应用用 `IsolateRemuxer(FlvToMp4Remuxer())` 放到后台 isolate 运行。用 libmpv 的 stream-record 转封装的尝试失败（不写 moov、按实时速度写）。范围是录制器会写出的编码：H.264、H.265（旧式 codec 12 与 Enhanced FLV `hvc1`，含虎牙那种 Annex B 负载，按参数集重建 `hvcC`）和 AAC（含 ADTS 包装）；其它编码、文件中途配置变化（写入器遇到配置变化本来就切分段）、损坏或截断的输入都报 `RemuxException`，源 FLV 保留。实测斗鱼、虎牙（H.264 与 H.265）、B 站各约 60 s：包数与 FLV 一致、DTS 单调、完整解码无错误，音视频负载 MD5 与 FLV 相同（Annex B 的 H.265 解码画面逐帧相同），时长与 `ffmpeg -c copy` 的结果一致；2.1 GiB 文件约 200 MiB/s、峰值内存 88 MiB（`packages/live_record/README.md`）。HLS 本地归档和旧 TS 的转封装在录制器产出它们时再加。

## 影响

- `spec/modules/record.md` 补充了决定 1–4、8 对应的说明。
- 应用接入时需要提供：`RecordRooms`（`SiteRecordRooms` 包住各平台适配器）、`RecordTaskStore`（`live_store`）、`Remuxer`（`IsolateRemuxer(FlvToMp4Remuxer())`）、`RecordChatSource`（`live_danmaku`），并在 Android 前台服务里观察 `activeCountChanges`，在 `onTimeout` 时调用 `interruptAll`，在桌面退出时调用 `stopAll`。
- `live_cli record` 是录制的真实网络探针：斗鱼每次改动拼接或写入器都要跑一遍，PASS 且 `gaps.json` 为空才算通过。
