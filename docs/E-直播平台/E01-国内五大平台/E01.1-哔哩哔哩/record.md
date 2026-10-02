# E01.1 哔哩哔哩

- 日期：2026-09-28
- 目标：`packages/live_core/lib/src/sites/bilibili/`（`bilibili_api.dart` 纯解析，`bilibili_site.dart` 请求编排）
- 样本：`fixtures/bilibili`，32 个真实接口录制，来自归档。每个样本附有 v3 解析器的冻结输出 `expected.json`，作为“行为和 v3 一致”的依据。
- 参考：归档 v4 的哔哩哔哩适配器和规格（`spec/sites/bilibili.md`，其中 25 条回归条目 REG-BILIBILI-001～025）；pure_live_TV `9fb40418`（只是去掉桥接、注释改英文、文字多语言化，没有新的行为修复）。

这是 E 的第一个平台，其余平台都按这里的做法来：解析写成纯函数、请求编排单独一层、用样本对照 v3 的输出、差异逐条说明。

## 做法

- **接口和输出沿用 v3**：`LiveSite` 和 `LiveRoom` 等模型，3.x 的 JSON 不变。
- **解析和会话采用归档 v4 的实现**。它就是 v3 行为的逐条重写，并且：
  - 错误有类型；
  - 并发请求合并；
  - 会话跟着登录 Cookie 走，Cookie 一变就重建。
- **v3 有而归档 v4 没有的部分，按 v3 补上**：
  - 搜索主播（`searchAnchors`）；
  - 醒目留言；
  - 开播状态查询；
  - 弹幕凭据的重试（最多 4 次，第 2、4 次刷新 WBI 密钥）；
  - 进房时弹幕凭据取不到也先开播，之后再补。

## 取流结果补上“线路”（对 E05.1 的扩充）

v3 播放用的请求头放在播放层的 `PlaybackHeaderResolver` 里，按平台写死；续期时间放在 `LivePlayLeaseMetadata` 里另外查询。诊断报告称之为“旁路”，还因此出现过“录制失败而播放正常”的问题（REG-BILIBILI-016）。

- 新增 `LivePlayLine`：每条线路带地址、请求头、格式（FLV/HLS）、编码、线路编号和有效期（`PlayLease`）。
- `LivePlayUrlResolution` 改由线路组成，`urls` 仍然可用。
- 播放、录制和多画面以后都直接读线路（G、H01.1），不再需要按平台写的请求头表。
- 另外在 `live_core` 加了通用的 JSON 读取工具，并把 v3 的 `normalizeNetworkImageUrl` 移为 `normalizeImageUrl`，所有平台共用。

## 与 v3 输出的对照

对照方式：用同一份录下的响应跑新代码，逐键比较 `toJson` 和 v3 的冻结输出。

| 样本 | 结果 |
|---|---|
| S01 分区（12 类） | 一致。v3 的 `shortName` 写 `null`，新代码写空字符串，3.x 读取时两者等价 |
| S03、S04 推荐（30 条、12 条） | 房间、顺序、各字段一致；只多了 `totalViewers`（见下） |
| S05 搜索（14 条） | 除封面和 `totalViewers` 外一致；后面追加了 v3 搜不到的主播（见下） |
| S06 详情（直播、未开播、轮播、短号、长号） | 除简介和 `totalViewers` 外一致；房间号保持请求时的号码 |
| S07 取流（5 个样本） | 画质列表、线路地址、实际画质、是否已确认都一致；HEVC 样本见下 |
| S09～S16 弹幕凭据、buvid、WBI 密钥、access_id、扫码、账号 | 一致 |

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 搜索卡片的封面用 `user_cover`（房间封面），不用 `cover` | `cover` 其实是直播关键帧截图，v3 请求时已经要求 `cover_type=user_cover`。另外 v3 对本来就是完整地址的封面拼出了 `https:https://…`，图片打不开（样本 S05 第 14 条） |
| 2 | 搜索第 1 页在直播间之后追加名字匹配的主播 | 平台只把未开播和轮播的主播放在 `live_user` 里，v3 从不读它，这些主播永远搜不到。追加的卡片没有标题、封面和热度，已经在列表里的房间不重复 |
| 3 | 新增 `totalViewers`（“N 人看过”，`watched_show.switch` 为 true 时） | v3 的平台能力表已经写明哔哩哔哩有累计观看数，但从来没读。显示逻辑仍优先热度，界面不变 |
| 4 | 简介里的 HTML 转成纯文本 | v3 原样显示 `<p>…</p>` |
| 5 | 公告取 `news_info.content` | v3 写死为空 |
| 6 | 同一组线路只保留一种编码 | 响应同时带 AVC 和 HEVC 时，v3 会把两种编码的线路混在一起（HEVC 样本）。v3 平时只请求 `codec=0`，所以只有这类响应会受影响 |
| 7 | 出错抛类型化错误，不返回“出错快照” | v3 进房失败时返回“当前播放房间”的快照并标为未开播，曾导致把别的房间显示出来（REG-BILIBILI-018）。界面层改用 `pendingAfterError` 保留旧信息（M13） |
| 8 | 取不到流时报“暂时无法播放” | 未开播和轮播房间的 `playurl_info` 为 null，v3 抛 FormatException |
| 9 | 线路自带请求头和有效期 | 见上一节 |
| 10 | 图片地址统一规范化 | 协议相对地址、带引号的地址、缺协议的地址都能处理 |

保持 v3 行为、没有采用归档 v4 做法的地方：

- **轮播（`live_status=2`）仍显示为未开播**。v4 标成“回放”，但回放在界面上算可播放，游客又拿不到轮播的播放地址，点进去只会报错。把轮播单独标出，列为后续升级候选。（T02.U 已改为单独的轮播状态，见文末“升级落地（T02.U）”。）
- **房间号保持请求时的号码**（短号 6 不改成长号 7734200）。v4 会换成长号，那样用短号关注的房间刷新时身份对不上，会合并失败。长号放在 `BilibiliRoomData` 里，只用于取流和弹幕。
- **搜索每页条数**按设置发送，并限制在 1～50（REG-BILIBILI-024）；v4 固定为 20。
- **搜索卡片保留头像**（3.x 的卡片会显示头像）；v4 的搜索卡片没有头像。

## 回归条目的覆盖

REG-BILIBILI-001～007、014～021、023～025 都有测试或实现直接覆盖。

- 008～013、022 属于弹幕协议，在 D01 覆盖；本模块提供它们需要的凭据：
  - 游客 uid 为 0，登录用户取同一份 Cookie 里的 `DedeUserID`；
  - 通用网关排在最前；
  - 进房时只试一次，之后按完整的重试策略补取。
- 017（图片 Referer）由界面的图片加载器处理（A01.1），本模块负责把地址补全成 https。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 弹幕协议（`BiliBiliDanmaku`） | D01；本模块输出 `BilibiliDanmakuArgs` |
| `getDanmaku()` | `live_core` 不能依赖 `live_danmaku`，D01 用一张“平台 → 弹幕连接”的表代替 |
| 扫码登录界面、账号页 | M13；本模块提供 `qrCode`、`qrPoll`、`account` |
| 图片请求的 Referer | A01.1 |

## 测试

61 个用例，`live_core` 共 176 个，连续跑 3 次全部通过：

- `bilibili_api_test.dart`（35 个）：逐个样本对照 v3 的输出，有意的差异逐条断言；错误类型、画质确认、线路自带的请求头和有效期、WBI 签名（官方公开的示例）、会话解析、醒目留言。
- `bilibili_site_test.dart`（26 个），用样本回放加少量合成响应：
  - 游客会话：并发请求只取一次 buvid 和密钥，登录 Cookie 自带 buvid3 时不另取，Cookie 一变就重建会话；
  - 签名和 -352 续签后重试一次；412 不重试；
  - 短号的身份和长号取流；
  - 进房时的弹幕凭据和兜底，uid 的优先顺序；
  - 分区的 `w_webid`、推荐的回退、搜索的每页条数；
  - b23 短链经解析器逐跳跟随，不请求房间页；
  - 扫码和账号校验；
  - 传输错误的映射。

## 升级落地（T02.U）

- 日期：2026-09-29
- 依据：[升级决定](../../../specs/UPGRADES.md)。本平台只有 1-1 一条；另外按“统一原则”填了 [E05.2](../../E05-平台框架和模型/E05.2-模型扩展/record.md) 的开播时间和受限类型。
- 只改了平台层（`bilibili_api.dart` 的解析，`bilibili_site.dart` 只补了注释）。没有新增通用代码，没有新样本。

### 逐条

| 编号 | 做了什么 | 用户会看到什么 | 状态 |
|---|---|---|---|
| 1-1 | `live_status=2` 改为 `LiveStatus.carousel`：详情、关注刷新、录制用的详情、搜索（`live_room` 和追加在后面的 `live_user` 主播卡）都一样。取流不看房间状态：`getRoomPlayInfo` 给了地址就照常给线路（登录后如果有），给不了时报 `StreamUnavailable`，说明里写 `carousel`。`getLiveStatus` 对轮播仍是 false | 轮播房间不再和未开播混在一起，显示为“轮播”（界面在 M13）；关注分组仍放在未开播；录制按下播处理，不录轮播 | 平台层完成，余下 M13 |

### 按统一原则填的新字段

- **开播时间 `startedAt`**：
  - 详情：`room_info.live_start_time`（Unix 秒），只在直播中且大于 0 时填。样本 S06-live 为 2026-09-27 08:56:16 UTC。
  - 搜索：`live_room` 的 `live_time`，格式 `yyyy-MM-dd HH:mm:ss`，是北京时间，按 UTC+8 换算。依据：S05 里最晚的一条是 17:53:25，比录制时间 09:53:53 UTC 早 28 秒，若按 UTC 理解就会晚于录制时间。未开播主播的 `0000-00-00 00:00:00` 不填。
  - 推荐和分区列表：接口里没有开播时间，不填，也不为它多发请求。
- **受限类型 `restriction`**：
  - 详情：`room_info.special_type` 为 1（付费直播间）且在播时填 `paid`，房间仍是直播中、分组在直播中；其他值（0 普通、2 拜年祭）和不在播时填 `none`；回答里没有这个字段时留 null。
  - 搜索和列表的回答里看不出受限情况，留 null（合并时保留关注里存下的值）。
  - 取流：`playurl_info` 为 null 时报 `StreamUnavailable`，说明分四种：`offline`、`carousel`、`paid broadcast`（`all_special_types` 含 1）、`live without a stream`。界面按房间的状态和受限类型给用户解释原因。
  - **没有付费房样本**：2026-09-29 用公开接口查了几个在播房间（`room_init`、`getInfoByRoom`、`getRoomPlayInfo`），`special_type` 都是 0，搜不到在播的付费直播间。`special_type` 的含义来自接口本身（`room_init` 同时给 `is_sp` 和 `special_type`）；`all_special_types` 含 1 表示付费，来自网页播放器的代码（`checkIsHasRights` 用它决定是否要求购票）。以后录到付费房时核对。加锁（`is_locked`，网页显示“直播间已封禁”）、加密（`encrypted` 且未验证，网页要求密码）不在本平台的条目里，没有做。

### 画质、设置、身份

- **画质**：没有改名、合并或调整顺序（10000 已经叫“原画”，请求时只要 H.264）。画质 id 不变，**没有旧 id → 新 id 的对照**，J02.1 不需要迁移本平台存下的画质偏好。
- **设置项**：无。
- **身份**：不变。房间号是数字，短号仍是关注的身份，长号放在 `BilibiliRoomData`。没有按主播关注的条目，J02.1 没有本平台的身份迁移规则。
- **请求数**：关注刷新、列表、搜索、进房的请求数都不变。

### 与 v3 冻结输出的新差异

样本对照测试里用 `changed:` 列出，原因写条目编号：

- S06-replay（房间 5440）的 `liveStatus`：v3 写 1（未开播），现在写 5（轮播，1-1）。`status`、`isRecord` 仍为 false，所以 3.x 读回来仍是未开播。
- 新键 `startedAt`（直播中的房间）、`restriction`（详情）：3.x 没有这两个键，读取时忽略（E05.2 的 JSON 兼容规则）。对照测试逐个样本检查了这两个键。

### 留给其他模块

| 内容 | 去向 |
|---|---|
| 轮播显示为单独的状态、放在未开播分组；房间页是否给“播放轮播”的入口（`isPlayableNow` 对轮播为假）；开播时间只在直播中显示；付费标记 | M13 |
| 录制把轮播当下播（`isExplicitlyOfflineNow` 为真），平台层不需要再做什么 | H01.1 |
| 游客播放轮播（见下面的线索），需要播放器从指定进度开始、播完换下一个 | G 评估 |

游客播放轮播的线索（没有做）：

- `api.live.bilibili.com/live/getRoundPlayVideo?room_id=…` 游客可用，返回正在轮播的视频：`bvid`、`cid`、标题、`play_time`（已播到第几秒）、`sequence`。
- 它给的 `play_url`（`interface.bilibili.com/v2/playurl`）已经失效，会跳到出错页。要播放得走普通视频的取流接口（`x/player/wbi/playurl`），并从 `play_time` 处开始。
- 这超出了 1-1 定的“登录后能取到地址就播放”，还要播放器配合，所以没有做。

### 受阻和未核实

- 没有受阻的条目。
- 未核实：登录后 `getRoomPlayInfo` 对轮播是否给地址。没有登录账号的样本，所以只用合成响应测试了“给了地址就播放”。适配器不挡轮播，平台给了就播。

### 测试

本平台 68 个用例（新增 7 个，另改写了 S06 对照、轮播状态和取流失败的用例），`live_core` 共 2889 个，全部通过：

- `bilibili_api_test.dart`（40 个）：
  - S06 对照：轮播的 `liveStatus` 列为 `changed:`（1-1），逐个样本检查 `startedAt` 只在直播中出现、`restriction` 为 `none`；
  - 轮播的状态、分组、可播放性和 3.x 读回的结果；
  - 详情的开播时间（直播、短号、未开播、轮播）；
  - 付费：`special_type` 1 的在播房间标 `paid`、仍在直播中分组，不在播时为 `none`，没有字段时为 null；
  - 搜索：`live_user` 里 `live_status` 2 的两个主播是轮播，其余未开播；`live_time` 按北京时间换算，不晚于录制时间；
  - 取流：未开播和轮播的说明、带地址的轮播能播放、付费房的说明；`live_status` 2 的开播状态查询为 false。
- `bilibili_site_test.dart`（28 个）：轮播房间刷新后是轮播，取流时照常请求 `getRoomPlayInfo`（不先挡）；登录后带地址的轮播能取到画质，请求带登录 Cookie。

## 国内平台完善（T02.D，2026-10-01）

- 改动：`bilibili_api.dart`、`bilibili_site.dart`、`live_danmaku` 的 `bilibili.dart`、三个测试文件、两个新样本。框架和公共模型没有改。
- 按协调者的加速要求：录制合计不到 10 分钟，测试只写主要路径，没做变异检查和 timeshift。

### 真实环境检查

2026-09-30 20:32～20:40 UTC，直连、游客（不登录、不发言），用本仓库的 `BilibiliSite` 和 `BilibiliDanmakuConnection` 跑（脚本在 scratchpad，不进仓库）。

| 功能 | 结果 | 说明 |
|---|---|---|
| 推荐第 1、2 页 | 正常 | 各 30 个；标题、主播、封面、头像、分区、热度齐全。第 2 页 3 个没有“看过”人数（`watched_show.switch` 为 false，按设计留空） |
| 分类 | 正常 | 12 类、462 个分区 |
| 分区（英雄联盟）第 1、2 页 | **失败 → 已修** | 见问题 1 |
| 搜索房间（英雄联盟、原神） | **分区名带标签 → 已修** | 各 36 个（31、30 个在播，其余是未开播的主播卡）；开播时间正确。见问题 2 |
| 搜索主播（原神） | 正常 | 30 个，2 个在播 |
| 详情：3 个在播（545068、1775719573、27632810） | 正常 | 标题、主播、开播时间、受限类型 `none`、公告、弹幕凭据（token、网关加 4 个节点、uid 0）都有 |
| 详情：1 个未开播（21987615） | 正常 | 未开播、没有开播时间；取流报 `StreamUnavailable`（offline） |
| 醒目留言板 | 正常 | 545068 有 2 条，另两个房间 0 条 |
| 画质和线路：545068 | 正常 | 蓝光 400、超清 250；游客请求 400 实际给 250（已知，线路上写明）。每档 6 条线路：FLV 2 条、HLS（TS）2 条、HLS（fMP4）2 条，都是 H.264。每条只读开头 4 KB：FLV 头、TS 同步字节、fMP4 的 `ftyp` 都对得上；只有备用节点 `gotcha104b` 的 HLS 第一个分片 404（平台侧，播放层会换下一条线路） |
| 画质和线路：1775719573、27632810 | 正常 | 原画 10000，各 4 条（FLV 2、HLS-TS 2），全部确认 |
| 弹幕 545068（120 s） | 正常 | 就绪；157 条聊天（154 条是游客看到的打码昵称）、27 次人数（热度 1 共 4 次、累计观看 23 次）；这 2 分钟没人发醒目留言 |
| 弹幕 1775719573（120 s） | 正常 | 就绪；7 条聊天、7 次人数 |

弹幕里收到但不解码的通知：`INTERACT_WORD_V2`（进场）、`ONLINE_RANK_COUNT`（见候选 D-1）、`ENTRY_EFFECT`、`LIKE_INFO_V3_*`、`ONLINE_RANK_V3`、`RANK_CHANGED_V2`、`UNIVERSAL_ASR_TEXT`（网页的 AI 字幕）等。没有录到撤回、醒目留言删除和警告（这 2 分钟里没有发生）。

### 修好的问题

| # | 问题 | 根因 | 做法 |
|---|---|---|---|
| 1 | 分区页打不开：游客每一页都报风控 | 3.x 和 E01.1 用的 `second/getList`（WBI 签名加 `w_webid`）现在对游客一律回 -352，续签重试一次后仍是 -352，于是 `RiskControl`。E01.1 的注释已经记下“游客每页都是 -352”，但没有换接口 | 先用不签名的 `room/v1/area/getRoomList`（`parent_area_id`、`area_id`、`sort_type=online`、`page`、`page_size` 限 1～30，游客可用，实测每页 30 个、翻页不重复、翻过最后一页为空），失败时（限流除外）再用原来的签名接口；两个都失败时报第一个的错误。一次请求，不再取 WBI 密钥和 `w_webid`。字段和原来的列表相同（`roomid` 是长号、`online`、`user_cover`/`cover`、`face`、`area_v2_name`），没有“看过”人数 |
| 2 | 关键词是分区名时，搜索卡片的分区显示 `<em class="keyword">英雄联盟</em>` | 搜索回答对 `cate_name` 也加高亮标签，解析只对标题和昵称去了标签 | `cate_name` 和标题一样去掉 `<em>` 并解码字符 |

### 这次做的已批准项（弹幕，按附录 B 的同类做法）

- **醒目留言带 id**：`SUPER_CHAT_MESSAGE` 的消息本身也带 `data.id` 作 `messageId`（原来只有里面的 `LiveSuperChatMessage` 带），同 YouTube、CHZZK、Picarto。和进房拉的醒目留言板（同一个 id）照旧按 id 合并。
- **醒目留言撤下**：`SUPER_CHAT_MESSAGE_DELETE`（`data.ids`，退款或被删除）每个 id 一条 `LiveRetraction.message(id)`。
- **撤回**：`RECALL_DANMU_MSG`，按网页播放器的处理（`recall_type`：2 撤回某用户的全部弹幕，uid 取 `data.uinfo.uid`，没有时 `data.target_id`；3 清屏）→ `LiveRetraction.user(uid)`、`LiveRetraction.all()`。uid 为 0 时不撤回（游客看到的 uid 都是 0，撤回会对不上）；1（单条）网页这里不处理，也不做。
- **通知**：`WARNING`（超管警告）、`CUT_OFF`（直播被切断）显示为系统通知 `直播间收到警告：<原因>`、`直播被切断：<原因>`（原因取 `msg`，没有时只显示前半句）。
- 三种都没有录到真实样本，用合成帧测试；字段名来自网页播放器代码（`app.*.js` 的 `RECALL_DANMU_MSG` 处理和 `F={NOTHING:0,DANMAKU:1,USER:2,ALL:3}`）和公开的协议说明。
- `DANMU_AGGREGATION`（网页的弹幕聚合）只是把相同弹幕合并显示，不是撤回，照旧不解码。

### 带登录 Cookie 时（只核对代码和文档）

- Cookie 从 `CookieVault` 取，去掉控制字符；Cookie 一变就换会话。自带 `buvid3` 时不另取游客 buvid，否则把游客的一对接在后面。
- API、取流、弹幕握手都带同一份 Cookie；弹幕 uid 取同一份 Cookie 的 `DedeUserID`，没有时用校验过的或存下的 uid。
- 新的分区接口是普通请求，同样带 Cookie；登录后是否和游客一样，没有账号核实。

### 候选（改变用户看到的内容，未做，等用户决定）

| 编号 | 内容 | 现状 | 建议 | 依据 |
|---|---|---|---|---|
| D-1 | 在线人数 | 游客的心跳热度恒为 1（M13 会丢掉，保留详情里的热度）；详情的 `online`（545068 为 52 万）是旧的“人气”值 | 弹幕的 `ONLINE_RANK_COUNT.data.online_count`（545068 为 5184，约 3 秒一次）按“在线人数”（`onlineViewers`）上报，界面有它时显示它 | 实测（2 分钟收到 39 次，`count` 和 `online_count` 相同）；要先核对网页现在显示哪个数 |
| D-2 | 礼物 | 不上报 | `SEND_GIFT`、`GUARD_BUY`（上舰）、`COMBO_SEND` 以礼物上报，界面暂不显示，和 B-21 一起定 | 其他平台（猫耳、克拉克拉、YouTube 等）已这样做；3.x 没有 |
| D-3 | 禁言通知 | 不显示 | `ROOM_BLOCK_MSG`（用户被禁言）、`ROOM_SILENT_ON/OFF`（全员禁言）显示为系统通知 | 网页聊天区显示“用户 X 已被 Y 禁言”；要先录到样本 |
| D-4 | 游客画质列表 | 列出游客拿不到的档（545068 的蓝光 400，请求后实际给 250，线路上写明） | 界面按实际给的画质显示，或给游客标“需登录” | 实测；3.x 相同 |

### 样本

- `S17-area-page1`：`room/v1/area/getRoomList`（英雄联盟第 1 页，30 个），2026-09-30 20:37 UTC。每个房间的 `session_id`（列表会话的 UUID）换成同形的合成值；主播的公开信息保留（同其他列表样本）。
- `S05-area-keyword`：搜索“英雄联盟”第 1 页（36 个，`cate_name` 带高亮），2026-09-30 20:33 UTC。`data.seid`（搜索会话号）换成同长度的合成数字；回答没有 `Set-Cookie`，响应头里没有客户端地址。
- 脱敏记录在各自的 `meta.json`；门禁的 `fixture privacy` 通过。两个样本都没有 3.x 的冻结输出（3.x 不读这两处）。

### 测试

本平台 102 个用例，全部通过：

- `bilibili_api_test.dart` 42 个（+2）：`S17` 分区列表（30 个、按热度、字段齐全、空页没有下一页）；`S05-area-keyword` 的分区不带标签。
- `bilibili_site_test.dart` 29 个（+1，改写 1 个）：分区页只发游客 buvid 和 `getRoomList`，`page_size` 限到 30；`getRoomList` 失败时改用签名接口（带 `w_webid`、-352 续签一次），都失败报第一个错误。
- `live_danmaku` 的 `bilibili_test.dart` 31 个（+3）：醒目留言带 id 和撤下；撤回的 2、3 型和 uid 0、其他类型；警告和切断的通知。冻结输出对照里醒目留言的 `messageId` 差异改为外层也带 id（S13-vectors 2 处、S13-protover3 6 处）。

## 附录 C 落地（T02.D2）

- 日期：2026-10-01。依据：[附录 C](../../../specs/UPGRADES.md) 的 C-1～C-3（用户答复“按建议全部处理”）。
- 只改了 `live_danmaku` 的 `bilibili.dart` 和它的测试；`live_core`、框架、公共模型、样本都没有改。

| 编号 | 做了什么 | 用户会看到什么 | 状态 |
|---|---|---|---|
| C-1 | `ONLINE_RANK_COUNT` 按在线人数（`onlineViewers`）上报：取 `data.online_count`，没有时取 `data.count`，负数和缺失不报。心跳回复的热度照旧上报（游客恒为 1，M13 不用它） | 有了和网页同一个在线人数（约 3 秒一次），房间页有它时显示它（M13）。它比卡片上的热度小得多：545068 卡片热度 41 万，这个数 1738 | 完成 |
| C-2 | `SEND_GIFT`、`COMBO_SEND`、`GUARD_BUY` 以 `gift` 上报，`data` 是新的 `BilibiliGift`（礼物 id、名字、数量、金瓜子价值、连击 id）；文字 `<名字> ×<数量>`，发送者是 `uname`/`username` 和 `uid`。连击按 `batch_combo_id` 每次连接只报第一条（之后同一连击的 `SEND_GIFT`、`COMBO_SEND` 都不报），没有连击 id 的每条都报 | 暂不显示（随 B-21） | 完成 |
| C-3 | 没做 | 不变 | 待做：没录到 |

### 核对和录制

- **网页显示哪个数（C-1）**：网页播放器（`app.3b48f866….js`）收到 `ONLINE_RANK_COUNT` 时，开关 `room_rank_rearrange` 打开用 `online_count_text`，否则用 `count_text`，写进 `onlineGoldCount`；右侧用户榜组件（`8445.d4c19004….js`）把它显示为 `contribution_tab` 标签（标题由服务端下发）上的人数。无头浏览器打开直播间时弹了验证码，没能截到这个标签，所以只核对了代码。录到的 562 条里 557 条两个数相同，5 条差 1～3（小房间），取 `online_count`。
- **录制**：2026-10-01 00:16～00:27 UTC，直连、游客（不登录、不发言），用本仓库的 `BilibiliSite` 取凭据、`BilibiliDanmakuConnection` 连接（protover 3），脚本在 scratchpad，不进仓库。两次共约 9 分钟：5 个房间 300 s（545068 等推荐前列），8 个房间 255 s。
  - 收到：`ONLINE_RANK_COUNT` 562 条、`GUARD_BUY` 2 条（舰长，`price` 198000 = 198 元，`num` 1）、`SEND_GIFT_V2` 32 条、`UNIVERSAL_EVENT_GIFT_V2` 34 条。
  - 没收到：`SEND_GIFT`、`COMBO_SEND`、`ROOM_BLOCK_MSG`、`ROOM_SILENT_ON/OFF`。
  - 用新代码回放录到的帧：每条 `ONLINE_RANK_COUNT` 都是一次在线人数，两次 `GUARD_BUY` 都是礼物。
- **游客收到的礼物是 `SEND_GIFT_V2`**：`data.pb` 是 Base64 的 protobuf（第 2 字段打码昵称，第 10 字段礼物：1 id、2 名字、3 数量、8 `gold`、9 `tid`、10 时间……），不是 JSON 的 `SEND_GIFT`。C-2 只列了 JSON 的三种，所以游客现在只能收到上舰。`SEND_GIFT`（JSON）的字段名来自归档 v4 的解析和公开的协议说明，登录后是否还发 JSON 版没有核实。解析 `SEND_GIFT_V2` 留作候选（见下）。
- **C-3 没录到**：网页播放器的处理是 `ROOM_BLOCK_MSG` → “`uname` 被房管/主播禁言”（`data.operator` 1 为房管，否则主播；`vaild_period` 期限），`ROOM_SILENT_ON/OFF` 只在主播自己的页面处理。按“录到样本后做”，没录到就没做。

### 测试

本平台弹幕 34 个用例（+3），全部通过：

- `bilibili_test.dart` 新增 `T02.D2` 组：C-1 的 `online_count`、`count` 回退、负数和缺失；C-2 的三种消息（`GUARD_BUY` 用录到的形状、合成的用户）、银瓜子礼物、没有名字不报；连击每次连接只报一次（同一连击的 `SEND_GIFT`、`COMBO_SEND` 不再报，中途加入时报 `COMBO_SEND`，新连接重新计）。
- 冻结输出对照改为先去掉在线人数再和 3.x 比，另外断言在线人数：S13-live 20 次、S13-protover3 5 次（逐个值）、S13-vectors 1 次（`acknowledgements` 向量里的 `ONLINE_RANK_COUNT`）。

### 候选（未做）

| 内容 | 现状 | 建议 |
|---|---|---|
| 解析 `SEND_GIFT_V2`（protobuf） | 游客只上报上舰 | 用 `live_danmaku` 的 protobuf 读取器按上面的字段读，同样按连击 id 只报一次；先多录几条核对数量和价值字段 |
