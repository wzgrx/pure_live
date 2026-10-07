# E05.1 基础模型与接口

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 逐块重构（D-001）的第一块：所有平台、直播间、关注、录制都依赖的模型和平台接口，必须先于 E01～E03 的平台重构完成
- 旧编号：M2、T02g.1
- 相关：模型扩展 [E05.2](../E05.2-模型扩展/README.md)；注册表和链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；封面补齐 [E05.3](../E05.3-房间详情补齐时连封面一起补/README.md)；弹幕模型的使用方 [D01.1](../../../D-弹幕/D01-平台弹幕协议/D01.1-弹幕框架和过滤/README.md)；3.x 数据迁移和存储 J 组（J02.1、J06.1）；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/` 的 `live_room.dart`（830 行）、`audience.dart`（350）、`live_area.dart`（167）、`live_message.dart`（434）、`live_site.dart`（518）、`live_danmaku.dart`（64）、`input_recipe.dart`（8）、`hls_source_query_policy.dart`（87）、`quality_label.dart`（122）、`convert.dart`（2）、`site_error.dart`（121）、`play_line.dart`（90）、`json.dart`（136）；对外导出 `packages/live_core/lib/live_core.dart`（95 行）

## 目标

把 3.x 散在 `lib/common/models/` 和 `lib/core/interface/` 里的直播间、分区、弹幕消息、画质、平台接口重构成一个纯 Dart 包 `live_core`（只依赖 `live_net`、`meta`，不依赖 Flutter、GetX、dio），后面 34 个平台适配器、弹幕包、存储、播放、录制、界面都只认这一套模型。做完以后：

- 直播间模型不可变、身份（平台 + 房间号）创建后不能改，放进集合和 Map 不会丢；
- 3.x 存下的 JSON（关注、观看记录、备份）逐字段读得进来、写回去 3.x 也读得懂；
- 平台出错用类型化的 `SiteError`，不再返回一个“看起来像未开播”的房间（3.x 临时出错会让录制停掉）。

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/`） | 现在（`packages/live_core/lib/src/`） | 说明 |
|---|---|---|---|
| 直播间 | `common/models/live_room.dart`（912 行），字段可变；`status`、`liveStatus`、`isRecord` 三份状态（`:290-292`），构造默认 `status=false` | `live_room.dart:154` `LiveRoom`，不可变；只有 `liveStatus`（`:9` `LiveStatus`：live、offline、replay、unknown、banned，E05.2 加 carousel），null 表示“这次回答没说” | 记录问题 1、3；没给状态就是“待定”而不是“未开播” |
| 身份和相等 | 按可变字段算 `==`、`hashCode` | `identityKey`（`:361`）、`hasIdentity`（`:368`）、`identityKeyFor`（`:376`）、`hashCode`（`:826`）；创建时平台转小写、房间号去空白 | 问题 1 |
| JSON | `toJson` 不写 `link` | `fromJson`（`:210`）、`toJson`（`:729`）键名照 3.x，`liveStatus` 存序号（顺序不能变），多写 `link` | 问题 5；J02.1 迁移靠它 |
| 回看 | 可空字段混在房间里，`copyWith` 清不掉 | `CatchUp`（`:92`）值对象、`withoutInterval()`（`:133`）、`LiveRoom.withoutCatchUp()` | 问题 4 |
| 合并 | 刷新时稀疏合并 | `mergeFrom`（`:587`）：空值保留已存的，标签只在本地，IPTV 请求头以播放列表为准；`pendingAfterError`（`:642`）；`fillFromDetail`（`:652`）；`withAudienceFallbackFrom`（`:550`） | 行为同 3.x；`fillFromDetail` 漏封面见 E05.3 |
| 人数口径 | 在 `live_room.dart` 里 | `audience.dart`：`AudienceMetricType`（`:4`）、`AudienceOnlineAvailability`（`:22`）、每个平台的能力表 `AudiencePlatformCapability`（`:36`）、排序键 `AudienceRankKey`（`:310`）；`LiveRoom.compareAudienceRanking`（`live_room.dart:525`） | 热度、在线、累计分开；数值相同按身份排，刷新不乱跳 |
| 分区、主播、画质 | `common/models/live_area.dart` 等 4 个文件 | `live_area.dart`：`LiveArea`（`:8`）、`LiveCategory`（`:92`）、`LiveAnchorItem`（`:112`）、`LivePlayQuality`（`:134`） | `withPlaybackUnconfirmed(unconfirmed:)` 改命名参数（问题 10） |
| 弹幕消息 | `common/models/live_message.dart`（200 行）；颜色只认 4、6、8 位十六进制 | `live_message.dart`：`LiveMessageType`（`:4`）、`LiveMessageColor`（`:187`，位运算解析）、`LiveMessage`（`:280`）、`LiveSuperChatMessage`（`:373`）；撤回、通知、人数、样式、表情、徽章（`:29`～`:257`）后来由 D01 加 | 问题 6；弹幕协议本身在 D01 |
| 平台接口 | `core/interface/live_site.dart:195` `class LiveSite`，`id`/`name` 可变，`getCategores`（`:203`）、`getPlayQualites`（`:244`）拼错，`getRoomDetail` 多一个 `platform`（`:223`） | `live_site.dart:19` `abstract class LiveSite`：`id`、`name` 是 getter，`getCategories`（`:30`）、`searchRooms`（`:33`）、`searchAnchors`（`:36`）、`getCategoryRooms`（`:39`）、`getRecommendRooms`（`:42`）、`getRoomDetail`（`:46`，默认 `unknown` 而不是空房间号）、`getPlayQualities`（`:50`）、`getPlayUrls`（`:53`）、`getLiveStatus`（`:56`）、`getSuperChatMessage`（`:59`） | 问题 7 |
| 可选能力 | `LivePlayUrlResolver` 等接口（`core/interface/live_site.dart:144-331`）、`live_search.dart`、`live_directory.dart`、`live_quality_discovery.dart` | `live_site.dart:277-416` 的 15 个接口（取流确认 `LivePlayUrlResolver`、游标 `LivePlayUrlCursorResolver`、恢复 `LivePlayRecoveryResolver`、租期 `LivePlayLeaseMetadata`、轻量刷新 `LiveSiteRoomRefresher`、录制详情 `LiveSiteRecordRoomResolver`、可取消搜索、分页策略、画质探测、目录分页、Cookie 被拒 `LiveSiteCookieRefusals`、目录说明）和统一调用的扩展 `LiveSiteCalls`（`:418`） | 调用方式和 3.x 一样经扩展方法；`CancelToken` 改用 `live_net` 的（问题 8） |
| 取流结果 | `LivePlayUrlResolution`（`core/interface/live_site.dart:26`） | `live_site.dart:80`；`normalized()`、`resolveAppliedPlayQuality`（`:224`）、`normalizePlayLines`（`:243`）；线路 `LivePlayLine`（`play_line.dart:41`，请求头、格式 `StreamFormat` `:4`、编码、线路编号、租期 `PlayLease` `:18`） | 线路模型由 E01.1 加，所有平台共用 |
| 错误 | 返回假房间或一句中文 | `site_error.dart:9` `sealed class SiteError` 和 9 种：`NotFound`（`:29`）、`NeedsLogin`（`:38`）、`RateLimited`（`:47`）、`RiskControl`（`:63`）、`RegionBlocked`（`:75`）、`StreamUnavailable`（`:85`）、`UnsupportedLink`（`:94`）、`ApiChanged`（`:103`）、`NetworkFailure`（`:112`） | 问题 9；来自归档 v4（D-002 只借鉴写好的包） |
| 画质标签 | `core/utils/live_quality_label.dart`（150） | `quality_label.dart:3` `LiveQualityLabel` | 平台代码转中文，原来是中文的不动 |

## 结果

- 首次重构（2026-09-28，提交 `50d4f9bdb`）：对照表、10 个 3.x 问题、保留的行为、有意变化（不再默认未开播、回放并入 `liveStatus`、多写 `link`）见 [record.md](record.md)。
- 放到别处的：`binary_writer`、`list_util` → D01；`tars` → 虎牙（现在是 `packages/live_core/lib/src/tars.dart`，E01.3 用）；音量存储 → G、J；`audienceMetricI18nKey` → 界面层。
- 后来在同一批文件上的增补（不在本任务的提交里）：E05.2 的开播时间、受限类型、轮播、身份；E01.1 的 `LivePlayLine`、`PlayLease`、`normalizeImageUrl`（`json.dart:123`）；D01 的消息样式、徽章、撤回；E06.1 的 `appliedQuality`、`start`、`LiveSiteCookieRefusals`。
- 测试：记录当时 81 个用例。现在 `packages/live_core/test/` 里本任务的文件：`live_room_test.dart` 30 个 `test(` 写法、`models_test.dart` 14、`live_site_test.dart` 12、`hls_source_query_policy_test.dart` 8。

## 验证

- 自动测试：上面四个文件：3.x 三个测试文件的 26 个用例移植（人数口径、状态、出错退回待定）；3.x JSON 逐字段往返；状态枚举序号；身份规范化和集合去重；弹幕颜色 1～3、5、7 位和负数；取流清理和画质确认；画质探测生命周期；基类默认实现。
- 3.x 数据：`live_room_upgrades_test.dart`（E05.2）读 `fixtures/*/*/expected.json` 里 3.x 输出的 6139 个房间 JSON，逐个检查往返不变。
- 真机：模型本身没有单独的真机步骤；JSON 兼容由覆盖安装 3.x 后关注、观看记录照旧来间接验证（[S02 的 CHECKLIST.md](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 5 节第 1 条恢复 3.x 备份、第 9 条 3.x 数据都在），这两条还没有结果。

## 留下的问题

- `fillFromDetail` 照 3.x 只补分区、昵称、头像（E05.2 加了标题），漏了封面：[E05.3](../E05.3-房间详情补齐时连封面一起补/README.md)。
- pure_live_TV 的模型改成 freezed，`AudienceMetricType` 顺序也变了，和 3.x JSON 不兼容；以 3.x 格式为准，电视端并入时用同一个模型（X 组）。
- pure_live_TV 的按弹幕类型取颜色（`LiveMessageColor.fromType`）留给 D01 评估，没有任务管。
- 记录里的旧编号（M2、M13 等）对照 [MAPPING.md](../../../MAPPING.md)。
