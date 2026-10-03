# A09.11 Picarto 搜索卡片显示频道简介：设计（第 0 版，还没出图）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 范围：搜索结果里 Picarto 的房间卡片（以及其他“标题就是主播名、平台给了简介”的卡片，见待选 X1）的第二行文字
- 对应：已批准升级 [11-5](../../../specs/UPGRADES.md)（“搜索卡片用频道名作标题并显示简介”）；平台任务 [E03.3 Picarto](../../../E-直播平台/E03-海外平台/E03.3-Picarto/record.md)（升级落地 11-5）；卡片设计 [A09.1](../A09.1-房间卡片/README.md)；搜索页 [A09.7](../A09.7-搜索/README.md)
- 评审页：还没有（出图后发布，源文件 `page.json`，效果图源文件 `src/`）
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

## v4 现在

- 平台层：`packages/live_core/lib/src/sites/picarto/picarto_api.dart:295-331` 的 `searchRooms`：`title: name`、`nick: name`、`introduction: bio`（解码 HTML 字符、去首尾空白，空的不填）。样本 `fixtures/picarto/S03-search` 的 20 个结果里 8 个有简介（E03.3 记录）。
- 卡片数据：`apps/pure_live/lib/shared/rooms/room_cards.dart:82-99` 的 `cardOf`：`title`、`anchorName`（主播名，在播时后面加“· 已播 N”）……没有简介。
- 卡片：`packages/live_ui/lib/src/widgets/room_card.dart:44` 的 `RoomCardData`（没有简介字段）；`packages/live_ui/lib/src/widgets/live_room_card.dart:309-330` 的 `title()`（一行，600）和 `anchorName()`（一行，500，`onSurfaceVariant`）。
- 搜索页：`apps/pure_live/lib/features/search/search_view.dart:569` 用 `RoomGridCard`，经 `shared/rooms/room_grid.dart:131` 调 `cardOf`。
- 其他平台也有“标题等于主播名、带简介”的卡片：已确认 CHZZK 的频道搜索（`packages/live_core/lib/src/sites/chzzk/chzzk_api.dart:725-730`：`nick`、`title` 都是频道名，`introduction` 是频道说明）；其余平台待查（brief 第 1 阶段在 `packages/live_core/lib/src/sites/` 里列出所有 `title` 取主播名的地方）。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 0 版 | 只有上面的核对和建议，还没出图 | — |

## 对比页（按章节导出）

无：还没出评审页。

## 单张图

无。要画的：3.x 的 Picarto 搜索卡片（标题空）、v4 现在（两行都是频道名）、v4 改后（第二行是简介），大号、小号、紧凑各一张，竖屏和宽屏。

## 确认的改动

还没确认。建议：

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 修改 | 标题等于主播名（不分大小写、去首尾空白）且房间有简介时，卡片第二行显示简介的第一行（一行省略，样式同主播名行）；主播名已经在标题里，不重复 | P1、P2 |
| c2 | 保留 | 卡片高度、行数、其他平台的卡片不变（不加第三行） | — |
| c3 | 保留 | 长按菜单不加简介（A09.1 的决定） | — |

## 按钮的作用和用法

无：只换第二行的文字，点按、长按照 A09.1。

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 搜索页的卡片 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 同一张卡片；电脑悬停时显示完整标题（A09.1 c9），简介同样一行省略 |
| 电视 | 电视搜索（A17.3）用同一个 `cardOf`，以后自动带上 |
| 苹果平台差异 | 无 |

## 待选和决定

- X1：规则只认 Picarto 还是通用。A（建议）通用规则“标题等于主播名且有简介”，所有平台一样（UI.md 第 3 节第 6 条：同一件事一种做法）；B 只对 `platform == 'picarto'`。
- X2：简介放哪一行。A（建议）替换重复的主播名行；B 加第三行（所有卡片高度不齐，不建议）。

## 实现和验证（开发后补）

- 还没开始。步骤见 [brief.md](brief.md)。
