# E02.5 映客

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 14-1～14-6）记在 [record.md](record.md)；目录说明文字由 E06.1 第 6 条改写
- 旧编号：M4.14、M4.U.14、T02b.5
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)（`audience.dart` 的人数能力表加了映客）、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；目录说明文字在 [E06.1](../../E06-平台层升级/E06.1-已批准升级的余项/README.md) 第 6 条改写；弹幕：平台匿名拿不到弹幕连接地址，D01 里没有映客的任务；HEVC 线路的播放在 G01.1，“优先 H.264”设置在 J01.1、A11.3；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/inke/`（`inke_api.dart` 769 行解析，`inke_site.dart` 440 行请求编排）；样本 `fixtures/inke/`（ls 共 15 项：14 组接口录制，另有 `legacy_expected.dart` 补出 3.x 冻结输出；没有弹幕样本）；应用在 `apps/pure_live/lib/app/platforms.dart:165` 建 `InkeSite(http, preferH264: preferH264)`，弹幕登记表不登记映客（同文件 `:191-195` 的注释）

## 目标

把 3.x 的映客适配器（`lib/core/site/inke/` 两个文件共 518 行）重构进 `live_core`。3.x 最大的问题是“关注的主播大多播不了”：网页房间接口匿名不给地址，3.x 只能在官网展示位（四五十个直播）里找同一场直播，找不到就让整个进房失败（REG-INKE-001）。这里改为取流时问 App 接口 `now_publish`（任何在播主播都给签名地址，和展示位里是同一路流），展示位查找留作兜底；升级落地后推荐改用 App 热门、显示人数和直播封面、加上 HEVC 的“原画”。

## 平台接口要点

| 功能 | 接口（网页 `webapi.busi.inke.cn/web/`、App `service.inke.cn/api/live/`，`inke_site.dart:127-135`；请求头 `Referer: https://www.inke.cn/`、`Origin`、UA `Mozilla/5.0`，不跟随跳转，回答最多 1 MiB） | 位置 |
|---|---|---|
| 分类 | `web/Live_channel_pc`：一个“映客”分类，第一格“官网推荐”（`Live_top_pc`，`InkeApi.topArea`，不用请求）加 6 个频道（`areaType` `showcase`）；坏频道只跳过这一个 | `inke_site.dart:147`；`inke_api.dart:143`、`:243` |
| 推荐 | App 热门 `simpleall`（15～25 个，有标题、直播封面、人数、开播时间），每次刷新内容会变；只有一页，第 1 页总是请求，之后 30 秒内的页用同一份快照（`InkeSite.snapshotLifetime`） | `inke_site.dart:58`、`:112`、`:158`、`:189`；`inke_api.dart:390` |
| 分区 | 官网推荐位和频道（展示位），只有一页，同样用快照 | `inke_site.dart:193`、`:196`；`inke_api.dart:257`、`:270` |
| 搜索 | 按昵称（不分大小写）过滤官网推荐位、全部频道和 App 热门（3 个请求），3.x 能搜到的排在前面，App 热门失败只少它的结果；uid 或映客链接直接查这个房间；`scheme://主机` 才算链接；可取消 | `inke_site.dart:211`、`:228`、`:269-281`；`inke_api.dart:281` |
| 详情 | `web/live_share_pc?uid=`，1099999920（“当前用户无直播”，不存在的 uid 也是它）是未开播；在播时再问一次 `now_publish` 换上 App 的封面、标题、人数、开播时间（进房、关注刷新、录制都是 2 个请求，开播状态只 1 个）；占位标题“正在直播中”留空 | `inke_site.dart:293`、`:308`、`:320-335`；`inke_api.dart:155`、`:469`、`:504` |
| 取流 | App `now_publish?id=<uid>`：网宿 H.264 FLV（`live-pull-ws.ikstatic.cn/live/<直播编号>_t.flv`，租期取 `wsABStime`，约签发后 2 小时，提前 min(10 分钟, 寿命的 1/4) 续）作“FLV”（id `flv`）；即构 HEVC FLV（`live-pull-zego.ikstatic.cn/inkemain/<直播编号>_0_en.flv`，`codecInfo=8192`）作“原画”（id `origin`，租期约开播后 24 小时）；进房后 30 秒内复用 App 的回答（`InkeSite.answerReuse`）；App 失败或只给即构地址时，FLV 按 3.x 的顺序翻三个展示位找同一场直播，“原画”没有兜底 | `inke_site.dart:346-371`、`:387`；`inke_api.dart:163`、`:169`、`:545`、`:584-613`、`:662` |
| 优先 H.264 | `InkeSite(preferH264:)`：开时 FLV 在前，关时“原画”在前，每次取画质时读 | `inke_site.dart:49`；`app/platforms.dart:165` 传入 |
| 目录说明 | `directoryNoticeKey` = `inke_directory_scope`（文字在界面层，E06.1 改写） | `inke_site.dart:86` |
| 链接 | 网页房间页 `www.inke.cn/liveroom/index.html?uid=`、App 分享链接 `mlive<n>.inke.cn/app/…?uid=`，只取唯一的 `uid`，不发请求 | `inke_site.dart:439`；`inke_api.dart:690-703` |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/site/inke/`） | 现在（`packages/live_core/lib/src/sites/inke/`） | 说明 |
|---|---|---|---|
| 进房和录制 | `inke_api.dart:277-299`、`:301`，`inke_site.dart:137-143`：详情里就要取流，不在展示位的直播进房直接失败（`inke_media_unavailable`：“当前官网精选未提供已验证的公开播放地址”） | `inke_site.dart:293`，取流另问 App | 3.x 问题 1、2（REG-INKE-001） |
| 推荐 | `inke_site.dart:69`，官网 8 个推荐位 | App 热门；8 个推荐位成了“官网推荐”分区 | 14-1 |
| 搜索 | `inke_site.dart:75`、`:94`，只找展示位；带冒号的关键词当成链接 | 加 App 热门；`scheme://` 才算链接 | 14-2；3.x 问题 4 |
| 人数 | 不显示（人数设置页写“缺失值保持未知”） | `numbers.real` 作在线、`online_users` 作热度 | 14-3（REG-INKE-003） |
| 封面和标题 | 封面是主播头像 | App 的直播封面和标题；占位标题“正在直播中”留空，uid 搜到的未开播主播不再叫“UID <uid>” | 14-4、统一原则 |
| 画质 | `inke_site.dart:149`，只有 `FLV`，没有即构 HEVC；未开播返回空列表 | `FLV` + “原画”（HEVC）；未开播报 `StreamUnavailable` | 14-5（REG-INKE-002）；3.x 问题 3 |
| 续期 | 不给到期时间 | `wsABStime` 租期 | 3.x 问题 7 |
| 分享链接 | 只认网页房间页 | 加 `mlive<n>.inke.cn/app/…` | 3.x 问题 8 |
| 列表容错 | 一行缺字段整页报错，一个坏频道整个分类失败 | 坏行、坏频道只跳过这一个 | 统一原则 |
| 弹幕 | `inke_site.dart:49` `getDanmaku()` 是 `EmptyDanmaku` | 不登记，直播间显示一次未连接 | 无变化（匿名拿不到连接地址） |

## 结果

- 首次重构（2026-09-28，提交 `656194b3f`）：10 个 3.x 问题、9 条有意差异见 record.md；用同一时刻录的 S05 一组样本证明展示位的地址和 App 的地址是同一路流（主机、路径、`stream_id` 相同），所以“修 bug，用户看到的不变”。兜底查找对 44 场直播找到的地址和请求数与 3.x 一致。
- 升级落地（2026-09-29，`26fa56da3`）：14-1～14-6 全部做完（14-6 目录说明的文字交给界面，E06.1 第 6 条 c1 改写）；开播时间取 `start_time`；App 给了地址就是受限类型 `none`；`audience.dart` 的人数能力表加了映客（`packages/live_core/lib/src/audience.dart`）；新样本 `S06-placeholder-*`。请求数：在播的关注刷新 1 → 2，进房加播放仍是 2 个，翻页的后续页 30 秒内 0 个。画质 id 不变（`flv` 照旧，`origin` 是新增），不用迁移。
- 测试：`packages/live_core/test/sites/inke_api_test.dart` 48 个 `test(` 写法、`inke_site_test.dart` 38 个（record.md 按实际用例统计 99 个：60 + 39）。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出（新差异写明条目编号）；S05 不在展示位的主播能进房、能播；兜底查找的顺序；快照 30 秒内共用（17 次调用的请求从 17 个减到 6 个）；`preferH264` 每次读；即构线路的校验、编码和租期。
- 真实接口：2026-09-28 实测 App 接口用 3.x 的请求头能正常回答、拉到的是 H.264 FLV；2026-09-29 直连、匿名用新适配器跑了推荐（25 个）、分类 7 格、进房、两条线路都读到 FLV 文件头；即构租期规则来自 54 个直播的统计（51 个正好是 `start_time + 86400`）。不用代理。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节映客一行“播放：完成”“弹幕：无”，指样本和探针测过）。HEVC“原画”要在高通真机上验证 FLV codec 12 硬解（REG-PLAY-022，G01.2 的硬解评估）。

## 留下的问题

- 默认画质会选中 HEVC：直播间和多画面按名字匹配画质偏好（`apps/pure_live/lib/shared/rooms/play_quality.dart:7` 的 `defaultQualityIndex`，偏好默认就是“原画”，`packages/live_store/lib/src/settings/settings.dart:270`），映客的“原画”只有即构 HEVC 一条线路；“优先 H.264”只在一档之内把 `hevc` 线路排后（`packages/live_media/lib/src/source.dart:166-168`），不影响选哪一档。所以“优先 H.264”开着时，映客默认仍播 HEVC 的“原画”（record.md“设置项”给 G 的注意，没有落实）：没有任务管，建议并入 G01.2 或单开任务。
- 超过 24 小时的直播，即构线路到期后能不能续上没核实，由播放在续期失败时按恢复处理（G02.1）。
- 付费、私密、密码房没有找到（54 个直播的 `live_type`、`sub_live_type` 都是空串），受限类型只填 `none`。
- 分类页“官网推荐”、类型名“映客官网精选”是平台层给的中文，英文界面仍显示中文 → [Z05.2](../../../Z-工程文档和维护/Z05-多语言/Z05.2-英文界面里平台给的中文/README.md)。
- 14-1～14-6（UPGRADES）都已完成，本平台没有“未排”或“受阻”的升级项；弹幕不做（匿名拿不到连接地址）。
