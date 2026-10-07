# E02.5 映客

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 14-1～14-6）记在 [record.md](record.md)
- 旧编号：M4.14、M4.U.14、T02b.5
- 相关：模型 [E05.1](../../E05-平台框架和模型/README.md)（`audience.dart` 的人数能力表加了映客）、[E05.2](../../E05-平台框架和模型/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/README.md)；目录说明文字在 [E06.1](../../E06-平台层升级/E06.1-已批准升级的余项/README.md) 第 6 条改写；HEVC 线路的播放在 G 组；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/inke/`（`inke_api.dart` 769 行解析，`inke_site.dart` 440 行请求编排）；样本 `fixtures/inke/`（15 组，`legacy_expected.dart` 补出 8 个 3.x 冻结输出）

## 目标

把 3.x 的映客适配器（`lib/core/site/inke/` 两个文件共 518 行）重构进 `live_core`。3.x 最大的问题是“关注的主播大多播不了”：网页房间接口匿名不给地址，3.x 只能在官网展示位（四五十个直播）里找同一场直播，找不到就让整个进房失败（REG-INKE-001）。这里改为取流时问 App 接口 `now_publish`（任何在播主播都给签名地址，和展示位里是同一路流），展示位查找留作兜底；升级落地后推荐改用 App 热门、显示人数和直播封面、加上 HEVC 的“原画”。

## 平台接口要点

| 功能 | 接口（网页 `InkeApi.webApi`、App `InkeApi.appApi`，`inke_site.dart:128-131`；请求头 `Referer: https://www.inke.cn/`、`Origin`、UA `Mozilla/5.0`，不跟随跳转） | 位置 |
|---|---|---|
| 分类 | `web/Live_channel_pc`：一个“映客”分类，第一格“官网推荐”（`Live_top_pc`）加 6 个频道（`areaType` `showcase`） | `inke_site.dart:147` |
| 推荐 | App 热门 `simpleall`（15～25 个，有标题、直播封面、人数、开播时间），每次刷新内容会变；列表只有一页，切片在 30 秒内共用一份快照 | `:158`、`:189` |
| 分区 | 官网推荐位和频道（展示位），只有一页 | `:193` |
| 搜索 | 按昵称（不分大小写）过滤官网推荐位、全部频道和 App 热门（3 个请求），3.x 能搜到的排在前面；uid 或映客链接直接查这个房间；可取消 | `:211-269` |
| 详情 | `web/live_share_pc?uid=`，1099999920（“当前用户无直播”，不存在的 uid 也是它）是未开播；在播时再问一次 `now_publish` 换上 App 的封面、标题、人数、开播时间（进房、关注刷新、录制都是 2 个请求，开播状态只 1 个） | `:320-335` |
| 取流 | App `api/live/now_publish?id=<uid>`：网宿 H.264 FLV（`live-pull-ws.ikstatic.cn/live/<直播编号>_t.flv`，租期取 `wsABStime`，约 2 小时）作“FLV”；即构 HEVC FLV 作“原画”（id `origin`，租期约开播后 24 小时）；进房后 30 秒内复用 App 的回答；App 失败或只给即构地址时按 3.x 的顺序翻三个展示位找同一场直播 | `:346-371` |
| 优先 H.264 | `InkeSite(preferH264:)`：开时 FLV 在前，关时“原画”在前 | `app/platforms.dart:165` 传入 |
| 目录说明 | `LiveDirectoryNotice`，文字键 `inke_directory_scope` | `:86` |
| 链接 | 网页房间页 `www.inke.cn/liveroom/index.html?uid=`、App 分享链接 `mlive<n>.inke.cn/app/…?uid=` | `:439`；`inke_api.dart:692-697` |

## 3.x 和现状

| 方面 | 3.x（`lib/core/site/inke/`） | 现在 | 说明 |
|---|---|---|---|
| 进房和录制 | `inke_api.dart:277-299`、`inke_site.dart:124-141`：详情里就要取流，不在展示位的直播进房直接失败（“当前官网精选未提供已验证的公开播放地址”） | 详情只读房间接口，取流另问 App | 3.x 问题 1、2（REG-INKE-001） |
| 推荐 | `inke_site.dart:69`，官网 8 个推荐位 | App 热门；8 个推荐位成了“官网推荐”分区 | 14-1 |
| 搜索 | `:75`，只找展示位；带冒号的关键词当成链接 | 加 App 热门；`scheme://` 才算链接 | 14-2；3.x 问题 4 |
| 人数 | 不显示（人数设置页写“缺失值保持未知”） | `numbers.real` 作在线、`online_users` 作热度 | 14-3（REG-INKE-003） |
| 封面和标题 | 封面是主播头像 | App 的直播封面和标题；占位标题“正在直播中”留空 | 14-4、统一原则 |
| 画质 | `:149`，只有 `FLV`，没有即构 HEVC | `FLV` + “原画”（HEVC） | 14-5（REG-INKE-002） |
| 列表容错 | 一行缺字段整页报错 | 坏行、坏频道只跳过这一个 | 统一原则 |
| 弹幕 | `getDanmaku()` `inke_site.dart:49` 是 `EmptyDanmaku` | 不登记（匿名拿不到连接地址），界面显示未连接 | 无变化 |

## 结果

- 首次重构（2026-09-28，提交 `656194b3f`）：10 个 3.x 问题、9 条有意差异见 record.md；用同一时刻录的 S05 一组样本证明展示位的地址和 App 的地址是同一路流（主机、路径、`stream_id` 相同），所以“修 bug，用户看到的不变”。兜底查找对 44 场直播找到的地址和请求数与 3.x 一致。
- 升级落地（2026-09-29，`26fa56da3`）：14-1～14-6 全部做完（14-6 目录说明的文字交给界面，E06.1 已改写）；开播时间取 `start_time`；App 给了地址就是受限类型 `none`；`audience.dart` 的人数能力表加了映客。请求数：在播的关注刷新 1 → 2，进房加播放仍是 2 个。
- 测试：`packages/live_core/test/sites/inke_api_test.dart` 48 个 `test(` 写法、`inke_site_test.dart` 38 个（record.md 统计 99 个用例）。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出（新差异写明条目编号）；S05 不在展示位的主播能进房、能播；兜底查找的顺序；快照 30 秒内共用（17 次调用的请求从 17 个减到 6 个）；`preferH264` 每次读。
- 真实接口：2026-09-28 实测 App 接口用 3.x 的请求头能正常回答、拉到的是 H.264 FLV；2026-09-29 用新适配器跑了推荐、分类、进房、两条线路的文件头；即构租期规则来自 54 个直播的统计。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节）。HEVC“原画”要在高通真机上验证 FLV codec 12 硬解（REG-PLAY-022，G 组）。

## 留下的问题

- 选默认画质时按名字匹配用户偏好（默认偏好就是“原画”），会在“优先 H.264”开着时选中 HEVC 的“原画”：G 组选档时要跳过 `codec` 为 `hevc` 的档（record.md“设置项”的注意）。
- 超过 24 小时的直播，即构线路到期后能不能续上没核实。
- 付费、私密、密码房没有找到，受限类型只填 `none`。
- 弹幕：匿名拿不到连接地址，不做。
