# 斗鱼（douyu）平台规格

第 1 阶段草案。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`douyu`（lib/core/sites.dart:44）。
- 证据写法：`文件:行号` 相对仓库根目录，基于当前 master 检出（c28c17fb）。提交哈希转引自所注文档，编写本规格时没有运行 git 复核。
- 能力：目录（分类、分区房间、推荐）、搜索（包括未开播）、详情、取流（HTTP-FLV，租期到期会断开连接，需要拼接）、弹幕（包括醒目留言）、可选登录 Cookie。
- 不提供：进房前的历史醒目留言，旧实现返回空（douyu_site.dart:670-673；docs/ISSUE_AUDIT_2026_08_23.md:19）；主播搜索、单独的开播状态查询，旧实现虽有但没有调用方（douyu_site.dart:619-654；docs/rewrite/diagnosis/01-sites.md ③-8）。

---

## 1. 房间身份与链接

**规范身份**：数字房间号 `rid`，以字符串保存。

- 详情接口返回的 `room.room_id` 是规范值。房间的 id 和弹幕参数都取这个值，不用用户输入的值（douyu_site.dart:548, 557）。
- 收藏键、签名、Referer、弹幕全部使用规范 rid。旧实现的 `link` 用的是输入值（:560），v4 改为规范 rid。

**可接受的输入**

| 形式 | 例 | 处理 | 证据 |
|---|---|---|---|
| 纯数字 | `9999` | 直接作为 rid | — |
| 房间页 | `https://www.douyu.com/9999?from=search`、`https://www.douyu.com/123/` | 主机是 `douyu.com` 或它的任意子域时，取路径第一段，忽略查询串和末尾斜杠 | web_search_room_parser.dart:143-144；web_search_room_parser_test.dart:11；live_url_tool_parser_test.dart:12 |
| 别名（靓号） | `https://www.douyu.com/fixtureAlias` | 手动链接工具接受 `[A-Za-z0-9_-]+`；网页搜索回流只接受数字 | live_url_tool.dart:141-143, 309-311；live_url_tool_parser_test.dart:26 |
| 分享文本 | 链接前后夹有中文 | 由通用提取器抽出 URL，去掉结尾标点 | live_url_tool.dart:47-88 |

- 保留段不是房间，例如 `search`、`topic`、`directory`、`video`、`user`、`index`、`login`（web_search_room_parser.dart:40-59；web_search_room_parser_test.dart:37；toolbox_link_detection_test.dart:45）。
- 斗鱼没有短链跳转。
- 别名不能直接用于详情接口：`betard/lpl` 返回 HTTP 403 的 Tengine HTML 页（S05-alias-betard）。别名的房间页 `https://www.douyu.com/<别名>` 返回 302，`Location` 是相对路径 `/<rid>`（S05-alias-redirect：`/lpl` → `/288016`）。
- 以下几点 [待确认]：
  - App 分享、`m.douyu.com` 分享的真实格式。
  - `…/topic/…?rid=` 这类专题页链接。

**归一流程**：去掉空白；如果是别名，请求房间页、不跟随跳转，从 302 的 `Location` 取第一段数字作为 rid（相对路径按 `https://www.douyu.com/` 解析）；不是 302 或取不到数字时报 NotFound（douyu_site.dart:275-290）。之后一律使用数字 rid。旧版把别名直接传给 betard，别名链接必然打不开（docs/rewrite/DIAGNOSIS.md:89）。

**外部打开**（room_external_opener.dart:170-173；room_external_opener_test.dart:60）：
- 网页：`https://www.douyu.com/<rid>`
- App：`douyulink://?type=90001&schemeUrl=douyuapp%3A%2F%2Froom%3FliveType%3D0%26rid%3D<rid>`

---

## 2. 目录

### 2.1 分类

- 请求：GET `https://m.douyu.com/api/cate/list`，不带特殊请求头（douyu_site.dart:75-100）。
- 一级分类：`data.cate1Info[]`，字段 `cate1Id`、`cate1Name`，按 `cate1Id` 数值升序排列。
- 二级分类：`data.cate2Info[]`，字段 `cate2Id`、`cate2Name`、`icon`，按 `cate1Id` 挂到对应一级分类下。
- 一次返回全部，没有分页。
- `japi/weblist/apinc/getC2List` 在旧代码里有实现，但没有调用方（:102-123），v4 不实现。

### 2.2 分区房间

- 请求：GET `https://www.douyu.com/gapi/rkc/directory/mixList/2_<cate2Id>/<page>`，page 从 1 开始（:126-154）。
- 响应顶层是 `code`、`msg`、`data`；`data` 有 `ct`、`rl`、`pgcnt`。
- 每页 120 条；`data.pgcnt` 是总页数（英雄联盟分区：第 1 页 120 条、第 6 页 24 条、第 7 页 `rl` 为空，三页的 `pgcnt` 都是 6；S02-mixlist-page1、S02-mixlist-last、S02-mixlist-beyond）。
- 只保留 `data.rl[]` 中 `type == 1` 的条目。录到的两页 144 条全是 `type == 1`，其它 type 的含义 [待确认]。
- 字段：

| 字段 | 含义 |
|---|---|
| `rid` | 房间号 |
| `rn` | 标题 |
| `nn` | 主播名 |
| `rs16` | 封面 |
| `ol` | 热度（见 §4） |
| `c2name` | 分区名 |
| `av` | 头像路径，例如 `avatar_v3/202602/ba65…`，拼成 `https://apic.douyucdn.cn/upload/<av>_middle.jpg`；为空则没有头像（S02-mixlist-page1） |

- 列表中的条目一律视为直播中。

### 2.3 推荐

- 请求：GET `https://www.douyu.com/japi/weblist/apinc/allpage/6/<page>`（:446-479）。
- 响应顶层是 `error`、`msg`、`data`、`redirectUrl`；`data` 只有 `pgcnt`、`rl`。
- 与分区房间相同：取 `rl`，过滤 `type == 1`，字段一致，只有 `av` 不同。
- 每页 40 条；`pgcnt` 恒为 0（第 1 页 40 条、第 218 页 12 条、第 1000 页 `rl` 为空，三页都是 0；S03-allpage-page1、S03-allpage-last、S03-allpage-beyond）。
- `av` 在这里已经是完整 URL，例如 `https://apic.douyucdn.cn/upload/avatar_v3/202505/6db2…_middle.jpg`，原样使用，不再拼接（S03-allpage-page1）。旧实现原样使用是对的（:468）。

### 2.4 分页与结束判断

- 游标内部保存页号，对外是不透明游标。
- 旧应用的做法有缺陷，v4 不沿用：它假设服务端每页固定 40 条，过滤后不足 40 条就判定到底（area_rooms_binding.dart:30-31；popular_controller.dart:65-66；server_fixed_page_controller.dart:153-166）。由于先过滤掉了 `type != 1`，这样会提前结束。
- v4 只根据服务端信号判断结束，不按条数判断（01-sites.md ⑥；douyu_parse.dart:65-84）：
  - `rl` 为空；
  - 或页号达到 `data.pgcnt`（只对 mixList 有效）。`pgcnt` 为 0 时（allpage）只能靠空 `rl` 结束。
  - 两个接口每页条数不同（120 和 40），这也说明不能按固定条数判断。
- 某一页请求失败时，已加载的页保留，报告失败，不当作“已到底”（server_fixed_page_controller.dart:142-149）。

---

## 3. 搜索

- 请求：GET `https://www.douyu.com/japi/search/api/searchShow?kw=<kw>&page=<p>&pageSize=<n>`（douyu_site.dart:573-617）。
  - `n` 限制在 1..50，应用传 20（search_controller.dart:380）。
  - 请求头使用通用 API 头（§6.7），另把 referer 设为 `https://www.douyu.com/search/`。
- 顶层 `error != 0` 表示失败，映射见 §9。
- 结果列表 `data.relateShow[]`：

| 字段 | 含义 |
|---|---|
| `rid` | 房间号 |
| `roomName` | 标题。可能含 HTML 实体，例如 `【CSTG】今天休&nbsp;陪家人过节`，必须先解码（S04-search-page2）。旧版没有解码（DIAGNOSIS.md:91） |
| `roomSrc` | 封面 |
| `cateName` | 分区 |
| `avatar` | 头像 |
| `nickName` | 主播名 |
| `hot` | 热度，是文本，例如 `"353.9万"`、`"24"`，按中文数量解析（S04-search-page1、S04-search-mixed） |
| `isLive`、`roomType` | 直播状态，见下 |

- 直播状态（douyu_parse.dart:102-106）：

| 条件 | 状态 |
|---|---|
| `isLive == 1 && roomType == 0` | 直播中 |
| `isLive == 1 && roomType == 3` | 回放轮播。S04-search-mixed（关键词“测试”）的 20 条里有 18 条是这种。录制时对照过，同一房间的 betard 是 `videoLoop == 1`（douyu_parse.dart:86-88）；样本里没有同一房间的 betard，S05-replay-videoloop 是另一个轮播房间 |
| 其它 | 未开播 |

  - 未开播的结果也返回，能力标为“直播与未开播”（search_capability.dart:122）。
  - 旧版把 `roomType == 3` 当作未开播，v4 改为回放。
  - `roomType` 其它取值的含义 [待确认]，录到的只有 0 和 3。
- 分页：页号从 1 开始。以下任一情况即结束：本页为空；请求失败；连续 2 页没有新的 rid（search_controller.dart:14, 341-368）。
  - 服务端在 `data.total` 给出总数，同时回显 `data.pageSize`（S04-search-page1：“英雄联盟”共 803 条；S04-search-empty：0 条）。v4 以空页结束，不依赖 `total`（douyu_parse.dart:112）。
- 错误：顶层 `error == 1`，`data` 为空数组，原因写在 `msg` 里：
  - 空关键词：`【kw】kw不能为空 | 【kw】个数必须在1和20之间`（S04-search-error-blank）。
  - 非空关键词也会间歇出现 `【kw】kw不能为空`：同一个 URL（kw=阿冷），先返回这个错误（S04-search-error-kw），约 30 s 后正常返回空结果（S04-search-empty）。线上探针轮换三个关键词（tool/interface_probe.py:289-306）大概就是这个原因。
  - 映射见 §9。

---

## 4. 房间详情

- 请求：GET `https://www.douyu.com/betard/<rid>`（douyu_site.dart:517-537）。
  - 请求头：`referer: https://www.douyu.com/<rid>` 和一个桌面 UA。旧实现这里用的是 Edge/114 的 UA，和其它请求不同。不必用这个 UA：样本用的是和其它请求相同的 Chrome/140 UA，直播、未开播、回放三种房间都正常返回（S05-live、S05-offline、S05-replay-videoloop）。
  - 响应可能是 JSON 字符串，需要先解码，再取 `room` 对象（:531-535）。录到的 3 个响应都是 JSON 对象，`content-type` 为 `application/json`；字符串形式没有遇到，解码规则保留（douyu_parse.dart:123-124）。
  - 房间不存在时返回 **HTTP 200 加 HTML 页**，页面正文是“该房间目前没有开放”，不是 404，也不是空 `room`（S05-not-found，rid 999999999）。正文以 `<` 开头即判为不存在，映射为 NotFound（douyu_parse.dart:117-121）。旧版在这里抛 FormatException（DIAGNOSIS.md:88）。
  - 别名会被拒绝，返回 HTTP 403（S05-alias-betard）。别名要先按 §1 换成数字 rid。

**字段**（:539-563）

| 字段 | 含义 |
|---|---|
| `room_id` | 规范 rid |
| `room_name` | 标题 |
| `owner_name` | 主播名 |
| `owner_avatar` | 头像 URL |
| `room_pic` | 封面 |
| `show_details` | 简介 |
| `second_lvl_name` | 分区 |
| `room_biz_all.hot` | 热度 |
| `show_status` | 开播状态 |
| `videoLoop` | 回放轮播标志 |

**直播状态**（:565-570；douyu_playback_parser_test.dart:8-17）。数值字段可能是数字，也可能是数字字符串，两种都要接受。

| 状态 | 条件 |
|---|---|
| 直播中 | `show_status == 1`，且 `videoLoop != 1`，且标题不以 `【回放】` 开头（S05-live） |
| 回放轮播 | `videoLoop == 1`，或标题以 `【回放】` 开头。房间状态记为“回放”，不能当直播录制（:541, 561）。轮播房间的 `show_status` 也是 1，所以必须先看 `videoLoop`（S05-replay-videoloop，rid 9804176，“24小时不间断”的斗地主轮播） |
| 未开播 | 其它情况。`show_status == 2` 表示未开播（S05-offline，rid 71415；docs/ISSUE_871_DOUYU_CHAT_COMPLETENESS_AUDIT_2026_09_19.md:31）；1、2 以外的取值 [待确认] |

**人数字段**：详情的 `room_biz_all.hot`、列表的 `ol`、搜索的 `hot` 都是**热度**，不是同时在线人数，界面按“热度”显示（RELEASE_NOTES.md:1284, 2128；live_room_audience_metric_test.dart:8）。

**失败处理**
- 详情请求失败必须作为失败返回，不能转成“未开播”或“状态未知”的房间。
- 旧的界面路径会吞掉错误（:481-499），严格路径则把错误传出去（:501-515）。录制曾因此被误停，修复见 233d858d（01-sites.md:139）。
- 房间不存在：HTTP 200 加 HTML 页，映射为 NotFound（见上，S05-not-found）。

---

## 5. 画质与线路

### 5.1 画质列表

- 来源：一次“元数据取流”，即以 `rate=-1`、`cdn=''` 请求 H5 接口（§6.3；douyu_site.dart:157-170, 325）。
- 取 `data.multirates[]`，字段 `name`、`rate`：
  - **保持接口给出的顺序**；
  - 按 `rate` 去重，先出现的保留；
  - 标签用 `name`（:172-213；douyu_playback_parser_test.dart:130-146）。
- 列表为空时，用 `data.rate` 生成一个“默认”选项（:201-211）。
- `rate` 是**不透明的请求码**，不是码率，禁止按数值排序或比较高低。
  - 已观察到的对应关系：0 = 原画（有 1080P30，也有 2K60）、4 = 蓝光 4M、3 = 超清、2 = 高清（docs/DOUYU_QUALITY_ACK_AUDIT_2026_09_06.md:18；docs/ISSUE_873_DOUYU_QUALITY_AND_SESSION_AUDIT_2026_09_23.md:11-13）。
  - `-1` 表示由服务端选默认档位。

### 5.2 线路（CDN）列表

- 取 `data.cdnsWithName[].cdn`，保持顺序并去重（:380-394）。
- 当前 CDN `data.rtmp_cdn` 如果不在列表中，插到最前面。
- 列表为空时，生成一条 `cdn=''` 的线路，由服务端挑选 CDN（:392；douyu_playback_parser_test.dart:74-87）。
- 以 `scdn` 开头的 CDN 码稳定地排到最后（:161-168），原因 [待确认]。录到的响应里没有 `scdn*`。
- **线路身份是 CDN 码，不是下标**。`cdnsWithName[].name` 是“线路7”“线路13”这样的编号（S08-meta-24422），可以显示，但不能当身份。
- `cdnsWithName[]` 还有 `isH265`（24422 两条线路为 true，4489985 为 false）和 `re-weight`（S08-meta-24422、S08-meta-4489985）。v4 请求 `hevc=0`，不读这两个字段。
- 请求列表以外的 CDN 码时，服务端不报错，改给列表里的另一条：24422 请求 `cdn=tct-h5`，响应的 `rtmp_cdn`、`selected_cdn` 都是 `hs-h5`，地址也是 hs 的主机（S09-24422-r0-tct-h5）。所以线路实际走的是响应里的 `rtmp_cdn`，不一定是请求的码。线路身份是否应改用响应的 `rtmp_cdn` [待确认]。

### 5.3 服务端确认的 rate

- 每次按 (rate, cdn) 取流时，响应里的 `data.rate` 是服务端实际给出的档位（:307-323）。
- 以下情况视为**已确认**：整数，可以是数字或整数字符串（`"0"` 也算），且大于等于 0。
- 以下情况一律视为**未确认**：缺失、负数、小数（例如 1.5）、非数字。不能截断成 0 冒充原画（:310-321；douyu_quality_ack_test.dart:114-128）。
- 匿名请求原画可能被服务端降档，这是平台限制，不是客户端缺陷：
  - 房间 24422（原画2K60）请求 rate 0，服务端确认为 4（S09-24422-r0-hw-h5、S09-24422-r0-hs-h5）；
  - 房间 4489985（原画1080P30）请求 0，现在也确认为 4（S09-4489985-r0-hw-h5，2026-09-27）。ISSUE_873 记录时这个房间确认为 0，说明降档不只针对 2K 房间，而且会随时间变化；
  - 元数据请求（`rate=-1`）两个房间也都给 4（S08-meta-24422、S08-meta-4489985）；
  - 请求 rate 2 确认为 2，没有降档（S09-24422-r2-hw-h5）。
  - 证据：以上样本；ISSUE_873…md:9-15；docs/ISSUE_TRIAGE_LEDGER_3_2_0.md:13, 20, 23。

### 5.4 按确认 rate 给线路分组

**播放**（:250-284）：对每个 CDN 用同一个请求 rate 取流，再按确认的 rate 分组，按以下顺序选一组：
1. 确认 rate 等于请求 rate 的组；
2. 否则，按 CDN 顺序第一个有确认 rate 的组；
3. 都没有确认时，用未确认组，并标为“未确认”。

同一个画质下的线路只能来自同一组，不能混合（douyu_quality_ack_test.dart:94-106, 145-150, 161-166）。单个 CDN 失败就跳过，全部失败才报错（:130-135, 152-159）。

**显示**
- 界面显示的画质是确认 rate 对应的选项。
- 确认的 rate 不在画质列表中，或者没有确认时，保留请求的名称并标“未确认”（:193-207）。
- “请求档位”用于重试游标，“展示档位”用于显示，两者分开保存（:168-191）。

**录制和续期**
- 只签当前使用的那一条线路（douyu_site.dart:286-301；douyu_playback_parser_test.dart:148-166）。
- 录制游标的推进顺序：同画质的下一条线路 → 下一个画质的第一条线路 → 回到开头（docs/RECORDER_REPAIR_AUDIT_2026-08-27.md:13；docs/rewrite/diagnosis/04-recorder.md:55）。

### 5.5 每条线路（StreamLine）必须带的数据

| 数据 | 值 |
|---|---|
| 地址 | 媒体 URL |
| 格式 | `flv` |
| 请求头 | 见 §6.7 |
| 线路身份 | CDN 码 |
| 请求档位 | 请求 rate |
| 实际档位 | 确认 rate，或“未确认” |
| 租期 | Lease，见 §6.8 |

---

## 6. 取流

### 6.1 加密描述符

- 请求：GET `https://www.douyu.com/wgapi/livenc/liveweb/websec/getEncryption?did=<DID>`，带通用 API 头，包括 Cookie（douyu_utils.dart:38, 164-185）。
- 返回的 `data` 字段：`key`、`rand_str`、`enc_data`、`enc_time`、`expire_at`（Unix **秒**）、`is_special`。
- 同时满足以下条件才可用，否则按 ApiChanged 处理（:119-135；platform_signing_utils_test.dart:16-20, 40-49）：
  - `key`、`rand_str`、`enc_data` 都不为空；
  - `1 ≤ enc_time ≤ 16`；
  - `expire_at > now + 30 s`。
- 缓存规则（:137-162）：
  - 同一个 DID、获取不到 5 分钟、仍然可用时复用；
  - DID 变化（例如换了账号）时立即作废；
  - 多个请求同时需要刷新时，只发一次请求。

### 6.2 签名

算法（douyu_utils.dart:601-637）：

```text
secret = rand_str
重复 enc_time 次：secret = md5_hex(secret + key)
salt   = is_special == 1 ? "" : rid + tt
auth   = md5_hex(secret + key + salt)
tt     = 当前 Unix 秒
```

测试向量：key=`key`、rand_str=`rand`、enc_time=1、is_special=0、rid=`123`、tt=1000，得到 auth=`1834439993932d590bceb2593c1c0cd0`（platform_signing_utils_test.dart:22-37；编写本规格时已用 Python 复算，结果一致）。

### 6.3 H5 取流接口

请求：POST `https://www.douyu.com/lapi/live/getH5PlayV1/<rid>`，请求体为 `application/x-www-form-urlencoded`（douyu_site.dart:337-343）。

表单字段（douyu_utils.dart:622-636）：

| 字段 | 值 |
|---|---|
| `enc_data` | 描述符里的原值 |
| `tt` | 签名用的秒数 |
| `did` | 见 §6.6 |
| `auth` | §6.2 算出的值 |
| `cdn` | CDN 码，可以为空 |
| `rate` | 请求码，`-1` 表示默认 |
| `hevc` | 0 |
| `fa` | 0 |
| `ive` | 0 |
| `ver` | `Douyu_new` |
| `iar` | 0 |

- 字段值必须 URL 编码，因为 `enc_data` 可能含 `+`、`/`、`=`（platform_signing_utils_test.dart:32）。
- 成功条件：`error` 为 0（没有 `error` 时看 `code`；数字或字符串都可以），并且 `data` 是对象（douyu_site.dart:363-378；douyu_playback_parser_test.dart:57-72）。
- 用到的 `data` 字段：`multirates`、`cdnsWithName`、`rtmp_cdn`、`rate`、`rtmp_url`、`rtmp_live`、`flv_url`，以及兜底用的 `player_1`、`stream_url`、`url`。
- 录到的响应还有这些字段，v4 不使用（S08-meta-24422、S09-*）：`client_ip`（客户端公网 IP，样本里已替换）、`p2pMeta`（P2P 参数，内含 `txSecret` 等签名，样本里已替换）、`selected_cdn`（与 `rtmp_cdn` 相同）、`show_id`（本场直播 id，与 URL 里的 `sid` 相同）、`cdnsWithName[].isH265`，以及 `h265_p2p*`、`av1_url`、`mixed_*`、`rtc_stream_*`、`streamStatus` 等。
- `hevc=0` 表示只要 AVC。探针显示斗鱼所有画质都是 AVC（docs/PLATFORM_PROBE_2026_09_25.md:87）。24422 的两条线路 `isH265` 为 true，但设 `hevc=1` 时服务端怎样响应 [待确认]。

### 6.4 重试

每个 (rate, cdn) 最多请求 2 次（douyu_site.dart:325-361）：
1. 第 1 次之前，按需续期会话（§8.2）。
2. 第 1 次失败后强制续期会话；第 2 次强制刷新描述符。
3. 仍然失败，则这条 CDN 记为失败。
4. 接口明确返回 `error != 0` 时不重试，直接失败。例如 `error=-5`（`房间未开播`，S10-offline）是下播，重试也不会成功（douyu_site.dart:205-206）。旧版对 `-5` 也重试，多发一次 H5 请求、一次续期和一次描述符刷新（DIAGNOSIS.md:90）。

日志只记录“请求形状”：出现了哪些 Cookie 字段名、DID 从哪里来。不记录任何值（douyu_utils.dart:544-568）。

### 6.5 组装媒体地址

所有值先做 HTML 实体解码（`&amp;` → `&`）。然后按以下顺序取第一个可用的地址（douyu_site.dart:396-427）：

1. `rtmp_live` 本身就是 http、https 或 rtmp 的绝对地址时，直接使用（douyu_playback_parser_test.dart:102-110）。
2. 以 `rtmp_url`（其次 `flv_url`）为基址，与 `rtmp_live` 拼接，拼接时去掉多余的斜杠（:89-100, 112-119）。
3. `player_1`、`stream_url`、`url` 中的绝对地址。
4. `flv_url` 本身的路径以 `.flv`、`.m3u8` 或 `.mp4` 结尾时，直接使用。

以上都不满足，就是“没有可播地址”。**CDN 基址绝不能直接当作媒体输入**（douyu_playback_parser_test.dart:120-127）。录到的 7 个成功响应都是第 2 种：`rtmp_url` 基址加相对的 `rtmp_live`，扩展名 `.flv`，没有 `&amp;`（S08、S09 全部样本）。目前只观察到 HTTP-FLV，是否会返回 m3u8 [待确认]。

### 6.6 DID 一致性

- 以下三处必须使用**同一个 DID**（douyu_utils.dart:164-168, 355-365, 523-542）：
  - 描述符请求的 `did` 参数；
  - 签名表单的 `did`；
  - 所有请求 Cookie 中的 `dy_did` 和 `acf_did`。
- DID 的来源（:113-115, 187-191；platform_signing_utils_test.dart:51-77）：
  - 账号 Cookie 里有 `dy_did` 时，用它；
  - 否则用一个进程级随机值：32 位小写十六进制，用安全随机数生成，进程内保持不变。
- DID 不一致的后果：边缘节点直接返回 403（§9）；已登录也会被当成游客（platform_signing_utils_test.dart:63-64）。
- 常量 `10000000000000000000000000001501` 只是测试里的默认值，生产代码不使用（douyu_utils.dart:37, 607）。

### 6.7 请求头

**API 请求**（描述符、H5 取流、搜索、续期）（douyu_utils.dart:509-519）：

| 头 | 值 |
|---|---|
| `accept` | `application/json, text/plain, */*` |
| `accept-language` | `zh-CN,zh;q=0.9,en;q=0.7` |
| `origin` | `https://www.douyu.com` |
| `referer` | `https://www.douyu.com/<rid>`；没有房间时为 `https://www.douyu.com/` |
| `user-agent` | 桌面 Chrome（旧值为 Chrome/128，:41-44） |
| `cookie` | 见下 |

**Cookie 组装**（:521-542；douyu_cookie_session_test.dart:346-374）：
- 最前面固定是 `dy_did=<DID>; acf_did=<DID>`，后面接账号 Cookie 的其余字段。
- 以下内容去掉：账号 Cookie 里原有的 `dy_did` 和 `acf_did`、**`LTP0`**、名称不合法的字段、开头的 `Cookie:`、控制字符。
- 字段值原样转发，不做解码，例如 `%2B` 保持原样（:137-143）。

**媒体请求**（CDN 上的 FLV）（douyu_utils.dart:592-597；playback_header_resolver.dart:68-69）：
- 带 `origin`、房间 `referer`、`user-agent`、`cookie`，值与 API 请求相同。
- 播放、多画面、纯音频、录制共用同一份请求头（RELEASE_NOTES.md:1258；docs/ISSUE_AUDIT_2026_08_25.md:15, 19）。
- 拼接探针不带任何请求头，也能正常拉流（tool/probes/douyu_splice_probe_test.dart:61）。CDN 是否真的需要 Referer 和 Cookie [待确认]；如果不需要，v4 不应把账号 Cookie 发给 CDN 主机。

### 6.8 租期

**何时有租期**
- 媒体 URL 的查询串里带 `expire=<秒>` 且大于 0 时，才有租期（douyu_site.dart:36-39；douyu_parse.dart:247-249）。
- 匿名时按确认档位区分（2026-09-27 样本）：
  - rate 4（文件名 `_4000.flv`）带 `expire=300`：24422 的 hw-h5、hs-h5 两条线路，4489985 的 hw-h5，以及两个房间的元数据响应（S09-24422-r0-hw-h5、S09-24422-r0-hs-h5、S09-4489985-r0-hw-h5、S08-meta-*）。以前说的“匿名原画 `expire=300`”，其实是原画被降到 4 以后的地址。
  - rate 2（文件名 `_900.flv`）带 `expire=0`，没有租期（S09-24422-r2-hw-h5）。
  - rate 0 未降档的地址、rate 3、登录后是否带 `expire`、时长多少 [待确认]（RELEASE_NOTES.md:36 说登录后链接更长）。
- `expire` 缺失或为 0 的地址没有租期，不做定时续期，连接 EOF 后再重新取流。

**Lease 的取值**（:50-64）

| 字段 | 值 |
|---|---|
| `issuedAt` | 发起 H5 请求之前的本地时间（:308, 317）。链接里没有绝对时间，这个取法偏保守 |
| `invalidAt` | `issuedAt + expire` |
| `refreshAt` | `invalidAt − min(45 s, expire / 4)`。expire=300 时，即签发后 255 s |
| `cutsConnection` | `true` |

**到期行为**
- CDN 在第 300 秒断开**已经建立的连接**（RELEASE_NOTES.md:36, 63；docs/rewrite/diagnosis/03-live-room-multiview-danmaku.md:137）。
- 断开时间是从签发起算还是从连接建立起算，没有直接测量过 [待确认，见 S11]。按签发起算不会晚于实际断开，v4 采用这种算法。

**续期**
- 续期是：对同一房间、同一 rate（当前线路的**确认** rate）、同一 CDN 码，重新签名，取一条新地址（docs/DOUYU_SOURCE_RECOVERY_AUDIT_2026_09_06.md:11）。
- v4 续期只签这一条线路。
- 旧实现续期时会重新取元数据、签全部 CDN，再按下标选线（douyu_site.dart:220-247；player_controller.dart:347-354；multiview_controller.dart:224-231）。这样请求多，而且下标可能指到另一个 CDN。

**时间线**
- 同一房间两次签发的地址，时间戳在同一条时间线上，可以直接接续（flv_splice_relay.dart:91-93；RELEASE_NOTES.md:7）。
- 不同 CDN 之间是否也共享同一时间线 [待确认]。

**按关键帧拼接**（flv_splice_relay.dart:84-319；test/flv_splice_relay_test.dart）

1. 到 `refreshAt` 时取新地址并建立连接，旧连接继续转发。
2. 读新连接：
   - 跳过文件头；
   - 记下视频解码配置（AVC/HEVC 序列头，或 Enhanced FLV 的 SequenceStart）和 AAC 配置；
   - 找第一个关键帧，要求它的时间戳（加上偏移后）大于已经送出的最后一个视频时间戳。
   - 等首包、找关键帧各有 15 s 超时（:227-234）。
3. 时间线检查（:117-119, 245-248；测试 :131-153）：
   - 新连接第一个视频时间戳与已送出位置相差不超过 60 s 时，偏移为 0；
   - 否则平移时间戳，使新连接从“已送出位置 + 1 ms”接上。
4. 旧连接继续送，直到视频时间戳 ≥ 切换点为止；切换点之后的旧音频丢弃；最多等 10 s（:103, 258-271）。
5. 关闭旧连接（:282-288；测试 :106, 155-178）：
   - 解码配置有变化时，先补发新配置，时间戳等于切换点；
   - 然后发出关键帧；
   - 配置没有变化时不重复发送。
6. 切换之后（:293-309）：
   - 不再转发 script tag；
   - 丢弃时间戳回退的视频包；
   - 丢弃时间戳没有增加的音频包。
7. 新地址还没准备好、旧连接就先断了：从新连接的下一个关键帧接上，最多跳过一个 GOP（:94；测试 :109-129）。
8. 续期失败（:146-151；测试 :180-197；RELEASE_NOTES.md:7）：
   - 保留旧连接，播到它结束为止；
   - 结束后交给上层重新取流。
   - 旧连接先结束、续期又失败时，会话会直接退出，所以外层需要一个会话循环（04-recorder.md:130；ADR 0005 决定 1）。
9. 同一租期上的多个下游会话，只共享一次续期请求（:375-385）。
10. 只对满足以下全部条件的地址做拼接（:341-351；测试 :199-206）：http 或 https；路径以 `.flv` 结尾；`expire` 大于 0；有 `refreshAt`。

**真实流测量**
- 探针每 60 s 换一次地址，读 150 s，共换源两次（RELEASE_NOTES.md:26；douyu_splice_probe_test.dart:36-114）：
  - 视频 DTS 最大间隔 34 ms，即一帧；
  - 音频最大间隔 24 ms；
  - 没有时间戳回退。
- Windows 便携版：单个直播间打开约 4 分钟后换到新连接，前后画面连续；多画面格子也完成了换源（RELEASE_NOTES.md:27）。
- 对照：3.2.10 采用断开后再重连，到期时会卡 1～2 秒（RELEASE_NOTES.md:55）。
- 还没做：30 分钟录制，DTS 最大间隔不超过一帧的门禁（ADR 0005 决定 6；04-recorder.md:145）。

**录制**
- 录制和播放共用拼接后的输出，续期不再新开一次录制尝试（ADR 0005 决定 1）。
- 旧实现大约每 255 s 新开一段，段与段之间有缺口（04-recorder.md:77）。

---

## 7. 弹幕

### 7.1 连接

- 地址：`wss://danmuproxy.douyu.com:8506`。只有这一个地址，不带额外请求头（douyu_danmaku.dart:45, 63-89）。
- 走应用的代理设置（web_socket_util.dart:19-24）；握手超时 10 s（:170）。
- 连接就绪后依次发送（:92-95）：

```text
type@=loginreq/roomid@=<rid>/
type@=joingroup/rid@=<rid>/gid@=-9999/
```

- 匿名连接，不需要账号。
- 心跳：每 45 s 发送一次 `type@=mrkl/`（:21, 97-101）。
- 超过 135 s 没有收到任何消息，就判定断线并重连。135 s 即 max(3 × 心跳间隔, 90 s)（web_socket_util.dart:239-259）。

### 7.2 包格式

所有整数都是小端（douyu_danmaku.dart:213-264）：

```text
len(4) len(4) type(2) encrypt(1)=0 reserved(1)=0 body '\0'
len = 8 + body 的 UTF-8 字节数 + 1
```

- 客户端发出的包 type 为 689。
- 一个 WebSocket 帧里可能有多个包，要按 `len` 逐个切开。`len < 9` 或长度越界时停止切分（测试 :7-22）。
- 旧实现用 UTF-16 长度计算 `len`（:222-223），只对 ASCII 内容正确；v4 必须用 UTF-8 字节数。
- 服务端包的 type（一般认为是 690）旧实现不做校验 [待确认]。

### 7.3 STT 编码

- 格式：`key@=value/` 依次连接（:266-300）。
- 值中的转义：`@` 写成 `@A`，`/` 写成 `@S`。
- 嵌套结构是经过转义的 STT 字符串，解码时需要递归。示例见测试 :92-95。
- 数组用 `//` 分隔。确切规则 [待确认，以样本为准]。

### 7.4 消息类型

| type | 处理 | 证据 |
|---|---|---|
| `chatmsg` | 见下 | :123-144；测试 :7-46, 75-85 |
| `comm_chatmsg` | 醒目留言，见下 | :159-178；测试 :87-104 |
| `voice_trlt` | 语音醒目留言，见下 | :180-201 |
| `dgb` | 礼物（v4）：`gfn` 名称、`gfid`、`gfcnt` 数量、`nn`/`uid`；`rid` 不同则丢弃；没有价格字段 | 2026-09-27 录制（S13） |
| 其它（`loginres`、`mrkl`、`uenter` 等） | 忽略 | :121-150 |

**`chatmsg`**
- `rid` 不为空且与当前房间不同时丢弃；`rid` 为空时保留。
- `txt` 为空时丢弃。
- 字段：`nn` 昵称、`uid`、`txt` 内容、`col` 颜色、`cst` 发送时间、`cid`。
- `cst` 大于 1e11 时按毫秒处理，否则按秒。
- 消息 id 为 `douyu:<cid>`。

**`comm_chatmsg`**（醒目留言）
- `now`：开始时间，毫秒。
- `cet`：持续时间，秒。
- `cprice`：价格，单位是分，除以 100 得到元。
- 嵌套的 `chatmsg{nn, txt, ic}`；头像为 `https://apic.douyucdn.cn/upload/<ic>_small.jpg`。
- 缺少任一必需字段时忽略这条。
- 价格或时长为 0 的不是醒目留言：2026-09-27 录到同类型的开箱通知（`btype@=pandora`、`cprice@=0`、`cet@=0`、`txt@=-`），旧实现会把它们当成 0 元醒目留言。

**`voice_trlt`**（语音醒目留言）
- 取 `list[0]` 的字段：`acptime` 开始时间（秒）、`etime` 结束时间（秒）、`realPrice`（分，除以 100 得元）、`content`、`un`。
- 头像为 `https://` + `uat[1]`。

**颜色**（`col`，:302-319）

| col | RGB |
|---|---|
| 1 | 255,0,0 |
| 2 | 30,135,240 |
| 3 | 122,200,75 |
| 4 | 255,127,0 |
| 5 | 155,57,244 |
| 6 | 255,105,180 |
| 其它 | 白色 |

某一个包解析失败，不影响同一帧里的其它包（:151-155）。

### 7.5 疑似机器人过滤（默认关闭）

- 判定条件：`chatmsg` 既没有 `dms` 字段，`if` 也不等于 `'1'`（:128-129）。
- 只有用户主动开启时才过滤。开关对每条消息实时生效，不需要重连（测试 :34-73）。
- 旧设置和备份中显式保存过的值原样保留；没有这个字段时按关闭处理（ISSUE_871…md:11-13, 20）。
- 依据：在房间 71415 做了两次 60 秒抓包，分别收到 69 条和 43 条 `chatmsg`，其中 6 条和 5 条会被这条规则过滤（docs/ISSUE_AUDIT_2026_09_04.md:12）。参考实现 bililive-go 和 biliup 都不做这种过滤（ISSUE_871…md:18）。

### 7.6 重连

- 发生错误或连接关闭时重连（web_socket_util.dart:267-292）：
  - 第一次失败时通知一次“正在重连”；
  - 最多重试 8 次；
  - 间隔依次为 2、3、4、5、6、6、6、6 s，即 1 s × (min(次数, 5) + 1)；
  - 收到任何消息后，计数清零；
  - 超过次数就关闭连接，并报告失败。
- 重连成功后，重新发送 `loginreq` 和 `joingroup`（douyu_danmaku.dart:69-74）。
- 换房间或停止时，旧连接的所有事件按代次丢弃（:50, 57-60, 104-113）。
- 错误以类型的形式交出去，不传中文句子（01-sites.md ③-1）。

---

## 8. 登录与 Cookie

### 8.1 令牌与状态

**会话令牌**，按优先级取第一个存在的（douyu_utils.dart:73-77, 219-227；douyu_cookie_session_test.dart:58-62）：`acf_jwt_token` → `acf_auth` → `dy_auth`。

两种令牌的到期判断：

| 令牌 | 来源 | 到期时间 | 证据 |
|---|---|---|---|
| `acf_jwt_token`、`acf_auth` | H5（m.douyu.com），是 JWT | 取 payload 里的 `exp`；不是 JWT 就视为“到期未知” | :229-268 |
| `dy_auth` | 网页（www.douyu.com），不透明 | 保存时间 + 7 天；没有保存时间就视为“未知”，不猜 | :62-65, 253-268；测试 :227-278 |

- `dy_did` 是这个登录所属的设备 id（§6.6）。
- 7 天的时效写在 Set-Cookie 的属性里，用户粘贴的 Cookie 字符串里没有，所以只能记录保存时间（:62-64）。
- 没有令牌的 Cookie 视为已过期，不能当作登录（:270-282）。

**五种状态**（:13-34, 341-353；测试 :98-120）

| 状态 | 条件 |
|---|---|
| none | 没有 Cookie |
| guest | 有 Cookie，但没有令牌 |
| valid | 未到期，或到期时间未知 |
| expiredRefreshable | 已过期，但有 LTP0 和 dy_did，可以续期 |
| expired | 已过期，且无法续期 |

### 8.2 LTP0 / dy_did 续期

**条件**：LTP0 和 DID 都有（:295-318；测试 :163-225）。
- 取值优先级：显式传入的字段 > Cookie 里的字段 > 单独保存的字段。
- 续期用的 DID **不会**回落到进程随机值。

**时机**（:284-293, 453-477；douyu_site.dart:329-332, 354-357）：
- 每次调用 H5 取流接口之前：离到期不足 1 天，或者没有令牌时，先续期；
- H5 请求失败后，强制续期一次；
- 续期本身从不抛错；失败时照常用现有 Cookie 请求，可能以游客身份。

**请求**（:398-433；测试 :188-206, 376-399）：
- GET `https://passport.douyu.com/lapi/passport/iframe/safeAuth?client_id=1&t=<毫秒>&_=<毫秒>&callback=axiosJsonpCallback`
- 使用通用请求头，但 Cookie **只包含** `dy_did=<DID>;LTP0=<LTP0>`。
- 不读响应体，只读 Set-Cookie。

**合并 Set-Cookie**（:367-396；测试 :322-343）：
- 响应没有提到的字段保留，其中包括 LTP0；
- 值为空的字段删除；
- 忽略 Path、Domain、Expires、Max-Age、SameSite、Secure、HttpOnly 这些属性。

**结果**（:435-450；测试 :401-416, 464-475）：
- 响应没有 Set-Cookie：视为没有续期，**不更新**保存时间；
- 合并后没有会话令牌：放弃这次续期，保留原 Cookie；
- 其它情况：保存新 Cookie，并把保存时间记为现在。

纯网页 Cookie 没有 LTP0，永远不会续期（测试 :133-155, 309-319）。

### 8.3 LTP0 只发给 passport

LTP0 不出现在任何其它请求的 Cookie 里（douyu_utils.dart:534-538）。

### 8.4 用户输入与存储

- 用户可以粘贴页面 Cookie，也可以粘贴 passport 请求的 Cookie。应用会从中自动提取 LTP0 和 dy_did，填到单独的字段里（douyu_cookie_controller.dart:25-50）。
- 粘贴的是 passport Cookie 时（没有会话令牌，但含有 `LTP0`、`acf_stk`、`acf_ccn`、`acf_ltkid`、`acf_ssid` 中的任一字段）（:52-99）：
  - 只保存 LTP0 和 DID；
  - 不替换已有的登录 Cookie；
  - 也不作为播放 Cookie 保存，因为这些字段发到播放接口会导致 403。
- 保存登录 Cookie 时，同时记录保存时间（:107-111）。
- 提供“立即续期”操作，用来检查 LTP0 和 DID 是否可用（:118-160）。
- 存储：旧版是明文（docs/rewrite/diagnosis/05-app-shell-data.md:54），v4 加密存储（宪法原则 8）。备份和局域网同步都不包含 Cookie（ISSUE_873…md:20；docs/UPSTREAM_PORT_2026_09_27.md:34）。
- 登录的作用：匿名请求原画可能被降为 4M，登录后能否拿到原画 [待确认]（ISSUE_873…md:26）。弹幕不需要登录。

---

## 9. 错误与风控

| 情况 | 证据 | 映射 |
|---|---|---|
| 网络错误、超时、HTTP 5xx（任何接口） | — | Network |
| H5 接口返回 HTTP 403，没有 API error | 01-sites.md:126；douyu_utils.dart:165-167, 544-548；S10-wrong-did | 正文是 JSON 字符串 `"鉴权失败"`：4 个汉字，加引号和换行共 15 字节，`content-type` 为 `application/json`（S10-wrong-did，故意用错 DID 触发）。以前说的“4 字节”应是 4 个字。先按 §6.4 做一次“强制续期 + 刷新描述符”的重试；仍然 403 就是 **RiskControl**（douyu_parse.dart:157）。附上请求形状（DID 来源、Cookie 字段名），不附任何值 |
| CDN 上的媒体返回 403 或 404 | flv_splice_relay.dart:396-398；04-recorder.md:105 | 不重试旧地址，重新取流。重新取流后仍然 403 时映射为 RiskControl [待确认] |
| H5 返回 `error != 0` | douyu_site.dart:368-372；douyu_parse.dart:161-164 | 不重试（§6.4），映射为 StreamUnavailable，保留原始 `error` 和 `msg`。`-5` 是 `房间未开播`（S10-offline，房间 71415，同时 betard 为 `show_status == 2`，S05-offline），属于房间状态：已知下播时由详情给出未开播，取流只报 StreamUnavailable。其它错误码 [待确认] |
| H5 成功，但没有 `data` 或没有可播地址 | :373-376, 426 | ApiChanged |
| 描述符缺字段、`enc_time` 越界或已过期 | douyu_utils.dart:174-181 | ApiChanged |
| 全部 CDN 都失败 | douyu_site.dart:273-275 | 用最后一条 CDN 的失败类型 |
| 详情接口找不到房间：HTTP 200 加 HTML 页“该房间目前没有开放” | S05-not-found；douyu_parse.dart:117-121 | NotFound |
| 详情接口返回 HTTP 403 | S05-alias-betard；douyu_parse.dart:122 | RiskControl。目前只见过别名输入引起的 403，v4 不会把别名发给 betard（§1） |
| 别名房间页没有 302 到数字 rid | douyu_site.dart:283-290 | NotFound |
| 详情接口结构变化（没有 `room` 或缺关键字段） | :531-535 | ApiChanged |
| 未开播、回放轮播 | §4 | 不是失败，是房间状态 |
| 匿名请求被降档（请求 0，确认 4） | §5.3 | 不是失败，用确认 rate 标注画质 |
| 搜索返回 `error != 0` | :583-585；S04-search-error-blank、S04-search-error-kw；douyu_parse.dart:91-92 | 录到的只有 `error == 1`，`msg` 为 `【kw】kw不能为空`（空关键词还附 `个数必须在1和20之间`）。按 ApiChanged 处理，附原始 `error` 和 `msg`。非空关键词也会间歇返回这个错误（§3），是否应该对它自动重试一次 [待确认] |
| 续期失败 | douyu_utils.dart:456-477 | 不报错，继续以当前身份请求 |
| 弹幕连接失败、重连超过次数 | web_socket_util.dart:276-280 | Network，同时在连接状态流里报告 |
| 调用方取消 | 01-sites.md:145 | Cancelled。取消只影响本次请求 |
| NeedLogin、RegionRestricted、AgeOrPaid | 旧代码中没有对应情形 | 目前不会产生。付费房、密码房的表现 [待确认] |

---

## 10. 踩过的坑

| 编号 | 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|---|
| REG-DOUYU-001 | 原画每 5 分钟断一次；3.2.10 在到期时卡 1～2 秒 | 匿名原画地址带 `expire=300`，CDN 在第 300 秒断开连接 | 租期从签发时刻算，提前 45 s 续签同画质同线路，在新连接的关键帧处拼接 | 31982153（01-sites.md:125）；flv_splice_relay_test；RELEASE_NOTES.md:7, 26, 55 |
| REG-DOUYU-002 | 多画面的斗鱼格子在 300 s 后冻结，不再恢复 | 流结束时 mpv 先发 `playing=false`、再发 `completed=true`，被当成用户暂停；恢复次数一辈子只有 2 次 | 按每一格的播放意图判断是否恢复；恢复次数改为 3 分钟内最多 2 次（由播放层规格承接） | bf570796、42cbded2；02-player.md:164；03-live-room…md:137；RELEASE_NOTES.md:63 |
| REG-DOUYU-003 | H5 接口返回 403，正文只有 JSON 字符串 `"鉴权失败"`（S10-wrong-did） | 描述符、签名、Cookie 用了不同的 DID；LTP0 或 passport 字段混进了播放 Cookie | 三处统一 DID，描述符随 DID 失效；LTP0 只发给 passport；passport Cookie 不当作播放 Cookie | 2c378d76（01-sites.md:126）；douyu_utils.dart:164-185, 534-538；douyu_cookie_controller.dart:85-99 |
| REG-DOUYU-004 | 已登录却被当成游客 | 签名时用进程 DID 覆盖了 Cookie 里登录所属的 `dy_did`（3.2.0 的做法，ISSUE_873…md:21） | Cookie 有 `dy_did` 就用它，没有才用进程 DID | 上游 2e2cb0d4（UPSTREAM_PORT_2026_09_27.md:69）；platform_signing_utils_test.dart:62-77 |
| REG-DOUYU-005 | 画质顺序颠倒 | 把 rate 当码率降序排列，原画（0）排到了最后 | 保持 `multirates` 的原始顺序 | douyu_site.dart:172-175；douyu_playback_parser_test.dart:130-146；RELEASE_NOTES.md:964 |
| REG-DOUYU-006 | 实际拿到的是 4M，界面却显示原画；同一画质下的线路档位不一致 | 丢掉了响应里的 `rate`；把各个 CDN 的地址合并成一个列表 | 按确认 rate 给线路分组，界面显示确认的档位 | 03234c7d（ISSUE_TRIAGE_LEDGER_3_2_0.md:33）；DOUYU_QUALITY_ACK…md:8-10；douyu_quality_ack_test.dart |
| REG-DOUYU-007 | rate 缺失或为小数时被当成原画 | 小数被截断，缺失时回填了请求值 | 标为“未确认”，单独显示 | douyu_site.dart:310-321；douyu_quality_ack_test.dart:114-128 |
| REG-DOUYU-008 | 报“输入流地址格式错误” | 把 `rtmp_url`、`flv_url` 这样的 CDN 基址当成了媒体地址 | 基址必须和 `rtmp_live` 拼接；裸基址不能作为输入 | RECORDER_REPAIR_AUDIT_2026-08-27.md:6-11；RELEASE_NOTES.md:875；douyu_playback_parser_test.dart:112-128 |
| REG-DOUYU-009 | 地址变成 `https://cdn/live/https://…` | `rtmp_live` 已经是绝对地址，又拼了一次前缀 | `rtmp_live` 是绝对地址时优先直接使用 | RELEASE_NOTES.md:780；douyu_site.dart:400-404；douyu_playback_parser_test.dart:102-110 |
| REG-DOUYU-010 | 签名参数损坏 | `rtmp_live` 里含有 HTML 实体 `&amp;` | 先解码 HTML 实体 | douyu_site.dart:398-399；douyu_playback_parser_test.dart:89-95 |
| REG-DOUYU-011 | 暂停约 90 s 后恢复，反复 EOF，最后黑屏 | 恢复时复用旧的地址列表，没有重新签名 | 恢复时重新取元数据并重新签名，按当前确认档位请求；不复用旧地址 | DOUYU_SOURCE_RECOVERY…md:7-11；WINDOWS_DOUYU_GUI_AUDIT_2026_09_06.md:25, 36-44, 53；douyu_playback_parser_test.dart:19-54 |
| REG-DOUYU-012 | 录制被误停 | 详情接口失败，被界面兜底逻辑转成了“未开播” | 详情失败必须作为失败传出去 | 233d858d（01-sites.md:139）；douyu_site.dart:508-515 |
| REG-DOUYU-013 | 录制启动慢 | 开录前把所有画质、所有线路都签了一遍 | 只签当前线路，失败后再推进游标 | RECORDER_REPAIR_AUDIT_2026-08-27.md:7, 13；douyu_site.dart:286-301 |
| REG-DOUYU-014 | 能播放但录制失败 | 录制请求缺少 Referer、Origin、UA 和 DID Cookie；403 被当成永久错误 | 播放和录制共用同一份请求头；4xx 时重新取流 | ISSUE_AUDIT_2026_08_25.md:15, 19；RELEASE_NOTES.md:1258 |
| REG-DOUYU-015 | 每次切画质或线路都重新拿描述符 | `expire_at` 是秒，却按毫秒比较 | 统一用 Unix 秒，提前 30 s 刷新，合并并发请求 | ISSUE_AUDIT_2026_08_24.md:39；platform_signing_utils_test.dart:16-20 |
| REG-DOUYU-016 | Linux 上因缺少 QuickJS 无法播放 | 签名依赖 JS 运行时 | 签名改为纯 Dart 实现 | 7410eb9f（ISSUE_AUDIT_2026_08_24.md:11, 38） |
| REG-DOUYU-017 | 热门房间间歇性漏弹幕 | 一个 WebSocket 帧只解了第一个包 | 按包长逐个切分 | RELEASE_NOTES.md:2100；ISSUE_AUDIT_2026_09_04.md:12；douyu_danmaku_protocol_test.dart:7-22 |
| REG-DOUYU-018 | 弹幕明显比网页少 | 疑似机器人过滤（`dms`、`if`）默认开启 | 默认关闭，由用户显式开启 | 31ee5cd7、4cbb43ba；ISSUE_871…md:7-13；03-live-room…md:151 |
| REG-DOUYU-019 | 上游重构弹幕解码时去掉了过滤开关，3 个协议测试失败 | 上游提交 587994b7 | 撤销该提交，保留开关 | UPSTREAM_PORT_2026_09_27.md:70 |
| REG-DOUYU-020 | 出现别的房间的弹幕 | 没有校验 `rid` | 丢弃 `rid` 与当前房间不同的 `chatmsg` | douyu_danmaku.dart:124-125；douyu_danmaku_protocol_test.dart:24-32；RELEASE_NOTES.md:2097 |
| REG-DOUYU-021 | 一个坏包导致同一帧里后面的消息全部丢失 | 以整帧为单位捕获异常 | 以单包为单位捕获异常 | douyu_danmaku.dart:151-155 |
| REG-DOUYU-022 | Cookie 已过期仍显示已登录；网页 Cookie 被当成游客 | 只看长度，或者只认 JWT | 按令牌类型判断；`dy_auth` 按保存时间 + 7 天计算 | ce49cea3、44c2a940、5b48694d（01-sites.md:129）；douyu_cookie_session_test.dart:122-161, 227-278 |
| REG-DOUYU-023 | 续期一次之后就再也续不上 | 用响应里的字段替换了整个 Cookie，丢掉了 LTP0 | 合并 Set-Cookie，保留响应没提到的字段 | douyu_utils.dart:367-372；douyu_cookie_session_test.dart:394-398 |
| REG-DOUYU-024 | 快过期的 Cookie 被当成刚续期的 | 响应没有 Set-Cookie 也更新了保存时间 | 没有 Set-Cookie 就不算续期 | douyu_utils.dart:435-438；douyu_cookie_session_test.dart:464-475 |
| REG-DOUYU-025 | 粘贴 passport Cookie 后被登出 | passport Cookie 覆盖了登录 Cookie | 只吸收其中的 LTP0 和 DID | douyu_cookie_controller.dart:76-99 |
| REG-DOUYU-026 | 热度显示成了在线人数 | 把 `ol`、`hot` 当作人数 | 标注为热度 | RELEASE_NOTES.md:1284, 2128；live_room_audience_metric_test.dart:8 |
| REG-DOUYU-027 | 用户报告“选了原画却拿到 4M”，被当成客户端缺陷 | 匿名接口对部分高规格房间会降档 | 显示服务端确认的档位；提供可选登录；不把 4M 伪装成原画 | ISSUE_TRIAGE_LEDGER_3_2_0.md:13, 20, 23；ISSUE_873…md:9-15 |

---

## 11. 样本清单

**存放与记录**
- 样本放在 `fixtures/douyu/`。
- 每个样本都要记录：URL、抓取时间、直连还是经 Clash、原始内容的 SHA-256、做过脱敏的字段（06-tests.md ⑥-1）。
- 媒体数据本身不入库，只保存 FLV tag 索引（06-tests.md:108）。

**生成期望值的旧入口**

06-tests.md:161 所说的“斗鱼 7 个”静态解析入口：

| 入口 | 位置 |
|---|---|
| `DouyuSite.parsePlayQualities` | douyu_site.dart:176 |
| `DouyuSite.parsePlayResponse` | :364 |
| `DouyuSite.parseCdnCodes` | :381 |
| `DouyuSite.parsePlayUrl` | :397 |
| `DouyuSite.isLiveRoomPayload` | :566 |
| `DouyuUtils.isEncryptionKeyUsable` | douyu_utils.dart:120 |
| `DouyuUtils.buildSignedData` | :601 |

另外可以直接调用的：
- `DouyuUtils` 的公开静态方法：`sessionExpiry`、`sessionState`、`mergeSetCookieLines`、`cookieHeader`、`decodeJwtPayload`；
- 不联网的弹幕实例方法：`DouyuDanmaku().decodeMessage`、`deserializeDouyuPackets`、`sttToJObject`。

分类、分区房间、推荐、搜索、详情字段映射没有静态入口。要把样本注入 `HttpClient.instance.dio` 的拦截器，再调用实例方法，做法同 douyu_quality_ack_test.dart:27-68。

**样本清单与录制情况**

2026-09-27 直连录制，共 31 个目录，其中 S07、S12 是合成向量（见各自的 README.md）。每个录制样本都有 `body.*`、`meta.json` 和旧版期望值 `expected.json`；v4 解析器的测试是 packages/live_core/test/sites/douyu_parse_test.dart 和 douyu_site_test.dart。

| 编号 | 接口或场景 | 需要覆盖的情况 | 生成期望值的旧入口 | 已录制 |
|---|---|---|---|---|
| S01 | `m.douyu.com/api/cate/list` | 全量 | `getCategores`（实例方法，注入 Dio） | `S01-cate-list`（10 个一级、496 个二级分类） |
| S02 | `mixList/2_<cid>/<page>` | 第 1 页、最后一页、越界页，用来确认总页数字段和空 `rl`；包含 `type != 1` 条目的页 | `getCategoryRooms` | `S02-mixlist-page1`、`S02-mixlist-last`（第 6 页）、`S02-mixlist-beyond`（第 7 页）。**缺**含 `type != 1` 的页：录到的条目全是 1 |
| S03 | `allpage/6/<page>` | 第 1 页、最后一页；确认 `av` 的形态 | `getRecommendRooms` | `S03-allpage-page1`、`S03-allpage-last`（第 218 页）、`S03-allpage-beyond`（第 1000 页） |
| S04 | `searchShow` | 同时有直播中和未开播的结果；第 2 页；会返回 `error != 0` 的关键词 | `searchRooms` | `S04-search-page1`、`S04-search-page2`、`S04-search-mixed`（直播中和 `roomType == 3` 轮播）、`S04-search-empty`、`S04-search-error-kw`、`S04-search-error-blank`。**缺**真正未开播（`isLive != 1`）的结果：录到的关键词没有返回这种条目 |
| S05 | `betard/<rid>` | 直播中；未开播（`show_status=2`）；回放（`videoLoop=1`）；标题以【回放】开头；不存在的房间；别名房间；响应为 JSON 字符串 | `isLiveRoomPayload`（静态）；字段映射用 `getRoomDetailForRefresh` | `S05-live`、`S05-offline`、`S05-replay-videoloop`、`S05-not-found`、`S05-alias-betard`、`S05-alias-redirect`（别名房间页的 302）。**缺**标题以【回放】开头的房间（录制时没找到）；**缺** JSON 字符串形式的响应（录到的都是 JSON 对象） |
| S06 | `getEncryption` | 正常；如果能遇到，再录一个 `is_special=1` | `isEncryptionKeyUsable` | `S06-encryption`。**缺** `is_special=1`：没有遇到 |
| S07 | 签名向量 | 描述符 + rid + tt + did → 表单（使用合成的描述符） | `buildSignedData` | `S07-vectors`（合成，按设计不录制） |
| S08 | `getH5PlayV1`（`rate=-1`、`cdn=''`） | 元数据：`multirates`、`cdnsWithName`、`rtmp_cdn` | `parsePlayResponse`、`parseCdnCodes`、`parsePlayQualities` | `S08-meta-24422`（2 条线路、原画2K60）、`S08-meta-4489985`（1 条线路、原画1080P30） |
| S09 | `getH5PlayV1`（逐个 CDN） | 确认档位与请求相同；被降档（请求 0、确认 4）；缺少 `rate`；`rtmp_live` 是绝对地址；基址 + 相对 `rtmp_live`；含 `&amp;` | `parsePlayUrl`；分组规则用 `resolvePlayUrlsRaw`（注入 Dio） | `S09-24422-r0-hw-h5`、`S09-24422-r0-hs-h5`、`S09-4489985-r0-hw-h5`（降档 0 → 4）；`S09-24422-r2-hw-h5`（请求与确认相同）；`S09-24422-r0-tct-h5`（请求不在列表里的 CDN）。**缺**缺少 `rate`、绝对 `rtmp_live`、含 `&amp;` 三种：线上响应没有出现，由 douyu_parse_test.dart 的无样本规则测试覆盖 |
| S10 | H5 错误 | 未开播房间（`error=-5`？）；故意用错 DID 触发的 403，记录状态码、响应长度、响应内容和响应头 | `parsePlayResponse` | `S10-offline`（`error=-5`，`房间未开播`）、`S10-wrong-did`（403，`"鉴权失败"`） |
| S11 | **两次续签** | 见下 | 没有静态入口。期望值按 §6.8 的规则计算，可复用 flv_splice_relay.dart:39-82 的 tag 解析 | **缺**：`live_cli fixture` 只录单次 HTTP 请求，还没有录制 FLV tag 索引和续签时间线的方式（docs/rewrite/STATUS.md:37） |
| S12 | passport `safeAuth` | Set-Cookie 列表，全部用合成值 | `mergeSetCookieLines`、`sessionExpiry`、`sessionState` | `S12-synthetic`（合成）。**缺**真实响应：没有可用的登录账号，真实 Set-Cookie 的字段组合 [待确认] |
| S13 | 弹幕二进制帧 | `loginres`；`chatmsg` 的各种情况（有 `dms`、没有 `dms`、`if=1`、别的房间的 `rid`、空 `txt`）；`comm_chatmsg`；`voice_trlt`；一帧多包；心跳回应；`uenter`、`dgb` 等其它类型 | `decodeMessage`、`deserializeDouyuPackets`、`sttToJObject` | `fixtures/douyu/danmaku/S13-live`（2026-09-27，`live_cli danmaku --record`，房间 9999，30 s）：`loginres`（客户端 IP 已替换）、147 条 `chatmsg`（含没有 `dms` 的和超过 45 s 的积压）、125 个 `dgb`、一帧多包、`uenter` 等。**缺**：付费的 `comm_chatmsg`、`voice_trlt`、别的房间的 `rid`（录制时没有出现） |
| S14 | CDN 上 FLV 的前 32 字节 | 用 Range 请求，只保存文件头 | —（参照 tool/interface_probe.py:256-268） | **缺**：还没有媒体文件头的录制方式（STATUS.md:37） |

**S11 两次续签的录法**
- 同一个房间、同一个 rate、同一个 CDN，在 t0、t0+255 s、t0+510 s 各签一次。
- 每条连接都记录：签发时刻、连接时刻、断开时刻，以及前 N 个 FLV tag 的索引（类型、时间戳、是否关键帧、配置哈希、大小）。
- 另外录一条“签发后等 120 s 再连接”的，用来判断租期是从签发起算还是从连接起算。
- 如果条件允许，再录一次“续期换到另一个 CDN”的情况，用来确认不同 CDN 是否共享时间线。

**需要脱敏的字段**
- Cookie 的所有值：`dy_auth`、`acf_jwt_token`、`acf_auth`、`LTP0`、`acf_stk`、`acf_ccn`、`acf_ltkid`、`acf_ssid`、`acf_uid`、`dy_did`、`acf_did`、`game_did`、`HMACCOUNT`、`_ga`、`dy_teen_mode` 里的 uid，以及 Set-Cookie 中的所有值。
- 签名材料：`key`、`rand_str`、`enc_data`、`auth`、`did`、`tt`。替换为合成值后，要用合成的描述符重新计算 `auth`，保证签名测试能离线复算。
- 媒体 URL：替换签名查询参数（参数名以样本为准），**保留 `expire`**。CDN 主机名可以换成 `example.test`，但要保留 CDN 码。
- H5 响应里的客户端 IP 在 `data.client_ip`，P2P 签名在 `data.p2pMeta.stream_props[].txSecret` 和 `data.p2pMeta.xp2p_txSecret`；媒体 URL 的签名参数是 `wsAuth`、`token`、`did`。这些都已替换（S08、S09 各样本 meta.json 的 `scrubbed`）。响应头 `x-request-id` 是每次请求的 UUID，不含身份，原样保留。
- 弹幕中观众的 `uid`、`nn`、`ic`、`uat`：按“同一个人对应同一个假名”替换。
- 房间的公开信息（标题、主播名、头像、封面）：按现有 fixtures README 的做法，统一替换或统一保留（06-tests.md:96-106）。
- 旧测试的 `webCookie` 常量里有 `dy_teen_mode` 的 uid 明文（douyu_cookie_session_test.dart:34-38），新样本不要沿用。

---

## 12. 待确认

| # | 问题 | 怎么查 |
|---|---|---|
| 1 | ~~别名能否直接请求 `betard/<别名>`~~：不能，返回 403；别名房间页 302 到 `/<rid>`（S05-alias-betard、S05-alias-redirect，§1）。仍待确认：App 分享和 `m.douyu.com` 分享的真实格式；带 `?rid=` 的专题页 | 收集真实分享文本 |
| 2 | ~~分页的总页数字段~~：mixList 是 `data.pgcnt`，每页 120 条；allpage 的 `pgcnt` 恒为 0，每页 40 条，只能靠空 `rl` 结束（S02、S03，§2）。仍待确认：`rl` 中 `type != 1` 的含义，录到的条目全是 1 | 找含其它 type 的分区补录 S02 |
| 3 | ~~推荐页的 `av` 是不是完整 URL~~：是；分区页的 `av` 是路径（S03-allpage-page1、S02-mixlist-page1，§2.3） | — |
| 4 | ~~搜索是否返回总数~~：返回 `data.total`。~~`roomType == 3`~~：轮播，按回放处理。~~搜索的错误码~~：`error == 1`，`msg` 为 `【kw】kw不能为空`，非空关键词也会间歇出现（S04，§3）。仍待确认：`roomType` 其它取值；非空关键词的 `error == 1` 要不要自动重试一次 | 补录 S04 |
| 5 | ~~房间不存在时 `betard` 的响应~~：HTTP 200 加 HTML 页“该房间目前没有开放”，映射为 NotFound（S05-not-found，§4）。仍待确认：`show_status` 除 1、2 以外的取值 | S05 |
| 6 | 为什么把 `scdn*` 排在最后（录到的响应里没有 `scdn*`）。~~`cdnsWithName[].name` 能否作为显示名~~：是“线路7”这样的编号，可以显示（S08-meta-24422）。新增：请求列表外的 CDN 会被换成别的线路（S09-24422-r0-tct-h5），线路身份是否改用响应的 `rtmp_cdn` | S08，对比各线路的可用率 |
| 7 | H5 接口的错误码表。~~`-5`~~：`房间未开播`，不重试，StreamUnavailable（S10-offline，§6.4、§9）。其它错误码仍待确认 | S10 |
| 8 | ~~403 响应的具体内容~~：JSON 字符串 `"鉴权失败"`，4 个字、15 字节（S10-wrong-did，§9）。仍待确认：CDN 上 403 是否应映射为 RiskControl | S14 之后对照 |
| 9 | 租期从签发起算还是从连接起算。~~非原画档位是否带 `expire`~~：匿名 rate 4 带 `expire=300`，rate 2 是 `expire=0`（S09，§6.8）。仍待确认：未降档的 rate 0、rate 3、登录后是否带、时长多少（RELEASE_NOTES.md:36 说登录后链接更长，但没有测量） | S11；登录账号补录 S09 |
| 10 | 不同 CDN 是否共享时间线；新连接是否从 CDN 缓存的 GOP 开始、落后于旧连接（这是测试替身的假设，flv_splice_relay_test.dart:81） | S11 |
| 11 | CDN 是否需要 Referer 和 Cookie。探针不带请求头也能拉流；如果不需要，v4 不再把账号 Cookie 发给 CDN | S14，对比带头与不带头 |
| 12 | `hevc=1` 时服务端的行为；H5 接口会不会返回 m3u8 | 做一次 S09 变体 |
| 13 | 服务端弹幕包的 type（是否为 690）；STT 数组的确切规则；是否要处理礼物、进场消息；有没有备用弹幕地址或端口 | S13 |
| 14 | 登录后能否拿到匿名时被降档的原画（ISSUE_873…md:26） | 用维护者账号对 24422 这类房间对照 |
| 15 | 斗鱼是否存在付费房、密码房，以及它们的响应（对应 NeedLogin、AgeOrPaid） | 找真实房间 |
| 16 | DID 来源不统一：签名只看 Cookie 里的 `dy_did`（douyu_utils.dart:361-365），续期还会用单独保存的 DID（:305-310）。Cookie 里没有 `dy_did`、但单独保存了 DID 时，签名用进程 DID，续期用保存的 DID。v4 是否应该让单独保存的 DID 也参与签名 | 用只有 passport 字段的账号做对照 |
| 17 | 旧实现续期时按下标选线（player_controller.dart:347-354；multiview_controller.dart:224-231）。v4 已规定按 CDN 码选线；旧做法是否实际导致过串线，目前不知道 | S11 的换 CDN 变体 |
| 18 | 3.2.11 之后，多画面斗鱼格子开播约 30 s 会重新取流一次，原因没查。来源是维护者记录，仓库里没有文档 | 在 Windows 上复现并查日志 |
| 19 | 元数据请求（`rate=-1`）本身返回的地址能否直接当默认线路用，从而省一次签名。S08 显示元数据响应确实带完整地址（确认 rate 4、`expire=300`，线路是 `rtmp_cdn`），还没有验证能否播放 | S08 与 S09 对比 |
| 20 | 描述符请求失败时有没有降级办法；`is_special=1` 在什么条件下出现 | S06 |
| 21 | ~~`betard` 是否必须用 Edge/114 的 UA~~：不必，Chrome/140 的 UA 正常返回（S05-live 等，§4） | — |
| 22 | 30 分钟录制、DTS 最大间隔不超过一帧的门禁（ADR 0005 决定 6）还没有执行 | 第 5 阶段录制验收 |
