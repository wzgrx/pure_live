# A09.11 Picarto 搜索卡片显示频道简介：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（从 master `bbd52a2a3` 开始，在 H05.4、A07.16 之后）
- 设计或说明：[README.md](README.md)（第 1 版定稿，D-003）

## 根因（缺口）

- 平台层已把 Picarto 搜索结果的标题设成频道名、简介放进 `introduction`（`packages/live_core/lib/src/sites/picarto/picarto_api.dart:313-325`），但卡片数据 `apps/pure_live/lib/shared/rooms/room_cards.dart:82-99`（改前）的 `cardOf` 只填标题和主播名，`packages/live_ui/lib/src/widgets/room_card.dart:44`（改前）的 `RoomCardData` 也没有放简介的地方，所以两行都是频道名、简介不显示。
- 不能直接把 `anchorName` 换成简介：头像的字母（`live_room_card.dart:306`）和未开播的行 `RoomRow`（第一行就是主播名，`:734`）也读它。

## 做了什么

- 第 1 阶段：复核所有带简介的来源（README“第 1 阶段复核”表）。总是“标题等于主播名”的：Picarto 搜索、CHZZK 频道卡片、快手主播搜索、SHOWROOM 详情；标题缺时退到主播名的：百度直播、PandaTV、TikTok。设计按 D-003 定稿（X1、X2 选 A，通用规则，不出图）。
- `packages/live_ui`：`RoomCardData` 加可选的 `introLine`（只加不改，进 `==` 和 `hashCode`）；`LiveRoomCard` 的第二行（`anchorName()`，大号、小号和“简洁”的紧凑行共用）显示 `introLine ?? anchorName`，一行省略，样式不变。
- `apps/pure_live`：`cardOf` 在标题（去首尾空白、不分大小写）等于主播名、且简介有字时，`introLine` 是简介第一个非空行（去首尾空白）；在播时后面照旧加“· 已播 N”。标题不等于主播名的卡片一个字都不变。
- 不改：长按菜单（A09.1 c3）；电视卡片 `tv_room_card.dart` 仍读主播名（README“各客户端”）；平台层的解析。
- 没有新翻译键。

## 测试

- `packages/live_ui/test/live_room_card_test.dart`：`A09.11: the introduction line takes the second line; ...`（标准和紧凑两种外观第二行是简介、一行；头像字母仍是主播名；卡片高度不变；`RoomRow` 不显示简介；`introLine` 进相等比较）。改前编不过（没有 `introLine`）。
- `apps/pure_live/test/shared/shared_test.dart`：`A09.11: a title that is the streamer shows the first line of the introduction instead`（大小写和空白、跳过空行取第一行、空简介和没有简介、标题不同、`anchorName` 不变、在播时加“· 已播 5 分钟”）；原有的 `cardOf` 用例加一条 `introLine` 为空。改前编不过。
- `apps/pure_live/test/features/search/search_test.dart`：`A09.11: Picarto channels show their introduction under the name; others are unchanged`：用 `fixtures/picarto/S03-search` 解析出的 Dianamation（有简介，第一行“Home of the Dianamation Art Stream”）、TheBaker（没有简介）和一个哔哩哔哩房间，看 `room-card-anchor-name`。改前失败（Dianamation 的第二行是“Dianamation”）。
- `packages/live_ui` 全部 196 个、`apps/pure_live` 全部通过；不访问网络。

## 真机

待 K90（brief“真机验证”，选了通用规则，加第 5 步）：

1. 开着应用代理，搜索 → 平台选 Picarto → 搜“art”：第一行是频道名；有简介的第二行是简介的第一行，一行省略；没有简介的第二行是频道名。
2. 设置 → 房间卡片外观 → “简洁”预设，再看同样的结果：紧凑行同样显示简介，不换行、不撑高。
3. 搜索“全部”，看哔哩哔哩、斗鱼的结果：和改之前一样。
4. 长按一张 Picarto 卡片：菜单和改之前一样（没有简介）。
5. CHZZK 搜一个频道：第二行是频道说明；快手按主播搜：第二行是主播简介（有的话）。

## K90 复查（2026-10-08，提交 `9126ec299`，经代理）

- 第 1 步：搜索 → Picarto → “art”：有简介的卡片第二行是简介（“NaughtyLeopard / Pony Hardware on Cat Software.”、SketchOtterly 的一长串一行省略）；没有简介的第二行是频道名 ✓。
- 第 2～5 步没做（简洁预设、全部平台对照、长按菜单、CHZZK 和快手），都有自动测试。

结论：通过。
