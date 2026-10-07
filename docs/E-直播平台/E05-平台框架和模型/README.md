# E05 平台框架和模型

所有平台共用的一层：直播间、分区、画质、弹幕消息的模型，平台接口和它的可选能力，平台注册表，类型化错误，以及刷新时房间资料怎么合并、进房时怎么补齐。34 个平台适配器、弹幕包、存储、播放、录制、界面都只认这一套。

## 范围

- 包括：
  - `packages/live_core/lib/src/` 里不属于某个平台的文件：模型 `live_room.dart`、`audience.dart`、`live_area.dart`、`live_message.dart`；接口 `live_site.dart`、`live_danmaku.dart`、`input_recipe.dart`；取流公共件 `play_line.dart`、`hls_source_query_policy.dart`、`hls_master.dart`、`quality_label.dart`；错误 `site_error.dart`；读取工具 `json.dart`、`html.dart`、`convert.dart`；平台编号和注册表 `sites.dart`；对外导出 `packages/live_core/lib/live_core.dart`。
  - 合并和补齐的规则：`LiveRoom.mergeFrom`、`fillFromDetail`、`withAudienceFallbackFrom`、`pendingAfterError`。
  - 应用里建注册表的地方 `apps/pure_live/lib/app/platforms.dart` 的 `buildSiteRegistry`（哪个平台带什么依赖）。
- 不包括（归哪里）：
  - 各平台自己的解析和请求（`sites/<平台>/`）→ [E01](../E01-国内五大平台/README.md)、[E02](../E02-其他国内平台/README.md)、[E03](../E03-海外平台/README.md)。
  - 链接和分享口令（`links.dart`）→ [E04](../E04-链接解析和分享口令/README.md)。
  - 弹幕连接、协议、`DanmakuRegistry`（`packages/live_danmaku/`）→ [D01](../../D-弹幕/D01-平台弹幕协议/README.md)；`live_message.dart` 的字段由 D01 的任务按需加，模型文件在这里。
  - 房间的存储、3.x 数据迁移（`packages/live_store/`，关注和观看记录怎么调用 `mergeFrom`）→ J 组；网络层 `packages/live_net/`（`LiveHttp`、代理、Cookie）→ Q 组。
  - 关注分组、受限标记、开播时长在界面上怎么显示 → A 组和 I 组。

## 现状：做到哪、怎么工作的

- 用户看得到的：模型本身不直接显示，但决定了几件用户能感觉到的事：
  - 平台出错时直播间显示“加载失败”和原因、录制不会把临时出错当下播（`SiteError` 九种，`site_error.dart:9`）；
  - 关注页三组（直播中、回放、未开播）由 `LiveRoom.followGroup`（`live_room.dart:408`）给出，轮播、封禁、待定、不可播放的回放都在“未开播”；
  - 刷新不会把存下的名字、标题、封面冲掉（`mergeFrom` 空值保留，UPGRADES X-2）；下播再开播不会显示上一场的开播时间（`startedAt`、`restriction` 状态变了就清掉）；
  - 大小写不同的同一个房间（`LPL`、`lpl`）只算一个关注（`SiteIds.caseInsensitiveRoomIds`，`sites.dart:223`，10 个平台）。
- 内部怎么工作：
  - 启动时 `apps/pure_live/lib/app/bootstrap.dart:186` 调 `buildSiteRegistry`（`platforms.dart:135-188`）建 `SiteRegistry`（`sites.dart:263`），每个平台一个工厂，第一次用到时创建、之后复用（3.x 每次 `Sites.of` 都新建）；应用里经 `sitesProvider`（`app/services.dart:112`）取。依赖：所有平台共用一个 `LiveHttp`（按平台走代理）、`CookieVault`（`StoreCookieVault` `:52`）；哔哩哔哩带 `storedUid`，斗鱼带续期 `StoreDouyuLogin`（`:68`），虎牙、快手、Twitch、映客、TikTok、酷狗、百度、17LIVE 带 `preferH264`，niconico、FC2 带代理策略（座位和控制连接是 WebSocket），Kick 只在有原生 HTTP 通道（`PlatformDeps.kickApi`，`:126`）时登记，网络电视在 `iptv` 不为空时登记。
  - 直播间（`features/live_play/logic/room_controller.dart`）：`getRoomDetail`（`:370`）→ `withAudienceFallbackFrom(requested).fillFromDetail(requested)`（`:384`）→ 关注快照 `follows.update`（`mergeFrom`）→ 能播时 `LiveQualityDiscoveryScope.discover`（`live_site.dart:486`）→ 扩展 `resolvePlayUrls`（`:421`）拿 `LivePlayUrlResolution`（线路或输入配方）→ `resolveAppliedPlayQuality`（`:224`）定显示的清晰度 → 第一次播起来后写观看记录（`:438-441`）。
  - 可选能力用 `is` 判断：录制前的严格详情 `LiveSiteRecordRoomResolver`、关注卡的轻量刷新 `LiveSiteRoomRefresher`、恢复时重新取地址 `LivePlayRecoveryResolver`、签名地址的续期时间 `LivePlayLeaseMetadata`、目录分页 `LiveSiteDirectoryPager`、Cookie 被拒 `LiveSiteCookieRefusals`（`live_site.dart:277-416`）。
- 完成度（和 3.x 对照）：
  - 一致的：3.x JSON 的键名和 `liveStatus` 序号、稀疏合并、人数三种口径和排序、画质标签、取流去重、全部可选能力接口、34 个平台的编号和顺序、11 个已下线平台和 15 个域名。
  - 确认过的改动：不可变模型和规范化身份（E05.1 问题 1）；只留 `liveStatus`（问题 3）；类型化错误（问题 9）；开播时间、受限类型、轮播、关注分组、身份大小写、占位值（E05.2，UPGRADES 统一原则和 X-2）；Kick 恢复（UPGRADES X-1，E03.16）。
  - 还缺：`fillFromDetail` 不补封面（E05.3）。

## 代码地图

模型和接口（`packages/live_core/lib/src/`）：

| 文件 | 职责 | 任务 |
|---|---|---|
| `live_room.dart`（830 行） | `LiveStatus`（`:9`，序号即存储格式，`carousel` `:30`）、`LiveRestriction`（`:39`）、`FollowGroup`（`:78`）、`CatchUp`（`:92`）、`LiveRoom`（`:154`：`fromJson` `:210`、`identityKey` `:361`、`isPlayableNow` `:390`、`followGroup` `:408`、`displayNick` `:420`、`withAudienceFallbackFrom` `:550`、`mergeFrom` `:587`、`pendingAfterError` `:642`、`fillFromDetail` `:652`、`copyWith` `:663`、`toJson` `:729`） | E05.1、E05.2、E05.3 |
| `audience.dart`（350） | 人数口径 `AudienceMetricType`（`:4`）、在线数能力 `AudienceOnlineAvailability`（`:22`）、每个平台的能力表 `AudiencePlatformCapability`（`:36`）、排序键 `AudienceRankKey`（`:310`） | E05.1 |
| `live_area.dart`（167） | `LiveArea`（`:8`）、`LiveCategory`（`:92`）、`LiveAnchorItem`（`:112`）、`LivePlayQuality`（`:134`） | E05.1 |
| `live_message.dart`（434） | 弹幕消息、颜色、样式、表情、徽章、撤回、通知、人数更新、醒目留言（`LiveMessage` `:280`、`LiveSuperChatMessage` `:373`） | E05.1；字段由 D01 加 |
| `live_site.dart`（518） | `LiveSite`（`:19`）、`superChatPlatforms`（`:70`）、`LivePlayUrlResolution`（`:80`）、`resolveAppliedPlayQuality`（`:224`）、`normalizePlayLines`（`:244`）、15 个可选能力接口（`:277-416`）、扩展 `LiveSiteCalls`（`:418`）、`LiveQualityDiscoveryScope`（`:486`） | E05.1、E06.1 |
| `play_line.dart`（90） | `StreamFormat`（`:4`）、`PlayLease`（`:18`，续期和失效时间）、`LivePlayLine`（`:41`，地址、请求头、格式、编码、线路编号、宽高） | E01.1 加，全平台用 |
| `site_error.dart`（121） | `SiteError`（`:9`）和九种错误 | E05.1 |
| `sites.dart`（303） | `SiteIds`（`:4`，平台编号；`supported` `:114` 显示顺序；`retired` `:157`、`retiredHosts` `:173`；`caseInsensitiveRoomIds` `:223`）、`SiteRegistry`（`:263`） | E04.1、E05.2 |
| `quality_label.dart`（122）、`hls_master.dart`（347）、`hls_source_query_policy.dart`（87）、`input_recipe.dart`（8） | 画质标签转中文；HLS 主列表解析和选档；按地址生效的查询参数策略；会话型输入配方接口（niconico、FC2） | E05.1、各平台 |
| `json.dart`（136）、`html.dart`（235）、`convert.dart`（2）、`aes.dart`（266）、`tars.dart`（448） | 宽松 JSON 读取、`normalizeImageUrl`（`json.dart:123`）、去占位字符；HTML 读取；AES（斗鱼、抖音等）；TARS/WUP（虎牙） | 各平台 |
| `live_danmaku.dart`（64） | 3.x 的 `LiveDanmaku`、`EmptyDanmaku`；现在没人用（见已知问题） | E05.1 |

应用（`apps/pure_live/lib/app/`）：

| 文件 | 职责 |
|---|---|
| `platforms.dart`（278） | 代理策略 `SettingsProxyPolicy`（`:13`）、`PlaybackProxyPolicy`（`:35`）；`StoreCookieVault`（`:52`）、`StoreDouyuLogin`（`:68`）；`PlatformDeps`（`:95`）；`buildSiteRegistry`（`:135`）；`buildDanmakuRegistry`（`:196`，D01）；3.x 关注身份迁移 `identityResolver`（`:265`，niconico、YouTube、抖音） |
| `bootstrap.dart`（273）、`services.dart`（146） | 启动时建注册表（`bootstrap.dart:186`）；`sitesProvider`（`services.dart:112`） |

测试（`packages/live_core/test/`）：

| 测试文件 | 覆盖什么 |
|---|---|
| `live_room_test.dart`（30 个 `test(`） | 3.x 移植的人数口径和状态用例、JSON 逐字段往返、枚举序号、身份、`fillFromDetail`（`:178-195`） |
| `live_room_upgrades_test.dart`（28） | E05.2 全部；3.x 样本 6139 个房间 JSON 往返 |
| `models_test.dart`（14）、`live_site_test.dart`（12）、`hls_source_query_policy_test.dart`（8）、`hls_master_test.dart`（9）、`html_test.dart`（3）、`aes_test.dart`（4） | 分区和画质、弹幕颜色、错误；取流清理和确认、画质探测生命周期；HLS；工具 |
| `sites_links_test.dart`（23） | 注册表和平台编号（E04.1） |

## 3.x 基线

- 模型：`git show v3.2.11:lib/common/models/live_room.dart`（912 行）：三份状态 `status`、`isRecord`、`liveStatus`（`:290-292`），`_legacyStatusToLiveStatus`（`:354`）；`fillFromDetail`（`:899-906`）。其余在 `lib/common/models/live_area.dart`、`live_message.dart`（200 行），`lib/model/` 的分类、主播、画质。
- 接口：`lib/core/interface/live_site.dart`（332 行）：`LivePlayUrlResolution`（`:26`）、可选能力（`:144-331`）、`class LiveSite`（`:195`，`getCategores` `:203`、`getRoomDetail(roomId, platform)` `:223`、`getPlayQualites` `:244`）。
- 注册表：`lib/core/sites.dart`（457 行）：`supportSites` 是 getter（`:217`），每读一次新建 34 个适配器；`Sites.of`（`:269-417`）每次新建。
- 必须保留：3.x JSON 能读、能写回（覆盖安装和备份，D-018）；平台编号和顺序；已下线平台的关注和链接显示“已下线”而不是报错。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| `fillFromDetail` 不补封面，详情不给封面时观看记录、纯音频封面、通知大图变空 | `live_room.dart:652-660` | 观看记录没封面 | [E05.3](E05.3-房间详情补齐时连封面一起补/README.md) |
| `LiveSite.getDanmaku()` 和 `live_danmaku.dart` 的 `LiveDanmaku`、`EmptyDanmaku` 没有调用方：弹幕走 `DanmakuRegistry`（`packages/live_danmaku/lib/src/registry.dart:42`） | `live_site.dart:27`、`live_danmaku.dart:9`、`:50` | 死代码，新平台作者可能以为要实现 `getDanmaku` | 写进本组报告；以后整理时删（Z 组），没有任务 |
| `LiveSite.getPlayUrls` 只返回地址、丢掉请求头和格式，应用都走 `resolvePlayUrls`；只剩测试替身实现它 | `live_site.dart:53` | 无（兼容 3.x 接口） | 不做 |
| 虎牙别名房间号、BIGO 以外的字母房间号是否不分大小写没核实完 | `sites.dart:223` | 大小写不同时可能出现两个关注 | 巡检时核实（E01.6、E07.1），有证据再加 |
| 代码注释里还用旧编号（`M3`、`M5`、`M9`、`M4.34` 等） | `platforms.dart:134`、`:190`、`:261`，`sites.dart:156`、`:217` 等 | 按注释找文档要先查 MAPPING | Z 组一次性替换 |

## 相关决定和规范

- D-001（在 3.x 代码上逐块重构）、D-002（类型化错误等借自归档 v4 的包）、D-017（测试不访问真实平台，样本测试）、D-018（3.x 设置键名和含义不变；同样适用于房间 JSON 的键）。
- [specs/UPGRADES.md](../../specs/UPGRADES.md)：“统一原则”（受限的直播仍是直播、拿不到的标不可播放）、X-1（Kick 恢复）、X-2（占位值不覆盖）。
- [specs/ENGINEERING.md](../../specs/ENGINEERING.md)：分层（第 35 行：内核是纯 Dart 包）和包的依赖方向（第 51 行：`live_core` → `live_net`，门禁 `check_deps.py` 检查）。

## 测试和验证

- 自动测试：`cd packages/live_core && dart test test/live_room_test.dart test/live_room_upgrades_test.dart test/models_test.dart test/live_site_test.dart`；全部平台测试 `dart test`。覆盖 JSON 兼容、合并、身份、取流清理；缺的：`fillFromDetail` 的封面（E05.3）。
- 真机：模型没有单独步骤；3.x 数据兼容看 [S02 的 CHECKLIST.md](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 5 节第 1、9 条（恢复 3.x 备份、覆盖安装后数据都在），关注分组看第 4 节第 1 条。

## 路线

1. [E05.3](E05.3-房间详情补齐时连封面一起补/README.md)（第二档，小）：`fillFromDetail` 加封面，一行代码加两个测试。
2. 以后：清理 `getDanmaku` 死代码和旧编号注释（Z 组）；虎牙等字母房间号的大小写在巡检时核实后加进 `caseInsensitiveRoomIds`。新想法写进 V01 提议，不直接加任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [E 直播平台](../README.md)。

- 代码：`packages/live_core/lib/src/`
- 进度：`████████████████░░░░` 80%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| E05.1 | 基础模型与接口 | 平台 | 完成 | 2026-09-28 | 50d4f9bdb | [设计或说明](E05.1-基础模型与接口/README.md)、[记录](E05.1-基础模型与接口/record.md) |
| E05.2 | 模型扩展：开播时间、受限类型、轮播和不可播放状态、房间身份 | 平台 | 完成 | 2026-09-29 | 87bc61dfc | [设计或说明](E05.2-模型扩展/README.md)、[记录](E05.2-模型扩展/record.md) |
| E05.3 | 房间详情补齐时连封面一起补（fillFromDetail 漏了封面，观看记录等处封面变空） | 功能 | 未开始 | — | — | [设计或说明](E05.3-房间详情补齐时连封面一起补/README.md)、[任务书](E05.3-房间详情补齐时连封面一起补/brief.md) |

## 还没完成的

- **E05.3 房间详情补齐时连封面一起补（fillFromDetail 漏了封面，观看记录等处封面变空）**（未开始，第二档，规模 小）
  - 说明：上游 pure_live fa67c637f、pure_live_TV 5bc53016 修了同一个问题

<!-- docs:生成结束 -->
