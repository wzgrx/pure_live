# IPTV（网络电视）规格

- 状态：第 6 阶段，2026-09-28
- 范围：播放列表和节目单的格式、频道与节目单匹配、回看地址规则、“网络电视”作为发现里的平台、同步、存储和备份
- 依据：product.md §10（F-IPTV-01～11 的 v4 处置）；ADR 0003（IPTV 不再算站点，是独立的本地数据源模块）；决策草案 [ADR 0024](../../docs/adr/0024-iptv.md)。旧版代码 `legacy/lib/core/iptv/`、`legacy/lib/modules/iptv/` 和测试 `legacy/test/m3u_parser_test.dart` 只用来核对真实格式的坑，不照搬
- 代码：解析、匹配、回看、数据源在 `packages/live_iptv`（纯 Dart，只依赖 live_core、live_net）；存储在 `packages/live_store`；界面在 `apps/pure_live/lib/features/iptv/`
- 只写行为和契约，不写类名和代码拆分

## 0 术语

| 术语 | 含义 |
|---|---|
| 播放列表 | 用户导入的一个 M3U / TXT / JSON 文件或网址 |
| 条目 | 播放列表里的一行流地址，带名称、分组、台标、`tvg-*`、回看属性和请求头 |
| 频道 | 名称相同（去首尾空白、连续空白并成一个）的全部条目；频道就是“网络电视”的房间，房间号是频道名 |
| 线路 | 频道的一个条目。多个播放列表里同名的条目都是同一频道的线路，顺序为播放列表顺序、再按文件顺序（F-IPTV-11） |
| 节目单源 | 一个 XMLTV / JSON 节目单文件或网址；同一时间只有一个“当前节目单” |

## 1 播放列表格式（F-IPTV-01）

格式按内容识别，不看文件名和 Content-Type：去掉 BOM 后以 `#EXTM3U` 开头或含 `#EXTINF:` → M3U；以 `{` 或 `[` 开头 → JSON；其它 → TXT。

### 1.1 M3U / M3U8

- **头部**：`#EXTM3U` 后面的属性。`x-tvg-url`、`url-tvg`、`tvg-url`（逗号分隔多个）是节目单地址；`catchup`、`catchup-type`、`catchup-source`、`catchup-days`、`catchup-correction` 是回看默认值；`http-user-agent`、`http-referrer` 等是请求头默认值。`#EXTM3Ubroken` 不是头部。
- **`#EXTINF` 属性**：读到第一个不在引号里的逗号为止，逗号后面全部是显示名（显示名里的“属性样子”的文字不解析）。引号可以是双引号或单引号，引号里可以有逗号和另一种引号；无引号的值到空白或逗号结束；`=` 两边可以有空白；键不区分大小写；重复的键取最后一个；裸词（时长 `-1`）跳过。引号不闭合、引号后紧跟非分隔符 → 这一段作废并记一条问题，绝不“猜”出半个频道。
- **名称**：显示名，没有时用 `tvg-name`；都没有 → 作废。
- **分组**：`group-title`；没有时继承前面的 `#EXTGRP:`（空的 `#EXTGRP:` 清除继承）；条目自己写了 `group-title`（即使是空）就结束继承。
- **请求头**，后面的覆盖前面的：头部默认 < `#EXTINF` 属性（`http-user-agent`、`user-agent`、`http-referrer`、`referrer`、`referer`、`origin`、`authorization`、`cookie`）< 指令（`#EXTVLCOPT:http-user-agent=`、`http-referrer=`；`#EXTHTTP:` 的 JSON 对象或 `a=b&c=d`；`#KODIPROP:…stream_headers=` / `manifest_headers=`）< 地址后缀 `url|name=value&…`（值做百分号解码；`seekable`、`reconnect_*`、`icy*` 是传输选项，忽略，前缀 `!` 强制当请求头）。头名统一小写，`http-user-agent` → `user-agent`，`referrer` → `referer`，`cookies` → `cookie`。指令写在 `#EXTINF` 之前作用于下一个条目，之后作用于当前条目。
- 请求头指令格式错误（JSON 坏了、值不是字符串、`url|Authorization` 这种缺值的选项、坏的百分号编码）→ 这个条目作废，不带着半截认证信息去请求。
- **地址**：只接受播放器能打开的协议：http、https、rtmp(s)、rtsp(s)、rtp、udp、mms(h)、srt。`p2p://`、TVBox 的 `proxy://`、`file://` 作废。
- **回看属性**：条目的值优先，缺失时用头部默认。`catchup-days` 为 0 或模式为 `0/false/off/none/disabled` → 关闭；没有模式但有旧属性 `timeshift` / `tvg-rec`（天数）→ `shift`；没有模式但有 `catchup-source` → `default`。
- 问题（缺头部、段落被截断、没有 `#EXTINF` 的地址、作废的段落）逐条记录行号，其余条目照常导入。

### 1.2 TXT

- `分组,#genre#`（`#genre#` 不区分大小写）开始一个分组；第一行分组之前的频道没有分组。
- `名称,地址` 是频道；地址部分可用 `#` 分隔多个源，每个源可以带 `$标签` 后缀（`url$电信`），标签去掉（`$` 前面不是合法地址时整段保留）。每个源是同一频道的一条线路（旧版改名为“名称 (线路N)”，v4 合并为线路）。
- 空行、`#` 或 `//` 开头的行跳过；没有逗号的行、空名称、坏地址记问题。
- 分组原样保留（包括“更新时间”这类说明分组）。

### 1.3 JSON

接受：频道数组；`{"channels": [...]}`；`{"groups": [{"name", "channels": [...]}]}`；TVBox 旧格式 `{"lives": [{"group", "channels": [{"name", "urls": [...]}]}]}`。对象上的 `epg`、`x-tvg-url`、`url-tvg`、`tvgUrl`、`epgUrl` 是节目单地址。

频道字段：名称 `name` / `title` / `channel` / `channel_name`；地址 `urls`（数组）、`url` / `src` / `stream` / `link`（字符串可用 `#` 分隔）；分组 `group` / `group-title` / `category` / `genre`；台标 `logo` / `tvg-logo` / `icon` / `image`；`tvg-id` / `tvgId` / `epgId`；`tvg-name` / `tvgName`；回看 `catchup`、`catchup-source`、`catchup-days`；请求头 `headers` 对象、`ua` / `userAgent`、`referer`。只写了另一个播放列表地址的 TVBox 源不跟随，记问题。

### 1.4 编码

gzip（`1f 8b`）先解压；UTF-8 BOM、UTF-16 LE/BE BOM 决定编码并去掉；其余按 UTF-8，坏字节换成替换字符。GBK 等旧编码暂不转换（§9）。

### 1.5 导入结果

- 至少有一个条目才算成功；成功后整体替换该播放列表的全部条目（一次事务），问题数写进结果提示。
- 零条目 → 失败，原有条目保留，记录失败原因和时间。

## 2 节目单（F-IPTV-02）

格式按内容识别：`<` 开头 → XMLTV；`{` 开头 → JSON；其它 → 格式错误。

### 2.1 XMLTV

- 流式解析（不建 DOM，几十 MB 的节目单也不占整份内存）；标记错误跳过，超过 200 处放弃剩余部分。
- `<channel id>`：全部 `<display-name>`（保留顺序）和第一个 `<icon src>`；同一 id 出现多次合并名称。
- `<programme channel start stop catchup-id>`：第一个 `<title>`、`<sub-title>`、`<desc>`（支持 CDATA 和实体）。没有标题、没有频道、时间坏 → 跳过并计数。
- 时间 `YYYYMMDDhhmm[ss] [±hhmm|±hh:mm|Z]`，没有时区按 UTC（XMLTV DTD）。缺 `stop` 时到同频道下一个节目开始为止；同频道同开始时间只留第一个。
- 节目引用了没有声明的频道 id 时，补一个没有名称的频道（仍可按 `tvg-id` 匹配）。

### 2.2 JSON

- `{"channels": [{"id", "name" | "displayName" | "names", "icon"}], "programmes" | "programs" | "epg" | "events": [{"channel" | "channelId", "title", "start", "stop" | "end", "duration"(分钟), "desc", "subtitle", "catchupId"}]}`。
- DIYP 单日格式 `{"channel_name", "date", "epg_data": [{"start": "08:00", "end": "09:00", "title", "desc"}]}`：时刻是本机时区的当地时间，结束早于开始表示跨到第二天。
- 时间：10 位数字是 Unix 秒，13 位是毫秒；12 或 14 位是 XMLTV 时间；其余按 ISO 8601（无时区按本机时区）。

### 2.3 保存窗口

- 同步时只保存 [现在 − 2 天, 现在 + 2 天) 之间的节目（节目单对话框显示前 2 天到后 1 天；多存 1 天，保证每天同步一次时对话框一直是满的）。
- 启动同步和每次节目单同步后删除结束时间早于“现在 − 2 天”的节目。
- 节目单同步整体替换该源的频道和节目（一次事务）；失败时保留旧数据并记录原因。

## 3 频道与节目单匹配（F-IPTV-02）

对当前节目单，按频道的每条线路依次尝试，第一条匹配上的为准。每一步只接受唯一答案，不唯一就进入下一步，所以结果与节目单里的顺序无关：

1. `tvg-id` 等于节目单频道 id（不区分大小写）。
2. 规范化后的 `tvg-name`、频道名、`tvg-id` 等于某个节目单频道规范化后的名称或 id。
3. 频道代码相同：规范化名称以“字母+数字”开头、后面只有中文时，这一段是代码（`CCTV-1 综合` → `cctv1`，`CCTV-5+` → `cctv5plus`）。
4. 一个规范化名称包含另一个（至少 2 个字），且不切开 ASCII 单词或数字：`cctv1综合` 包含 `cctv1`，但 `cctv10`、`cctv4k`、`cctv1plus` 都不包含 `cctv1`。

规范化：全角转半角、转小写、`+` 写成 `plus`、去掉括号里的注释（`()` `[]` `（）` `【】`）、去掉画质标记（独立的 `hd fhd uhd sd hdr hevc h264 h265 1080p 720p 2160p 50fps…`，紧跟在数字或中文后面的 `hd fhd uhd sd`，以及 `高清 超清 标清 蓝光 超高清 频道`），最后只留字母、数字和中文。`4K`、`8K` 保留（`CCTV-4K` 是独立频道）。

匹配结果不存库，按当前节目单的版本（最后同步时间）缓存在内存里。v4 不提供手动指定匹配（旧版也没有入口，只有表）。

## 4 回看（F-IPTV-06）

### 4.1 节目状态与可回看

- 节目区间左闭右开：开始时刻属于这个节目（直播中），结束时刻属于已结束。状态：未开始 / 直播中 / 已结束。
- 已结束的节目可回看，除非：该线路关闭了回看；结束时间早于 `catchup-days` 窗口；模板要 `{catchup-id}` 但节目没有；`vod` 模式既没有模板也没有 `catchup-id`；未知模式又没有模板。频道的多条线路里只要有一条可回看就可回看。
- 没有任何回看属性的频道按 playseek 规则回看（国内 IPTV 最常见；不支持的源会播放失败，界面照常提示并可“回到直播”）。

### 4.2 地址规则

先按 `catchup-correction`（小时）平移节目时间，然后：

| 模式 | 规则 |
|---|---|
| 无属性、`default`、`playseek`、`append`，且没有模板 | playseek：查询参数 `playseek=<开始>-<结束>`，本地时间 `yyyyMMddHHmmss`，替换已有的 `playseek`，其它参数（含重复参数）保留 |
| `default`、`playseek` 有模板 | 展开模板；结果是绝对地址就替换原地址，是 `?…` / `&…` 就追加到原地址 |
| `append` 有模板 | 展开后追加到原地址（原地址有查询用 `&`，否则 `?`；片段 `#…` 保持在最后） |
| `shift`、`timeshift` | 追加 `utc={utc}&lutc={lutc}` |
| `offset` | 有模板同 `default`；否则设置 `catchup=default&offset=<开始到现在的秒数>`（旧版规则） |
| `flussonic`、`flussonic-hls`、`flussonic-ts`、`fs` | `…/mpegts`、`fs`、`flussonic-ts` → `…/timeshift_abs-{utc}.ts`；`…/index.m3u8` → `…/timeshift_rel-{offset:1}.m3u8`；`…/名.m3u8` → `…/名-timeshift_rel-{offset:1}.m3u8` |
| `xc` | `/live/用户/密码/id.ext` → `/timeshift/用户/密码/{duration:60}/{Y}-{m}-{d}:{H}-{M}/id.ext`（没有扩展名用 `.ts`） |
| `vod` | 有模板同 `default`；否则节目的 `catchup-id` 就是地址 |
| 其它 | 有模板同 `default`；否则不可回看 |

### 4.3 模板占位符

`{…}` 和 `${…}` 等价：

| 占位符 | 值 |
|---|---|
| `utc`、`start` / `utcend`、`end` / `lutc`、`now`、`timestamp` | 开始 / 结束 / 现在的 Unix 秒 |
| `utc:格式` 等上面各名加 `:格式` | UTC 时间，格式字母 `Y m d H M S`（其它字符原样） |
| `Y` `m` `d` `H` `M` `S` | 开始时间的本地时间字段 |
| `(b)格式`、`(e)格式` | 开始 / 结束的本地时间，Java 风格 `yyyy MM dd HH mm ss`；`(b)timestamp` 是 Unix 秒（APTV、DIYP 列表常用 `?playseek=${(b)yyyyMMddHHmmss}-${(e)yyyyMMddHHmmss}`） |
| `duration`、`duration:N` | 节目时长秒数（除以 N） |
| `offset`、`offset:N` | 开始到现在的秒数，不为负（除以 N） |
| `catchup-id` | 节目的 `catchup-id` |

未知的占位符 → 不可回看，不去请求一个含糊的地址。

### 4.4 播放

- 回看按节目单里点选的节目打开，每条可回看的线路一条线路，画质仍是“原画”；以“非连续直播”打开（playback SES-11：不做意外暂停、意外结束和退避这几项直播专属恢复）。
- 回看时显示“回看：节目名”和“回到直播”；“回到直播”按原地址重新打开直播。点选直播中的节目等于回到直播；未开始的节目只提示。

## 5 “网络电视”平台（F-IPTV-05）

- 平台 id `iptv`，名称“网络电视”，在发现里和其它平台一样是一个标签（可在平台设置里隐藏和排序）。没有播放列表时显示导入入口。
- 分类 = 播放列表（按用户顺序），分区 = 播放列表里的分组（按首次出现顺序；无分组的叫“未分组”），分区 id 为 `<播放列表 id>/<分组>`（不同播放列表的同名分组互不影响收藏）。
- 推荐 = 全部频道（按播放列表顺序、文件顺序，频道名去重），分区房间 = 该分组的频道；每页 60 个。搜索 = 频道名包含关键字（ASCII 不区分大小写）。
- 卡片：主播名 = 频道名，标题 = 当前节目（没有节目单时是频道名），封面 = 台标，状态总是“直播中”。
- 房间：房间号是频道名（`0`、`null` 这类会被房间号规则拒绝的名称加前缀 `#`）。没有任何播放列表还有这个频道 → “频道不存在”。关注照常（F-IPTV-08 合并到关注）；**不记录观看历史**（F-HIS-01）。
- 取流：只有“原画”一档；每个条目一条线路（F-IPTV-11），线路名“线路 N”；换线路由播放层处理（playback REC-1）。请求头：条目自己的 > 播放列表的 UA > 全局自定义 UA（F-IPTV-04）。
- 直播间信息区显示频道名、当前节目和简介、“节目单”按钮；回看中显示“回到直播”。
- 链接解析：IPTV 没有网页链接，不参与。

## 6 导入与同步（F-IPTV-01、F-IPTV-03、F-IPTV-04）

- **导入**：本地文件（M3U / M3U8 / TXT / JSON，名称默认取文件名）或网址（名称默认取网址最后一段）。文件导入时把内容复制到 `<数据根>/IPTV/playlists/`，“同步”就是重新解析这份副本；网址导入先下载解析成功才保存。与已有网址相同的播放列表不重复添加，改为同步它。
- **节目单源**：同样从文件或网址添加；第一个添加的自动设为当前。播放列表声明了节目单地址而用户还没有任何节目单源时自动添加并同步；已有节目单源时在节目单管理页列为“播放列表提供的节目单”，一键添加。
- **下载**：请求平台键为 `iptv`（走代理规则），超时 2 分钟；有自定义 UA（播放列表的优先，其次全局）就带上。404 / 410 为“地址不存在”，其它为网络失败。
- **自动同步**：设置开关（默认关）和间隔（默认 24 小时，1～168）。开启时，应用启动 3 秒后同步“到期”的网址播放列表和网址节目单源（自己的自动同步开关打开，且距上次尝试超过间隔）；运行期间每小时检查一次。文件来源不参与自动同步。
- **手动**：逐个同步、全部同步、删除（确认）、改名、设置播放列表 UA、单个自动同步开关、复制或打开来源地址。
- **Android 分享**：分享到应用的文本如果是以 `.m3u`、`.m3u8`、`.txt`、`.json` 结尾的网址、或内容本身是 M3U（含 `#EXTM3U`），打开“导入播放列表”并预填（用户确认后导入，`.m3u8` 也可能是单个直播流，所以不自动导入）；分享或用本应用打开的播放列表文件读成内容后同样确认导入（上限 32 MB）。

## 7 存储与备份

- 数据在主库（schema 2）：`iptv_playlists`（名称、来源、UA、自动同步、节目单地址、上次成功 / 尝试时间、失败原因、顺序）、`iptv_channels`（每个条目一行：播放列表、文件位置、名称、分组、地址、`tvg-*`、台标、回看四项、请求头 JSON）、`iptv_guide_sources`（名称、来源、自动同步、是否当前、同步时间、失败原因、顺序）、`iptv_guide_channels`、`iptv_programmes`（UTC 毫秒）。删除播放列表或节目单源级联删除它的数据。
- 设置：`iptv.autoSync`（旧键 `isAutoSyncEnabled`）、`iptv.autoSyncHours`（`autoSyncHoursInterval`）、`iptv.userAgent`（`customIptvUserAgent`），均为 `synced`。旧版的 `selectedSourceId` / `selectedSourceName` 指向旧库的 id，不导入。
- 备份（store.md §7.1 的 `iptv` 分区）：`{"playlists": [{name, url, userAgent?, autoSync, order}], "epgSources": [{name, url, autoSync, selected, order}]}`，只含网址来源；文件来源、频道和节目不进备份（换设备后重新同步即可）。恢复时替换本机的网址播放列表和网址节目单源，本机文件来源保留在前面；恢复进来的来源下次同步（手动或自动）后才有频道。`providers` 作为 `playlists` 的别名读取。
- 旧版 IPTV 库（store.md §1.7）的迁移不在本模块，见 §9。

## 8 验收

| 项 | 方式 |
|---|---|
| §1 各格式、坏数据、编码 | 【单元】`packages/live_iptv/test/m3u_test.dart`、`playlist_test.dart` |
| §2 XMLTV / JSON、窗口、gzip | 【单元】`guide_test.dart` |
| §3 匹配 | 【单元】`matcher_test.dart` |
| §4 回看规则和占位符 | 【单元】`catchup_test.dart` |
| §5 平台行为 | 【单元】`iptv_site_test.dart` |
| §7 存储、迁移、备份 | 【单元】`packages/live_store/test/iptv_test.dart`、`test/drift/store/migration_test.dart` |
| 管理页、发现、节目单 | 【组件】`apps/pure_live/test/iptv_test.dart`；【真机】导入一个真实列表、切换线路、回看、回到直播 |

## 9 待确认与已知缺口

1. GBK 等非 UTF 编码的 TXT 列表：纯 Dart 没有现成解码，引入依赖前先确认用户量。
2. DIYP 节目单接口（`…?ch={name}&date={date}` 按频道按天查询）：只支持单日文件，按频道实时查询的接口未做。
3. Xtream Codes 导入（F-IPTV-07）、定时录制（F-IPTV-10 并入录制中心）未做。节目提醒（F-IPTV-09 并入 F-NEW-01）已做：节目单里未开始的节目可“提醒我”，开始前 1 分钟通知，只在进程存活期间有效（ADR 草稿 ADR 0028）。
4. live_core 的流格式只有 flv / hls：MPEG-TS、RTSP、UDP 等线路暂标为 flv（没有租期，直连播放，不影响播放）；录制接入 IPTV 前需要在 live_core 增加格式。
5. 旧版 IPTV 库（`IPTV_CACHE/pure_live_tv/pure_live_tv.db`）的迁移：v4 数据在主库，旧库只读导入（播放列表来源、节目单源；不升级旧库结构，回退安全），随 store.md §6 的迁移实现。
6. 全屏时控制层还没有“节目单”按钮，全屏下要先退出全屏再打开节目单。
