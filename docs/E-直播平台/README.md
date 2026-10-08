# E 直播平台

35 个来源（3.x 的 33 个平台、4.x 恢复的 Kick、网络电视）的平台层：推荐、分类和分区、搜索、房间详情、清晰度和线路、开播状态、链接和短链、登录用的平台接口，以及它们共用的模型、平台接口、注册表和错误类型。排在功能组的第三位（A 界面、C 直播间、D 弹幕之后）：直播间和弹幕都靠它取数据，平台一改接口，用户最先看到的就是“打不开”，所以这一组的重点已经从“重构”转到“定期巡检、及时修”。

## 范围

- 管什么：
  - **平台适配器**：`packages/live_core/lib/src/sites/<平台>/`（34 个目录，每个是 `*_api.dart` 纯解析 + `*_site.dart` 请求编排，少数另有签名、座位、控制连接文件），样本 `fixtures/<平台>/`，测试 `packages/live_core/test/sites/`。
  - **框架和模型**：`packages/live_core/lib/src/` 的 `live_room.dart`、`live_site.dart`、`sites.dart`、`site_error.dart`、`play_line.dart`、`live_area.dart`、`audience.dart` 等；房间资料的合并和补齐（`mergeFrom`、`fillFromDetail`）。
  - **链接**：`packages/live_core/lib/src/links.dart` 和各平台的 `LiveSiteLinks` 方法。
  - **应用里建适配器的地方**：`apps/pure_live/lib/app/platforms.dart` 的 `buildSiteRegistry`（构造参数、代理、Cookie）和 3.x 关注身份迁移 `identityResolver`。
  - **平台层升级的收尾**（UPGRADES 的余项接到应用）和**巡检工具** `tools/live_cli`（`probe`、`patrol`，E07.1）。
- 不管什么（归哪组）：
  - **弹幕协议**：每个平台的弹幕连接和解析 `packages/live_danmaku/` → [D01](../D-弹幕/D01-平台弹幕协议/README.md)（另一位在写）。分工：E 组给弹幕需要的参数（哔哩哔哩 `getDanmuInfo` 凭据、抖音签名和 `DouyinDanmakuArgs`、快手 feed 参数、各平台的 `*DanmakuArgs`），D01 管连接、协议、消息；弹幕凭据接口失效时可以在 E 组的巡检任务里一起修。
  - 直播间怎么用这些数据（进房、取流、换线、恢复）→ [C](../C-直播间/README.md)、[G](../G-播放/README.md)；会话型输入的打开（niconico、FC2、BIGO）在 `packages/live_media` → G；录制 → [H](../H-录制/README.md)。
  - 热门、分区、关注、搜索页面的数据流和界面 → [I](../I-浏览和发现/README.md)、A09；账号和登录界面、Cookie 存储 → [K](../K-账号和登录/README.md)、[J](../J-设置和数据/README.md)；网络电视的播放列表和节目单 → [L](../L-网络电视和点播/README.md)（`packages/live_iptv`，在注册表里算一个来源）。
  - 网络层（`packages/live_net`：HTTP、代理、Cookie 接口）、Android 原生 HTTP 通道 → [Q](../Q-网络和代理/README.md)；分享接收和剪贴板口令 → O03。

## 子分类怎么分

| 子分类 | 管什么 | 和其他子分类、其他组的关系 |
|---|---|---|
| [E01 国内五大平台](E01-国内五大平台/README.md) | 哔哩哔哩、斗鱼、虎牙、抖音、快手；它们的持续巡检和修复（E01.6） | 弹幕 D01.2～D01.6；巡检工具来自 E07；轮播接界面在 E06.2 |
| [E02 其他国内平台](E02-其他国内平台/README.md) | YY、网易 CC、AcFun、猫耳、映客、克拉克拉、小红书、微博、京东、酷狗、百度、六间房、LOOK | 弹幕 D01.7、D01.10、D01.13、D01.14、D01.25～D01.29；YY FLV 优先在 E06.3 |
| [E03 海外平台](E03-海外平台/README.md) | SOOP、Twitch、Picarto、TwitCasting、niconico、SHOWROOM、CHZZK、LiveMe、TikTok、YouTube、BIGO、PandaTV、FC2、Steam、17LIVE、Kick | 要代理；弹幕 D01.8、D01.9、D01.11、D01.12、D01.15～D01.24、D01.30、D01.31；配方取流的打开在 G；Twitch、Kick 的原生通道在 Q |
| [E04 链接解析和分享口令](E04-链接解析和分享口令/README.md) | 分享文字里取链接、短链跟随、按平台顺序认房间、已下线平台的链接 | 规则写在 E01～E03 各平台；3.x 分享口令和剪贴板在 O03 |
| [E05 平台框架和模型](E05-平台框架和模型/README.md) | 模型、平台接口和可选能力、注册表、错误类型、合并和补齐 | 所有组的底座；存储（J）按它的 JSON 存 |
| [E06 平台层升级](E06-平台层升级/README.md) | UPGRADES 的余项：平台层做完、要接到应用的（轮播、名字颜色和徽章、PK、Twitch、实际档名、FC2、YY FLV） | 改应用的直播间（和 C01.4 同一处）、聊天行（A08）、`platforms.dart` |
| [E07 平台巡检](E07-平台巡检/README.md) | 巡检工具 `tools/live_cli` 和每一轮的结果 | 修复在 E01.6（五大平台）或 E02、E03 新开的任务；弹幕失效归 D01；巡检不进门禁（D-017） |

## 现状（2026-10-07）

- 做到哪：
  - 34 个平台的平台层全部完成（E01.1～E03.16，2026-09-28～10-01），模型和框架（E05.1、E05.2）、链接（E04.1）、UPGRADES 余项的平台层（E06.1）完成；UPGRADES 222 条主表：完成 196、部分完成 17、受阻 9（2026-10-03 核对）。
  - K90 上看过的：国内五大平台的播放和弹幕、YY 和网易 CC 的播放（2026-10-01 两轮真机，[FEATURES.md](../inventory/FEATURES.md) 第 14 节）；其余 11 个国内平台和 16 个海外平台没有专门在真机上看过（海外要代理，Twitch、Kick 归 S02.4）。
  - 没做的：定期巡检（E01.6、E07.1，第一档，未开始）；平台层新数据接到界面（E06.2，暂停，半成品只有 FC2 的一半）；YY FLV 优先（E06.3）；`fillFromDetail` 补封面（E05.3）。
- 和 3.x 比：
  - 一样的：3.x 的平台和功能都在，行为以 3.x 的冻结输出（`fixtures/<平台>/*/expected.json`）为准，差异在各平台 record.md 逐条列出。
  - 多的：Kick 恢复（Android）；14 个平台新增弹幕（D01）；轮播、受限类型、开播时间、关注身份大小写（E05.2）；类型化错误（不再把临时出错当下播）；各平台修掉的 3.x 问题（每个平台 10～20 个）。
  - 少的：没有（3.x 的“已下线”平台照旧显示已下线）。
- 主要的代码：`packages/live_core`（纯 Dart，只依赖 `live_net`、`meta`、`crypto`；约 5.5 万行，其中平台适配器占大半）；`apps/pure_live/lib/app/platforms.dart`（278 行，建注册表）；样本 `fixtures/`（34 个平台加 `live_vod`）。

## 当前重点和顺序

1. **第一档**：[E07.1](E07-平台巡检/E07.1-平台巡检工具/README.md) 巡检工具（取回 `tools/live_cli`、按现在的接口重写探针、加 `patrol`）和 [E01.6](E01-国内五大平台/E01.6-国内五大平台巡检和修复/README.md) 国内五大平台巡检和修复。理由：上一轮一次检查就发现三处已经失效，4.0.0 已发布，用户每天在用这五个平台。两者可以同时开工：E01.6 第 1 阶段（清单）和 E07.1 第 1 阶段（检查项）是同一份 `CHECKS.md`。
2. **第二档**：[E06.3](E06-平台层升级/E06.3-YY优先用FLV/README.md)（小）→ [E05.3](E05-平台框架和模型/E05.3-房间详情补齐时连封面一起补/README.md)（小，观看记录封面）→ [E06.2](E06-平台层升级/E06.2-平台层新数据接到界面/README.md)（中，6 个阶段，第 5 阶段和 C01.4 一起做）。
3. 以后：E07.1 第一轮巡检发现的其他平台失效，在 E02、E03 开修复任务；UPGRADES 仍“未排”的 7-9、C-17、C-22 等维护者决定。

## 风险和注意

- **平台改接口、加风控**：签名（抖音 a_bogus、斗鱼 `getH5PlayV1`、虎牙 AntiCode、哔哩哔哩 WBI）、游客门禁（快手）、搜索拦截（虎牙 UA）随时会变。对策：定期巡检（E07、E01.6）；失效时先录样本、写改之前会失败的测试再修。
- **测试不访问真实平台**（D-017）：所有平台测试都用 `fixtures/` 的样本回放；巡检工具的联网部分永远不进门禁。
- **样本隐私**：录样本时 Cookie、设备号、令牌、客户端 IP 必须换成合成值（`fixtures/README.md`；门禁 `fixture privacy`）；17LIVE 的归档分支 `archive/v4` 里还有一份没脱敏的样本（E03 已知问题，待维护者决定）。
- **3.x 兼容**：清晰度名称和 id、房间身份、分区 id、设置键名（D-018）不能随便改：关注、录制任务、偏好都按它们存；身份要变时写迁移规则（niconico、YouTube、抖音已有，`platforms.dart:265`）。
- **代理和电脑上的差别**：海外平台国内要代理；Kick、Twitch 在 Android 上走系统 TLS，电脑（含巡检工具）上可能被 Cloudflare 拒。
- **同一个文件多人改**：`apps/pure_live/lib/app/platforms.dart`（E06.2、E06.3）、`features/live_play/logic/room_controller.dart`（E06.2、C01.4）；平台适配器和 D01 的弹幕文件同一平台同时只给一个人改。
- 改这一组的代码要遵守：[specs/ENGINEERING.md](../specs/ENGINEERING.md)（依赖方向：`live_core` 不依赖 Flutter 和弹幕包）；[specs/UPGRADES.md](../specs/UPGRADES.md) 的统一原则（受限的直播仍是直播、拿不到的标不可播放、占位值留空）。

## 相关

- 规范：[specs/UPGRADES.md](../specs/UPGRADES.md)（已批准的平台升级）、[specs/ENGINEERING.md](../specs/ENGINEERING.md)；清点：[inventory/FEATURES.md](../inventory/FEATURES.md) 第 14 节（平台能力表）；样本规则：`fixtures/README.md`。
- 决定：D-001（照 3.x 逐个重构）、D-002（借用归档 v4 的包和工具）、D-004（只做 Android：Kick 只在 Android 登记）、D-013（哔哩哔哩打码昵称）、D-017、D-018。
- 其他组：D01（弹幕协议）、G（播放和配方输入）、C01.4（清晰度显示）、I（浏览数据）、J02.1 / J06.1（3.x 数据和身份迁移）、K（登录）、Q（网络和原生通道）、S02（真机清单）、W（上游对照：pure_live、pure_live_TV 的平台修复）、Z05.2（平台层的中文）。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 进度和子分类

`███████████████████░` 93%

| 子分类 | 范围 | 进度 | 完成 / 全部 |
|---|---|---|---:|
| [E01 国内五大平台](E01-国内五大平台/README.md) | 哔哩哔哩、斗鱼、虎牙、抖音、快手。 | `█████████████████░░░` 84% | 5 / 7 |
| [E02 其他国内平台](E02-其他国内平台/README.md) | YY、网易 CC、AcFun、猫耳 FM、映客、克拉克拉、小红书、微博、京东、酷狗、百度、六间房、LOOK。 | `████████████████████` 100% | 15 / 15 |
| [E03 海外平台](E03-海外平台/README.md) | SOOP、Twitch、Picarto、TwitCasting、niconico、SHOWROOM、CHZZK、LiveMe、TikTok、YouTube、BIGO、PandaTV、FC2、Steam、17LIVE、Kick。 | `████████████████████` 99% | 16 / 18 |
| [E04 链接解析和分享口令](E04-链接解析和分享口令/README.md) | 直播间链接、短链、分享口令。 | `████████████████████` 100% | 1 / 1 |
| [E05 平台框架和模型](E05-平台框架和模型/README.md) | 模型、平台接口、注册表、错误类型、房间资料的合并和补齐。 | `██████████████░░░░░░` 70% | 2 / 4 |
| [E06 平台层升级](E06-平台层升级/README.md) | 已批准的升级和平台新数据接到界面。 | `████████████░░░░░░░░` 58% | 1 / 3 |
| [E07 平台巡检](E07-平台巡检/README.md) | 定期用真实接口检查各平台还能不能用。 | `████████████████████` 100% | 1 / 1 |

## 还没完成的（8）

| 任务 | 状态 | 档位 | 阶段 |
|---|---|---|---|
| [E01.6](E01-国内五大平台/E01.6-国内五大平台巡检和修复/README.md) 国内五大平台巡检和修复（持续） | 开发中 | 第一档 | 0/3：下一阶段“写巡检清单” |
| [E03.17](E03-海外平台/E03.17-Twitch推荐语言参数/README.md) 接 E07.1：Twitch 推荐的 GraphQL 语言参数类型变了 | 待真机 | 第一档 | — |
| [E01.7](E01-国内五大平台/E01.7-斗鱼在播无流/README.md) 斗鱼在播但没有流：streamStatus 为 0 时报“没有画面”，不再交给播放器 404 地址 | 待真机 | 第二档 | — |
| [E03.18](E03-海外平台/E03.18-17LIVE线路和翻页/README.md) 接 E07.1：17LIVE 线路全部不通、第 2 页只给重复的一个 | 待真机 | 第二档 | — |
| [E05.3](E05-平台框架和模型/E05.3-房间详情补齐时连封面一起补/README.md) 房间详情补齐时连封面一起补（fillFromDetail 漏了封面，观看记录等处封面变空） | 待真机 | 第二档 | — |
| [E05.4](E05-平台框架和模型/E05.4-平台层小问题合集/README.md) 平台层小问题合集：克拉克拉列表提前到底、LOOK 搜索能力、AcFun 付费直播仍连弹幕、百度签名过期后重连用旧地址、多画面里六间房没有弹幕、京东酷狗百度的 3.x 占位名、getDanmaku 死代码、斗鱼设置键注释 | 未开始 | 第二档 | 0/3：下一阶段“列表和搜索：克拉克拉空页、LOOK 搜索说明” |
| [E06.2](E06-平台层升级/E06.2-平台层新数据接到界面/README.md) 平台层新数据接到界面：哔哩哔哩轮播、17LIVE 名字颜色和徽章、酷狗 PK 标签、Twitch Cookie 提示和编码、恢复后的实际清晰度、FC2 接手 | 暂停 | 第二档 | 0/6：下一阶段“哔哩哔哩轮播” |
| [E06.3](E06-平台层升级/E06.3-YY优先用FLV/README.md) YY 优先用 FLV：应用打开 YySite.flvFirst，换算存下的画质 id（UPGRADES 6-1） | 待真机 | 第二档 | 2/2 |

决定见 [DECISIONS.md](../DECISIONS.md)，做法见 [PROCESS.md](../PROCESS.md)。

<!-- docs:生成结束 -->
