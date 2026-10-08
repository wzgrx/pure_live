# A09.11 Picarto 搜索卡片显示频道简介：设计（第 1 版，定稿）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 范围：搜索结果里 Picarto 的房间卡片（以及其他“标题就是主播名、平台给了简介”的卡片，见待选 X1）的第二行文字
- 对应：已批准升级 [11-5](../../../specs/UPGRADES.md)（“搜索卡片用频道名作标题并显示简介”）；平台任务 [E03.3 Picarto](../../../E-直播平台/E03-海外平台/E03.3-Picarto/record.md)（升级落地 11-5）；卡片设计 [A09.1](../A09.1-房间卡片/README.md)；搜索页 [A09.7](../A09.7-搜索/README.md)
- 评审页：没有（定稿说明见“各版的经过”：卡片的尺寸、行数、样式都是 A09.1 已确认的，只换第二行的文字）
- 来源：V03.3 核对升级表时，11-5 的界面部分写着“A09.1 卡片信息区只有标题、主播名两行……要显示需先改 A09.1 设计 → 未排（E06.1 第 3 条 c2 不做）”，开了本任务

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| A09.11-01 | Picarto 搜索结果卡片（大号“标准”） | 搜索 → 平台选 Picarto 或“全部” → 输入关键词 | 竖屏、宽屏 | 在播、未开播；有简介、没简介 |
| A09.11-02 | 同上，小号（`dense`）和“简洁”预设的紧凑信息行 | 设置 → 房间卡片外观改预设 | 竖屏、宽屏 | 同上 |
| A09.11-03 | 长按菜单的标题行 | 搜索结果长按卡片 | 竖屏、宽屏 | 不改（A09.1 去掉了简介，保持） |

## 3.x 的样子和问题

- 3.x 的 Picarto 搜索（`git show v3.2.11:lib/core/site/picarto/picarto_api.dart:189-235` 的 `searchProfiles`）：资料里没有直播标题，`LiveRoom` 不填 `title`（`:220-232`），只有 `nick` = 频道名，简介 `bio` 不读。卡片（3.x `lib/common/widgets/room_card.dart:1172-1221` 的信息区：标题一行、主播名一行）的标题行是空的。
- 问题：P1 标题行空着（3.x）；P2 v4 平台层把标题改成了频道名（11-5 的前半），结果两行都是频道名，简介（`bio`）读了却没地方显示。

### v4 现在（2026-10-03 核对）

- 平台层：`packages/live_core/lib/src/sites/picarto/picarto_api.dart:295-331` 的 `searchRooms`：`title: name`、`nick: name`、`introduction: bio`（解码 HTML 字符、去首尾空白，空的不填）。样本 `fixtures/picarto/S03-search` 的 20 个结果里 8 个有简介（E03.3 记录）。
- 卡片数据：`apps/pure_live/lib/shared/rooms/room_cards.dart:82-99` 的 `cardOf`：`title`、`anchorName`（主播名，在播时后面加“· 已播 N”）……没有简介。
- 卡片：`packages/live_ui/lib/src/widgets/room_card.dart:44` 的 `RoomCardData`（没有简介字段）；`packages/live_ui/lib/src/widgets/live_room_card.dart:309-330` 的 `title()`（一行，600）和 `anchorName()`（一行，500，`onSurfaceVariant`）。
- 搜索页：`apps/pure_live/lib/features/search/search_view.dart:569` 用 `RoomGridCard`，经 `shared/rooms/room_grid.dart:131` 调 `cardOf`。
- 其他平台也有“标题等于主播名”的卡片。2026-10-03 在 `packages/live_core/lib/src/sites/` 里按“`LiveRoom(` 里 `nick:` 和 `title:` 是同一个表达式”粗查了一遍（只查了字面相同的，`title` 由别的变量拼出主播名的没查到，brief 第 1 阶段要再核一遍、并确认这些房间会不会出现在卡片列表里）：

| 平台 | 位置 | 有没有简介 | 规则通用时 |
|---|---|---|---|
| Picarto | `picarto/picarto_api.dart:313`（`searchRooms`，`nick`/`title` `:317-318`，`introduction` `:325`） | 有（`bio`） | 本任务的目标 |
| CHZZK | `chzzk/chzzk_api.dart:721`（`channelCard`，`:725-726`，`introduction` `:730`） | 有（频道说明） | 受影响（频道搜索卡片） |
| 快手 | `kuaishou/kuaishou_api.dart:196`（`_searchRoom` `:190`，`:200-201`，`introduction` `:206`） | 有（`author['description']`） | 受影响（主播搜索结果） |
| SHOWROOM | `showroom/showroom_api.dart:496`（`room` `:493`，`:500-501`，`introduction` `:509`） | 有（`profile.description`） | 受影响（看 `room` 用在哪些列表） |
| 映客 | `inke/inke_api.dart:359`（`_card` `:353`，`:363-364`） | 没有 | 不受影响（没有简介照旧显示主播名） |
| PandaTV | `pandalive/pandalive_api.dart:685`（`profileCard` `:676`，`:689-690`，`introduction: ''` `:696`） | 空 | 不受影响 |
| 微博 | `weibo/weibo_api.dart:292`（`recommendations` `:280`，`:296-297`） | 没有 | 不受影响 |

### 第 1 阶段复核（2026-10-08）

按“`LiveRoom` 带非空 `introduction`”逐个看了 `packages/live_core/lib/src/sites/` 里的 37 处，标题等于主播名的情况：

| 来源 | 位置 | 什么时候标题等于主播名 | 出现在哪些卡片 |
|---|---|---|---|
| Picarto 搜索 | `picarto/picarto_api.dart:313-325` | 总是 | 搜索 |
| CHZZK 频道卡片 | `chzzk/chzzk_api.dart:721-730` | 总是 | 搜索（频道）；未开播的详情（`:874`） |
| 快手主播搜索 | `kuaishou/kuaishou_api.dart:190-206` | 总是 | 搜索（主播） |
| SHOWROOM 详情 | `showroom/showroom_api.dart:493-509` | 总是（资料没有直播标题） | 进房、刷新关注后关注页的卡片 |
| 百度直播 | `baidulive/baidulive_api.dart:813-821` | 没有视频标题时退到主播名 | 推荐和搜索 |
| PandaTV | `pandalive/pandalive_api.dart:851-863`、`:889-905` | 没有频道标题时退到主播名 | 详情 |
| TikTok | `tiktok/tiktok_api.dart:402-412` | 标题空时退到主播名 | 详情 |

- 不受影响：标题为空的（AcFun 用户搜索、Kick 频道、YouTube 未开播频道，卡片标题是“未命名直播间”，和主播名不同）；克拉克拉的 `profileRoom` 标题是主播名但没有简介；快手推荐 `:539` 标题是简介本身，不等于主播名。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 0 版 | 只有上面的核对和建议，还没出图 | — |
| 第 1 版（2026-10-08） | 定稿：c1～c3 按建议，X1、X2 选 A（D-003，维护者按建议定）；受影响的来源按上面的复核表。不出图：卡片的尺寸、行数、字号、颜色都是 A09.1 已确认的，只把重复的主播名换成简介的第一行。判断放在应用层 `cardOf`；为了让头像的字母、电视卡片和未开播的行（`RoomRow`，第一行就是主播名）仍用主播名，`RoomCardData` 加一个可选字段 `introLine`（只加不改），只有房间卡片的第二行读它 | 按 D-003 定，用户可以推翻 |

## 对比页（按章节导出）

无：没有新的布局和控件，不出评审页（第 1 版说明）。

## 单张图

无：同上。改前改后只差第二行的文字：v4 现在两行都是频道名，改后第二行是简介的第一行（3.x 第一行是空的）。

## 确认的改动

已确认（第 1 版，D-003）：

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 修改 | 标题等于主播名（不分大小写、去首尾空白）且房间有简介时，卡片第二行显示简介的第一个非空行（一行省略，样式同主播名行）；主播名已经在标题里，不重复。在播时照旧在后面加“· 已播 N”（E06.1） | P1、P2 |
| c2 | 保留 | 卡片高度、行数、其他平台的卡片不变（不加第三行） | — |
| c3 | 保留 | 长按菜单不加简介（A09.1 的决定） | — |

## 按钮的作用和用法

无：只换第二行的文字，点按、长按照 A09.1。

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 搜索页的卡片 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 同一张卡片；电脑悬停时显示完整标题（A09.1 c9），简介同样一行省略 |
| 电视 | 电视卡片（`tv_room_card.dart`）仍读主播名，没改；以后电视搜索要显示时读 `introLine` |
| 苹果平台差异 | 无 |

## 待选和决定

- X1：规则只认 Picarto 还是通用。**定：A**（D-003）。A（建议）通用规则“标题等于主播名且有简介”，所有平台一样（UI.md 第 3 节第 6 条：同一件事一种做法）；B 只对 `platform == 'picarto'`。**需要维护者决定**（单元 1 已提出）：选 A 时，上面粗查到的 CHZZK 频道搜索、快手主播搜索、SHOWROOM 的卡片第二行也会变成简介，评审页要把这几个平台各画一张。
- X2：简介放哪一行。**定：A**（D-003）。A（建议）替换重复的主播名行；B 加第三行（所有卡片高度不齐，不建议）。
- 判断放在哪一层：建议在应用层的 `cardOf`（`apps/pure_live/lib/shared/rooms/room_cards.dart:82`）里比较标题和主播名、取简介第一行，`live_ui` 的卡片和平台层都不改（单元 1 的建议“在应用层取数据”）。**定**：判断在 `cardOf`；`live_ui` 只加 `RoomCardData.introLine`、卡片第二行优先显示它（不能直接改 `anchorName`：头像的字母和 `RoomRow` 的第一行也读它）。

## 实现和验证（开发后补）

- 2026-10-08 做完（待真机）：`apps/pure_live/lib/shared/rooms/room_cards.dart` 的 `cardOf` 在标题（去空白、不分大小写）等于主播名且简介有字时填 `introLine`（简介第一个非空行，在播时加“· 已播 N”）；`packages/live_ui` 的 `RoomCardData.introLine`、`LiveRoomCard` 第二行优先显示它（大号、小号、“简洁”的紧凑行是同一个 `anchorName()`）。根因、测试和真机步骤见 [record.md](record.md)。
