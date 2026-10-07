# E05.2 模型扩展：开播时间、受限类型、轮播和不可播放状态、房间身份

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：[specs/UPGRADES.md](../../../specs/UPGRADES.md) 的“统一原则”和模块列含 E05.2 的 28 条已批准升级（例如 1-1 哔哩哔哩轮播、7-9 SOOP 开播时间、11-8 关注大小写重复、X-2 占位值）；各平台的升级落地（2026-09-29）都依赖这里先加的字段
- 旧编号：M2.1、T02g.2
- 相关：基础模型 [E05.1](../E05.1-基础模型与接口/README.md)；平台层升级 [E06.1](../../E06-平台层升级/E06.1-已批准升级的余项/README.md)（各平台按这里的规则填字段）；轮播接到界面 [E06.2](../../E06-平台层升级/E06.2-平台层新数据接到界面/README.md)；`fillFromDetail` 补封面 [E05.3](../E05.3-房间详情补齐时连封面一起补/README.md)；存储和迁移 J02.1；关注分组的界面 I 组；决定 D-001、D-018
- 代码：`packages/live_core/lib/src/live_room.dart`（830 行）、`packages/live_core/lib/src/sites.dart`（303 行）

## 目标

在不改变 3.x JSON 的前提下，给直播间模型加上 3.x 没有、已批准升级都要用的几样东西，让各平台在升级落地时有统一的地方填：

- 开播时间（卡片和直播间显示“已开播 N 分钟”）；
- 受限类型（付费、仅订阅者、私密、地区受限……），卡片能标出来、播放时能说明原因；
- 轮播（哔哩哔哩主播不在时放录像）单独成状态，不再当“直播中”或“未开播”；
- 关注分组（直播中、回放、未开播）由模型给出；
- 房间号是用户名、平台不分大小写的，大小写不同的写法算同一个房间（关注不重复）；
- 占位名字的规则：拿不到就留空，界面显示平台名。

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/common/models/live_room.dart`） | 现在（文件:行） | 说明 |
|---|---|---|---|
| 开播时间 | 没有 | `LiveRoom.startedAt`（`live_room.dart:176`，构造时转 UTC `:195`）；JSON `startedAt` 读 ISO 或毫秒（`:243`） | 只在有值时写键，旧数据读进来为 null |
| 受限类型 | 没有；各平台用 `banned`、`unknown` 或报错表示 | `LiveRestriction`（`:39`）：none、needsLogin、paid、subscribersOnly、private、appOnly、regionBlocked、password、adult、unplayable；`fromName`（`:74`，不认识的名字读成 none）；`effectiveRestriction`（`:400`）、`isRestricted`（`:403`） | null =“这次没说”，none =“平台说没有限制” |
| 轮播 | `live_status=2` 当未开播（3.x 只认 1） | `LiveStatus.carousel`（`:30`，下标 5，追加在末尾）；`isPlayableNow`（`:390`）为假、`isExplicitlyOfflineNow`（`:393`）为真 | 3.x 读到 5 退回 `status`，读成未开播，不报错 |
| 关注分组 | 3.x 关注页里按 `status`、`isRecord` 分 | `FollowGroup`（`:78`）、`followGroup`（`:408`）：受限的直播仍在直播中，`replay` + `unplayable` 归未开播 | 分组规则写进模型，关注页直接用 |
| 身份 | 按原写法比较 | `SiteIds.caseInsensitiveRoomIds`（`sites.dart:223`，现在 10 个：Twitch、SOOP、Picarto、TwitCasting、TikTok、PandaTV、斗鱼、快手、BIGO、Kick）、`ignoresRoomIdCase`（`:238`）；`identityKeyFor`（`live_room.dart:376`）转小写后比较 | 记录时 6 个，之后各平台实测加了斗鱼（E01.2）、快手（E01.5）、BIGO（E03.11）、Kick（E03.16） |
| 合并 | — | `mergeFrom`（`:587-640`）：`startedAt`、`restriction` 新值优先；没给时状态没变就保留，状态变了就清成 null | 防止下一场显示上一场的开播时间 |
| 占位值 | 适配器填“JD Live”“Steam Broadcast”等 | 类注释（`:146-152`）；`hasNick`（`:415`）、`displayNick(平台名)`（`:420`） | UPGRADES X-2 |
| 补齐 | `fillFromDetail` 补分区、昵称、头像（`:899-906`） | `fillFromDetail`（`:652`）多补标题（A-3：快手房间页没有标题） | 封面仍漏，E05.3 |

## 结果

- 2026-09-29 合并（提交 `87bc61dfc`；记录写的是 2026-09-28 完成）：上表全部；JSON 兼容规则、状态对照表（6 个下标 × 直播中 / 可播放 / 明确不在播 / 分组 / 3.x 读到的状态）、受限类型和对应错误、合并规则、身份平台表、给 E06、J02.1、界面的说明都在 [record.md](record.md)。
- 适配器只做了机械更新：`youtube_site.dart`、`tiktok_site.dart` 两处穷尽 `switch` 把 `carousel` 并进 `offline` 分支，行为不变。
- 测试：`packages/live_core/test/live_room_upgrades_test.dart` 28 个 `test(` 写法（开播时间往返、受限类型和“未提供 / none”、轮播下标和分组、所有平台逐个比较大小写、合并规则、占位值、3.x 样本 6139 个房间 JSON 往返不变）；`live_room_test.dart` 的枚举顺序用例加了 `carousel`。

## 验证

- 自动测试：上面两个文件；`live_room_upgrades_test.dart` 读 `fixtures/*/*/expected.json`，覆盖 33 个平台的 3.x 冻结输出。
- 真机：没有单独的 K90 记录。2026-10-01 的两轮真机测试看过国内五大平台、YY、CC 的播放（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节），关注分组、开播时长、受限标记没有逐项记录，归 [S02 的 CHECKLIST.md](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 1 条（开播时长）、第 4 节第 1 条（分组）；轮播在直播间里的入口还没接（E06.2），没看过。

## 留下的问题

- 哔哩哔哩轮播在直播间里能播、从中途开始：平台层已给（E06.1），界面在 [E06.2](../../E06-平台层升级/E06.2-平台层新数据接到界面/README.md) 第 1 阶段。
- 虎牙别名房间号是否不分大小写没有实测，没加进集合；有证据后按记录的规则加（巡检时顺带核实，[E01.6](../../E01-国内五大平台/E01.6-国内五大平台巡检和修复/README.md)）。
- 3.x 关注里大小写不同的重复项要在迁移时按 `identityKey` 合并（UPGRADES 11-8）：归 J02.1 / J06.1。
- `fillFromDetail` 不补封面：[E05.3](../E05.3-房间详情补齐时连封面一起补/README.md)。
- 记录里的旧编号（M13、M2.1）对照 [MAPPING.md](../../../MAPPING.md)。
