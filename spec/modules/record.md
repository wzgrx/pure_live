# 录制（record）模块规格

第 1 阶段草案。只写行为和外部契约，不规定类名和函数拆分。对应包 `live_record`（分帧、拼接能力由 `live_media` 提供），方案依据 ADR 0005。

- 证据写法：`文件:行号` 相对仓库根目录，基于 master 检出 c28c17fb（`lib/recorder` 与第 0 阶段诊断 49ceccb0 相同，14,241 行）。提交哈希转引自 docs/rewrite/diagnosis/04-recorder.md 和所注文档，编写时没有运行 git 复核。
- 标记：**[待确认]** 需要查证；**[决定]** 是本规格新定的 v4 行为（旧版没有，或有意改掉旧行为）。有长期影响的 [决定] 在第 3/5 阶段补 ADR。
- 平台的租期、签名、线路细节以 `spec/sites/<平台>.md` 为准；本规格只写录制侧怎么用。房间身份、表结构、设置注册表见 `spec/modules/store.md`。

---

## 0. 术语

| 术语 | 含义 |
|---|---|
| 任务 | 一个房间的录制意图。每个房间（RoomRef）最多一个任务（recorder_controller.dart:695-696；live_record_task.dart:180） |
| 录制会话 | 用户看到的一次录制：从“开始”到用户停止、确认下播或致命错误。一次会话产出一组时间连续的文件 |
| 连接 | 一次上游读取：一条 HTTP-FLV 连接、一个 HLS 播放列表地址、一条单条 HTTP 流（§8）或一个会话型输入。一次会话内可有多次连接 |
| 分段 | 一个输出文件。只在编解码配置变化或按时间/大小切分时换分段 |
| 缺口 | 会话内没有录到的媒体时间，记入 gaps.json |
| 租期类型 | 取流地址自带的续期语义：到期断开 / 只限新建连接 / 无（§5） |

## 1. 范围

**支持的输入**

- HTTP(S)-FLV，包括 Enhanced FLV 和旧式 codec 12 HEVC。
- HLS：TS 分片、fMP4（EXT-X-MAP）、AES-128 / SAMPLE-AES、BYTERANGE、LL-HLS（只取完整分片）、音视频分离的 master。
- 会话型输入：Bigo、FC2、niconico。平台适配器提供 HLS 地址、请求装饰和保活（live_input_recording_binding.dart:27-107）。
- 单条 HTTP(S) 流（线路格式 `other`，IPTV 的 `.ts`、udpxy 等）：按开头的字节判断，连续 MPEG-TS 按包原样写 `.ts`，FLV 和 HLS 列表按对应的规则录（§8）**[决定]**。
- 实现进度（2026-09-28）：HTTP(S)-FLV、HLS（TS、fMP4、AES-128、BYTERANGE、LL-HLS 只取完整分片）和单条 HTTP 流（§8）都已实现；同一画质先用 FLV 和单条 HTTP 流线路，没有或都失败再用 HLS（§7.1）。未做：SAMPLE-AES 和音视频分离的 master（报 `unsupportedProtocol` 并换线路）、会话型输入（§7.9）。

**不支持**

- rtmp / rtmps / rtsp / rtp / udp / tcp / srt。旧版经 FFmpeg 支持（stream_resolver_service.dart:91-102；ffmpeg_command_builder.dart:204-208）；v4 没有 FFmpeg 拉流，遇到时报“该线路不支持录制”并推进线路游标。**[待确认]** IPTV 用户是否依赖这些协议录制。
- 转码、剪辑、DASH。
- IPTV 定时录制：旧库有 ScheduledRecordings 表，但没有执行者（tables.dart:171-184；database.dart:562-565）。**[待确认]** v4 是否实现。

## 2. 任务模型

| 字段 | 说明 | 落盘 |
|---|---|---|
| 房间身份 | RoomRef：平台小写 + 区分大小写的房间号 | 是 |
| 展示快照 | 主播名、标题、头像、封面、人气（只用于显示） | 是 |
| 画质偏好 | 任务级覆盖，缺省用设置 `record.defaultQuality` | 是 |
| 游标 | 上次使用的画质请求 id 和线路序号，不是 URL（live_record_task.dart:46-50） | 是 |
| 自动重连 | 用户开始时从设置拷贝（recorder_controller.dart:758） | 是 |
| 状态、失败类型、脱敏后的错误文本 | §3、§21 | 是 |
| 用户已停止 | 用户意图锁存（live_record_task.dart:122） | 是 |
| 会话信息 | 开始时间、输出位置、分段列表、累计字节、媒体时长、缺口数 | 是（节流） |
| 连接期数据 | 当前 URL、请求头、Cookie、预取凭据、实时码率 | 否，只在内存 |

- 任务快照不可变，每次变化发布新快照；进度按任务单独推送，不重建整个列表（旧版一个 Obx 包住整表、任务对象每秒替换：recorder_page.dart:88-90；recorder_controller.dart:130）。
- 列表顺序稳定，不随状态或进度重排（recorder_controller.dart:625-628）。
- 同一任务的用户意图（开始、停止、删除、恢复）串行：后一个等前一个完成（recorder_controller.dart:734-768, 1235-1262；e7670220；recorder_user_intent_test.dart:116-243）。
- 所有异步结果带“任务身份 + 会话代次”栅栏，过期代次的回调直接丢弃（recorder_controller.dart:169-312, 320-323；recorder_output_lifecycle_test.dart:163-286；recorder_poll_lifecycle_test.dart:68-196）。
- 删除任务：先按“用户停止”收尾再移除，已产出的文件不删（recorder_controller.dart:1435-1448）。
- “立即录制”是用户明确意图，不看房间卡片的缓存状态，由 §4 的严格判定决定（recorder_controller.dart:701-704；record_action_button.dart:173, 181）。
- “重新录制”：已完成、失败、已停止的任务再次“用户开始”（§3 第一行），开一个新会话（新前缀、新文件），旧会话的文件不动。录制中心对这三种终态都给这个入口；失败的任务同时显示出错环节（§21 的阶段，界面译成“房间检查 / 选画质 / 取流 / 连接 / 写文件 / 转封装 / 排队调度 / 后台运行 / 开播检查”）。
- “强制开始” **[决定 2026-09-28]**：只对排队中和等待开播的任务。排队中：不再等并发槽和 §11.3 的启动间隔，立即多占一个槽开始（可以暂时超过 `record.maxConcurrent`，这个槽随会话结束释放）；等待开播：取消轮询定时器，同样不排队立即开会话。两者都照常先做 §4.1 的严格检查，未开播按 §3 结束会话（轮询开回到等待开播）。3.x 的“开始”按钮对排队中的任务不起作用（startTask 发现任务已在调度队列就直接返回：recorder_controller.dart:746-749, 770-772），等待开播时这个按钮叫“立即检查”，调用的也是 forceStartTask（recorder_page.dart:373-440）；v4 的“立即检查”只查开播（§12），“强制开始”才真正插队。
- 确认 **[决定]**：删除任务、移除监控，以及停止正在解析、录制或重连的任务，都先弹确认框（录制中心和直播间录制按钮一致）；停止排队中或等待开播的任务不确认（没有文件受影响）。3.x 只有“移除监控”确认（recorder_page.dart:743-800）。

## 3. 状态机

| v4 状态 | 旧值（record_status.dart:3-13） | 占并发槽 | 说明 |
|---|---|---|---|
| 排队 queued | queued | 否 | 等并发槽 |
| 解析 resolving | preparing | 是 | 严格房间检查、只签当前线路 |
| 录制中 recording | running | 是 | 已写入第一个媒体 tag / 分片（旧版以“有输出字节”为准：recorder_controller.dart:374-376） |
| 重连中 reconnecting | reconnecting | 是 | 会话未结束，在等重连或重新解析 |
| 收尾 finalizing | processing | 否 | 关闭文件，定稿 gaps.json / XML，可选转封装 |
| 等待开播 waitingLive | waitingLive | 否 | 轮询中（§12）。用户列出的状态之外，旧版就有，必须保留。只在轮询打开时存在：处于这个状态就一定有排队的检查 **[决定]** |
| 完成 completed | completed | — | 终态 |
| 失败 failed | failed | — | 终态，带失败类型 |
| 用户停止 stopped | stopped | — | 终态 |

**转换**

| 从 | 事件 | 到 | 证据 |
|---|---|---|---|
| 终态 / 等待开播 | 用户开始 | 排队。先等上一次停止、恢复、收尾完成；清零会话计数、游标和重试次数 | recorder_controller.dart:734-768 |
| 等待开播 | 轮询确认开播 | 排队 | :1362-1366 |
| 排队 | 拿到并发槽 | 解析 | ffmpeg_scheduler.dart:124-151 |
| 排队 / 等待开播 | 用户强制开始 | 解析：不等并发槽和启动间隔（§2） | [决定] |
| 解析 | 写入第一个媒体数据 | 录制中 | :195-208 |
| 解析 / 重连中 | 严格检查确认下播 | 收尾（有输出时）→ 等待开播（轮询开）/ 完成（轮询关） | :958-967 |
| 解析 | 封禁、房间不存在、平台不支持、需要登录 | 失败 | stream_resolver_service.dart:118-127, 148-150 |
| 解析 | 网络、状态未知、无画质、全部线路失败 | 重连中（常规退避 §11.5） | recorder_controller.dart:968-974 |
| 录制中 | EOF、连接中断、读空闲超时 | 重连中（快速 §11.4） | :273-276 |
| 录制中 | HTTP 4xx | 重连中（立即重新解析 §11.7） | cf35dcf9 |
| 重连中 | 新连接写入数据 | 录制中（同一会话、同一文件） | [决定] |
| 重连中 | 常规重试用尽 | 收尾 → 等待开播（轮询开）/ 失败（轮询关） | :1205-1214；[决定] |
| 排队 / 解析 / 录制中 / 重连中 | 用户停止 | 收尾 → 用户停止 | :1235-1293 |
| 录制中 / 重连中 | 致命错误（磁盘满、无权限、只读、路径无效） | 收尾 → 失败 | recorder_continuation_policy.dart:15-40 |
| 任意活跃态 | 后台服务被系统中断 | 收尾 → 失败（后台） | recorder_controller.dart:1038-1057 |
| 收尾 | 会话因下播结束且自动重连开 | 等待开播（轮询开）/ 完成 | :498-509 |
| 收尾 | 转封装失败 | 失败，源文件保留 | :478-483 |
| 等待开播 | 关闭轮询 | 已停止（原因：轮询已关闭）；重新打开轮询时回到等待开播并立即检查 | [决定]，REG-RECORD-033 |
| 任意活跃态 / 等待开播 | 应用退出（§16.2） | 收尾 → 已停止（原因：应用退出），开机恢复的候选 | [决定] |

**不变量**

- 重连不结束会话、不开新文件、不新建目录。旧版每次重连都新建“平台/主播/日期/时分秒”目录和一个新 MP4（cache_service.dart:262-279；recorder_controller.dart:820-835），v4 改掉 **[决定]**。
- 收尾只在会话结束时执行；重连之前不做转封装（db7d0df3；recorder_controller.dart:457-466）。
- 失败和用户停止之后不自动重试；只有用户再次开始，或 §14.2 的开机恢复规则，才重新排队。
- 连续录到 ≥10 s 媒体后，重试计数清零（:227-230）。

## 4. 解析

### 4.1 严格房间状态

录制判定开播只用平台的严格房间接口。详情失败按网络错误处理，绝不当成下播（stream_resolver_service.dart:132-145；233d858d）。

| 严格详情结果 | 录制侧结论 | 证据 |
|---|---|---|
| 请求失败、超时、解析失败 | 网络错误，可重试 | :139-145 |
| 封禁 | 失败，不重试 | :148-150 |
| 明确未开播 | 下播 | :151-154 |
| 回放（轮播、重播） | 按下播处理，不录 **[决定 2026-09-28]**：轮播是旧内容，接着录只占满空间，还让监控任务一直停在录制中。旧版会照常录（:151；live_room.dart:518） | — |
| 直播中 | 取流 | :151 |
| 状态未知 | 网络错误，可重试 | :155-157 |
| 画质列表为空 | 无画质，可重试 | :175-180 |

### 4.2 画质排序

按选择 id 去重 → 有平台 sort 时按 sort 降序、否则保持原序 → 与偏好标签精确匹配（忽略大小写、空白、`_`、`-`）的档移到最前；没有精确匹配时，按五档偏好的相对位置取最近的一档（stream_resolver_service.dart:299-347）。平台画质 id 互不可比，不做数值比较。

### 4.3 只签当前线路与线路游标

- 每次解析只签名本次要用的那一条线路，不预先签所有画质 × 线路（065427ed；:183-188；owned_record_input_test.dart:33, 61）。
- 续签（同一会话因租期或 EOF 续接）：优先原画质原线路（:196-220）。
- 失败推进：同画质下一线路 → 下一画质第一线路（循环）→ 全部失败后回绕到原画质线路 1 并重新签名（:221-280）。
- 判断“是不是同一条线路”只比较 scheme + host + path，忽略签名参数（:395-404）。
- 全部失败 → “全部线路失败”，可重试（:282-285）。
- 只接受 §1 支持的 scheme（http、https）。同一画质里 FLV 线路和单条 HTTP 流线路（`other`，§8）按原顺序排在前面，HLS 线路在后，线路序号按这个顺序（§7.1）。

## 5. 来源：按租期类型处理

每条线路带租期（PLAN §05：`lease(refreshAt, cutsConnection)`）。

| 租期类型 | 平台 | 处理 | 证据 |
|---|---|---|---|
| 到期断开连接 | 斗鱼匿名原画 FLV（`expire=N`） | 拼接续流（§5.1） | douyu_site.dart:30-64；flv_splice_relay.dart:341-350；31982153 |
| 只限新建连接 | 虎牙 WUP 原生 FLV（`ctype=huya_pc_exe&t=100`） | 保持连接，预取下一凭据，真正 EOF 才换（§5.2） | huya_transport_policy.dart:71-78；recorder_controller.dart:1075-1078；f66cff51 |
| 无租期 | 其它 | EOF 后续接（§5.3） | recorder_continuation_policy.dart:73-83 |
| 有 refreshAt，类型未确认 | 虎牙网页 FLV/HLS（100/125 s）、酷狗、猫耳、YouTube | FLV 按拼接处理（两种语义下都没有缺口）；HLS 按 §7.6 换列表地址。**[待确认]** 用真实探针确认是否会断开连接 | huya_site.dart:57-58；kugou_live_site.dart:280-283；missevan_site.dart:154-155；youtube_site.dart:219-222 |

### 5.1 拼接（到期断开连接）

- 续签时刻 = 失效时刻 − min(45 s, 租期 / 4)（douyu_site.dart:58-64）。续签取同画质同线路。
- 续签失败：保留旧连接直到它结束，再交给外层循环（flv_splice_relay_test.dart:180）。
- 新连接 15 s 内要给出 FLV 头，并在 15 s 内出现关键帧，否则放弃这条新连接（flv_splice_relay.dart:227-233）。
- 切换点是新连接里第一个“旧连接还没送出”的视频关键帧。旧连接继续送到这个时间戳（最多等 10 s），此后旧连接的音频丢弃；再从新连接的关键帧开始（:103, 256-291；flv_splice_relay_test.dart:70）。
- 时间线：新连接首个视频时间戳与已送出位置相差 ≤60 s，视为同一时间线，不平移；否则平移到已送出位置之后（:104, 245-248；flv_splice_relay_test.dart:131）。**[决定]** v4 平移量改为“已送出 + 1 帧时长”，与 §6.3 一致（旧版 +1 ms）。
- 编解码配置和之前不同：在切换关键帧前送出新配置（:282-287；flv_splice_relay_test.dart:155），写入器据此开新分段（§6.5）。
- 旧连接在新连接就绪前结束：从新连接下一个关键帧接上，最多跳过一个 GOP，仍写同一文件，这段记为缺口（:87-94；flv_splice_relay_test.dart:109）。
- 拼接本身退出（旧流结束且续签失败，:146-147）→ 外层循环重新解析（§5.4）。

### 5.2 只限新建连接

- 不按时间主动断开健康连接（f66cff51；recorder_lease_lifecycle_test.dart:173, 196, 218）。
- refreshAt 前 5 s 预取下一凭据，只放内存（recorder_continuation_policy.dart:88-95）。预取失败不影响当前连接（recorder_controller.dart:1136-1143）。之后按新凭据的 refreshAt 维护，间隔不短于 30 s（:1144-1160；policy:105-112）。每个任务最多一个在途预取、一个定时器。
- 真正 EOF 或 4xx：预取凭据仍有效（失效时刻在未来、来源 URL 没变）就立即用它重连（0 s）；否则按 §11.4 重连并重新解析（:862-879）。**[决定]** 有有效预取时 0 s 重连（旧版固定等 2 s）。

### 5.3 无租期

EOF → 按 §11.4 重连，重新解析（续签优先原线路）。

### 5.4 外层会话循环

```
会话开始 → 解析 → 按租期类型打开来源 → 数据交给写入器（整个会话只有一个写入器）
来源结束时按原因处理：
  用户停止            → 收尾
  EOF / 中断 / 读空闲  → 快速重连（§11.4），用预取凭据或重新解析
  HTTP 4xx           → 立即重新解析（§11.7）
  HTTP 5xx           → 同一地址重试最多 3 次（1、2、4 s），仍失败按网络错误
  网络 / 解析失败      → 常规退避（§11.5）
  严格检查确认下播      → 收尾
  致命（磁盘/权限）     → 收尾 → 失败
新连接接回同一个写入器：同一文件继续，时间戳重定基准（§6.3），缺口记账（§6.4）
```

- 连接读空闲超时 = `record.readTimeout`（15 / 30 / 60 s，默认 15 s；旧 rwTimeout：recorder_config.dart:29, 69）。
- 5xx 只在同一地址重试（旧版 FFmpeg `-reconnect_on_http_error 5xx`，ffmpeg_command_builder.dart:188-201）；5xx 的次数和间隔为 **[决定]**。4xx 绝不重试旧签名（cf35dcf9）。

### 5.5 实现：每条 FLV 连接都经过拼接器 [决定]

- 录制在进程内使用与回环中继相同的 `FlvSplicer`（live_media），不经过 127.0.0.1 的 HTTP 转发；拼接器的输出直接进写入器。拼接器读上游前先等写入器有空位，所以 §6.8 的背压一直传到套接字。
- 到期断开连接的租期按 §5.1 在拼接器内续期。其它线路（不断开连接的租期、没有租期）在旧连接 EOF 时由拼接器立即续接：有 §5.2 的有效预取就用它，否则重新解析同画质同线路；从下一个未送达的关键帧接上，最多跳过一个 GOP，记 reason=`splice` 的缺口。这相当于 §11.4 快速重连的第一次为 0 s，并且不开新连接计数。
- 拼接器续接失败（新连接给不出关键帧、解析失败）才结束连接，交给外层循环按 §11 重试；外层循环每次都先做严格房间检查。
- 连接前失败（没有录到媒体）的线路按 §4.3 立即推进游标；第一次 4xx 先续签原线路，第二次推进游标，第三次起常规退避（§11.7）。
- 真实网络验证：`live_cli record`（见 packages/live_record/README.md）。

## 6. FLV 写入规则

### 6.1 文件结构

- 每个分段的 FLV 头（9 字节 + PreviousTagSize0）只写一次。音视频标志取会话首个连接的头。**[待确认]** 会话中途新增音轨或视轨时是否要开新分段补标志。
- 脚本 tag（onMetaData）每个分段只写一次，取会话首个连接的；之后各连接和拼接带来的脚本 tag 全部丢弃（flv_splice_relay.dart:295）。不回写时长。
- 分段开头依次是：头 → 脚本 → 视频配置（AVC/HEVC 序列头）→ 音频配置（AAC）→ 视频关键帧。首个关键帧之前的视频 tag 丢弃，时间戳早于该关键帧的音频丢弃。纯音频流从第一个音频配置开始。
- 只写完整 tag（tag 头 + 数据 + PreviousTagSize），不写半个。
- 内容相同的重复配置 tag 丢弃；内容不同见 §6.5。
- 写入中的分段文件名带 `.part`（`<前缀>_<NNN>.flv.part`），关闭时改为最终名；名字按 §6.9 事先占好 **[决定]**。

### 6.2 时间戳单调

- 视频：DTS 小于上一个视频 DTS 的 tag 丢弃，相等允许（flv_splice_relay.dart:301-303）。
- 音频：不大于上一个音频时间戳的 tag 丢弃（:304-306）。
- 超过 0xFFFFFF ms 时正确写扩展时间戳字节。
- 每个分段的时间戳从 0 开始（减去分段起点）**[决定]**。

### 6.3 断流重定基准

- 同一会话内，新连接首个媒体时间戳与已写位置相差 ≤60 s 且大于已写位置：视为同一时间线，不改。
- 否则：新基准 = 已写视频末时间戳 + 1 帧时长。帧时长取最近若干帧 DTS 差的中位数，取不到用 1000/30 ms。音频平移同一偏移量。
- 墙钟间隔超过 1 帧时，在 gaps.json 记一条缺口。
- 文件时间轴保持连续，不把缺口时长插进时间戳；缺口只靠 gaps.json 表达 **[决定]**（ADR 0005 §2）。

### 6.4 gaps.json

- 每个会话一个：`<前缀>.gaps.json`。写 `.tmp` 后原子改名；每记一条缺口就更新，会话结束定稿。没有缺口也写空数组，供验收使用。
- 格式：

```json
{
  "version": 1,
  "room": "douyu:5526219",
  "session": "20260927_101530_123",
  "gaps": [
    {
      "part": "20260927_101530_123_001.flv",
      "atMs": 123456,
      "wallStart": "2026-09-27T02:17:33.120Z",
      "wallEnd": "2026-09-27T02:17:35.270Z",
      "missingMs": 2150,
      "reason": "eof|network|lease|splice|http4xx|http5xx|sequenceJump|reset|stop|crash|damaged",
      "source": "flv|hls:video|hls:audio|ts",
      "fromSeq": null,
      "toSeq": null
    }
  ]
}
```

- `atMs` 是分段内的文件时间；`missingMs` 是估计值（FLV 用墙钟，HLS 用缺失分片的 EXTINF 或 TARGETDURATION 累加，连续 TS 见 §8）。
- `damaged` 只用于连续 TS（§8）：上游丢包或失去同步，写入器丢到下一个关键帧。

### 6.5 分段：在关键帧处开新文件

- 触发条件：
  1. 视频或音频配置内容变化（分辨率、编码、采样率）→ 下一个关键帧处开新分段，新分段以新配置开头。
  2. `record.splitMinutes`（0 = 不按时间切，默认 0）或 `record.splitMegabytes`（0 = 不按大小切，默认 0）达到阈值 → 下一个视频关键帧处开新分段；纯音频流在下一个音频 tag 处。
- 旧键 `segmentTime`（默认 300 s）是 TS 分片长度，这些分片最终合并为一个 MP4，用户看不到切分，因此不映射为 v4 的切分 **[决定]**（recorder_config.dart:12；video_processor_service.dart:244-270）。
- 每个分段都能独立播放；弹幕 XML 跟随分段（§17）。

### 6.6 codec 12 改写

- 旧式 codec id 12 的 HEVC video tag 改写为 Enhanced FLV（FourCC `hvc1`）：序列头 → SequenceStart；NALU → CodedFrames，保留 composition time；序列结束 → SequenceEnd；负载原样复制（flv_legacy_hevc_relay.dart:9-60；flv_legacy_hevc_relay_test.dart）。
- 已是 Enhanced 的 tag 不动；无法识别的原样写。
- 旧版录制不走这个改写，依赖 FFmpeg 9 识别（诊断 04 ②）；v4 在写入端统一改写，文件对其它播放器也可读。

### 6.7 停止时的收尾边界

- 文件不能以只含 SEI / SPS / PPS / AUD 的视频 tag 结尾：停止时继续读到下一个含画面的 tag，最多等 3 s；超时就丢掉尾部只含前缀 NAL 的 tag（1abbff9a、26de4378；ffmpeg_flv_input_relay.dart:222-226；ffmpeg_flv_access_unit_stop_test.dart）。
- 先让写入器排空、关闭文件，再断上游；不能先中断输出（263e458a；docs/HUYA_RECORDER_LEASE_AUDIT_2026_09_05.md §2）。
- 实现：写入器把只含前缀 NAL 的视频 tag（以及其后的音频）先扣住，出现含画面的 tag 时一起写出；停止时最多等 3 s，然后丢掉仍扣着的视频 tag、写出音频。换连接和按关键帧切分时同样丢掉扣着的视频 tag。

### 6.8 背压与刷盘

- 写入队列有字节上限（默认 8 MiB **[决定]**）；队列满时暂停读上游（TCP 背压），不丢数据，也不无限缓冲。旧拼接中继没有背压（flv_splice_relay.dart:411-420）。
- 磁盘写入停滞超过 30 s，或写入出错 → 致命磁盘错误（§21）**[决定]**。
- 至少每 1 s 或每 1 MiB 刷盘一次；进程被杀最多丢失最后一个刷盘周期的数据 **[决定]**。

### 6.9 不覆盖

独占创建文件；同名已存在时依次加 `-1`、`-2`（video_processor_service.dart:347-355；video_processor_lifecycle_test.dart:284）。

## 7. HLS 下载器

实现：`live_record` 的 `HlsFeed`（下载）和 `HlsSessionWriter`（写文件），2026-09-28 起可用（ADR 0035）。一条 HLS 连接就是一个 `HlsFeed` 的运行；会话的外层循环（§5.4）照常处理它的结束原因。

### 7.1 选择

- 同一画质的线路先用 FLV（拼接无缝，§5.5）和单条 HTTP 流（§8，平台线路不会有，IPTV 才有；两者按原顺序），都没有或都在录到媒体前失败时再用 HLS；游标的线路序号按“FLV 和单条 HTTP 流在前、HLS 在后”编 **[决定 2026-09-28]**。
- 线路地址是 master 时取 `BANDWIDTH` 最高的变体（mpv 默认也这样），之后直接轮询这个变体地址；续签（§7.6）或重连时重新取一次 master。录制器只按解析结果选路，不自己跟随 master 换画质（hls_prefetch_scheduler.dart:40-42）。字幕和 I-frame 列表不录。
- 暂不支持 **[决定 2026-09-28]**：选中变体的 AUDIO 组带独立地址（音视频分离，niconico）、`SAMPLE-AES` / `SAMPLE-AES-CTR` 和非 `identity` 的密钥格式（DRM）、既不是 MPEG-TS 也不是 fMP4 的分片（packed audio）。遇到时这条线路报 `unsupportedProtocol`，立即换下一条；所有画质的所有线路都这样才以 `unsupportedProtocol` 失败（§21）。

### 7.2 轮询

- 首次立即请求。列表内容（全文比较）变了，等 1 个 TARGETDURATION 再请求；没变，等半个（RFC 8216 §6.3.4）。从请求开始时刻计时；同一时间只有一个列表请求，慢响应之后不再额外等待（docs/HLS_RELOAD_CADENCE_AUDIT_2026_09_10.md:22, 26；hls_reload_cadence_test.dart）。
- 一个会话的第一个列表从倒数第 3 个分片开始录（RFC 8216 §6.3.3，与旧版所用 FFmpeg 的 `live_start_index -3` 一致）**[决定]**；之后的列表按序号接着录（§7.4）。
- 列表正文上限 4 MiB（同上 :26）。
- LL-HLS 不带 `_HLS_skip`、`_HLS_msn`；收到含 EXT-X-SKIP 的增量列表按请求失败处理，因为无法给其中分片正确编号（hls_retained_window.dart:89-91, 174-175）。
- 列表请求 4xx：经适配器续签一次（同画质同线路，§7.6 的续签），用新地址立即重试；续签失败或新地址仍被拒 → 结束连接，外层按 §11.7 处理 **[决定]**。5xx、网络错误、解析失败连续 3 次 → 结束连接，交外层循环 **[决定]**；3 次以内按半个 TARGETDURATION（至少 1 s）重试。
- 卡住：`max(record.readTimeout, 4 × TARGETDURATION)` 内列表没有出现新分片 → 结束连接（录到过媒体时按 §11.4 快速重连，每次先严格检查）**[决定]**。`EXT-X-ENDLIST` → 已列出的分片写完后连接正常结束，同样由严格检查决定是否下播。

### 7.3 分片

- 整片下载完才写（6415d42e；hls_media_spool.dart:4-5）：分片在内存里收完整（有 `Content-Length` 时字节数必须一致，单片上限 64 MiB），需要时解密，然后整片追加进文件（§7.5）；从不写半个分片 **[决定 2026-09-28]**：不再有每片的 `.part` 文件和本地列表。
- BYTERANGE：解析时把隐式偏移算成绝对范围（hls_retained_window.dart:8-9）；请求带 `Range`，服务器忽略它返回整个资源时按范围截取。
- 读空闲：一个响应超过 `record.readTimeout` 没有数据即失败。
- 按序号顺序写入；同时最多 2 个分片在下载或下载完等待写入（背压：写入器 §6.8 的队列满时不再开始新的下载）**[决定]**。
- LL-HLS 只取完整父分片，不取 PART，不把 PRELOAD-HINT 当下载许可（hls_low_latency.dart:3-4）。
- 所有请求（列表、分片、密钥、初始化段）都带线路的请求头和 §7.7 的会话 Cookie，走应用代理（§18）。

### 7.4 序号去重与缺口

- 分片身份 = (feed, 媒体序号)。一个会话内已写或已放弃的序号不再下载，跨重连保留：新连接的列表仍含下一个序号时无缝接上，不记缺口。
- 新列表的最小序号 > 已处理的最大序号 + 1 → 跳号：记缺口，reason=`sequenceJump`，填 fromSeq / toSeq，missingMs = 缺失片数 × TARGETDURATION。缺失片数换算的时长比离开的墙钟时间长得多（> 2 × 墙钟 + 3 × TARGETDURATION + 60 s）时，视为序号体系变了，按下一条处理 **[决定]**。
- 重新编号（服务器重启、换了源站）：列表最后一个序号比已处理的落后超过 max(10, 3 × 列表片数)，或落后期间列表又增长了两次 → 从新列表的倒数第 3 片接着录，记 reason=`reset`；由续签换地址引起的记 `lease`（§7.6）。文件不插入标记，时间线由转封装接上（§10）**[决定]**。
- 单个分片下载失败（404 / 410 / 5xx / 网络，含密钥或初始化段失败）重试 ≤2 次（间隔 1 s）后放弃并记缺口，reason 按错误为 `http4xx` / `http5xx` / `network`，fromSeq = toSeq = 该片；连续 3 个分片被放弃 → 结束连接 **[决定]**。
- `EXT-X-GAP` 标记的分片不请求，记 `sequenceJump` 缺口。
- DISCONTINUITY-SEQUENCE 一次跳变超过 512 → 该次列表按请求失败处理（hls_retained_manifest.dart:97-98）。
- 会话写入第一个媒体之前不记缺口（还没有文件）。

### 7.5 连续文件（取代本地 VOD 归档）[决定 2026-09-28]

- MPEG-TS 分片按序整片追加，写成 `<前缀>_<NNN>.ts`；fMP4 写成 `<前缀>_<NNN>.m4s`：初始化段（EXT-X-MAP）在前，后面是各分片。写入中带 `.part`，关闭时改名；写入队列、背压、刷盘、磁盘错误同 §6.8、§6.9。与 FLV 分段共用编号：一个会话在 FLV 与 HLS 线路之间切换时关旧文件、开新文件，编号接着往后。
- 开新文件（在分片边界）：编码配置变化（TS：PMT 的音视频流类型、SPS/PPS/VPS、AAC 配置；fMP4：初始化段内容变化）、TS 与 fMP4 交替、`record.splitMinutes` / `record.splitMegabytes` 达到阈值（§6.5）。
- 每个文件从关键帧开始：分片不以关键帧开头时（Amazon IVS 的部分分片），在分片内第一个关键帧处切开：切分时前段留在旧文件，文件开头的前段丢掉（解不出来）；新文件以该分片的 PAT/PMT 开头，其他流在切点之前开始的残余包也丢掉。没有关键帧的分片不作为新文件的开头：切分顺延到下一个分片，录制开头的这种分片直接跳过。
- AES-128 分片在内存里解密后写盘（key 只按地址缓存在内存，最多 8 个），初始化段同理；文件里没有密钥，也不需要密钥文件（§13）。
- TS 字节原样写（只去掉分片末尾不足 188 字节的残余），fMP4 同样原样；文件保留上游时间戳，DISCONTINUITY、缺口、重新编号都不改写时间戳，转封装时连成一条时间线（§10）。分段的文件时间 = 已写分片 EXTINF 之和，用于 gaps.json 的 `atMs`、进度和弹幕时间（§17、§19）。
- PROGRAM-DATE-TIME、DATERANGE 不保存；Twitch 服务端插入的广告照常录（§23 第 4 项）。
- 旧规格的 `<前缀>.hls/` 本地 VOD 归档（每片一个文件、本地 index.m3u8、本地 key 文件）不再使用：一小时 2 秒分片要 1800 个文件，key 要落盘（与 §13 冲突），转封装还得再拼一遍；连续文件与 FLV 分段同样只有一个文件、能直接播放和转封装。

### 7.6 租期

- 线路带租期时，在 refreshAt 通过适配器续签同画质同线路（只取同格式的线路），下一次轮询换成新地址；新地址是 master 时重新选变体（PandaTV 的 master 令牌只能用一次）。序号连续则无缝；新地址序号体系不同 → 按 §7.4 重新编号，记 reason=`lease`。
- 续签失败：旧地址继续用，30 s 后再试；旧地址被拒时走 §7.2 的 4xx 续签。
- 真实网络验证：`live_cli record … --renew-after <秒>` 让每条线路按指定间隔续签（见 packages/live_record/README.md）。

### 7.7 会话 Cookie

只在内存，按发出它的源站（scheme + 主机 + 端口）隔离，不跨主机共享；每个源站上限 64 条 / 16 KiB，单条 4 KiB；过期或 `Max-Age=0` 的删除（core/common/hls_session_cookies.dart:3-13）。与线路请求头里的 `cookie` 合并发送。一个会话一个客户端，会话结束时清空。TwitCasting 的分片必须带列表响应下发的 `lvhls_ssid_<id>`（spec/sites/twitcasting.md §6.2）。

### 7.8 停止

冻结列表（不再轮询、不再开始新的下载）→ 在途分片最多再等 1 个 TARGETDURATION（不超过 10 s）并照常写入 **[决定]** → 仍没下完的和还没开始下载的分片记一条 reason=`stop` 的缺口（fromSeq / toSeq 为这些分片）→ 关闭文件（连续文件没有 ENDLIST 要补）（29caea0b；ffmpeg_hls_input_relay.dart:327-329）。

### 7.9 会话型输入（Bigo、FC2、niconico）

- 平台提供播放列表、请求装饰（Cookie、座位）、保活（WebSocket）和字节修复。Bigo 受保护的 TS 字节在写盘前还原（bigo_hls_input.dart:15-16）。
- 每个消费者独占一份会话，不和播放共享（niconico_hls_input.dart:36-38；fc2_hls_input.dart:23-24）。
- 会话丢失（新媒体根、座位失效）→ 外层循环重新获取，文件继续。
- 实现进度（2026-09-28）：线路自带 ADR 0033 的配方（`StreamLine.hlsRelay`），`HlsFeed` 直接按配方处理：每个请求带路径匹配的 Cookie（替换线路自己的 `cookie` 头），分片解密后用列出它的那份媒体列表的还原函数还原。录制自己下载整片，不经播放用的回环中继。
  - Bigo：分片还原后写盘，可以录。
  - FC2：普通 HLS 加租期，`HlsFeed` 按租期经适配器续签，控制连接随之保持，可以录（待实录验证）。
  - niconico：Cookie 已按路径发送，但主列表是音视频分离的，仍报 `unsupportedProtocol`（§23 第 9 项）。

## 8. 单条 HTTP 流与连续 TS（IPTV）

实现：`live_record` 的 `TsFeed`（读连续 TS）写进 `HlsSessionWriter`（与 HLS 的 `.ts` 同一个写入器），2026-09-28 起可用（ADR 0035 修订）。一条连接就是一次 HTTP GET 的响应体；会话的外层循环（§5.4）照常处理它的结束原因。

### 8.1 线路与嗅探

- 线路格式 `other`（live_core `StreamFormat.other`）：一条 HTTP(S) 响应就是整条流，容器由内容决定。IPTV 的 `.ts`、udpxy 的 `/udp/…`、`/rtp/…`、没有扩展名的地址都是这种（spec/modules/iptv.md §5）；播放层直连（playback SRC-2 的“其它”）。rtmp、rtsp、udp 等非 HTTP 地址不是 `other`，录制照旧报 `unsupportedProtocol` 换线路（§1）。
- 嗅探 **[决定 2026-09-28]**：每次连接先读开头的字节（最多 64 KiB），按内容分派：
  - `FLV` 签名 → 按 FLV 线路录（§5.5、§6，续接时重新连接也照样嗅探）；
  - 前 188 字节里某个位置起连续 5 个包的同步字节 `0x47` 都对齐 → 连续 MPEG-TS（§8.2），之前的字节丢掉；
  - `#EXTM3U`（可带 BOM 和空白）→ 按 HLS 线路录（§7）：没有 `.m3u8` 扩展名的 IPTV 列表地址很常见；
  - 其它（HTML 错误页、MP4 点播文件、192 字节包的 M2TS…）或读满 64 KiB 还判断不了 → `unsupportedProtocol`，立即换下一条线路（§21）。
- 请求头、代理、TLS 与 FLV 相同（§18）；`record.readTimeout` 是读空闲超时；没有租期，EOF 按 §11.4 快速重连（每次先严格检查），4xx、5xx 按 §11.7、§5.4。

### 8.2 连续 TS 写文件

- 188 字节的包按收到的顺序原样写成 `<前缀>_<NNN>.ts`：与 HLS 的 `.ts`（§7.5）同一种文件，共用编号、`.part`、写入队列、背压、刷盘和磁盘错误（§6.8、§6.9），转封装相同（§10）。只写整包，关闭时自然是 188 字节的整数倍。
- 单元完整 **[决定 2026-09-28]**：每个 PES 和 PSI 段要么整个写进文件，要么整个不写，写入器只丢整包、从不改写包。单元收完才写（视频 PES 到下一个视频 PES 开头为止，声明了长度的 PES 到收满为止），所以写入落后读取约一帧。节目里所有音视频流（PMT 列出的）和 PAT/PMT 都这样；其它 PID（SDT、EIT、空包…）照原样跟着写。
- 起点：录制开头和每次断流之后，从第一个视频关键帧的 PES 开始（H.264 IDR 或恢复点、H.265 IRAP、MPEG-1/2 序列头；其它视频编码看 `random_access_indicator`，一直没有这个标志时每个 PES 都算），前面的包丢掉；其它流各自从关键帧之后的第一个 PES 开头开始。关键帧前先写一份最近收到的 PAT 和 PMT。纯音频节目从第一个音频 PES 开始。
- 断流（EOF、连接中断、读空闲超时）：已收完的单元照写，没收完的单元（通常是正在收的那一帧）丢掉。重连后接着写同一文件（§3 不变量），从新连接的第一个关键帧开始。
- 停止：先等正在收的视频帧收完（下一个视频 PES 开头出现，最多 3 s，同 §6.7），然后按断流收尾；不记 `stop` 缺口（丢掉的最多一帧）。
- 上游损坏：连续计数器跳变（`discontinuity_indicator` 标出的和逐字节重复的包不算）或失去同步。视频流和 PAT/PMT 损坏 → 按断流处理，丢到下一个关键帧，记 reason=`damaged` 的缺口；其它流损坏 → 只丢那个 PES。失去同步 → 重新找 5 个对齐的包，再按断流处理。udpxy 转发的组播丢包就是这种；不处理的话转封装会因“单元中间丢包”失败（§10）。
- 开新文件（在关键帧处）：PMT 的音视频流类型、SPS/PPS/VPS、AAC 配置变化，或 `record.splitMinutes` / `record.splitMegabytes` 达到阈值（§6.5）。新文件以 PAT、PMT 和关键帧开头；在关键帧之前开始的其它流的 PES 整个留在旧文件（旧文件多写这几个包再关）。PMT 的流或 AAC 配置在两个关键帧之间变化时，按断流处理：丢到下一个关键帧，在那里开新文件。
- 文件时间：按视频 DTS（纯音频按 PTS）累加，相邻两个单元的差在 (0, 60 s] 内照加，回退或跳过 60 s 的按一帧计，与转封装连接时间线的规则一致（§10）；33 位回绕照常跟上。用于进度（§19）、`gaps.json` 的 `atMs` 和弹幕时间（§17）。
- 写文件不限编码：MPEG-2 视频、MP2 / AC-3 音频也照写；转封装只复制 H.264、H.265 和 AAC（§10），其它编码转封装失败、保留 `.ts`。

### 8.3 断流与时间戳 [决定 2026-09-28，原“待确认”]

- 不改写时间戳，由转封装连接时间线（§10）。实测（packages/live_record/README.md，本地 HTTP 服务按实时速率输出 H.264 + AAC 的 TS）：
  - 上游不断、只是连接断了（udpxy 的组播源一直在跑）：新连接的时间戳比断开处前进了断流的时长，转封装在这里留下同样长的空档（视频最后一帧多显示这么久），不回退；
  - 源重启、时间戳从头开始或跳变超过 60 s：转封装把新的一段接在已写内容之后；
  - 33 位时间戳回绕：跟上，不算跳变。
  三种情况 `.ts` 和转出的 MP4 都完整解码无错、DTS 无回退。
- 缺口：重连或损坏之后的第一个关键帧处记一条，source=`ts`，reason 按断开原因（`eof`、`network`、`http4xx`、`http5xx`；损坏为 `damaged`），`wallStart` 是断开时刻；missingMs 在 60 s 窗口内是 DTS 差减一帧，否则是墙钟时长；和 FLV 一样只有超过一帧才记（§6.3）。同一会话从别的线路格式（FLV、HLS）换到连续 TS 时不记。

## 9. 输出布局与命名

- 根目录见 §15。
- 会话目录：`<根>/<平台>/<主播>/<yyyy-MM-dd>/`。旧版在此下还有每次尝试一层 `HH-mm-ss/`（cache_service.dart:262-279），v4 去掉 **[决定]**。
- 前缀：会话开始的本地时间 `yyyyMMdd_HHmmss_SSS`，精确到毫秒（live_record_task.dart:313-318）。
- 文件：

| 内容 | 名字 |
|---|---|
| FLV 分段 | `<前缀>_<NNN>.flv`，NNN 从 001 开始 |
| HLS 分段 | MPEG-TS 为 `<前缀>_<NNN>.ts`，fMP4 为 `<前缀>_<NNN>.m4s`（§7.5）；与 FLV 分段共用编号 |
| 弹幕 | `<前缀>_<NNN>.xml`（与分段同名，HLS 也一样） |
| 缺口 | `<前缀>.gaps.json` |
| IPTV TS | `<前缀>_<NNN>.ts` |
| 转封装结果 | `<前缀>_<NNN>.mp4`（每个分段一个，FLV、TS、fMP4 都一样） |
| 写入中 | 分段和弹幕加 `.part`（`<前缀>_<NNN>.flv.part`、`.xml.part`），转封装输出加 `.partial`；判断重名时它们也算占用 **[决定]** |

- 路径组件清洗：控制字符、`<>:"/\|?*` 和空白换成 `_`，合并连续 `_`，去掉结尾的点和空格，最多 80 个字符，Windows 保留名（con、nul、com1…）前加 `_`，结果为空时用 `unknown`；可选转拼音（path_helper.dart:6-31）。

## 10. 转封装

- 触发：会话收尾时，由 `record.remuxToMp4` 决定（默认开，与旧版一致：旧版总是转 MP4）。转封装单独排队，默认同时 1 个，不占录制并发槽 **[决定]**。
- 方式：stream copy 为 MP4（不解码、不转码），`+faststart`（`moov` 在 `mdat` 前）。纯 Dart 实现，在后台 isolate 运行（`IsolateRemuxer`；ADR 0021 补充决定，取代 ADR 0005 §4 的原生垫片）。`Mp4Remuxer` 按内容分派 **[决定 2026-09-28]**：
  - FLV 分段（H.264、H.265、AAC）：`FlvToMp4Remuxer` 的规则。
  - MPEG-TS（§7.5、§8）：H.264（0x1B）、H.265（0x24）视频和 ADTS AAC（0x0F）音频，其它音视频流（MP3、AC-3、MPEG-2…）且没有可复制的同类流时报错；ID3、SCTE-35 等数据流忽略。一个 PES 是一个访问单元；PES 开头在第一个起始码之前的字节属于上一个访问单元（Twitch / Amazon IVS 把访问单元跨 PES 拆开，与 FFmpeg 的解析器一致）。起始码改为 4 字节长度，与 `avcC`/`hvcC` 相同的参数集从样本里去掉，ADTS 头去掉。第一个关键帧之前的视频丢弃。重复包只认逐字节相同的包：拼起来的 HLS 分片会把连续计数器从头开始。
  - fMP4（§7.5）：样本描述（`avc1`/`hvc1`/`mp4a` 等及其配置盒）原样复制，样本表按 `trun` 重建；加密轨（`encv`/`enca`）报错。
  - 时间线：上游的多段时间戳（DISCONTINUITY、重新编号、广告）连成一条：某条轨的时间戳后退超过 1 s 或前进超过 60 s 视为新一段，接在已写的所有轨之后；另一条轨跳到同一段时跟着接上。更小的前跳保留（漏掉的分片在文件时间里是空档，与 §6.3 一致），33 位时间戳回绕照常跟上。
  - 旧 TS（仅迁移时用 concat，§14.3）不走这里。
- 提交：写 `<目标>.partial`，成功后原子改名；不覆盖已有文件（video_processor_service.dart:206-209, 291-296, 347-355）。
- 成功条件：转封装返回成功、没有任何解复用或复用错误（包括 invalid data、PES 长度不符、单元中间丢包、失去同步、截断的 tag 或包、不支持的编码、文件中途配置变化、写入失败）、输出大小 > 0。文件末尾被崩溃截断的最后一个音频 PES 丢弃，不算错误（§14.1 已截到完整分片）。stream copy 不解码，退出码为 0 不能说明输入完整（263e458a、a65638bd、9a588f4b；docs/HUYA_RECORDER_LEASE_AUDIT_2026_09_05.md §2）。
- 失败：删 `.partial`，保留源文件，任务标失败（类型 remuxFailed），界面可重试（video_processor_service.dart:79-91）。
- 成功后是否删源：`record.keepSourceAfterRemux`（默认关，即删除，与旧版一致：video_processor_service.dart:297-303）。删除失败（文件被占用）不影响成功结果，下次清理再删。
- 可中断：取消后立即停止，删 `.partial`，保留源；进入“改名提交”后不可取消（:33-38, 291-294）。
- 进度：已读输入字节 / 输入总字节，单调不减，最高 0.99，提交成功后才报 1（:385-405）。旧版合并进度没有订阅者，界面只能显示“处理中”（诊断 04 ①），v4 必须接到界面。
- 看门狗：60 s 没有进度 → 失败 **[决定]**。旧版按大小和时长估算总超时，下限 30 s、上限 1 h（:407-422）；更早的固定 5 s 超时曾把健康的长录制判失败（:407-411 注释）。
- 没有媒体的空分段不转封装，直接删除 **[决定]**。

## 11. 并发、调度与重连退避

### 11.1 并发

同时进行的录制会话数 ≤ `record.maxConcurrent`（1–10，默认 3；recorder_config.dart:14, 58-59）。超出的排队，先进先出（ffmpeg_scheduler.dart:44-62, 124-151）。用户“强制开始”的会话例外（§2），它多占的槽在会话结束时释放；强制开始也算一次启动，下一个排队任务仍要隔 5 s。

### 11.2 槽位

解析、录制中、重连中都占槽。重连期间不释放槽 **[决定]**：旧版重连会释放槽，排队任务可能趁机占走（ffmpeg_scheduler.dart:164-170；recorder_controller.dart:1229-1232；诊断 04 ③-4）。收尾和转封装不占槽。

### 11.3 启动间隔

新会话之间至少间隔 5 s（ffmpeg_scheduler.dart:9, 130-140）。重连不受这个间隔限制 **[决定]**。

### 11.4 快速重连（EOF、连接中断、读空闲超时，且之前已录到媒体）

- 延迟从 2 s 起，每次翻倍，上限 15 s（recorder_continuation_policy.dart:58-71）。**[决定]** 总是按指数增长，不看 `record.backoff`（旧版没开退避时固定 2 s）。有有效预取凭据时第一次为 0 s（§5.2）。
- 不设次数上限，不进入慢轮询（policy:73-83；7c3275b4；recorder_continuation_policy_test.dart:94, 127）。每次都经过严格房间检查，确认下播才结束会话。
- 快速重连路径上如果解析失败（网络错误），改为常规退避 **[决定]**。旧版此时仍按 2 s 无限重试（recorder_controller.dart:862, 973, 1219-1228）。

### 11.5 常规重连（网络错误、状态未知、无画质、全部线路失败、5xx 用尽）

- 延迟 = `record.retryDelay`（5–120 s，默认 30 s）；开 `record.backoff` 时每次翻倍，上限 `record.maxCheckInterval`（300–3600 s，默认 300 s）（recorder_config.dart:22-24, 44-48, 63-68；policy:42-56）。
- 达到 `record.maxRetries`（1–20，默认 5）→ 收尾；轮询开 → 等待开播；轮询关 → 失败，原因“重试次数用尽” **[决定]**。旧版轮询关时停在“等待开播”却没有任何检查（recorder_controller.dart:1205-1214, 1296）。

### 11.6 关闭自动重连

非用户停止的中断一律收尾后结束（完成或失败），不重连（recorder_controller.dart:456, 968-970, 980-985）。

### 11.7 HTTP 4xx

不在同一签名上重试；立即（0 s）重新解析，先续签原线路，不行再推进游标（cf35dcf9）。连续 3 次 4xx 后改为常规退避 **[决定]**。

## 12. 轮询（等待开播）

- 开关 `record.polling`（默认关），间隔 `record.liveCheckInterval`（10–300 s，默认 30 s），退避规则同 §11.5（recorder_controller.dart:1295-1314）。
- 用房间详情判断；请求失败只记失败次数和错误，不改状态（:1371-1376）；确认开播 → 排队（:1362-1366）。
- 同一任务同时最多一个轮询请求；手动刷新和自动轮询合并（:1336-1347）；超时只结束等待，迟到的结果被栅栏丢弃（:1356-1359）。
- 关闭轮询：取消全部定时器和自动请求，等待开播的任务转为已停止（原因：轮询已关闭），不会停在等待开播却没有检查；重新打开：这些任务回到等待开播，并立即检查所有等待开播的任务（:1399-1417；[决定]）。
- 添加任务但不立即开始 → 轮询开时等待开播（:707-711）；轮询关时已停止（原因：轮询已关闭），打开轮询后开始等待 **[决定]**。

## 13. 持久化

- 存到 store 的 record_tasks / record_files（ADR 0004），不再用 Hive `recorder_tasks`（live_record_task.dart:324-378）。
- 状态变化 2 s 防抖合并写入；进度快照最多每 10 s 写一次；会话结束和释放后台保活之前必须等写入完成（recorder_controller.dart:633-661, 343-349, 1027-1033）。
- 绝不落盘：签名 URL、请求头、Cookie、预取凭据、会话 Cookie、HLS key（cf35dcf9；live_record_task.dart:345-347, 418-419；live_record_task_persistence_test.dart:124-182）。游标只存画质 id 和线路序号。
- 错误文本先脱敏（去掉 URL 查询串、Cookie、token）再存（live_record_task.dart:301-306；recorder_diagnostics.dart）。
- 持久化的时长超过 1 年视为损坏，归零（live_record_task.dart:521-528；e9d11a09）。
- record_files 登记每个分段、HLS 归档、MP4、XML、gaps.json 的路径和状态；删除任务不删文件记录 **[决定]**。

## 14. 恢复

### 14.1 崩溃或被杀后的恢复

每次启动都执行，不依赖“开机恢复”开关 **[决定]**。旧版只有开关打开或进入录制页时才创建控制器执行恢复（initial_services.dart:77-99）。

1. 首帧之后在后台执行，不阻塞启动。
2. 找出落盘时处于活跃态（排队、解析、录制中、重连中、收尾）的任务（recorder_controller.dart:1486-1503）。在任务显示出来之前先占住恢复锁；用户这时点“开始”要等恢复完成（:1516-1524）。
3. FLV：从头按 tag 扫描到最后一个完整 tag（PreviousTagSize 也要对得上），截掉其后的残余字节，`.flv.part` 改为最终名；一个媒体 tag 都没有的分段删除。HLS 与连续 TS：`.ts.part` 截到整包；有多个 PAT 时，最后一个 PAT 正好在视频单元边界上（HLS 分片以 PAT 开头）就从它截掉，即去掉最后一个分片（崩溃可能写了一半），否则（连续 TS 的 PAT 夹在帧中间，§8）从最后一个视频 PES 的开头截掉，即去掉没写完的那一帧；只有一个 PAT 时保留；`.m4s.part` 截到最后一个完整的 moof + mdat，然后改名；没有媒体的删除。XML：补 `</i>`，`.xml.part` 改名。未完成的转封装 `.partial` 删除。gaps.json：补一条 reason=`crash`，时长未知。
4. 按 §10 转封装（若开启）。成功 → 状态“用户停止”（与旧版一致：:1586）；失败 → 失败，源文件保留。
5. 已完成、已停止、失败的任务不会因为目录里还有文件而被重新处理（:1528-1530）。

### 14.2 开机恢复（应用启动时恢复待录任务）

- 开关 `record.resumeOnLaunch`（旧 `auto_start_on_boot`，默认关：recorder_config.dart:50-51）。含义是“应用启动时”，不是设备开机（assets/translations/zh.json:24-25；AndroidManifest.xml 没有 BOOT_COMPLETED）。
- 候选：落盘时不是用户停止，状态为排队、解析、录制中、重连中或等待开播的任务（recorder_controller.dart:1494-1503）；以及因应用退出而停止的任务（§16.2，原因“应用退出”）**[决定]**。开机恢复关闭时，下次启动清掉“应用退出”这个原因，之后不再是候选。
- 先完成 §14.1。只检查录制目录是否可写，不请求任何权限；不可写就保持停止并注明原因（723b4452；:663-669, 1548；recorder_user_intent_test.dart:243）。
- 候选逐个做一次严格状态检查，同时最多 3 个（:1552-1566）。开播 → 排队；未开播 → 等待开播；轮询关闭时只查这一次（translations 同上）。
- 后台时间被系统用尽而失败的任务不在候选内（§16.1）。

### 14.3 旧版遗留录制（一次性）

- 旧任务的 pendingAttempts（未合并的 TS 组）和活跃态任务目录里的 clock-v1 TS：首次启动时用 concat 按 clock-v1 段表合并为 MP4。段表缺失、不完整、与文件不匹配时不合并、保留源（video_processor_service.dart:160-187；recording_segment_clock.dart；f46ebe56、608c1d5d；recording_segment_clock_test.dart:53-76）。
- 没有段表的旧 strftime 分段只在这次迁移中接纳（video_processor_service.dart:147-154, 359-375）。
- 旧记录标为“输入损坏”的组不合并、保留源（:103-116；video_processor_lifecycle_test.dart:152）。
- 合并成功删除该组 TS 和段表；失败保留。完成后在 meta 记“旧录制收尾完成”，之后不再扫描。

## 15. 录制目录与缓存保护

- 根目录：未设置或设为默认时用应用数据目录 `RECORDS`；用户选的目录只当父目录，实际写入 `<选定目录>/PureLiveRecords/`，并放标记文件 `.pure_live_recording_root`；选的目录本身就是带标记的 `PureLiveRecords` 时直接用它（cache_service.dart:13-39, 70-87）。Android 私有路径（`/data/user/…`、`/data/data/…`）按默认处理（:231-238）。
- 保存目录设置前，先在里面建唯一临时目录写探针验证可写（:41-68）。
- 清理和容量限制只作用于这个目录，标记文件不删（:130-177）。
- 活跃保护：录制中、重连中、收尾、转封装、恢复中的目录按引用计数保护；受保护目录里的文件不删，但计入总量（:107-128, 195-229；cf35dcf9、f07d1861；recorder_storage_policy_test.dart:145-186）。
- 容量限制：`record.cacheLimitEnabled`（默认关）、`record.cacheLimitMB`（≥1，默认 1024）。名字里的“缓存”是 3.x 的叫法，实际含义是**录制目录的总大小上限**，与网络和图片缓存无关（3.x 的 `maxCacheMB` 同样只算录制目录：cache_service.dart:130-150, 195-229）；设置页写作“限制录制目录大小”。每分钟检查一次；超限时按修改时间从旧到新删除未受保护的文件，直到不超限；基于一次快照、步数有限，被占用的文件跳过（recorder_controller.dart:125-127, 1419-1433；cache_service.dart:195-229）。
- 实现 **[决定]**：录制器（`RecordManager`）在开关打开时每 60 s 扫描一次根目录（改设置立即生效，关掉即停）。总量包括受保护目录里的文件；标记文件不计入也不删。受保护目录 = 处于解析、录制中、重连中、收尾（含转封装、崩溃恢复）的任务的会话目录（`<根>/<平台>/<主播>/<日期>/`，同一目录被多个任务用到时任一个活跃就保护）。删除只针对根目录下的文件（包括用户放进去的其它文件，因为根目录是录制器专用的 `PureLiveRecords` 或应用目录）；删掉的录制文件仍留在任务的会话信息里，录制中心照常显示。
- 空目录从深到浅清理，受保护的跳过（:167-176）。只在这次扫描确实删了文件时清理。
- **[待确认]** Android 默认目录是否改为公共媒体目录（如 Movies/PureLive）并用系统接口写入，替代 MANAGE_EXTERNAL_STORAGE（AndroidManifest.xml:16；recorder_controller.dart:663-689）。

## 16. 后台

### 16.1 Android

- 有活跃会话时运行独立的录制前台服务（与播放的后台服务分开），保活 Flutter 引擎（绑定音频服务），持有 CPU 部分唤醒锁和高性能 Wi-Fi 锁；最后一个会话结束才释放（recorder_background_service.dart:15-18, 53-77；RecorderBackgroundPlugin.kt:291-305, 417-440；9a512919、f4d40174）。“活跃会话”= 排队、解析、录制中、重连中、收尾（含转封装）的任务，即 `RecordManager.activeCount` > 0；等待开播不算。
- 旧会话的释放不能停掉新会话的保活（recorder_background_service.dart:15-16, 72-77）。v4 由 Dart 按活跃任务数驱动一个进程级的保活（数量从 0 变正启动、变回 0 停止，中间只更新通知），不再按任务发租约，所以不存在“旧租约释放”这回事 **[决定]**。
- 实现（`RecordService.kt`，方法通道 `purelive/record`；Dart 侧 `lib/core/recording.dart` 的 `RecordKeepAlive`）**[决定 2026-09-28]**：`update(title, text)` 启动或刷新服务，`stop` 停止并释放锁和引擎绑定；原生回调 `onTimeout`。服务在 `onStartCommand` 里立即 `startForeground`，不再需要 3.x 的 15 s 启动/停止超时状态机（RecorderBackgroundPlugin.kt:90-91）。
- 通知：渠道“录制”（低重要度，不响铃、不显示角标），标题“正在录制 N 个直播间”，正文是主播名（最多 3 个，多了加“等”），有任务在收尾时附“M 个正在收尾”；只剩收尾的任务时标题为“正在处理录制文件”。点通知回到应用。Android 13 起通知要通知权限：第一次启动服务且应用在前台时请求一次；拒绝也照常录制，只是通知只出现在系统的前台服务管理里。
- 释放保活前先把最终状态落盘，再解绑引擎（recorder_controller.dart:1027-1033）：Dart 在活跃数归零后先 `RecordManager.flush()` 再发 `stop`。
- 服务类型 **[决定 2026-09-28]**：`specialUse`（子类型说明：直播录制，把用户选择录制的直播流写成本地文件，直到下播或用户停止），Android 14 起 `startForeground` 传这个类型，更早的系统用 manifest 里的类型。不用 `dataSync`：目标 Android 15 及以上时，`dataSync` 和 `mediaProcessing` 前台服务 24 小时内合计只能运行 6 小时（两种类型分别计时，同类型的所有服务共用），到时系统调用 `Service.onTimeout(int, int)`，服务必须在几秒内 `stopSelf()`，否则应用崩溃（`RemoteServiceException: A foreground service of type dataSync did not stop within its timeout`）；此后在用户把应用切回前台之前，再启动同类型服务会抛 `ForegroundServiceStartNotAllowedException`（“Time limit already exhausted”）；用户把应用切到前台会重置计时。一场直播常超过 6 小时，开播监控加过夜录制更长，所以 `dataSync` 不适合。`specialUse` 没有时间上限，只在上架 Google Play 时审核 manifest 里的用途说明；本应用不在 Google Play 发布。`mediaPlayback` 语义不符，用户发起的数据传输作业（UIDT）要求用户手势当场启动、面向有限大小的传输，也不保活 Flutter 引擎。详见 docs/adr/0029-record-service.md。
- 系统中断（`onTimeout`：`specialUse` 不会触发，保留作防御，例如以后的系统版本或厂商改动）：服务立即 `stopForeground` + `stopSelf`（系统只给几秒），唤醒锁再保留最多 45 s；Dart 收到后对所有活跃任务 `interruptAll`（按用户停止收尾后标失败，原因：后台运行时间被系统用尽），然后 `stop`。之后在应用回到前台之前不再启动服务（与系统“切回前台才重置计时”一致），自动重连和开播监控触发的录制照常进行但没有保活（RecorderForegroundService.kt:188-197；RecorderBackgroundPlugin.kt:93, 217-225；recorder_controller.dart:1038-1057）**[决定]**：3.x 是“之后只允许用户手动重新开始”。
- 后台启动限制：Android 12 起应用在后台不能启动前台服务（`ForegroundServiceStartNotAllowedException`）。用户在前台开始录制时服务随之启动；开播监控在后台检测到开播、要启动服务时可能被拒，此时录制照常进行，但进程随时可能被冻结或回收。**[待确认]** 开播监控是否也要在等待期间运行服务（`specialUse` 没有时间限制，但要常驻通知和唤醒锁，耗电），第 5 阶段真机评估。

### 16.2 Windows 与桌面

- 退出（关闭窗口选“退出”、托盘退出、注销）时如有活跃会话，先提示“正在录制 N 个房间，退出会停止录制”。确认后按用户停止收尾：排空写入器、关闭文件、定稿 gaps.json / XML、落盘，最多等 10 s，然后退出 **[决定]**。转封装不在退出时做，下次启动由 §14.1 处理（已关闭的分段直接转封装，不补 crash 缺口）。任务落盘为已停止（原因：应用退出），开机恢复打开时下次启动恢复录制（§14.2）。旧版直接销毁窗口，不排空录制（plugins/utils.dart:16-76）。
- FLV、TS、fMP4 分段都没有尾部结构，关闭文件即可。
- 关机或强杀没有提示，靠 §14.1 恢复。

## 17. 弹幕 XML

- 开关 `record.danmaku`（默认关：recorder_config.dart:54）。弹幕和视频互不影响：弹幕连不上、写失败都不影响录制（recording_danmaku_service.dart:110-116, 211-215）。
- 每个任务一条弹幕连接，会话处于解析、录制中、重连中时保持；连接超时 20 s，失败后 30 s 再试（recorder_controller.dart:144-167；recording_danmaku_service.dart:122, 156-179；recording_danmaku_service_test.dart:119）。
- 每个视频分段一个 XML，与分段同名；分段切换时关旧开新。重连不关 XML（同一文件继续）**[决定]**；旧版每次尝试新开一个 XML（:181-199）。
- 格式：B 站弹幕 XML，DanmakuFactory、PotPlayer、biliup / blrec 可读（:22-66）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<i>
<chatserver>pure_live</chatserver>
<d p="秒.毫秒,1,25,十进制RGB,unix秒,0,用户哈希十六进制,0" user="用户名">文本</d>
</i>
```

- 只写普通聊天；文本做 XML 转义，去掉 XML 1.0 不允许的字符；空文本不写（:44-58, 68-96）。
- 按消息 id 去重，保留最近 2048 个（:204-210）。
- 用户哈希用稳定算法（如 userId 或用户名的 CRC32）**[决定]**；旧版用 Dart `String.hashCode`（:51），不保证跨版本稳定。
- unix 字段用消息自带的发送时间，没有则用收到时间（:52）。
- **时间基 [决定]**：弹幕时间 = 该分段的文件时间。写入器维护“墙钟 ↔ 文件时间”锚点（分段开始、每次重定基准各记一个）；弹幕时间 = 最近锚点的文件时间 + (收到时刻 − 锚点墙钟)，夹在 [0, 当前已写末尾]；缺口期间收到的弹幕落在缺口位置。旧版以“尝试开始”为零点，这个时刻在解析之前，早于首个媒体包（:193；诊断 04 ③-7）。
- 关闭时写 `</i>`，并等文件真正关闭后才返回（Windows 文件锁：8c5fb87e；:225-235）。

## 18. 网络

- 请求头与播放共用：UA、Origin、Referer、Cookie 和平台专用头都来自同一个播放请求头解析（ffmpeg_header_factory.dart:4 → playback_header_resolver.dart:53-146）。缺一个就会“能播放不能录”（spec/sites/douyu.md REG-DOUYU-014）。
- 代理：所有上游请求统一走应用代理策略（17a192f1；recorder_proxy_routing.dart:1-11；initialized.dart:94-100）。
- TLS：由 live_net 处理，正常校验证书和主机名；不再有 ca_file 注入（e35247d0；ffmpeg_hls_input_relay.dart:41-49）。
- 日志：URL 查询串、Cookie、Authorization、token 一律脱敏（ffmpeg_service.dart:809-820）。

## 19. 进度与指标

- 字节：已写入各分段的总字节（包括正在写的 `.part`；HLS 不含还在下载的分片）。
- 时长：按写入的媒体时间戳计算（FLV 各分段末 DTS − 首 DTS 累加；HLS 为已写分片 EXTINF 之和；连续 TS 按 DTS 累加，§8.2），以墙钟为上限；不用任何“统计时间”字段（INT32_MAX 哨兵值：e9d11a09；ffmpeg_service.dart:29-37）。
- 码率：最近一个时间窗内写入的字节 / 墙钟（ff0119b0；recording_bitrate_window.dart）。
- 另有：连接次数、拼接次数、缺口数、最近一次缺口时长。
- 每个任务每秒最多推送一次。

## 20. 录制设置

| v4 id | 旧键（recorder_keys.dart） | 取值 | 默认 | 说明 |
|---|---|---|---|---|
| record.defaultQuality | default_quality | 五档枚举 | 原画 | 旧值是显示文案 `原画` / `蓝光8M` / `蓝光4M` / `超清` / `流畅`（recorder_config.dart:91-92, 151-155） |
| record.maxConcurrent | maxTaskCount | 1–10 | 3 | |
| record.autoReconnect | autoReconnect | bool | true | |
| record.maxRetries | max_retry_count | 1–20 | 5 | |
| record.retryDelay | retry_delay | 5–120 s | 30 | |
| record.polling | enable_polling | bool | false | |
| record.liveCheckInterval | live_check_interval | 10–300 s | 30 | |
| record.backoff | enable_backoff | bool | false | |
| record.maxCheckInterval | max_check_interval | 300–3600 s | 300 | |
| record.resumeOnLaunch | auto_start_on_boot | bool | false | |
| record.readTimeout | recorder_rw_timeout | 15 / 30 / 60 s | 15 | |
| record.pinyinFolders | recorder_folder_naming_strategy | bool | false | |
| record.danmaku | recorder_record_danmaku | bool | false | |
| record.cacheLimitEnabled | enableCacheLimit | bool | false | |
| record.cacheLimitMB | maxCacheMB | ≥1 | 1024 | |
| record.directory | recordSavePath | 路径（仅本机） | 空 = 默认 | |
| record.splitMinutes | —（segmentTime 不映射） | 0 或 ≥1 | 0 | [决定] |
| record.splitMegabytes | — | 0 或 ≥64 | 0 | [决定] |
| record.remuxToMp4 | — | bool | true | [决定] |
| record.keepSourceAfterRemux | — | bool | false | [决定] |

- 丢弃：`recorder_prefer_best_stream`（FFmpeg `-map`）、`recorder_thread_queue_size`（FFmpeg 队列）、`segmentTime`（见 §6.5）。
- 越界的旧值按旧规则夹紧后导入（recorder_config.dart:72-92, 262-285）。

## 21. 错误分类

错误是类型化的，不靠解析日志字符串（旧版两份致命清单不一致：ffmpeg_service.dart:58-146 与 recorder_continuation_policy.dart:15-40；诊断 04 ③-5）。

| 类型 | 可重试 | 处理 |
|---|---|---|
| roomOffline | — | 结束会话（§3） |
| roomBanned、roomNotFound、platformUnsupported | 否 | 失败 |
| loginRequired | 否 | 失败，提示登录 |
| roomStateUnknown、network、noQuality、allLinesFailed | 是 | 常规退避 |
| unsupportedProtocol | 推进游标 | 线路协议（rtmp 等）或内容（SAMPLE-AES、音视频分离、packed audio、单条 HTTP 流既不是 FLV 也不是 MPEG-TS 或 HLS 列表，§8.1）录不了：立即换下一条；所有画质的所有线路都这样 → 失败 |
| upstreamEof、readTimeout、sessionLeaseLost | 是 | 快速重连 |
| http4xx | 是 | 立即重新解析 |
| http5xx | 是 | 同址重试后常规退避 |
| diskFull、permissionDenied、readOnly、pathInvalid、diskStalled | 否 | 失败 |
| backgroundInterrupted | 否 | 失败，只允许手动重试 |
| regionBlocked | 否 | 失败（适配器报地区限制）**[决定]** |
| retriesExhausted | 否 | 常规重试用尽且轮询关闭：失败（REG-RECORD-033）**[决定]** |
| remuxFailed、inputDamaged | 否 | 失败，保留源文件 |

- 保留失败阶段：room / quality / stream / network / writer / remux / scheduler / background / status（live_record_task.dart:497-514）。
- unsupportedProtocol：解析时单条不支持的线路直接跳过，某画质没有可录线路就跳到下一画质；所有画质都没有时才报这个失败。HLS 线路连上后才发现录不了（§7.1）时同样换下一条，一轮下来全是这种才失败。
- 提示：同一任务的同一错误只提示一次；重试中的错误不弹提示（recorder_controller.dart:295-298）。

## 22. 验收门禁

| 门禁 | 方法 | 通过条件 |
|---|---|---|
| 斗鱼 30 分钟 | 匿名原画（expire=300），真实网络；`ffprobe -select_streams v -show_entries packet=dts_time` 检查 FLV 和转出的 MP4 | 相邻视频 DTS 最大间隔 ≤ 1 帧（按流帧率，允许 1 ms 取整）；DTS 无回退；拼接次数 ≥5；gaps.json 为空；全解码无错误 |
| 虎牙 60 分钟 | WUP 原生 FLV | 应用主动断开次数 = 0；只在真正 EOF 时续接；gaps.json 为空；时长 ≥ 59:30 |
| IPTV 连续 TS | 本地 HTTP 服务按实时速率持续输出 H.264 + AAC 的 TS（模拟 udpxy），中途断开一次；`live_cli record url <地址> --remux` 录 60 s | `.ts` 和 MP4 的 `ffmpeg -v error -i … -f null -` 输出都为空；两者的音视频包数相同；`gaps.json` 只有这次断开的一条 |
| HLS 全解码 | 每个 HLS 平台（B 站 fMP4、Twitch、SOOP、TwitCasting、PandaTV、Bigo、FC2、niconico 分离音频、YouTube 等）录 ≥10 分钟 | `.ts` / `.m4s` 和 MP4 的 `ffmpeg -v error -i … -f null -` 输出都为空；分片序号无重复；每个缺口都记录在 gaps.json 且有原因 |
| 杀进程后恢复 | 录制中 `kill -9`（Android 强行停止），重新启动 | 恢复后文件能被 ffprobe 完整读取、转封装成功；任务状态正确；开机恢复开启时无权限弹窗，60 s 内重新进入录制 |
| 确定性测试 | 假 FLV / HLS 源按真实事件顺序：拼接、跨时间线、配置变化、codec 12、SEI 尾、背压、4xx / 5xx / EOF、序号跳号与回退、停止边界、迟到回调、意图竞态 | 全部通过 |
| 不泄密 | 扫描数据库、日志、导出的诊断包 | 没有签名 URL、Cookie、token |

样本（诊断 04 ⑥）：斗鱼两次续签、虎牙 WUP、B 站 fMP4 HLS、Twitch、niconico 分离音频、Kilakila SEI 尾、codec 12。

## 23. 待确认汇总

1. rtmp / rtsp / udp / srt 录制是否还需要（§1）；IPTV 定时录制是否实现（§1）。
2. 虎牙网页 FLV/HLS、酷狗、猫耳、YouTube 的租期是否断开连接（§5）。
3. 会话中途新增音轨或视轨时是否开新分段（§6.1）。
4. Twitch 广告 DATERANGE 是否剔除（§7.5）。目前照录，广告分辨率不同时会切出单独的文件。
5. ~~IPTV 连续 TS 断流后的时间戳处理（§8）~~：2026-09-28 实测后定为不改写时间戳，由转封装连接（§8.3）。
6. Android 默认录制目录和存储权限方案（§15）。
7. ~~Android 前台服务类型（§16.1）~~：2026-09-28 定为 `specialUse`。新增：开播监控在后台是否也运行前台服务（§16.1）。
8. 旧版弹幕时间基的实际偏差量（§17，只影响回归说明）。
9. SAMPLE-AES 与音视频分离的 HLS 录制（§7.1）：目前报 `unsupportedProtocol` 换线路；接入 niconico 或遇到需要它们的平台时再做。

## 24. 必须继承的坑

| 编号 | 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|---|
| REG-RECORD-001 | 虎牙 WUP 录到约 270 s 被切断，文件尾损坏 | 定时轮换取消了健康连接；该凭据只限制新建连接 | 只预取下一凭据，真正 EOF 才用；预取失败不影响当前连接 | f66cff51；recorder_lease_lifecycle_test.dart:173, 196, 218；docs/HUYA_RECORDER_LEASE_AUDIT_2026_09_05.md §1 |
| REG-RECORD-002 | 斗鱼每 5 分钟断一次 | `expire=300`，CDN 按签发时刻断开；新旧连接时间戳在同一时间线 | 提前 45 s 续签，在新连接首个未送达的关键帧处拼接；时间线不同时平移 | 31982153；douyu_site.dart:30-64；flv_splice_relay_test.dart:70-155；tool/probes/douyu_splice_probe_test.dart |
| REG-RECORD-003 | 流结束被当成下播，任务进入慢轮询 | 直播没有自然 EOF | EOF 快速重连 2→15 s，不进入慢轮询，由严格检查判断下播 | 7c3275b4；recorder_continuation_policy_test.dart:94, 127 |
| REG-RECORD-004 | 403 / 404 反复重试旧签名 | FFmpeg 内部对所有 HTTP 错误重连 | 只有 5xx 在同址重试，4xx 交上层重新解析 | cf35dcf9；ffmpeg_command_builder.dart:188-201 |
| REG-RECORD-005 | 首个 URL 启动时已过期，录制启动慢 | 开录前签名了所有画质 × 线路 | 按游标只签本次要用的一条 | 065427ed；stream_resolver_service.dart:183-188；owned_record_input_test.dart:33, 61 |
| REG-RECORD-006 | 录制被误停，显示下播 | 界面加载器失败时保留旧卡片状态，被当成未开播 | 录制用严格房间接口；详情失败、状态未知都按网络错误 | 233d858d；stream_resolver_service.dart:139-157 |
| REG-RECORD-007 | 重连被 MP4 合并阻塞 10–20 s，形成缺口 | 先合并再重连 | 先重连，会话结束后才收尾 | db7d0df3；recorder_controller.dart:457-466 |
| REG-RECORD-008 | 停止后 TS 尾部损坏，转 MP4 仍返回 0 并删了源文件 | 取消同时中断了输出 IO；stream copy 不解码，退出码 0 不代表完整 | 先让输入自然结束、写入器排空再关；任何解复用错误都算失败并保留源 | 263e458a、a65638bd、9a588f4b；video_processor_lifecycle_test.dart:152；docs/HUYA_RECORDER_LEASE_AUDIT_2026_09_05.md §2 |
| REG-RECORD-009 | 文件尾只剩 SEI，没有画面 | 完整 tag 不等于完整访问单元 | 停止时等到下一个完整画面（3 s 预算），否则丢掉尾部前缀 NAL | 1abbff9a、26de4378；ffmpeg_flv_access_unit_stop_test.dart |
| REG-RECORD-010 | 分段边界约 90 ms 时钟阶跃 | concat 按文件时长累加 | v4 一个会话一个连续文件；迁移旧 TS 时用 CSV 起点差 + inpoint 0 | f46ebe56、608c1d5d；recording_segment_clock_test.dart:53-76；docs/RECORDING_CONCAT_CLOCK_DRIFT_2026_09_10.md |
| REG-RECORD-011 | 时长显示 596523:14:08 | 首个统计时间是 INT32_MAX 哨兵 | 时长按写入的媒体时间戳算、墙钟封顶；持久化值超过 1 年归零 | e9d11a09；ffmpeg_service.dart:29-37；live_record_task.dart:521-528 |
| REG-RECORD-012 | 码率显示偏低 | 用源时间戳做分母 | 按文件增长的时间窗计算 | ff0119b0；recording_bitrate_window.dart |
| REG-RECORD-013 | 签名 URL、Cookie 泄漏到本地存储 | currentUrl 被持久化 | 只存画质 id 和线路序号；日志和错误文本脱敏 | cf35dcf9；live_record_task.dart:345-347, 418-419；live_record_task_persistence_test.dart:124-182 |
| REG-RECORD-014 | 重试混入旧分片，同一秒的文件互相覆盖 | 文件名只精确到秒 | 毫秒前缀；`.partial` 原子提交；不覆盖已有文件 | video_processor_lifecycle_test.dart:284；live_record_task.dart:313-318 |
| REG-RECORD-015 | 清理缓存删掉正在写的文件 | 没有活跃保护，且会删用户目录里的其它文件 | 只管理 PureLiveRecords 子目录；活跃目录引用计数保护 | cf35dcf9、f07d1861；recorder_storage_policy_test.dart:145-186 |
| REG-RECORD-016 | 旧会话的迟到回调覆盖新任务状态 | 事件没有代次 | 会话代次 + 任务身份做栅栏 | recorder_output_lifecycle_test.dart:163-286；recorder_poll_lifecycle_test.dart:68-196 |
| REG-RECORD-017 | 停止、启动、恢复互相打架 | 用户意图没有串行化 | 同一任务的意图按顺序执行，后一个等前一个完成 | e7670220；recorder_user_intent_test.dart:116-243 |
| REG-RECORD-018 | 锁屏或关掉界面后录制中断 | 引擎随 Activity 一起销毁 | 独立前台服务 + 保活引擎 + 唤醒锁；被系统中断后只允许手动重试 | 9a512919、f4d40174；recorder_background_service_test.dart |
| REG-RECORD-019 | Android 15 上长时间录制被系统停止 | dataSync 前台服务 24 h 内限 6 h，到时系统回调 onTimeout | onTimeout 后 45 s 内有界收尾并标失败，不自动重启服务 | RecorderForegroundService.kt:188-197；RecorderBackgroundPlugin.kt:93, 217-225 |
| REG-RECORD-020 | HLS 把半个分片交给了封装器 | 流式转发 | 整片收完才写进文件；停止时冻结列表，在途分片等一个目标时长 | 6415d42e、29caea0b；hls_media_spool.dart:4-5 |
| REG-RECORD-021 | HLS 子请求证书校验失败 | FFmpeg 不把 ca_file 传给子请求 | TLS 在 Dart / live_net 侧处理 | e35247d0；ffmpeg_hls_input_relay.dart:41-49 |
| REG-RECORD-022 | 录制不走应用代理 | FFmpeg 直连 | 上游统一走代理策略 | 17a192f1；recorder_proxy_routing.dart |
| REG-RECORD-023 | 开机恢复时弹出权限框 | 不是用户手势却请求权限 | 只检查可写，不请求；不可写保持停止 | 723b4452；recorder_user_intent_test.dart:243 |
| REG-RECORD-024 | Windows 弹幕文件被锁 | 没有等 close 完成 | 等文件真正关闭再返回 | 8c5fb87e；recording_danmaku_service.dart:225-235 |
| REG-RECORD-025 | 每次续期都产生一个新文件和缺口 | 续期等于新开一次尝试：排空 ≤3 s + 重连 2 s + 解析 + 探测 ≤5 s | 一个会话一个写入器，续期在来源层完成 | 诊断 04 ③-1；recorder_controller.dart:1080-1085, 883-887 |
| REG-RECORD-026 | HLS 跳号（Missing HLS sequence interval） | 列表刷新按固定半秒或按响应结束计时，慢响应后错过分片 | 按 RFC 节奏、从请求开始计时，每 feed 一个定时器 | docs/HLS_RELOAD_CADENCE_AUDIT_2026_09_10.md:22, 26；hls_reload_cadence_test.dart |
| REG-RECORD-027 | 分片序号被编错 | 把 LL-HLS 增量列表当完整列表 | 不请求增量；收到 EXT-X-SKIP 按错误处理 | hls_retained_window.dart:89-91, 174-175 |
| REG-RECORD-028 | 同一段媒体录了两遍 | LL-HLS 同时取了 PART 和父分片 | 只取完整父分片 | hls_low_latency.dart:3-4；hls_low_latency_recording_test.dart |
| REG-RECORD-029 | BYTERANGE 分片取错字节 | 隐式偏移依赖前一片，前一片被移除后变了 | 解析时算成绝对范围 | hls_retained_window.dart:8-9 |
| REG-RECORD-030 | 一个 CDN 的会话 Cookie 被发给另一个主机 | Domain Cookie 按域名共享 | 会话 Cookie 按发出它的源站隔离，有数量和大小上限 | core/common/hls_session_cookies.dart:3-13 |
| REG-RECORD-031 | 重连期间排队任务抢走并发槽 [代码推断] | 重连会释放调度槽，再重新排队 | 重连期间保留槽 | ffmpeg_scheduler.dart:164-170；诊断 04 ③-4 |
| REG-RECORD-032 | 错误判定前后不一致 | 两份按日志字符串匹配的致命清单不一致 | 错误类型化 | ffmpeg_service.dart:58-146；recorder_continuation_policy.dart:15-40 |
| REG-RECORD-033 | 轮询关闭时重试用尽，任务停在“等待开播”再也不动 [代码推断] | 进入等待开播后要靠轮询，而轮询被关 | 轮询关闭时重试用尽直接标失败 | recorder_controller.dart:1205-1214, 1296 |
| REG-RECORD-034 | 断网时每 2 s 无限重试 [代码推断] | EOF 后的快速标记一直保留到录满 10 s，解析失败也走 2 s | 快速重连路径上解析失败改走常规退避 | recorder_controller.dart:862, 973, 1219-1228 |
| REG-RECORD-035 | 进程被杀后残留 TS 一直不收尾，直到打开录制页 [代码推断] | 恢复逻辑挂在控制器初始化上，控制器只在开机恢复开启时预热 | 崩溃恢复每次启动都做，与开机恢复开关无关 | initial_services.dart:77-99 |
| REG-RECORD-036 | 长录制的 MP4 收尾被判失败 | 转封装固定 5 s 超时 | 不设固定超时；按进度看门狗判断 | video_processor_service.dart:407-422 |
| REG-RECORD-037 | 收尾时只显示“处理中”，没有进度 | 合并进度事件没有订阅者 | 转封装按字节报进度并接到界面 | 诊断 04 ①；video_processor_service.dart:26-29 |
| REG-RECORD-038 | “立即录制”被卡片的旧状态拦住 | 按缓存的卡片状态判断开播 | 用户明确开始时由严格解析决定 | recorder_controller.dart:701-704 |
| REG-RECORD-039 | 录制卡片在读或操作时跳来跳去 | 每次状态或进度变化都重新排序 | 列表顺序稳定 | recorder_controller.dart:625-628 |
| REG-RECORD-040 | 弹幕和画面对不上 | 弹幕零点取尝试开始（解析之前），早于首个媒体包 | 弹幕时间按文件时间锚点换算 | recording_danmaku_service.dart:193；诊断 04 ③-7 |
| REG-RECORD-041 | 录制失败但播放正常 | 录制请求缺少 Referer / Origin / UA / Cookie | 录制与播放共用同一份请求头 | playback_header_resolver.dart:53-146；spec/sites/douyu.md REG-DOUYU-014 |
| REG-RECORD-042 | Twitch 录制转出的 MP4 画面花屏（ffmpeg 报 error while decoding MB），TS 本身正常 | Twitch / Amazon IVS 把访问单元拆到两个 PES：下一个 PES 以上一帧末尾的几十到上百字节开头，按 PES 切帧时这些字节被丢掉 | PES 开头、第一个起始码之前的字节接回上一个访问单元（与 FFmpeg 解析器一致） | v4 2026-09-28 `live_cli record twitch caedrel`：修复前 3600 帧中 828 帧样本变短，修复后解码画面逐帧相同 |
| REG-RECORD-043 | SOOP 录制转 MP4 失败：PES of 1559 bytes, declared 868 | 分片首尾相接后各 PID 的连续计数器从 0 重新开始，恰好等于上一片最后的计数时被当成重复包丢掉 | 只有逐字节相同的包才是重复包 | v4 2026-09-28 `live_cli record soop devil0108` |
| REG-RECORD-044 | PandaTV 录制的 TS 开头解码报 non-existing PPS 0 referenced | Amazon IVS 列表里较早的分片不以关键帧开头，录制从这样的分片开始 | 文件从关键帧开始：在分片内第一个关键帧处切开，之前的部分丢掉（切分时留在旧文件） | v4 2026-09-28 `live_cli record pandalive … --renew-after 20` |
| REG-RECORD-045 | IPTV 的 `.ts`、udpxy 线路录制一连上就失败（按 FLV 解析） | live_core 只有 flv / hls 两种格式，IPTV 把非 HLS 的线路都标成 flv | 线路格式加 `other`，录制按开头的字节分派 FLV、连续 TS、HLS 列表；连续 TS 按单元完整写，断流、停止、丢包都不留半个单元 | v4 2026-09-28 `live_cli record url`（§8、§22） |
