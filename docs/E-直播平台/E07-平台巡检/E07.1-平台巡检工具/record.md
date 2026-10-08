# E07.1 平台巡检工具：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（`[E07.1]` 提交）
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)；检查项和对象表：[CHECKS.md](../CHECKS.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 验收 1 工作区成员、依赖方向 | 做了 | `tools/live_cli` 加进根 `pubspec.yaml` 的 `workspace`（`pubspec.lock` 不变：`args` 已经在锁里）；依赖只有 `args`、`live_core`、`live_net`、`live_danmaku`、`meta`。`check_deps.py` 的规则收窄到实际用的三个 `live_*` 包 |
| 验收 2 `CHECKS.md` | 做了 | P1～P13 的做法和判定、34 行对象表；代码里同一份表是 `lib/src/patrol/targets.dart`。等维护者看 |
| 验收 3 `patrol` 命令 | 做了 | 平台名、`--domestic`、`--overseas`、`--all`、`--proxy`、`--danmaku`、`--out`、`--json`；退出码 0/1/64 |
| 验收 4 报告格式和隐私 | 做了 | 见下“报告” |
| 验收 5 单元测试 | 做了 | 58 个，全部用假的 `LiveSite`、`LiveHttp`，`head()` 只连本机回环 |
| 验收 6 跑一遍 | 做了 | 34 个平台都有结果（国内直连，海外经本机代理 127.0.0.1:7897，即 `purelive-env.sh` 里的代理）；失败项都有去向，见“第一轮” |

## 做了什么

- `bin/live_cli.dart`：`CommandRunner` 注册 `probe`、`patrol`，保留归档的 `exit(exitCode)`。
- `lib/src/sites.dart`：34 个平台的工厂表（参数照 `apps/pure_live/lib/app/platforms.dart` 的默认值：空的 `MemoryCookieVault`、`preferH264` 默认开、Twitch 不给后备、Kick 的接口用 dart:io）、弹幕连接表（同 `buildDanmakuRegistry`，设置取默认）、`patrolProxyPolicy`（国内一律直连，海外走 `--proxy`，`FixedProxyPolicy(perSite: …)`）。
- `lib/src/probe/probe_command.dart`：按现在的接口重写归档的探针：链接经 `LinkParser` → `getRoomDetail` → `discoverPlayQualities` → `resolvePlayUrls` → 每条线路开头 64 KB。
- `lib/src/patrol/`：`targets.dart`（对象表）、`checks.dart`（`PlatformPatrol`，P1～P13 每项一个方法；错误转成说明；每项超时；遇到 `RiskControl` 停这个平台）、`media.dart`（`head()` 经 `LiveHttp.open` 读够 64 KB 就断开，`container()` 识别 FLV、`#EXTM3U`、TS、fMP4、DASH、HTML）、`danmaku.dart`（P13 只听不发）、`report.dart`（Markdown、JSON、`redact`、`scrub`）、`patrol_command.dart`（参数和 `runPatrol`，网络、媒体、链接、弹幕都能注入）。
- 和归档的不同：归档的 `fixture`、`danmaku`、`lease`、`record`、`remux` 命令没有取回（任务书范围外）；`head()` 不再自己开 `HttpClient`，走 `IoLiveHttp`，所以代理规则和请求头与应用一致。
- 悬空引用：`docs/specs/ENGINEERING.md`（目录图加上 `tools/live_cli` 和它的依赖，删掉“还没有”的说明）、`tools/gate/check_deps.py:34`（规则收窄并注明用途）、`fixtures/README.md`“录制”（写明 `fixture capture` 还在 `v4-archive`，现在手工补录，脱敏规则在归档里）；Z02、Z01.1、Z07.3、Z 组 README 和 E 组 README 里“`tools/live_cli` 不存在”的说法一并改掉。

## 报告

- 开头一行：开始和结束时间（UTC）、国内直连 / 海外经代理或没有代理、匿名、弹幕秒数、总用时；一张总表（每个平台网络、用时、四种结果各几项）；每个平台一张 `| 检查项 | 结果 | 说明 |`。
- 说明里的地址经 `redact` 只留主机和路径前两段（没有查询参数和签名）；保留段和文档段以外的 IPv4 换成 `x.x.x.x`（同 `check_fixtures.py`）；表格里的 `|` 转义。JSON 同样脱敏。

## 测试

- 新增 58 个（`checks_test.dart` 38、`media_test.dart` 5、`report_test.dart` 5、`patrol_command_test.dart` 10），全部通过；`dart analyze --fatal-infos` 无问题。
- 判定：第 2 页重复超过一半、空页、卡片缺房间号、没有第 2 页、空分类、只搜直播中搜出未开播、按房间号查用推荐的房间号、不支持的项、详情缺标题（卡片补标题）、要求分区时先挑分区房间、受限房间跳过、链接换一种写法但详情是同一房间、按卡片的房间号拼房间页（niconico）、开播时间晚于现在、固定房间状态不对或已不存在、P8 报错类型不对（含 `RiskControl`）或不报错、清晰度重复或为空、配方取流、HLS 线路开头是 FLV、HTTP 403 和降档、租期已过和未到、链接认错、大小写不敏感的平台、弹幕没就绪和正常、超时（1 秒）、平台自己的超时、遇到风控后停下、整行跳过（Kick）。
- `head()`：本机回环的原始套接字只给 128 KB 且不结束回答，断言只读到 64 KB 并且是客户端先断开；404 不读正文。
- 参数：平台顺序、`--domestic` 18、`--overseas` 16、`--all` 34、代理和弹幕参数、各种错参数（命令里是用法错误，退出码 64）；没有代理时海外平台全部“没测到”不算失败；国内失败使报告失败（退出码 1）；工厂表和 `SiteIds.supported` 一致。

## 真机上要看的

- 不需要：工具在电脑上跑。修复任务各自有真机步骤。

## 第一轮（2026-10-08）

- 报告：[runs/2026-10-08.md](runs/2026-10-08.md)（`patrol --all --proxy 127.0.0.1:7897`，2026-10-08 00:10～00:21 UTC，总用时 10 分 43 秒；国内直连、海外经代理、匿名、弹幕不跑）。国内五大平台另跑了一轮 `--danmaku 60`，在 [E01.6](../../E01-国内五大平台/E01.6-国内五大平台巡检和修复/README.md) 的 `runs/2026-10-08.md`。
- 这之前跑过两轮（10-07 23:22 国内、23:44 全部），用来改工具自己的判定（见下“跑出来的工具问题”）；下表是改好以后的第三轮。

| 平台 | 网络 | 用时 | 正常 | 失败 | 没测到 | 不支持 |
|---|---|---|---|---|---|---|
| 哔哩哔哩 | 直连 | 20 秒 | 12 | 0 | 1 | 0 |
| 斗鱼 | 直连 | 11 秒 | 11 | 1 | 1 | 0 |
| 虎牙 | 直连 | 11 秒 | 12 | 0 | 1 | 0 |
| 抖音 | 直连 | 20 秒 | 11 | 0 | 1 | 1 |
| 快手 | 直连 | 1 分 28 秒 | 12 | 0 | 1 | 0 |
| 网易 CC | 直连 | 7 秒 | 12 | 0 | 0 | 1 |
| Twitch | 代理 | 25 秒 | 10 | 1 | 1 | 1 |
| SOOP | 代理 | 41 秒 | 10 | 0 | 2 | 1 |
| YY | 直连 | 16 秒 | 12 | 0 | 1 | 0 |
| AcFun | 直连 | 4 秒 | 12 | 0 | 1 | 0 |
| Picarto | 代理 | 31 秒 | 11 | 0 | 1 | 1 |
| TwitCasting | 代理 | 27 秒 | 11 | 0 | 1 | 1 |
| 猫耳 FM | 直连 | 4 秒 | 11 | 0 | 1 | 1 |
| 映客 | 直连 | 24 秒 | 9 | 1 | 1 | 2 |
| 克拉克拉 | 直连 | 9 秒 | 11 | 0 | 1 | 1 |
| 小红书 | 直连 | 1 秒 | 2 | 1 | 6 | 4 |
| niconico | 代理 | 18 秒 | 10 | 0 | 2 | 1 |
| 微博直播 | 直连 | 3 秒 | 11 | 0 | 0 | 2 |
| SHOWROOM | 代理 | 25 秒 | 10 | 1 | 1 | 1 |
| CHZZK | 代理 | 37 秒 | 11 | 0 | 1 | 1 |
| Kick | — | 0 秒 | 0 | 0 | 13 | 0 |
| LiveMe | 代理 | 18 秒 | 9 | 0 | 0 | 4 |
| TikTok | 代理 | 3 秒 | 3 | 0 | 5 | 5 |
| YouTube | 代理 | 23 秒 | 8 | 0 | 2 | 3 |
| BIGO LIVE | 代理 | 20 秒 | 11 | 0 | 1 | 1 |
| PandaTV | 代理 | 30 秒 | 11 | 0 | 1 | 1 |
| FC2 LIVE | 代理 | 14 秒 | 11 | 0 | 1 | 1 |
| Steam 直播 | 代理 | 19 秒 | 10 | 0 | 2 | 1 |
| 京东直播 | 直连 | 5 秒 | 10 | 0 | 2 | 1 |
| 酷狗直播 | 直连 | 4 秒 | 11 | 0 | 1 | 1 |
| 百度直播 | 直连 | 9 秒 | 10 | 0 | 2 | 1 |
| 六间房 | 直连 | 4 秒 | 11 | 0 | 1 | 1 |
| LOOK 直播 | 直连 | 2 秒 | 9 | 1 | 2 | 1 |
| 17LIVE | 代理 | 1 分 09 秒 | 8 | 3 | 1 | 1 |

“没测到”里每个平台都有 P13（这一轮不跑弹幕）；另外：Kick 整行（要 Android 原生通道）；SOOP 的固定房间 phonics1 正好在播；映客、YouTube、Steam、京东、LOOK 没有固定的不存在房间号，niconico、百度没有固定的未开播房间（CHECKS.md 待补）；小红书和 TikTok 拿不到在播房间，后面各项跟着没测到。

### 失败项、初步根因和去向

| 平台 | 检查项 | 现象 | 初步根因 | 去向 |
|---|---|---|---|---|
| 斗鱼 | P10 | 9263298 唯一的线路 404，三轮都是 | `getH5PlayV1` 对这个房间答 `streamStatus: 0`（推流断了），同时 12 个 `streamStatus: 1` 的房间全部 200；签名和地址都对 | 平台状态，不是失效；候选写在 [E01.6](../../E01-国内五大平台/E01.6-国内五大平台巡检和修复/README.md) 的 record.md |
| Twitch | P1 | `ApiChanged`：`$languages` 是 `[String!]`，平台要 `[Language!]` | `twitch_api.dart:156` 的 GraphQL 查询类型声明过时（平台改了 schema），不是电脑上 TLS 被拒 | [E03.17](../../E03-海外平台/README.md)（第一档） |
| 映客 | P10 | 三轮里每次 3 个房间有 2 个的网宿线路（`live-pull-ws.ikstatic.cn`）10 秒没有数据 | 只保留网宿 H.264 线路（`inke_api.dart:171`、`:324`）；可能是本机到网宿的网络，要复测 | [E02.15](../../E02-其他国内平台/README.md) |
| 小红书 | P1 | 推荐第 1 页为空，没有报错 | `xiaohongshu_site.dart:100` 的推荐请求现在答空列表，没细查 | [E02.14](../../E02-其他国内平台/README.md) |
| SHOWROOM | P10 | 581109 的 HLS 两轮都超时，其余 2 个房间正常 | 单个房间经代理超时，可能是代理出口；先观察 | 不开任务，下一轮再看 |
| LOOK 直播 | P10 | 95878198 的线路三轮都是 404，其余 2 个房间正常 | 和斗鱼的断流相似（在播但没有流），单个房间；先观察 | 不开任务，下一轮再看 |
| 17LIVE | P1、P3、P10 | 第 2 页只有 1 个且和第 1 页重复；每个房间 tencent 线路 404、wansu 线路超时 | 线路 `seventeenlive_api.dart:717`；游标翻页 `seventeenlive_site.dart:101-109`；可能和代理出口地区有关 | [E03.18](../../E03-海外平台/README.md) |

国内五大平台没有适配器失效（E01.6 第 1 轮）。

### 跑出来的工具问题（已在本任务改好，测试覆盖）

| 现象 | 原因 | 改法 |
|---|---|---|
| 快手 P2 超时 | 分类约 20 个请求、间隔 2.5 秒，超过每项 30 秒 | 对象表可以给平台单独的超时（快手 90 秒） |
| 快手、酷狗 P6“缺标题” | 快手房间页本来没有标题（A-3），直播间用卡片的标题 | P6 先用 `fillFromDetail` 拿卡片补，和 `room_controller.dart` 一样 |
| 抖音 P6“缺分区” | 非游戏房间本来没有分区，推荐里挑到的都是非游戏房间 | 要求分区的平台先挑 P3 分区（游戏）里的房间 |
| YY、京东、Steam、17LIVE P4 结果为空 | 关键词不对：YY 以娱乐房间为主、京东和 Steam 按店铺或主播名搜 | 换成能搜到的词（王者荣耀、京东、game、a） |
| 克拉克拉 P7 `NotFound` | 固定房间写成了场次号，详情要的是主播 uid | 换成主播 uid 1775178981381 |
| FC2 P9 `NeedsLogin` | P6 挑到会员限定的房间 | P6 跳过受限房间 |
| SHOWROOM、YouTube P12“应为…” | 详情的链接用 url key、直播视频号指向同一房间 | 认出的号不同时再查一次详情，是同一房间就算正常 |
| niconico P12 `nico.ms` 认不出 | 详情的房间号是主播 `user/…`，`nico.ms` 只认节目号 | 只对 `lv…` 拼 `nico.ms`，并且按卡片的号拼 |

### 巡检频率

- 建议每两周一次、发布前一次；PROCESS 第 12 节已经有这一行（“每两周、每次发布前：平台巡检”），没有再改。国内五大平台的那一轮由 E01.6 做（`--danmaku 60`）。
