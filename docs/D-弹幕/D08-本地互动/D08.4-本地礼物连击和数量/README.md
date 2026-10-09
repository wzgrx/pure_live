# D08.4 本地礼物连击、数量和横幅队列

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：[V03.6](../../../V-需求和反馈/V03-审查和调研/V03.6-弹幕系统和本地互动体验/README.md) 第 2.2 节 P6、第 4 节 E8、第 5.5 节第一段（做法 A）；用户 2026-10-09 点名“本地礼物和特效”（D-040）
- 相关：记录合并依赖 [D08.1](../D08.1-结构化的本地历史/README.md)；后续 [D08.5](../D08.5-三档礼物特效/README.md)（三档特效用这里的队列）；平台礼物的连击规则 [D07.1](../../D07-礼物和付费消息/D07.1-礼物过滤连击合并和限速/README.md)（参考，不共用代码）；礼物横幅界面 [A08.2](../../../A-界面设计/A08-弹幕界面/A08.2-本地互动/README.md)（c9）；flame_barrage `ComboAnimation`（MIT）；任务书 [brief.md](brief.md)

## 目标

本地礼物像平台礼物一样能连击、能一次送多个：3 秒内再点同一个礼物，横幅上的数字跳成 ×2、×3…，聊天列表合成一行、记录也是一条；长按礼物选数量（1、10、66、520）；不同礼物排队，一个横幅播完再下一个，不再互相顶掉。

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 数量 | 一次 1 个 | 同：`sendGift` 的 `count: 1`、文字“×1”（`features/live_play/local_interaction/logic/local_interaction.dart`） | 1、10、66、520 |
| 连击 | 没有 | 没有；快速连点每次一行、一条记录 | 3 秒内同一礼物合并 |
| 横幅 | 3 秒，新的顶掉旧的（`v3.2.11:lib/modules/live_play/controllers/live_play_controller.dart:594-598`） | 同：`LocalRoomSession.sendGift` 里 `_effectTimer?.cancel()` 后换成新的（`logic/local_room_session.dart`） | 同一礼物连击改数字；不同礼物排队（最多 5 个） |
| 横幅层 | 整页重建 | `LocalGiftLayer`（`local_interaction/local_gift_effect.dart:13`），画面上单独一层 | 不变 |

## 方案（做法 A，D-003 维护者选 A）

- c1 连击：`LocalRoomSession` 记最后一次送的礼物和时间；**3 秒**内再送同一个礼物 → 不新开横幅，`LocalGiftShow` 的数量加上去，横幅计时重新开始 3 秒；聊天列表里那一行改数量（本地行，用 `ChatFeed` 替换一行的方法——D07.1 会加；没合并时在本任务里加，两边用同一个方法）；D08.1 的记录合成一条（`count` 累加）。每次仍然扣币、加经验。
- c2 数字跳动：“×N”放大到 1.8 倍再回缩（借 flame_barrage `lib/src/animation/combo_animation.dart` 的做法，只借画法、保留 MIT 版权声明；用 Flutter 的隐式动画实现，不引入 Flame）；系统要求减少动态时不跳。
- c3 数量：长按礼物格弹出贴着它的小菜单（A07 的小菜单样子）：1、10、66、520，余额不够的变灰；选了就一次送这么多（扣 `价格 × 数量`）。
- c4 队列：不同礼物的横幅排队，最多 5 个，超出的只进列表不出横幅；一个播完（3 秒）播下一个。
- 不做：特效分档（D08.5）。

## 定稿的选择（D-003，维护者定，2026-10-09）

c1～c4 照上面做；任务书没写死、开发时定下的：

| 编号 | 选择 | 理由 |
|---|---|---|
| g1 | **连击 = 同一个直播间里连着送同一个礼物，离上一次不到 3 秒**（`LocalCatalog.giftComboWindow`，从上一次算，严格小于 3 秒）；中间送了别的礼物就断开（甲、乙、甲是三个）；中间发弹幕不断开。用 `LocalRoomSession` 自己的时钟（默认是 `LocalInteraction.now`），测试里换成假时钟 | 和横幅的 3 秒一样长：连击在继续时，它的横幅一定还在；平台的连击也只算连着的同一个礼物（D07.1） |
| g2 | 连击里每一次照旧扣自己的币、加同样多的经验；币不够时照旧提示“体验币余额不足”，这一次不算进去，连击不断 | 任务书第 2 条；3.x 的规则不变 |
| g3 | **接着连击时不再飞一条本地弹幕**：第一次送出时照旧飞过画面（开着“本地弹幕显示到画面”时），后面的数量只在横幅和列表里涨 | 连点 5 下飞 5 条一样的字只会挡画面；数字在横幅上看得到 |
| g4 | 列表：连击的新数量用 `ChatFeed.replace`（D07.1 已经加的那一个，没有另加）换掉原来那一行，换上的一行在最下面（最新），“×N”放大到 1.2 倍再回来，和平台礼物行一样（抽出来的 `GiftCountPulse`，`GiftLine` 和 `LocalChatLine` 共用）。原来那一行已经不在列表里（清空了、被挤出 500 条）时加一行新的 | 任务书“列表只有一行”；和 A08.11 同一种跳法 |
| g5 | 记录：**一个连击一条**（D08.1 的 `local_events`，`count` 累加，`coins` 改成“这些礼物一共花的币”，`LocalEventStore.updateCount` 按 id 改），时间是第一次送出的时间；3.x 的 `localInteraction.history` 也只留一行（还是最新一行时改它的数量，不是就加一行，D-018）。连击中间清空了记录，后面几次另起一条 | 任务书“记录一条”；改数量不改时间，记录的顺序不跳 |
| g6 | 横幅：“×N”从第一行里拿出来放在右边、大一号（小礼物 24、大礼物 30，粗 800、等宽数字），第一行写“Pure Live 送出 辣条”；连击时同一个横幅（同一个 `serial`）只换数字，数字从 1.8 倍缩回原来大小（200 毫秒，减速；借 flame_barrage `ComboAnimation`：放大 1.8 倍、每秒缩 4 倍，正好 0.2 秒），计时重新 3 秒 | 任务书 c2；数字单独放才能只让它跳 |
| g7 | 队列（`LocalGiftQueue`）：一次只有一个横幅，按送出的顺序一个播完（3 秒）播下一个；**最多 5 个**（正在播的 + 等着的，`LocalCatalog.giftBannerLimit`），第 6 个起只进列表；等着的那个连击了，在原来的位置改数量（轮到它时才开始算 3 秒）；连击开始时没排上的，下一次送出时再试一次 | 5 × 3 秒 = 最多 15 秒以后才看到；再多就离点的时候太远了，列表里照样有。每个横幅还是 3 秒，不因为排队缩短（3.x 的 3 秒） |
| g8 | **数量四档 1、10、66、520**（`LocalCatalog.giftCounts`）：1 是点一下；10 是整数；66（六六大顺）、520（我爱你）是斗鱼、哔哩哔哩、虎牙数量菜单里都有的；1314 不放：最便宜的礼物（10 币）× 1314 = 13140，比加币按钮一次给的都多，一直是灰的 | V03.6 第 5.5 节的四档；菜单只有四行，横屏右边的面板里也放得下 |
| g9 | 长按礼物格（电脑上右键）弹出贴着它的小菜单（`showAppMenu`，取消关注、录制卡片用的那一个）：标题“小电视 · 选择数量”，每行“×10”，下面一行“共 1000 电池”（按直播间的币名）；**币不够的灰掉、点不了**（`AppMenuEntry.enabled`；`showAppMenu` 原来对点不了的行只是不响应、看起来一样，这次改成 38% 的灰，所有菜单都受益）；点一下照旧送 1 个，读屏软件读“长按：选择数量” | 任务书 c3；A07 的小菜单样子；灰色要看得出来 |
| g10 | 记录里礼物的“再发一次”送这一条的数量（×66 的那条再发 66 个，连击 ×7 的那条再发 7 个），币不够照旧提示 | 一条记录就是一次送出，再发一次就是同样再送一次 |
| g11 | 横幅**一直躲开控制层上下两条**（和 A08.12 飞过的礼物用同一个 `giftClearance`：竖屏小画面上下各 52，横屏全屏是状态栏或挖孔 + 52，竖屏全屏是两排按钮），全屏时再躲开左右的挖孔；右边的面板照旧让开；在剩下的地方居中，放不下时整个等比缩小（`FittedBox`），系统字体 2 倍、竖屏小画面都不会被裁掉或压在按钮下面 | 和飞过的礼物一样不管控制层显示没有（不会一出控制层就跳位置）；平时上下对称，居中的位置和以前一样 |
| g12 | 减少动态时横幅不放大进场、“×N”不跳，列表的“×N”也不跳；排队、连击、计时照旧 | UI.md 第 8.6 节 |
| g13 | **不加新设置**：横幅还是由“显示本地礼物特效”管（关着时没有横幅，连击和数量照样有）；连击和数量一直开着 | D-040“新设置默认保持现在的样子”；连击只是把原来的多行、多个横幅合成一个，没有什么要关的 |
| g14 | 给 D08.5 留的接口：`LocalGiftQueue.durationOf`（每个横幅自己的时间，例如大礼物的座驾）；`LocalGiftLayer.presenter`（`LocalGiftPresenter`：拿到 `LocalGiftShow`，画在已经躲开控制层和面板的那块地方里，默认是 `LocalGiftLayer.banner`）；`LocalGiftShow` 的 `serial`（同一个横幅）、`revision`（数量涨了几次）、`count`、`gift`（`LocalGiftData`：`id`、`price`、`count`、`big`、`effect`） | D08.5 的三档在同一个队列里按价格换画法，不用再改队列和连击 |

## 实现和验证

- 代码：
  - `logic/local_catalog.dart`：`giftCounts`、`giftComboWindow`、`giftBannerLimit`。
  - `logic/local_interaction.dart`：`LocalGiftCombo`（一个连击：礼物、数量、花的币、记录的那一条）；`sendGift` 加 `count`、`combo`（数量、扣币、经验、记录合一条、3.x 那一行）；`LocalGiftData` 加 `id`、`count`、`price`。
  - `logic/local_gift_queue.dart`（新）：`LocalGiftShow`（从 `local_room_session.dart` 挪过来，加 `revision`、`count`、`grown`）、`LocalGiftQueue`（`add`、`grow`、`clear`、`durationOf`，`LocalOneShotTimer` 换假定时器）。
  - `logic/local_room_session.dart`：`sendGift(gift, count:)` 判断连击、换列表那一行、横幅进队列或改数量；`giftEffect` 换成 `LocalGiftQueue`（`value` 还是正在播的那个）。
  - `features/live_play/logic/room_controller.dart`：`addLocal` 返回那一行；新 `replaceLocal`（`ChatFeed.replace`，不飞）。
  - `features/live_play/danmaku/gift_count_pulse.dart`（新，带 flame_barrage 的 MIT 声明）：`GiftCountPulse`、`GiftCountJump`（`line` 1.2、`banner` 1.8）；`gift_line.dart` 改用它（`GiftLine` 变成无状态的，样子和测试不变）。
  - `local_chat_line.dart`：“×N”读礼物的数量、连击时跳（`merged`）；`chat_list.dart` 传 `line.revision > 0`。
  - `local_gift_effect.dart`：`LocalGiftLayer` 加 `clearance`、`presenter`，`FittedBox` 缩小；`LocalGiftBanner` 的数字单独放。`player/player_view.dart` 的 `_bannerClearance` 传进去。
  - `local_interaction_panel.dart`：礼物格长按、右键的数量菜单；“再发一次”送记录的数量。
  - `packages/live_store/lib/src/local_events.dart`：`LocalEvent.withCount`、`LocalEventStore.updateCount`（表结构不变）。
  - `packages/live_ui/lib/src/widgets/app_menu.dart`：点不了的行灰掉。
  - 翻译 3 条：`local_gift_count_title`、`local_gift_count_cost`、`local_gift_count_hint`。
- 借的代码：flame_barrage `lib/src/animation/combo_animation.dart`（MIT，Copyright (c) 2026 bobobo，提交 `3eddae8`）只借了跳法（1.8 倍缩回），用 Flutter 的 `ScaleTransition` 重写，没有引入 Flame；版权声明在 `gift_count_pulse.dart` 文件头。
- 测试和真机上要看的：[record.md](record.md)。
