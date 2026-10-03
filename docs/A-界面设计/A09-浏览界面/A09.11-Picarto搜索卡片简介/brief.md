# A09.11 Picarto 搜索卡片显示频道简介：任务书

## 背景

- 来源：已批准升级 11-5（`docs/specs/UPGRADES.md`）：“搜索卡片用频道名作标题并显示简介”。平台层在 E03.3 做完（标题是频道名、`introduction` 是资料的 `bio`）；E06.1 第 3 条 c2 因为 A09.1 卡片没有简介的位置没做；V03.3（2026-10-03）开了本任务。
- 现象：搜索 → Picarto → 输入关键词，每张卡片两行都是同一个频道名，频道简介不显示。
- 为什么现在做：第三档；已批准升级里唯一还没落到界面的卡片项，改动小。
- 已经做过的：E03.3（平台层 11-5）、A09.1（卡片设计）、I05.1（搜索）、E06.1（卡片“已播 N”）。

## 目标和验收

1. 先出图、发评审页（3.x、v4 现在、v4 改后；大号、小号、紧凑；竖屏、宽屏），用户确认或按 D-003 用建议定稿。
2. 定稿后：标题等于主播名且有简介的卡片，第二行显示简介的第一行（一行省略）；没有简介的照旧显示主播名。
3. 其他卡片（标题不等于主播名的）一个字都不变；卡片高度不变。
4. 测试和门禁通过。

## 现状（读代码得出，写文件:行）

- `packages/live_core/lib/src/sites/picarto/picarto_api.dart:295-331` 的 `PicartoApi.searchRooms`：`title: name`、`nick: name`、`introduction: bio.isEmpty ? null : bio`（`:310` 解码 HTML 字符）。
- `packages/live_core/lib/src/sites/chzzk/chzzk_api.dart:725-730`：CHZZK 频道搜索同样 `nick`、`title` 都是频道名，`introduction` 是频道说明（规则通用时也会受影响，见 README 待选 X1）。
- `apps/pure_live/lib/shared/rooms/room_cards.dart:82-99` 的 `AudiencePolicy.cardOf`：`title`（空时“未命名直播间”）、`anchorName`（`displayNick`，在播时加“· 已播 N”）。
- `packages/live_ui/lib/src/widgets/room_card.dart:44-126` 的 `RoomCardData`（`title`、`anchorName` 等，没有简介）；`packages/live_ui/lib/src/widgets/live_room_card.dart:309-330` 的 `title()`、`anchorName()` 两行。
- 搜索页：`apps/pure_live/lib/features/search/search_view.dart:569` 的 `RoomGridCard` → `apps/pure_live/lib/shared/rooms/room_grid.dart:131` 的 `policy.cardOf(...)`。

## 3.x 基线

- `git show v3.2.11:lib/core/site/picarto/picarto_api.dart:189-235`（`searchProfiles`）：`LiveRoom` 没有 `title`，`nick` 是频道名，不读 `bio`。
- `git show v3.2.11:lib/common/widgets/room_card.dart:1172-1221`：信息区标题一行、主播名一行；Picarto 搜索卡片的标题行是空的。
- 要保留的：卡片两行的结构和尺寸（A09.1 定稿）；点按进房、长按菜单。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 4.1 节界面任务设计、第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 3 节（第 6 条同一件事一种做法）。
3. 本文件夹的 `README.md`；`docs/A-界面设计/A09-浏览界面/A09.1-房间卡片/README.md`（信息区、预设）；`docs/E-直播平台/E03-海外平台/E03.3-Picarto/record.md`（11-5、样本 S03）；`docs/E-直播平台/E06-平台层升级/E06.1-已批准升级的余项/record.md`（3-c2）。

## 范围

- 可以改：`apps/pure_live/lib/shared/rooms/room_cards.dart`（`cardOf` 第二行的文字）；需要时 `packages/live_ui/lib/src/widgets/room_card.dart` 的 `RoomCardData` 加一个可选字段（只加不改）；对应测试；本文件夹（`page.json`、`src/`、效果图）。
- 不能改：卡片的尺寸、行数、样式（A09.1）；长按菜单；平台层的搜索解析；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 列出所有“标题等于主播名且有简介”的列表来源（读 `packages/live_core/lib/src/sites/*/` 的搜索、目录解析）；出图和评审页 | README、`src/`、`page.json`、`page/` | README 写清受影响的平台；评审定稿，登记表改“已确认” |
| 2 | c1：`cardOf` 按定稿的规则换第二行 | `room_cards.dart`、测试 | 验收 2～4 |

## 测试

- 改之前会失败：`apps/pure_live/test/features/search/search_test.dart` 加用例：用 `fixtures/picarto/S03-search` 解析出的房间（有 `bio` 的那几个）建卡片，断言 `room-card-anchor-name` 的文字是简介第一行（现在是频道名）。
- 加：没有简介的 Picarto 结果仍显示频道名；标题和主播名不同的房间（例如哔哩哔哩）不变；简介有换行时只取第一行。
- `apps/pure_live/test/shared/shared_test.dart` 里 `cardOf` 的已有断言照旧通过。
- 测试不访问真实平台，定时器至少 1 秒；`apps/pure_live` 跑 `flutter analyze`、全部 `flutter test`、`dart format --output=none --set-exit-if-changed .`；`python3 tools/gate/check_ui_structure.py`。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 开着应用代理，搜索 → 平台选 Picarto → 搜“art” | 卡片第一行是频道名；有简介的第二行是简介，一行省略；没有简介的第二行是频道名 |
| 2. 设置 → 房间卡片外观 → 换成“简洁”预设，再看同样的结果 | 紧凑行同样显示简介，不换行、不撑高 |
| 3. 搜索“全部”，看哔哩哔哩、斗鱼的结果 | 和改之前一样 |
| 4. 长按一张 Picarto 卡片 | 菜单和改之前一样（没有简介） |

## 风险和注意

- 通用规则会影响 CHZZK 频道搜索等其他来源：第 1 阶段要列全，写进 README 和评审页，用户看过再定。
- 简介可能很长或带表情：只取第一行、`maxLines: 1` 省略，不要让卡片变高。
- 可能冲突的文件：`room_cards.dart`（E06.2 的卡片标记也可能改它）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 效果图：`tools/ui/mock/README.md`；`python3 tools/ui/mock/render.py docs/A-界面设计/A09-浏览界面/A09.11-Picarto搜索卡片简介/src/`；评审页 `python3 tools/ui/mock/page.py docs/A-界面设计/A09-浏览界面/A09.11-Picarto搜索卡片简介/page.json`。
- 分支 `ai/A09.11` 或本机工作区；提交信息以 `[A09.11]` 开头（英文）；不推 master。
- 提交前：`dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

评审结果和定稿的规则；受影响的平台列表；测试数量；改了哪些文件；要在真机上看的；可能冲突的文件。
