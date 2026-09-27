# 平台规格：抖音直播（douyin）

- 平台 id：`douyin`（lib/core/sites.dart:46）；显示名“抖音直播”（lib/core/site/douyin/douyin_site.dart:25）。
- 阶段：第 1 阶段平台规格，首批重写平台（docs/adr/0003-platform-batches.md:14）。
- 能力：推荐、分类目录、直播搜索（不支持主播搜索）、房间详情、取流、弹幕、可选 Cookie 登录、录制。
- 证据口径：`文件:行号` 取自 2026-09-27 工作树；提交哈希取自 docs/ 中的审计记录。旧代码只作参考，本文只描述行为和外部契约。
- 路径简写：`site/` = lib/core/site/douyin/，`utils/` = lib/core/utils/douyin/，`dm` = lib/core/danmaku/douyin_danmaku.dart，`xb` = lib/core/danmaku/xbogus.dart，`url_tool` = lib/common/utils/live_url_tool.dart。

## 1. 房间身份与链接

### 两种 ID

| ID | 形态 | 生命周期 | 用途 | 证据 |
|---|---|---|---|---|
| `web_rid` | 纯数字，网页房间号（常见 11–12 位） | 跟随主播，长期稳定 | **唯一可持久化的房间身份**：收藏、历史、录制任务、分享链接 `https://live.douyin.com/{web_rid}` | site/douyin_site.dart:433,443 |
| `room_id` | 19 位数字（`id_str`） | **每次开播生成新值**，下播后作废 | 弹幕连接、reflow 查询、App 深链 `snssdk1128://webcast_room?room_id=` | site/douyin_site.dart:418-423；dm:119；lib/modules/live_play/services/room_external_opener.dart:152-159 |

### 归一规则（输入 → web_rid）

1. 纯数字且长度 ≤16：视为 web_rid；长度 >16：视为 room_id（site/douyin_site.dart:389-392）。长度阈值 16 是经验值 [待确认]。
2. room_id → web_rid：请求 reflow 信息，取 `data.room.owner.web_rid`（site/douyin_site.dart:404-407）。该 room_id 已结束（`status==4`）时仍用 owner 的 web_rid 重新查询详情（site/douyin_site.dart:418-423）。
3. 链接：
   - `live.douyin.com/{数字}[/…][?…]`：取路径第一段，必须全为数字（lib/modules/search/web_search_room_parser.dart:140-142,173-176）。
   - `www.douyin.com/{数字}`：仅当路径恰好一段且为 1–20 位数字（url_tool:92-98）。`www.douyin.com/`、`/video/{id}`（作品）、`/search/{kw}`（搜索页）**不是**房间（url_tool:95-96；test/live_url_tool_parser_test.dart:43-45；提交 1e4f566e，docs/TOOLBOX_ROOM_LINK_PREFILTER_AUDIT_2026_09_23.md:5-9）。
   - `webcast.amemv.com/…/reflow/{数字}`：数字是 room_id，必须再按规则 2 转成 web_rid。旧的直链路径直接把 room_id 当房间号返回（url_tool:315-317），而短链路径会转换（url_tool:353-378），两者不一致；v4 统一转换。
   - `v.douyin.com/{code}`（分享短链）：逐跳跟随重定向，只允许经过 `v.douyin.com`、`www.douyin.com`、`webcast.amemv.com`，落到 `live.douyin.com` 时按上条取 web_rid，落到 reflow 路径时调 reflow 信息接口取 `owner.web_rid`，并校验它是字符串或整数且全为数字（url_tool:335-386）。短链解析共用一个会话：最多 8 次 HTTP 请求、总时限 12 秒、只读响应头不下载正文、处理 301/302/303/307/308 与相对 Location、拒绝重复/非法/带 userinfo/非 http(s) 目标（docs/LIVE_SHORT_LINK_AUDIT_2026_09_07.md:17-19；url_tool:155-192）。
   - 分享文本：先提取 http(s) URL，去掉结尾的中英文标点（url_tool:55-87）。
4. 短链内 reflow 查询参数为 `app_id=1128, verifyFp=, type_id=0, live_id=1, sec_user_id=`（url_tool:356-363），而详情里的 reflow 查询用 `app_id=6383, version_code=99.99.99`（site/douyin_site.dart:648-657）。两种组合都能用：同一个 room_id 分别请求，都返回 `data.room.owner.web_rid`（S05-reflow-shortlink-live、S05-reflow-live）。哪些参数是必需的最小集合 [待确认]。
5. 未覆盖的格式：`www.douyin.com/root/live/{id}`、`www.douyin.com/follow/live/{id}`、`www.iesdouyin.com/share/live/…` 等 [待确认 是否存在、是否需支持]。web_rid 是否可能含非数字字符 [待确认]（旧解析一律要求数字）。
6. 推荐和搜索卡片在缺少 web_rid 时回退用 room_id 作为卡片身份（site/douyin_site.dart:293；site/douyin_search.dart:257）。v4：进入房间或加入收藏前必须先归一成 web_rid，不得持久化 room_id。

## 2. 目录

### 分类

- 来源：`GET https://live.douyin.com/?from_nav=1` 的 HTML。旧实现定位转义文本 `{\"pathname\":\"/\",\"categoryData\":`，按花括号配对截取，再把 `\"` 还原为 `"`、`\\` 还原为 `\`（site/douyin_site.dart:111-139；test/douyin_parser_test.dart:8-17）。
- 页面实际是 React Server Components 的流式载荷：数据分散在多个 `<script …>self.__pace_f.push([1,"…"])</script>` 里（首页 10 段，S01-home）。把各段字符串按顺序拼接后，按行拆成 `id:<JSON>` 或 `id:T<十六进制字节数>,<文本>` 两种行；值里的 `"$<十六进制>"` 引用另一行，`"$$…"` 是转义的 `$`，`"$undefined"` 是空值。v4 按这个格式解析，再在 JSON 行里找含 `categoryData` 的对象（douyin_parse.dart:479-586）。
- 结构：`categoryData[]` 每项 `partition{id_str,type,title}` 是一级分类，`sub_partition[].partition{id_str,type,title}` 是二级分区（site/douyin_site.dart:144-158）。
- 还有第三级：二级分区下面可以再有 `sub_partition`，是单个游戏。例如“游戏”（`103,4`）→“射击游戏”（`1,1`）→“和平精英”（`1010032,1`）等 23 个（S01-home）。v4 只把前两级做成目录；第三级不列出，可以经分区搜索找到（第 3 节，S08-partition-search 返回的就是 `1010032,1`）。
- 分区身份 = `(id_str, type)` 二元组（旧实现拼成 `"id_str,type"`，site/douyin_site.dart:146,149）。录到的一级 `type` 都是 4，二、三级都是 1；取值含义 [待确认]。
- 每个一级分类在子分区列表**最前面**插入它自己，作为“该分类全部”入口（site/douyin_site.dart:159-170）。旧界面对抖音把二级分区平铺显示（lib/modules/areas/areas_list_controller.dart:16）。
- 标记缺失或结构不符 → `ApiChanged`。

### 分区房间

- `GET https://live.douyin.com/webcast/web/partition/detail/room/v2/`，带 a_bogus 签名（第 6 节）。参数：`aid=6383, app_name=douyin_web, live_id=1, device_platform=web, language=zh-CN, enter_from=link_share, cookie_enabled=true, screen_width=1980, screen_height=1080, browser_*…, count=15, offset=(页-1)*15, partition, partition_type, req_from=2`（site/douyin_site.dart:182-205）。
- 分页：每页固定 15 条，忽略调用方的页大小；按 offset 翻页。旧代码不读“是否还有更多”字段。
  - 响应的 `data.count` 是**本页**条数，`data.offset` 是**下一页**的 offset，没有 `has_more` 和总数：第 1 页 `count 15, offset 15`，第 2 页 `count 15, offset 30`（S03-partition-p1、S03-partition-p2）；越界页（offset=1500）`count 0, offset 0, data []`（S03-partition-empty）。
  - v4 用不透明游标，内含下一页的 `data.offset`；`count` 为 0 或 `offset` 没有前进就结束（douyin_parse.dart:100-141）。
- 条目：`data.data[]`，`web_rid` 在条目顶层；`room.title`、`room.cover.url_list[0]`、`room.owner.nickname`、`room.owner.avatar_thumb.url_list[0]`、条目 `tag_name` 为分区名；人数见第 4 节（site/douyin_site.dart:207-231）。列表内房间一律视为直播中（site/douyin_site.dart:217-219）。
- 列表里的 `room.status` 没有意义：在播的房间也是 0（S03-partition-p1 的 15 条、S08-partition-rooms-amemv 的 20 条都是 0）。不能拿它判断状态。
- 签名：
  - `live.douyin.com` 上不带 a_bogus 请求，返回 HTTP 200、空正文，响应头带 `bdturing-verify` 和 `x-vc-bdturing-parameters`（`{"code":"10000",…,"type":"verify","subtype":"whirl",…}`），是滑块验证，映射为 RiskControl（S08-partition-rooms-unsigned）；
  - 带 a_bogus 正常返回（S03）；
  - 换用 `webcast.amemv.com` 主机不签名也能取到数据（S08-partition-rooms-amemv；site/douyin_search.dart:445-481；tool/interface_probe.py:606-640）。这个主机上请求 `count=30` 实际给 20 条，`tag_name` 为空。

### 推荐

- `GET https://live.douyin.com/webcast/feed/`，不签名，参数 `aid=6383, app_name=douyin_web, need_map=1, is_draw=1, inner_from_drawer=0, enter_source=web_homepage_hot_web_live_card, source_key=web_homepage_hot_web_live_card`，需带匿名 Cookie（site/douyin_site.dart:237-249）。
- `status_code` 存在且不为 0 → 失败（site/douyin_site.dart:268-271；test/douyin_parser_test.dart:105-107）。
- 两代响应都要接受（site/douyin_site.dart:256-326；test/douyin_parser_test.dart:19-81）：
  - 2026-08 起：`data` 是信封数组，房间在每个信封的 `data` 字段，**可能是 JSON 字符串**，需再解码一次；
  - 旧版：`data.data` 是房间数组；
  - 信封本身也可能直接是房间，或房间在 `room` 字段。判定“像房间”：有 `owner` 对象、`title`、`id_str` 或 `stream_url` 对象（site/douyin_site.dart:344-346）。
- 字段取值顺序：身份 `信封.web_rid → owner.web_rid → room.web_rid → room.id_str → room.id`；标题 `room.title → 信封.title → owner.nickname`；封面/头像取 `url_list` 第一个非空 http(s) 地址（site/douyin_site.dart:292-299,357-369）。
- 分区名：`tag_name` → `partition_road_map[]` / `tags[]` 的 `title|name|tag_name`；都没有时旧实现写死中文“热门推荐”（site/douyin_site.dart:371-385）。v4 返回“无分区”，由界面决定文案。
- 同一身份去重（site/douyin_site.dart:294）。
- 分页：请求不带页码或偏移，每次返回同一批（site/douyin_site.dart:237-249）；旧界面按固定 20 条的单页处理（lib/modules/popular/popular_controller.dart:98-99）。v4：推荐只有一页，不给下一页游标。响应的 `extra` 里有 `has_more: true`、`offset: 0`、`total: 20`（S02-feed），但请求没有偏移参数可用，feed 是否支持偏移 [待确认]。
- feed 里的 `room.status` 也没有意义：20 个在播房间都是 0（S02-feed）。`stats.total_user` 在 20 条里都是 0，是占位（第 4 节）。
- 公开探针另要求推荐里至少有一个房间带可播放描述（`live_core_sdk_data`、`flv_pull_url` 或 `hls_pull_url_map`）和明确的在线人数（tool/interface_probe.py:689-717；docs/STAGE_UPDATE_2_9_6.md:30）。

## 3. 搜索

- 只支持直播间搜索，不支持主播搜索（site/douyin_site.dart:855-858；lib/modules/search/search_capability.dart:124）。关键词先去首尾空白，空词直接返回空（site/douyin_search.dart:563-570）。
- 旧实现按顺序尝试三条路径，前一条“失败或为空”就走下一条，最后所有异常都被吞掉返回空列表（site/douyin_search.dart:563-598）：
  1. 直播搜索 `GET https://www.douyin.com/aweme/v1/web/live/search/`，参数 `device_platform=webapp, aid=6383, channel=channel_pc_web, search_channel=aweme_live, search_source=switch_tab, query_correct_type=1, need_filter_settings=1, list_type=single, keyword, offset, count, os_version=10`（site/douyin_search.dart:319-348）。
  2. 综合搜索 `GET https://www.douyin.com/aweme/v1/web/general/search/stream/`，参数同上但少三项（site/douyin_search.dart:350-375）。响应是流式分块，响应头带 `tt_api_type: STREAM_FORECAST`：正文由若干块组成，每块是“十六进制字节数、换行、一个 JSON 文档、换行”，最后以 `0` 块结束，例如 `5c\r\n{"status_code": 2483, …}\r\n0\r\n\r\n`（S08-general-search-anon）。要逐块解码，不能整体当一个 JSON（douyin_parse.dart:454-477）。旧实现因此报 HttpError。
  3. 分区匹配 `GET https://live.douyin.com/webcast/web/partition/search/?keyword=&aid=6383`，取 `data.SearchResult` 前 3 个分区，再拉这些分区的房间合并（site/douyin_search.dart:377-443）。**这一步返回的是“名称匹配关键词的分区里的房间”，不是关键词匹配的房间。**
- 请求头：桌面 UA、`Referer: https://www.douyin.com/search/{关键词URL编码}?source=switch_tab&type=live`、`Origin: https://www.douyin.com`、`Sec-Fetch-Dest/Mode/Site: empty/cors/same-origin`、Cookie（site/douyin_search.dart:87-99）。三条路径都**不带** a_bogus/msToken。
- 匿名直播搜索会要求登录，旧实现因此回退到分区匹配（tool/interface_probe.py:541）。拒绝时是 HTTP 200、`{"status_code": 2483, "status_msg": "请先登录，再继续搜索吧"}`，直播搜索和综合搜索都一样（S08-live-search-anon、S08-general-search-anon），映射为 NeedsLogin。
- 分区匹配接口匿名可用，`data.SearchResult[].partition` 就是分区（`id_str`、`type`、`title`），例如关键词“和平精英”返回 `1010032,1`（S08-partition-search）。
- 结果解析：条目中的房间可能嵌在 `lives.rawdata`、`lives.raw_data`、`live.rawdata`、`live_info.rawdata`、`aweme_info.live_info.rawdata`、`data.rawdata`、`rawdata`、`lives`、`live`、`live_info`、`aweme_info`、`data` 或条目本身，值可能是 JSON 字符串（site/douyin_search.dart:132-175）。身份优先 `owner.web_rid`，否则回退 room_id；`status==2` 为直播中；按身份去重（site/douyin_search.dart:177-314；test/douyin_search_test.dart:8-52）。
- 分页：`count` 限制在 1–50，`offset = count*(页-1)`；不读服务端的“是否还有更多”（site/douyin_search.dart:320-321）。v4 用 offset 游标 [待确认 结束字段]。
- v4 行为：
  - 必须区分“无结果”和“失败”：直播搜索要求登录 → `NeedLogin`；其它见第 9 节。
  - 是否保留分区匹配作为匿名兜底 [待确认]；若保留，结果必须标明“来自分区匹配”，不得混作关键词结果。
- 网页搜索兜底地址：`https://www.douyin.com/search/{关键词}?type=live`（lib/modules/search/search_controller.dart:127-128）。

## 4. 房间详情

### 获取顺序

1. 输入是 room_id：reflow 信息接口（第 6 节），`data.room` 为房间；若 `status==4`（已结束）改用 owner.web_rid 走步骤 2（site/douyin_site.dart:402-423）。
2. 输入是 web_rid：先调 enter 接口（签名），失败再抓 HTML 页面（site/douyin_site.dart:462-470）。
   - enter：房间 = `data.data[0]`，主播 = `data.user`（下播时 `room.owner` 可能缺失，昵称头像取 `data.user`）（site/douyin_site.dart:475-521；S04-enter-offline）。
     - 房间不存在：HTTP 200，`{"data":{"prompts":"该内容暂时无法无法查看"},"status_code":4001038}`，映射为 NotFound（S04-enter-notfound）。旧实现在这里下标出错，掉进 HTML 兜底，不报“房间不存在”（DIAGNOSIS.md:86）。
     - 不带 Cookie（没有 `ttwid`）时返回 HTTP 200、**空正文**（S04-enter-no-cookie，请求已签名）。所以匿名 Cookie 必须先取好（第 6 节）；仍然空正文映射为 RiskControl（douyin_parse.dart:401-427）。
   - HTML：先 `HEAD https://live.douyin.com/{web_rid}` 收集 `ttwid`、`__ac_nonce`、`msToken` Cookie，再 `GET` 同一地址，用正则取出转义的 `{\"state\":{\"appStore…]\n` 段并还原；房间 = `state.roomStore.roomInfo.room`，主播 = `state.roomStore.roomInfo.anchor`，访客 ID = `state.userStore.odin.user_unique_id`（19 位才采用）（site/douyin_site.dart:526-571,587-625）。
     - 房间页和首页一样是 RSC 流式载荷（25 段 `self.__pace_f.push`，S06-room-html-live），格式见第 2 节。值里的 `"$<十六进制>"` 必须解析：`stream_url.live_core_sdk_data.pull_data.stream_data` 在页面里就是 `"$13"`，指向 13 号文本行（`13:T38c8,{…}`）。旧实现只做字符串替换，不解析引用，`stream_data` 解不出来，只剩旧的 `FULL_HD1/HD1/SD2/SD1` 四档，`MD` 丢失（douyin_parse.dart:266-301, 566-586）。
3. 旧实现的最后一个错误原样抛出，不返回“状态未知”的房间（site/douyin_site.dart:395-400）；录制和多画面依赖这一点（docs/RECORDING_AUDIT_3_0_13.md:45；docs/ISSUE_866_DOUYIN_MULTIVIEW_AUDIT_2026_09_15.md:42-43）。v4 保持：详情永不吞错。

### 字段

| 输出 | 来源 | 备注 |
|---|---|---|
| 房间身份 | web_rid | 始终返回 web_rid（site/douyin_site.dart:433,495,545） |
| 本场 room_id | `room.id_str` | 弹幕、深链用；每场不同 |
| 标题 | `room.title` | |
| 封面 | `room.cover.url_list[0]` | 仅直播中；下播为空（site/douyin_site.dart:435,497,547） |
| 主播昵称/头像 | 直播中取 `room.owner`；下播取 `data.user`（enter）或 `anchor`（HTML） | site/douyin_site.dart:498-501,548-551 |
| 简介 | `owner.signature`（HTML 路径旧实现误填标题；录到的房间页没有这个字段，S06-room-html-live） | site/douyin_site.dart:447,511,561 |
| 分区 | 旧实现留空 | enter 的 `data.partition_road_map` 在录到的 3 个样本里是空对象或缺失（S04）；是否有可用字段 [待确认] |
| 流描述 | `room.stream_url` 整体保留 | 仅直播中；解析见第 5 节 |
| 访客 ID | 见第 8 节 | 弹幕用 |

### 直播状态

- `room.status == 2` 为直播中，其它值一律按下播处理；`status` 可能是整数或数字字符串（site/douyin_site.dart:416,425,487,536）。enter 里还有 `status_str`，与 `status` 相同。
- `4` 表示本场已结束（site/douyin_site.dart:418-423；S04-enter-offline、S05-reflow-ended）。其它取值（例如主播暂离、预告）的含义与映射 [待确认]。
- enter 响应另有 `data.room_status`：0 为直播中，2 为已结束（S04-enter-live 是 `status 2` + `room_status 0`；S04-enter-offline 是 `status 4` + `room_status 2`）。两者一致；v4 以 `room.status` 为准，只在它缺失时看 `room_status`（douyin_parse.dart:617-625）。
- 列表和 feed 里的 `room.status` 是 0，与是否在播无关（第 2 节），只有 enter、reflow 和房间页的 `status` 有意义。
- 没有回放概念。下播是房间状态，不是失败。

### 人数口径（user_count 的含义）

旧规格把 `room_view_stats.display_value` 一律当累计观看，这是错的（DIAGNOSIS.md:84）。`room_view_stats.display_type` 决定它的口径：

| `display_type` | `display_value` 的含义 | 文案 | 证据 |
|---|---|---|---|
| 1 | **在线观众**（并发） | `display_long: "2268在线观众"` | S04-enter-live-portrait；S02-feed 20 条里 19 条是 1 |
| 3 | **累计观看** | `display_long: "3055.0万人看过"` | S04-enter-live |
| 其它 | 不使用 | — | douyin_parse.dart:627-632 |

- **在线（并发）**：按顺序取第一个可用的值（douyin_parse.dart:631-647）：`room.user_count`、`room.online_user_count`、`room.online_user_for_anchor`、`display_type == 1` 时的 `room_view_stats.display_value`、`room_view_stats` 和 `stats` 下的 `user_count`、`online_user_count`、`online_user_for_anchor`、`stats.user_count_str`、`room.user_count_str`。`0` 也是有效值（test/douyin_audience_metric_test.dart:6-26）。
  - **精确整数优先于分档文本**：先在所有候选里找整数（含数字字符串），都没有才解析“1.2万”这类文本。enter 的 `room.user_count_str` 是分档的 `"2000+"`，同一房间的 `stats.user_count_str` 是精确的 `"2665"`（S04-enter-live），取后者。旧实现没有 `room.user_count` 时取了分档文本（DIAGNOSIS.md:85）。
- **累计观看**：`display_type == 3` 时的 `room_view_stats.display_value`，其次 `room_view_stats`、`stats`、`room` 下的 `total_user`、`total_user_str`，只接受大于 0 的（douyin_parse.dart:648-656）。`total_user` 为 0 是占位，不能当 0 人：feed 20 条的 `stats.total_user` 全是 0（S02-feed；docs/STAGE_UPDATE_2_9_7.md:17）。
- 两个口径**绝不互相顶替**（test/douyin_audience_metric_test.dart:28-52；docs/PLATFORM_COMPATIBILITY.md:45）。值可能是带单位的文本（如“1.2万”“4万+”）。
- 下播房间两个口径都为空（site/douyin_site.dart:426-427；S04-enter-offline 没有 `room_view_stats`）。
- 抖音没有“热度”口径；旧应用默认显示累计观看（lib/common/models/live_room.dart:61-65,629）。旧实现不看 `display_type`，把 display_type 1 的在线人数当成了累计观看（lib/core/site/douyin/douyin_audience.dart:42）。

## 5. 画质与线路

### 数据来源（均在详情的 `stream_url` 内，无需单独请求）

- 新版：`stream_url.live_core_sdk_data.pull_data.stream_data` 是 **JSON 字符串**，解码后 `data.{sdk_key}.main.{flv,hls,sdk_params}`；描述在 `pull_data.options.qualities[]`（`name, sdk_key, level, v_bit_rate, resolution`）（site/douyin_site.dart:676-694）。
- 旧版：`stream_url.flv_pull_url.{key}`、`stream_url.hls_pull_url_map.{key}`，名称在 `stream_url.resolution_name.{key}`（site/douyin_site.dart:696-704）。
- 两者**只按 sdk_key 关联，不按 JSON 顺序配对**；键名不分大小写，画质 id 用小写 sdk_key（site/douyin_site.dart:668-674,706-716,770,806-814；test/douyin_playback_parser_test.dart:8-31）。
- `sdk_params` 可能是对象或 JSON 字符串，含 `vbitrate`、`resolution`（site/douyin_site.dart:740,794-804）。

### 规则

1. 候选键 = options 里的 sdk_key ∪ stream_data 键 ∪ flv 键 ∪ hls 键。
2. 每个键收集地址：`main.flv`、`main.hls`、`flv_pull_url[key]`、`hls_pull_url_map[key]`，只收 http/https，去重保序（site/douyin_site.dart:722-730,816-821）。没有任何地址的键不出现（test/douyin_playback_parser_test.dart:33-61）。`main` 里的 `lls`、`cmaf`、`dash` 等其它协议旧实现不读 [待确认 是否存在、是否需要]。
3. **排除纯音频档**：键规范化（小写、去掉非字母数字）后为 `ao`、`audio`、`audioonly`，或该键**所有**地址都带 `only_audio=1|true`（site/douyin_site.dart:732-736,823-832；test/douyin_playback_parser_test.dart:144-176）。
4. 显示名：options 的 `name` → `resolution_name[key]` → 键名；中文名原样使用，英文键映射为：`origin/origion`→原画，`full_hd1/uhd`→蓝光，`hd/hd1`→超清，`sd/sd2`→高清，`ld/sd1`→标清，`md`→流畅（site/douyin_site.dart:738-769；lib/core/utils/live_quality_label.dart:51-60）。v4 只返回画质 id 与语义等级，文案由界面决定。
   - options 的名称跟着 `level` 和实际分辨率走，同一个键在不同房间叫法不同：横屏 1080p 房间是 `ld` 标清、`sd` 高清、`hd` 蓝光、`origin` 原画（S04-enter-live）；竖屏房间是 `hd` 超清、`origin` **蓝光**（1088×1920，S04-enter-live-portrait）。所以名称不能由键推出，有中文名时用平台给的。
   - `stream_data` 里的 `md` 在 options 里没有条目（两个 enter 样本都是），名称只能按键映射成“流畅”。
5. 顺序（高→低）：`ORIGION/ORIGIN` > `FULL_HD1/UHD` > `HD1/HD` > `SD2/SD` > `SD1/LD` > `MD`；未知键按 `level`，再按 `v_bit_rate`；同级按 id 字母序（site/douyin_site.dart:747-756,777-780,834-842）。**码率只作元数据，不决定顺序**：原画的瞬时码率可能低于转码档（test/douyin_playback_parser_test.dart:63-100；docs/RECORDING_AND_QUALITY_AUDIT_3_0_12.md:12）。旧实现里未知键的 `level*1000000` 可能与已知键的等级值相撞 [待确认 level 与已知键的对应]。
6. 别名去重：地址集合完全相同的两个档（如 `ORIGION` 与 `origin`）只保留排序靠前的一个（site/douyin_site.dart:782-791；test/douyin_playback_parser_test.dart:102-142）。
7. 主播只提供一档时只显示一档（docs/RECORDING_AND_QUALITY_AUDIT_3_0_12.md:26）。
8. 线路：同一画质下的地址顺序就是线路顺序，通常“线路 1 = FLV、线路 2 = HLS”（site/douyin_site.dart:725-730；实机两条线路 docs/ANDROID_RUNTIME_AUDIT_3_1_8_K90PRO.md:94）。v4 每条线路标明格式（flv/hls），不按下标识别线路。
9. 默认画质：`options.default_quality.sdk_key` 或 `stream_url.default_resolution`（lib/player/core/live_stream_geometry_hint.dart:55-61）；是否作为起播默认 [待确认]。

### 编码（H.264 / H.265）

- 实测抖音同时出现 H.264（实机录制 docs/ANDROID_RUNTIME_AUDIT_3_1_8_K90PRO.md:101,111）和 HEVC（竖屏样本 1088×1920，docs/STAGE_UPDATE_3_0_9.md:14）。
- 旧实现不读编码，也不按编码分组。v4 每条线路记录编码，来源有两处，取值一致（douyin_parse.dart:883-889）：
  - `stream_data.data.{key}.main.sdk_params.VCodec`：`h264` 或 `h265`；
  - `options.qualities[].v_codec`：`264` 或 `bytevc1`（字节的 HEVC）。
  - feed 里 HEVC 很常见：`stream_data` 的 123 个档位里 81 个 `VCodec` 是 `h265`、42 个是 `h264`；options 里 81 个 `v_codec` 是 `bytevc1`、2 个是 `264`（S02-feed；douyin_parse_test.dart 核对了两处一致）。录到的 enter 样本都是 H.264（S04-enter-live、S04-enter-live-portrait）。
- 抖音 FLV 里的 HEVC 用增强型 FLV 还是国内 codec id 12 扩展 [待确认]；若是后者，需走 live_media 的 HEVC 标签转写（参考 docs/PLATFORM_PROBE_2026_09_25.md 的 Shopee 记录）。
- enter 请求带 `is_need_double_stream=false`（site/douyin_site.dart:636），与双画面、编码的关系 [待确认]。

### 几何提示

- 竖横屏/宽高只取**当前选中线路**所属 sdk_key 的 `sdk_params.resolution`，其次该档在 options 里的 `resolution`（lib/player/core/live_stream_geometry_hint.dart:71-93）。
- 已选中具体地址却关联不到 sdk_key 时，不借用其它档或默认档的尺寸（同上:95-98）。比较地址时忽略旧解析器追加的 `codec` 参数（同上:219；docs/STAGE_UPDATE_3_0_8.md:26）。
- `stream_orientation` 不是横竖屏，是双画面候选选择；顶层 `stream_url.extra.width/height` 也用于 256×256 音频占位，二者都不能作为比例依据（docs/STAGE_UPDATE_3_0_8.md:11-17）。

## 6. 取流与签名

抖音的播放地址随详情一起返回。“取流”= 获取详情（第 4 节）+ 解析 `stream_url`（第 5 节）+ 给每条线路附上请求头和租期。

### 接口一览

| 用途 | 请求 | 签名 | 证据 |
|---|---|---|---|
| 匿名 Cookie、分类 | `GET https://live.douyin.com/?from_nav=1` | 无 | site/douyin_site.dart:68-83,135-139 |
| 推荐 | `GET https://live.douyin.com/webcast/feed/` | 无 | site/douyin_site.dart:237-249 |
| 分区房间 | `GET https://live.douyin.com/webcast/web/partition/detail/room/v2/` | a_bogus + msToken | site/douyin_site.dart:182-205 |
| 详情（web_rid） | `GET https://live.douyin.com/webcast/room/web/enter/?app_name=douyin_web&enter_from=web_live&live_id=1&web_rid=…&is_need_double_stream=false` | a_bogus + msToken | site/douyin_site.dart:629-643 |
| 详情（room_id） | `GET https://webcast.amemv.com/webcast/room/reflow/info/?type_id=0&live_id=1&room_id=…&sec_user_id=&version_code=99.99.99&app_id=6383` | 无 | site/douyin_site.dart:647-661 |
| 详情兜底 | `HEAD` + `GET https://live.douyin.com/{web_rid}` | 无 | site/douyin_site.dart:587-625 |
| 搜索 | 见第 3 节 | 无 | site/douyin_search.dart |
| 账号 | `GET https://live.douyin.com/webcast/user/me/?aid=6383` | 无 | site/douyin_site.dart:85-109 |

### 通用请求头

- 接口：`User-Agent`（桌面 Chrome 134，utils/douyin_request_params.dart:2-4）、`Referer: https://live.douyin.com`、`Authority: live.douyin.com`（非标准头，是否必要 [待确认]）、`Cookie`（site/douyin_site.dart:30-43,45-66）。
- 账号接口另带 `accept: application/json, text/plain, */*`、`accept-language: zh-CN,zh;q=0.9,en;q=0.8`（site/douyin_site.dart:91-96）。
- 旧代码里 UA 版本各处不一：接口 Chrome 134、搜索 Chrome 120（site/douyin_search.dart:10-12）、播放 Chrome 140（lib/player/core/playback_header_resolver.dart:33-36）、签名参数声称 Edge 125（utils/douyin_utils.dart:32-33）、a_bogus 默认 Edge 130（utils/abogus.dart:613）。v4 用一个 UA；**签名时使用的 UA 必须与实际发送的 UA 完全相同**（a_bogus 把 UA 编进签名，utils/abogus.dart:651-657）。`browser_name/browser_version` 参数是否必须与 UA 一致 [待确认]。

### 签名参数（a_bogus 请求）

1. 合并基础 URL 已有查询和调用参数（不修改调用方的参数表，test/platform_signing_utils_test.dart:89-104），再强制设置 `aid=6383, compress=gzip, device_platform=web, browser_language=zh-CN, browser_platform=Win32, browser_name=Edge, browser_version=125.0.0.0`；没有 `msToken` 时补一个（utils/douyin_utils.dart:23-36）。
2. 按表单编码序列化成查询串 Q；对 Q 计算 a_bogus；最终查询串为 `Q&a_bogus={值}`，a_bogus 放最后（utils/douyin_utils.dart:37-40；utils/abogus.dart:729）。旧实现原样拼接 a_bogus（其字母表含 `/`、`-`、`=`，不含 `+`）；是否需要百分号编码 [待确认]。

### msToken

- 旧实现随机生成 184 个字符，字母表 `A–Z a–z 0–9 =`，安全随机源（utils/douyin_utils.dart:12-21；test/platform_signing_utils_test.dart:81-87）。它不是服务端签发的真令牌；服务端下发的 `msToken` Cookie 只在 HTML 兜底路径里被收集（site/douyin_site.dart:598-600）。服务端是否校验 msToken 来源 [待确认]。

### a_bogus（SM3 + RC4）

外部契约：输入（查询串 Q、请求体 B（GET 为空串）、UA、时间、随机数、浏览器指纹），输出 a_bogus 字符串。参考实现 utils/abogus.dart，要点：

- 常量：`aid=6383`、`pageId=0`、盐 `"cus"`、选项 `[0,1,14]`、UA 加密密钥 `[0,1,14]`、两套 64 字符字母表（:510-511）、流加密状态表初值（:46-303）、两张取值顺序表（:516-607）。
- 步骤：
  1. `p = SM3(SM3(Q+"cus"))`，`b = SM3(SM3(B+"cus"))`，`u = SM3(base64(字母表 1, RC4([0,1,14], UA)))`（最后一个不加盐）（:649-657）。
  2. 开始、结束毫秒时间戳拆成字节；与 `p[21],p[22],b[21],b[22],u[23],u[24]`、选项、aid、pageId、指纹长度一起填入字段表（:659-710）。
  3. 按顺序表 1 取值，追加指纹字符串的字节，再追加按顺序表 2 计算的异或校验字节（:712-724）。
  4. 前面加 12 字节随机前缀（3 组，每组由一个 0–9999 随机数派生 4 字节，:19-36），第 3 步结果经状态表流加密（**每次签名都从状态表初值开始**，:340-376；旧实现每次请求新建签名器保证这一点，utils/douyin_utils.dart:24）。
  5. 用字母表 0 编码，补 `=`（:395-424）。
- 浏览器指纹：`innerW|innerH|outerW|outerH|0|screenY|0|0|sizeW|sizeH|availW|availH|innerW|innerH|24|24|Win32`，各值在固定范围内随机（:469-485）。
- 可测性：时间、随机前缀、指纹、msToken 都必须能注入固定值，才能生成金样本（旧实现只有指纹可注入，:610-617）。

### ttwid、__ac_nonce、访客身份

- 匿名 Cookie：`GET https://live.douyin.com/?from_nav=1`，只保留 Set-Cookie 里的 `ttwid` 与 `UIFID_TEMP`，拼成 `name=value; name=value`（site/douyin_site.dart:68-83）。引导请求必须**完整读完响应体**再复用 Cookie，否则紧接着的 feed 会稳定返回假 503（tool/interface_probe.py:580-586,656-658）。
- 并发的首次获取合并成一次请求（site/douyin_site.dart:54-55）。
- `__ac_nonce`：只在 HTML 兜底路径从 `HEAD` 响应收集（site/douyin_site.dart:595-597）。旧实现不计算 `__ac_signature`；页面是否因此返回挑战页 [待确认]。
- 访客 ID（user_unique_id）：19 位数字，形如 `7[3-9]` 开头再加 17 位（取值区间 7.3e18–8e18），**进程内复用同一个**，换房间不换（site/douyin_site.dart:37,409-411,882-892；test/douyin_danmaku_protocol_test.dart:98-104）。HTML 路径拿到 19 位的 `odin.user_unique_id` 时用它（site/douyin_site.dart:531-532）。v4：每个平台保持固定的设备标识（docs/rewrite/PLAN.md:535）；是否跨进程持久化 [待确认]。

### 播放请求头（随每条线路下发）

- `user-agent`（桌面 UA）、`origin: https://live.douyin.com`、`referer: https://live.douyin.com/{web_rid}`（无 web_rid 时用 `https://live.douyin.com/`）、有 Cookie 时带 `cookie`（lib/player/core/playback_header_resolver.dart:84-95；test/multiview_test.dart:349-405）。
- CDN 是否真的校验这些头 [待确认]。旧实现会把用户的登录 Cookie 发给 CDN 主机；v4 按隐私原则，默认只在样本证明需要时才向 CDN 发送 Cookie [待确认]。

### 租期

- 旧实现不给抖音链接任何租期或续期信息（site/douyin_site.dart:20 未实现租期接口；lib/core/interface/live_site.dart:177-193），也就不会走斗鱼那种 FLV 拼接（lib/player/core/flv_splice_relay.dart:341-351 只在站点提供刷新时间时启用）。
- 播放地址的到期时间是**绝对时刻**，录到的都是签发后 7 天，但写法有好几种（S02-feed 的 226 个地址；S04、S05 的地址都带 `expire`）：

| 写法 | 例 | 解释 |
|---|---|---|
| `expire` 十进制 | `expire=1791107488` | Unix 秒 |
| `expire` 十六进制 | `expire=6ac221a0` | Unix 秒 |
| `volcTime`（与 `expire` 同时出现） | `volcTime=1791107488` | Unix 秒 |
| `wsTime` + `keeptime` | 都是十六进制 | `wsTime + keeptime` 是 Unix 秒 |
| `k` + `t` | `t=1791107488` | `t` 是 Unix 秒 |
| `auth_key` | 时间戳在签名串里，样本里已替换 | 读不出到期时间 |

- 现有文档里没有抖音连接中途被切断的记录，实机录制只到约 50 秒（docs/ANDROID_RUNTIME_AUDIT_3_1_8_K90PRO.md:94）。
- v4 租期（douyin_parse.dart:381-396, 891-915）：
  - `issuedAt` = 获取详情的时刻；
  - `invalidAt` = 上表读出的时刻。十进制和十六进制都试，只接受落在签发前 1 天到签发后 31 天之间的值；读不出时没有租期；
  - `refreshAt` = `invalidAt` − min(10 分钟, 寿命的 1/4)；
  - `cutsConnection` = false，到期只预取新地址。到期后已建立的连接会不会被切断 [待确认]：需要一段跨过到期时刻的长时录制样本，确认前**不得**套用斗鱼的“expire 即断开”规则。7 天远长于一次观看，这个问题主要影响长时间录制。
- 恢复：断流后必须重新获取详情拿新地址，不复用缓存地址（同 docs/rewrite/diagnosis/01-sites.md ⑤“恢复时重开了过期地址”）。

## 7. 弹幕

### 连接

- 地址：`wss://{节点}/webcast/im/push/v2/`，节点按顺序 `webcast100-ws-web-lq.douyin.com`、`webcast100-ws-web-hl.douyin.com`（dm:65-73）。
- 查询参数（dm:87-124）：`app_name=douyin_web, version_code=180800, webcast_sdk_version=1.0.15, update_version_code=1.0.15, compress=gzip, cursor=h-1_t-{毫秒时间}_r-1_d-1_u-1, host=https://live.douyin.com, aid=6383, live_id=1, did_rule=3, debug=false, maxCacheMessageNumber=20, endpoint=live_pc, support_wrds=1, im_path=/webcast/im/fetch/, user_unique_id={访客 ID}, device_platform=web, cookie_enabled=true, screen_width=1920, screen_height=1080, browser_language=zh-CN, browser_platform=Win32, browser_name=Mozilla, browser_version={UA 去掉 "Mozilla/" 前缀}, browser_online=true, tz_name=Asia/Shanghai, identity=audience, room_id={本场 room_id}, need_persist_msg_count=15, heartbeatDuration=0, signature={签名}`。
- `room_id` 必须是**本场** room_id，不是 web_rid（dm:119；site/douyin_site.dart:449-454）。
- 握手头：`User-Agent`、`Origin: https://live.douyin.com`、`Referer: https://live.douyin.com/{web_rid}`；Cookie 非空才带（dm:184-192；test/douyin_danmaku_protocol_test.dart:73-96）。
- 日志里 Cookie 一律显示为 `<redacted>`（dm:26-36）。

### 签名（X-Bogus 式）

- 明文：`live_id=1,aid=6383,version_code=180800,webcast_sdk_version=1.0.15,room_id={room_id},sub_room_id=,sub_channel_id=,did_rule=3,user_unique_id={访客 ID},device_platform=web,device_type=,ac=,identity=audience`（按此顺序，逗号连接），取 MD5 十六进制 H（dm:306-324）。
- 编码（xb:91-139）：随机 r1、r2（r2 ∈ 0–254）；`m = MD5(H 按十六进制解码成的 16 字节)`；10 字节负载 `[1&0x3f, 0, 1, 0x0e, 0x45, 0x3f, m[14], m[15], r2, 前 9 字节异或]`，用单字节密钥 r2 做 RC4；输出 `[0x40|(r1&0x1f), r2, 负载…]` 共 12 字节，用字母表 `Dkdpgh4ZKsQB80/Mfvw36XI1R25+WUAlEi7NLboqYTOPuzmFjJnryx9HVGcaStCe` 编成 16 字符（xb:4-5,50-72）。
- 字母表含 `+`、`/`：签名必须作为查询参数值做百分号编码，不能原样拼接，否则 `+` 会被当成空格（dm:168-182；test/douyin_danmaku_protocol_test.dart:50-71）。
- 签名失败时旧实现返回空串并照常连接（dm:330-333）；v4 报连接失败，不静默。服务端是否真的校验 signature [待确认]。
- 可测性：r1、r2 需可注入。

### 故障切换与保活

- 所有节点使用同一份签名和查询参数（dm:126-134,174-182）。
- 断开后轮换到下一个节点；连续失败最多 8 次，每轮完整试完所有节点后等待时间按 1 秒 × (轮数+1) 递增，上限 6 秒；8 次后终止并上报（lib/core/common/web_socket_util.dart:123-125,267-292）。收到任何消息即清零失败计数（同上:261-265）。建连超时 10 秒（同上:170）。
- 心跳：连接就绪后立即发一次，之后每 10 秒发 `PushFrame{payloadType:"hb"}`（dm:41,145-153,194-199,282-286）。
- 静默：45 秒没有收到任何下行消息视为半开连接，主动重连（dm:136；web_socket_util.dart:239-251）。
- 旧实现重连时沿用首次连接的 `cursor` 和 `room_id`；主播重新开播后 room_id 已变，弹幕会被第 7 节的房间过滤全部丢弃 [待确认 是否发生]。v4：终止或长时间无聊天时应重新获取详情确认 room_id。

### 帧格式与解码

- 上下行都是二进制 `PushFrame`（protobuf）：`seqId=1, logId=2, service=3, method=4, headersList=5, payloadEncoding=6, payloadType=7, payload=8`（lib/core/danmaku/proto/douyin.proto:502-511）。
- 下行：`payloadEncoding` 为 `gzip`（不分大小写）**或**负载以 `1f 8b` 开头时 gunzip，否则原样（dm:204-211）；再解为 `Response`：`messagesList=1, cursor=2, fetchInterval=3, now=4, internalExt=5, fetchType=6, routeParams=7, heartbeatDuration=8, needAck=9, pushServer=10, liveCursor=11, historyNoMore=12`（proto:6-19）。
- 每条 `Message`：`method=1, payload=2, msgId=3, msgType=4, …`（proto:21-30），按 `method` 分发。
- ACK：`needAck` 为真时立即回 `PushFrame{payloadType:"ack", logId: 原帧 logId, payload: UTF-8(internalExt)}`，然后继续处理本帧消息（dm:213-216,274-280）。

### 消息类型

| method | 处理 | 规则 |
|---|---|---|
| `WebcastChatMessage` | 聊天 | 内容 `content`，用户 `user.nickName` / `user.id`；消息 id 优先 `common.msgId`，为 0 时用外层 `msgId`，都没有则为空，输出加前缀 `douyin:`；时间 `common.createTime`，>1e11 视为毫秒，否则秒，≤0 为空；`common.roomId` 非 0 且不等于当前 room_id 时丢弃（dm:226-253；test/douyin_danmaku_protocol_test.dart:18-48） |
| `WebcastRoomUserSeqMessage` | 在线人数 | 用 `onlineUserForAnchor`（并发）；`totalUser` 是累计，不得当在线；文本不含数字时忽略（dm:255-272；proto:65-80） |
| 其它（礼物 `GiftMessage`、进场 `MemberMessage`、点赞 `LikeMessage`、关注 `SocialMessage` 等，proto 已有定义 proto:106,200,316,331） | 旧实现忽略 | v4 是否输出 [待确认] |
| 下播控制消息 | 旧实现无定义 | 是否有 `WebcastControlMessage` 及其字段 [待确认] |

- 颜色旧实现一律白色（dm:241-245）；颜色字段含义 [待确认]。

## 8. 登录与 Cookie

- 匿名可用：推荐、分类、分区房间、详情、取流、弹幕都只需匿名 `ttwid`（第 6 节）。
- 可选登录：用户粘贴浏览器 Cookie 字符串，保存前规范化（lib/modules/account/douyin/douyin_cookie_controller.dart:13-17）。有用户 Cookie 时所有请求改用它：接口（site/douyin_site.dart:45-52）、搜索（site/douyin_search.dart:24-35）、弹幕握手（site/douyin_site.dart:449-454）、播放（lib/player/core/playback_header_resolver.dart:84-86）。
- 账号信息：`/webcast/user/me/?aid=6383` 带 Cookie，返回 `data`（昵称等）（site/douyin_site.dart:85-109）。Cookie 变化时重新读取，旧请求的迟到结果丢弃（docs/ACCOUNT_IDENTITY_LIFECYCLE_AUDIT_2026_09_11.md:18,27）。
  - Cookie 失效和不带 Cookie 的响应相同：HTTP 200，`{"data":{"message":"User doesn't login","prompts":"请登录后进入直播间"},"status_code":20003}`，映射为 NeedsLogin（S09-user-me-invalid-cookie、S09-user-me-no-cookie）。旧实现把这份错误数据当成了用户信息（DIAGNOSIS.md:87）。
- 用户 Cookie 被修改或清空后，后续请求必须立刻改用新值或回到匿名；搜索模块做到了（site/douyin_search.dart:37-42），站点主体没有（见 REG-DOUYIN-017）。
- 登录能解锁什么：
  - 直播搜索（第 3 节）；
  - **原画**：匿名只能试看 30 秒。房间页的配置写着 `"trial_text":"原画可试看30s，登录可无限畅享原画画质"`、`"trial_end_text":"30s试看完成，已切换为标清画质"`、`"trial_duration":30`（S06-room-html-live）。匿名的 enter 响应照样给出原画地址（S04-enter-live 的 `origin`）。实机匿名样本出现过没有“原画”的五档菜单（docs/ANDROID_RUNTIME_AUDIT_3_1_8_K90PRO.md:94）。
  - 试看是由网页播放器切档，还是 CDN 在 30 秒后停止供流 [待确认]。
  - 对界面的影响：匿名时原画不是可以一直看的画质。平台给的默认画质 `options.default_quality` 恰好是 `origin`（S04-enter-live、S04-enter-live-portrait），照它起播的匿名用户 30 秒后就会被切档或断流，匿名录制原画也一样。
  - **[决定]** 匿名（没有用户 Cookie）时：默认画质选原画以外最高的一档（通常是“蓝光”）；原画仍然列在菜单里，名称后标“试看 30 秒”，用户主动选择时照常播放；录制不使用匿名原画。登录后按平台默认画质。理由：默认起播就在 30 秒后掉档或断流，比默认低一档更糟；隐藏原画又会让用户以为这个直播间没有原画。
- 存储：Cookie 加密保存，备份默认不含 Cookie（spec/constitution.md 原则 8；docs/rewrite/PLAN.md:532）。日志一律脱敏。

## 9. 错误与风控 → SiteFailure

| 情况 | 旧行为 | v4 |
|---|---|---|
| DNS/连接/TLS/超时 | HTTP 客户端异常 | `Network` |
| feed 偶发 HTTP 503 | 整页失败（docs/STAGE_UPDATE_3_0_8.md:73；docs/ACCEPTANCE_HISTORY_3_2_0.md:1281） | `Network`（可重试）；若证明是限流则 `RateLimited` [待确认] |
| HTTP 429 | 无证据 | `RateLimited`（带 `retry-after` 时附上等待时间） |
| HTTP 401、403 | 无证据 | `RiskControl` |
| 响应头带 `bdturing-verify` 或 `x-vc-bdturing-parameters`（滑块验证），正文为空 | 分区接口拿到 null 数据 | `RiskControl`（S08-partition-rooms-unsigned：`live.douyin.com` 的分区接口不签名） |
| 200 但响应体为空 | 类型错误后走 HTML 兜底或失败 | `RiskControl`。已见的原因：请求没带 `ttwid`（S04-enter-no-cookie）；滑块验证（上一行） |
| 200 但响应体不是 JSON | 类型错误 | `RiskControl` |
| JSON `status_code ≠ 0` | feed 抛异常（site/douyin_site.dart:268-271）；搜索静默返回空（site/douyin_search.dart:346,373）；分区跳过（site/douyin_search.dart:482-484） | 按下面几行的码表映射；未知码 → `ApiChanged` 并附原始码和 `status_msg` / `data.prompts`（douyin_parse.dart:429-451） |
| `status_code 2483`（`请先登录，再继续搜索吧`） | 静默回退分区匹配 | `NeedLogin`（S08-live-search-anon、S08-general-search-anon） |
| `status_code 20003`（`User doesn't login`） | 把错误数据当用户信息 | `NeedLogin`（S09） |
| `status_code 4001038`（web_rid 不存在，`data.prompts` 为 `该内容暂时无法无法查看`） | 下标出错 → HTML 兜底 → 正则失败 | `NotFound`（S04-enter-notfound）；enter 返回空的 `data.data` 也按 NotFound |
| 房间存在但不在播 | 下播房间 | 不是失败：房间状态 = 下播 |
| 在播但没有可用视频档（只有纯音频或没有地址） | 空画质列表 | `StreamUnavailable` |
| 页面标记缺失、必需字段缺失或类型不符 | FormatException/类型错误 | `ApiChanged` |
| 调用方取消 | 多数请求不支持取消 | `Cancelled`，且只取消自己的请求 |
| 地区限制、年龄/付费 | 无证据 | 暂不使用 [待确认] |
| 弹幕签名失败、握手被拒、8 次重连耗尽 | 返回空签名继续连；回调中文句子（dm:157,162） | 连接状态流报告终止和原因枚举，不传文案 |

## 10. 踩过的坑

| 编号 | 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|---|
| REG-DOUYIN-001 | 多画面黑屏（小格只有声音） | 纯音频档 `ao`（`only_audio=1`）被当成最低画质，小格降质选列表末项 | 按键名和 `only_audio` 过滤纯音频档；最低档必须仍是视频 | 56cd4d97、09a716e6；site/douyin_site.dart:732-736,823-832；test/douyin_playback_parser_test.dart:144-176；docs/ISSUE_866_DOUYIN_MULTIVIEW_AUDIT_2026_09_15.md |
| REG-DOUYIN-002 | 部分房间没有弹幕 | 签名里的 `+`、`/` 原样拼接，`+` 被当空格；只有一个节点（旧“备用地址”替换不存在的 `webcast3`） | 签名作为参数值编码；两个 webcast100 节点轮换 | f491afd7；dm:65-72,168-182；docs/ISSUE_AUDIT_2026_09_04.md:13 |
| REG-DOUYIN-003 | 同上 | 访客 ID 12 位（网页端为 19 位）；握手缺 Referer；SDK 仍是旧 beta；半开连接无人发现 | 19 位访客 ID 并复用；补 Referer 和 `need_persist_msg_count=15`；SDK 1.0.15；45 秒静默重连 | f491afd7；docs/ISSUE_AUDIT_2026_09_04.md:13；test/douyin_danmaku_protocol_test.dart:73-104 |
| REG-DOUYIN-004 | 多个画质按钮指向同一个或错误的流 | 按 JSON Map 位置（`length - level`）配对名称和地址 | 只按 sdk_key 关联 | site/douyin_site.dart:668-674；docs/STAGE_UPDATE_2_9_5.md:35；test/douyin_playback_parser_test.dart:8-31 |
| REG-DOUYIN-005 | 画质顺序错、`MD` 缺失、`SD1/SD2` 名称颠倒 | 新旧 SDK 键混用；按瞬时码率排序 | 按键的语义等级排序，码率只作元数据 | docs/RECORDING_AND_QUALITY_AUDIT_3_0_12.md:12；site/douyin_site.dart:747-756,834-842；test/douyin_playback_parser_test.dart:63-142 |
| REG-DOUYIN-006 | 画质菜单重复（如两个“原画”） | 新旧键指向同一地址 | 地址集合相同的档只保留一个 | site/douyin_site.dart:782-791；上游 #806（docs/UPSTREAM_AUDIT_E696BB79.md:240） |
| REG-DOUYIN-007 | 推荐页报 `type 'String' is not a subtype of type 'int' of 'index'` | 2026-08 起 feed 的 `data` 从对象变成信封数组，房间还可能是 JSON 字符串 | 同时接受两代结构，不盲目下标 | site/douyin_site.dart:256-326；docs/STAGE_UPDATE_2_9_6.md:26-28；test/douyin_parser_test.dart:19-81 |
| REG-DOUYIN-008 | 在线人数显示成几十万或假 0；在线人数被当成累计观看 | 把累计 `total_user` 当在线；不看 `room_view_stats.display_type`（1 是在线，3 是累计）；feed 的 `total_user=0` 是占位 | `display_value` 按 `display_type` 归口径；精确整数优先于分档文本；累计只接受正数；两口径不互相顶替 | docs/STAGE_UPDATE_2_9_7.md:17,26；site/douyin_audience.dart；test/douyin_audience_metric_test.dart；S04-enter-live、S04-enter-live-portrait；DIAGNOSIS.md:84-85 |
| REG-DOUYIN-009 | 竖屏画面被压成窄条 | 把 `stream_orientation` 当横竖屏；用了可能属于音频占位的顶层 `extra.width/height` | 只用选中线路所属档的 `sdk_params.resolution`；关联不上就不猜 | docs/STAGE_UPDATE_3_0_8.md:11-17,24-28；lib/player/core/live_stream_geometry_hint.dart:39-98 |
| REG-DOUYIN-010 | 作品链接、搜索页被当成直播间 | `www.douyin.com/video/{id}`、`/search/{kw}` 按尾部数字取号 | 只接受恰好一段数字路径 | 1e4f566e；url_tool:92-98；docs/TOOLBOX_ROOM_LINK_PREFILTER_AUDIT_2026_09_23.md:5-9 |
| REG-DOUYIN-011 | 输入 `www.douyin.com/` 报 `Bad state: No element` | 空路径直接取最后一段 | 空路径不是房间 | docs/LIVE_LINK_PARSER_AUDIT_2026_09_07.md:7,17 |
| REG-DOUYIN-012 | 短链解析卡住、资源泄漏 | 自动跟随最多 100 次跳转，终点再新建客户端，不关闭、不设时限 | 显式逐跳、限定主机、最多 8 次请求、总时限 12 秒、只读响应头、结束即释放 | docs/LIVE_SHORT_LINK_AUDIT_2026_09_07.md:7-8,17-19；url_tool:335-386；test/live_short_link_test.dart:76-172 |
| REG-DOUYIN-013 | 收藏或历史打开后找不到房间 | room_id 每场不同，下播即作废 | 持久化只用 web_rid；room_id 只在本场会话内使用 | site/douyin_site.dart:418-423 |
| REG-DOUYIN-014 | 搜索卡片链接无效、刷新后变化、相邻结果冲突 | 缺 web_rid 时用毫秒时间戳充当房间号 | 身份确定：web_rid 优先，否则 room_id，并在使用前归一 | site/douyin_search.dart:254-257；test/douyin_search_test.dart:8-52 |
| REG-DOUYIN-015 | 重复请求的签名参数互相污染 | 签名时修改了调用方共享的参数表 | 复制参数表后再签名 | docs/ISSUE_AUDIT_2026_08_24.md:41；utils/douyin_utils.dart:26；test/platform_signing_utils_test.dart:89-104 |
| REG-DOUYIN-016 | 探针里 feed 稳定返回 503 | 获取匿名 Cookie 的首页响应只读一个字节就关闭 | 完整读完引导响应再发后续请求 | tool/interface_probe.py:580-586,656-658 |
| REG-DOUYIN-017（现存） | 登录、换号或退出后仍用旧 Cookie，直到重启 | 站点把第一次拿到的 Cookie（匿名或用户）存进进程级静态变量，之后不再比较设置值 | Cookie 只从凭据存储读取，变化即失效缓存；匿名 Cookie 也应可刷新 | site/douyin_site.dart:35,45-58；对照 site/douyin_search.dart:37-42 |
| REG-DOUYIN-018 | 录制被误判下播、多画面拿不到流 | 详情失败被吞成“未知/下播”，或丢了 `stream_url` | 详情永不吞错；API 和 HTML 路径都保留完整 `stream_url` | site/douyin_site.dart:395-400；docs/RECORDING_AUDIT_3_0_13.md:45 |
| REG-DOUYIN-019 | Linux 构建依赖 QuickJS | 签名依赖 JS 运行时 | 签名全部纯 Dart | 上游 7410eb9f；docs/ISSUE_AUDIT_2026_08_24.md:11,38 |
| REG-DOUYIN-020 | 外部打开时报类型异常，网页也打不开 | 构建 App 深链时要求弹幕参数 | 网页链接只依赖 web_rid；有本场 room_id 才给深链 | docs/ROOM_EXTERNAL_OPEN_AUDIT_2026_09_08.md:12,25；lib/modules/live_play/services/room_external_opener.dart:152-159 |

## 11. 样本清单

录制工具：`dart run live_cli`（docs/rewrite/PLAN.md:196,608）。通用脱敏：Cookie（`ttwid`、`UIFID_TEMP`、`sessionid`、`sid_tt`、`odin_tt` 等）、`msToken`、`a_bogus`、`signature`、`user_unique_id`、`sec_uid`；播放地址中的 `sign`、`unique_id` 等令牌参数（替换成等长占位，保留参数名、主机和 `expire`）；弹幕里观众的昵称、用户 id、头像。主播公开信息（web_rid、昵称、标题）可保留。

2026-09-27 直连录制，匿名（没有登录账号），共 21 个目录，放在 `fixtures/douyin/`，目录名 `S<两位编号>-<情况>`，编号对应下表。每个都有旧版期望值 `expected.json`；v4 解析器的测试是 packages/live_core/test/sites/douyin_parse_test.dart。

| # | 样本 | 覆盖点 | 旧版期望值入口 | 已录制 |
|---|---|---|---|---|
| S1 | `GET /?from_nav=1` 的 HTML 与 Set-Cookie | 分类标记、ttwid | `DouyinSite().extractCategoryDataJson`（site/douyin_site.dart:111-130） | `S01-home` |
| S2 | feed：当前信封数组；含 JSON 字符串房间；`status_code≠0`；503 | 推荐解析、人数口径、错误 | `DouyinSite.parseRecommendRooms`（site/douyin_site.dart:263-326）；`douyinOnlineViewers`/`douyinTotalViewers`（site/douyin_audience.dart） | `S02-feed`（信封数组，房间是 JSON 字符串）。**缺** `status_code≠0` 和 503：录制时没有遇到 |
| S3 | 分区房间第 1、2 页和末页（或空页） | 分页、结束判定 | 无静态入口，需假 HTTP [待确认] | `S03-partition-p1`、`S03-partition-p2`、`S03-partition-empty`（offset=1500） |
| S4 | enter：直播中（含 `ao`、新旧键混用、只有一档）；已下播（status 4）；不存在的 web_rid；竖屏房间；双画面房间；HEVC 房间 | 详情、状态、画质、编码、几何、NotFound | 画质：`DouyinSite.parseStreamQualities`（site/douyin_site.dart:675-792）；几何：`LiveStreamGeometryHint.resolveDouyin`（lib/player/core/live_stream_geometry_hint.dart:48-155）；详情字段无静态入口 | `S04-enter-live`（含 `ao`，新旧键混用）、`S04-enter-live-portrait`、`S04-enter-offline`、`S04-enter-notfound`、`S04-enter-no-cookie`（不带 Cookie 的空响应）。**缺**只有一档的房间、双画面房间、enter 里的 HEVC 房间：录制时没有找到（HEVC 在 S02-feed 里有） |
| S5 | reflow/info：在播和已结束的 room_id | room_id→web_rid | 短链解析 `LiveUrlTool.parseLiveUrl(clientFactory:)`（url_tool:155-192，用法见 test/live_short_link_test.dart:83-99） | `S05-reflow-live`、`S05-reflow-ended`、`S05-reflow-shortlink-live`（短链用的 `app_id=1128` 参数组合） |
| S6 | `live.douyin.com/{web_rid}` HTML（兜底路径） | state JSON 提取 | 无静态入口 | `S06-room-html-live` |
| S7 | `v.douyin.com` 短链的完整跳转链（只要状态码和 Location） | 短链归一 | 同 S5 | **缺**：跳转链没有录，只录了最后一步的 reflow（S05-reflow-shortlink-live）；录制时没有记下原因 |
| S8 | 直播搜索：匿名（要求登录）与带 Cookie；综合搜索；分区搜索 | NeedLogin、结果嵌套、身份 | `DouyinSearch.parseSearchPayloadForTesting`（site/douyin_search.dart:316-317） | `S08-live-search-anon`、`S08-general-search-anon`、`S08-partition-search`，以及分区匹配后续的 `S08-partition-rooms-unsigned`（`live.douyin.com` 不签名，滑块验证）和 `S08-partition-rooms-amemv`（`webcast.amemv.com` 不签名，正常）。**缺**带 Cookie 的搜索：没有登录账号 |
| S9 | `user/me`：有效 Cookie、失效 Cookie、无 Cookie | 账号状态 | 无静态入口 | `S09-user-me-invalid-cookie`、`S09-user-me-no-cookie`。**缺**有效 Cookie：没有登录账号 |
| S10 | 每档播放地址的前 64 KB 媒体头（或 ffprobe 摘要） | 编码、FLV HEVC 形态 | 不适用 | **缺**：还没有媒体首部的录制方式（docs/rewrite/STATUS.md:37） |
| S11 | 一段跨过 `expire` 的长时 FLV 拉流记录（时间戳、断开时刻、错误码） | 租期、cutsConnection | 不适用 | **缺**：同 S10；到期在 7 天后，需要专门安排 |
| S12 | 弹幕握手 URL（签名脱敏）与握手响应头、关闭码 | 连接契约 | `DouyinDanmaku.buildServerUrls` / `buildHandshakeHeaders`（dm:168-192） | **缺**：还没有 WebSocket 的录制方式（STATUS.md:37） |
| S13 | 弹幕下行二进制帧：gzip 与非 gzip 各一；`needAck=true`；聊天；在线人数；礼物、进场、点赞、关注；下播控制消息（如能录到）；他房 roomId 的聊天 | 解码、ACK、分发、过滤 | `DouyinDanmaku` 设置参数后调用 `decodeMessage`/`unPackWebcastChatMessage`/`unPackWebcastRoomUserSeqMessage`（dm:201-272；用法见 test/douyin_danmaku_protocol_test.dart:11-48） | **缺**：同 S12 |
| S14 | 上行帧：心跳、ACK | 编码契约 | 旧实现 `heartbeat`/`sendAck` 生成的字节（dm:194-199,274-280） | **缺**：同 S12 |
| S15 | 签名金样本：固定输入下的 a_bogus、X-Bogus、msToken、访客 ID | 签名算法 | 访客 ID：`DouyinSite.generateAnonymousUserUniqueId(random:)`（site/douyin_site.dart:884-892）。a_bogus 只有指纹可注入（utils/abogus.dart:610-617），时间和随机前缀不可注入；X-Bogus 用安全随机（xb:99-102）。需要临时改造的旧算法副本才能出金样本 [待确认 做法] | **缺**：旧算法的时间和随机数不能注入，还没做 |

## 12. 待确认

1. web_rid 与 room_id 的长度阈值 16 是否可靠；web_rid 是否可能含非数字字符。
2. 其它网页链接形态（`/root/live/`、`/follow/live/`、`iesdouyin.com`）是否需要支持；短链实际落地主机有哪些。
3. reflow 信息接口的必需参数：~~`app_id=1128` 还是 `6383`~~ 两种组合都能用（S05-reflow-live、S05-reflow-shortlink-live）；最小参数集合仍待确认。
4. 分区 `type` 取值含义（录到一级 4、二三级 1）；~~分区房间的“是否还有更多”字段~~：没有，用 `data.count` 和 `data.offset` 判断（S03）；搜索的结束字段；feed 是否支持偏移（`extra.has_more` 为 true，但请求没有偏移参数）。
5. ~~分区房间接口是否必须带 a_bogus~~：`live.douyin.com` 上必须带，不带是滑块验证；`webcast.amemv.com` 不用（S08-partition-rooms-unsigned、S08-partition-rooms-amemv）。仍待确认：`Authority` 头和 `browser_*` 参数是否必须与 UA 一致。
6. 服务端是否校验 msToken 来源；a_bogus 是否需要百分号编码。
7. ~~综合搜索是否为流式响应；匿名直播搜索被拒的响应~~：是十六进制长度分块；匿名都是 `status_code 2483`（S08）。仍待确认：是否保留分区匹配兜底。
8. `status` 除 2、4 以外的取值（暂离、预告等）与映射。~~enter 里是否有 `room_status`~~：有，0 在播、2 已结束，与 `status` 一致（S04）。
9. 画质：未知键 `level` 与已知键等级的对应；`main` 里 `lls/cmaf/dash` 等协议；默认画质字段是否用于起播。~~原画是否需要登录~~：匿名只能试看 30 秒（S06-room-html-live，第 8 节）；试看由谁执行、界面怎么处理仍待确认。
10. ~~编码字段名~~：`sdk_params.VCodec`（`h264`/`h265`）和 `options.qualities[].v_codec`（`264`/`bytevc1`）（S02、S04）。仍待确认：FLV 内 HEVC 的封装形式；`is_need_double_stream` 的作用。
11. 租期：~~`expire` 的进制和单位~~：绝对 Unix 秒，十进制或十六进制，另有 `volcTime`、`wsTime+keeptime`、`k+t` 几种写法，都是签发后 7 天（S02-feed，第 6 节）。仍待确认：到期后已建立的连接是否被切断（`cutsConnection`）。
12. CDN 是否校验 UA/Origin/Referer/Cookie；能否不向 CDN 发送登录 Cookie。
13. HTML 兜底是否因缺少 `__ac_signature` 而拿到挑战页；访客 ID 是否应跨进程持久化。
14. 弹幕：服务端是否校验 `signature`；重连时是否需要刷新 `cursor`；主播重开播后 room_id 变化的处理；是否输出礼物、进场、点赞、关注；下播控制消息的 method 与字段；颜色字段含义。
15. 风控与错误：~~空响应体的含义~~：没带 ttwid，或滑块验证（带 `bdturing-verify` 头）（S04-enter-no-cookie、S08-partition-rooms-unsigned）；~~web_rid 不存在的响应~~：`status_code 4001038`；~~Cookie 失效时 `user/me` 的响应~~：`status_code 20003`。仍待确认：完整的 `status_code` 码表；503 属于网络抖动还是限流。
16. 地区限制、年龄/付费限制在抖音是否存在。
