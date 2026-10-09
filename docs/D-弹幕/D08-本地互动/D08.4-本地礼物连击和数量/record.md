# D08.4 本地礼物连击、数量和横幅队列：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区，没有推送、没有合并）
- 分支和提交：工作区分支 `worktree-agent-a266a343f788243f1`，起点 master `a3e58b781`（D08.3 合并，含 D08.1～D08.3、A08.10～A08.15、D07.1、D07.2）；提交 `c026e99a1`（阶段 1：连击、横幅队列、数字跳动、记录合并）、`24f5f4744`（阶段 2：长按选数量、菜单灰掉）、文档一次
- 任务书：[brief.md](brief.md)；设计和每条选择的理由：[README.md](README.md)“方案”c1～c4、“定稿的选择”g1～g14（维护者按 D-003 定）；来源：V03.6 第 2.2 节 P6、第 4 节 E8、第 5.5 节第一段

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 1 3 秒内再送同一个礼物：横幅不换，“×N”加上去并跳一下（减少动态时不跳），计时重新 3 秒；列表一行、数字更新；记录一条 | 做了 | “×N”从横幅第一行里拿出来单独放（g6）；接着连击不再飞本地弹幕（g3）；列表那一行换到最下面（`ChatFeed.replace`，和 D07.1 的合并一样，g4）；3.x 的 `localInteraction.history` 也只留一行（g5） |
| 2 每次仍然扣币、加经验；余额不够照旧提示 | 做了 | 币不够的那一次不算，连击不断（g2） |
| 3 长按礼物格：1、10、66、520，余额不够的变灰；选了一次送这么多 | 做了 | 每行下面写“共 N 电池”；电脑上右键也能打开；`showAppMenu` 原来对点不了的行不变灰，这次改了（g9） |
| 4 不同礼物排队，最多 5 个，播完一个下一个；超出的只进列表 | 做了 | 5 个 = 正在播的 + 等着的（g7）；等着的那个连击了在原位改数量 |
| 5 横幅层不重建直播间 | 做了 | 还是 `LocalGiftLayer` 自己一层（`RepaintBoundary` + `ListenableBuilder` 只听队列和面板）；新加躲开控制层、放不下时缩小（g11） |
| 6 借的代码保留 MIT 版权声明 | 做了 | 只借了 flame_barrage `ComboAnimation` 的跳法（1.8 倍缩回，0.2 秒），用 `ScaleTransition` 重写；声明在 `gift_count_pulse.dart` 文件头 |

## 根因

- 新功能。3.x（`v3.2.11:lib/modules/live_play/controllers/live_play_controller.dart:594-598`）和 4.x 原来（`logic/local_room_session.dart` 的 `sendGift`：`_effectTimer?.cancel()` 后换成新的 `LocalGiftShow`）每次送礼都新开一个横幅、顶掉正在播的，`logic/local_interaction.dart` 的 `sendGift` 写死 `count: 1` 和“×1”，每次一行、一条记录：P6。

## 存储

- 表结构不变（D08.1 的 `local_events`，`schemaVersion` 2）。一个连击一条 `gift`：`count` 累加，`coins` 是这些礼物一共花的币（原来一次一个，就是单价，旧记录照样对）；新方法 `LocalEventStore.updateCount(id, count:, coins:)`，连击的第一条存下拿到 id 以后再改（`LocalGiftCombo` 记着 id 的 Future，改是按顺序排在写入后面的）。
- 3.x 的 `localInteraction.history`（30 行的句子）：连击那一行还是最新一行时改它的数量，不是就照旧加一行；键和格式不变（D-018），覆盖回 3.x 照样读。
- 没有新设置（g13），备份、设备同步不用改。

## 改了哪些文件

- `apps/pure_live/lib/features/live_play/local_interaction/logic/local_catalog.dart`：`giftCounts`、`giftComboWindow`、`giftBannerLimit`。
- `apps/pure_live/lib/features/live_play/local_interaction/logic/local_interaction.dart`：`LocalGiftCombo`；`sendGift` 的 `count`、`combo`（`_recordGift`、`_growGift`、`_sameEntry`）；`LocalGiftData` 的 `id`、`count`、`price`。
- `apps/pure_live/lib/features/live_play/local_interaction/logic/local_gift_queue.dart`（新）：`LocalGiftShow`（挪过来）、`LocalGiftQueue`、`LocalOneShotTimer`。
- `apps/pure_live/lib/features/live_play/local_interaction/logic/local_room_session.dart`：`sendGift(gift, count:)` 的连击判断；`giftEffect` 是 `LocalGiftQueue`；`timer` 参数；时钟默认用 `interaction.now`。
- `apps/pure_live/lib/features/live_play/logic/room_controller.dart`：`addLocal` 返回那一行；`replaceLocal`。
- `apps/pure_live/lib/features/live_play/danmaku/gift_count_pulse.dart`（新）：`GiftCountPulse`、`GiftCountJump`。
- `apps/pure_live/lib/features/live_play/danmaku/gift_line.dart`：改用 `GiftCountPulse`（`GiftLine` 变成无状态的，样子、时间不变）。
- `apps/pure_live/lib/features/live_play/danmaku/chat_list.dart`：本地行传 `merged`。
- `apps/pure_live/lib/features/live_play/local_interaction/local_chat_line.dart`：“×N”读数量、连击时跳。
- `apps/pure_live/lib/features/live_play/local_interaction/local_gift_effect.dart`：`LocalGiftLayer` 的 `clearance`、`presenter`（`LocalGiftPresenter`）、缩小；`LocalGiftBanner` 的数字。
- `apps/pure_live/lib/features/live_play/player/player_view.dart`：`_bannerClearance`。
- `apps/pure_live/lib/features/live_play/local_interaction/local_interaction_panel.dart`：礼物格的长按、右键菜单；“再发一次”的数量。
- `packages/live_store/lib/src/local_events.dart`：`LocalEvent.withCount`、`LocalEventStore.updateCount`、注释。
- `packages/live_ui/lib/src/widgets/app_menu.dart`：点不了的行（文字、图标、第二行）灰掉。
- 翻译（zh、en，按键名排序）3 个：`local_gift_count_cost`（“共 {coins} {currency}”）、`local_gift_count_hint`（“选择数量”）、`local_gift_count_title`（“{gift} · 选择数量”）。没有删键（D-024）；没有新图标。
- 测试：新 `apps/pure_live/test/features/live_play/local_gift_combo_test.dart`；改 `local_interaction_test.dart`（横幅第一行不再带“×1”，数字单独一个）、`packages/live_store/test/local_events_test.dart`、`packages/live_ui/test/app_menu_test.dart`。
- 文档：本文件夹 README（g1～g14、实现）、本记录；D08 子分类 README（代码地图、已知问题、测试）；A08.2 README“实现和验证”补一条；`docs/tasks.toml`；生成的文件（docs.py、settings_audit.py：只有行号变了）。
- 没改：平台礼物（D07 的 `GiftCombiner`、`gift_combo.dart`、飞过的礼物）；弹幕层；3.x 键；版本号。`shared/danmaku/gift_combo.dart` 里的函数是平台礼物的（`LiveGift` 的 `comboKey`、`comboTotal`），本地礼物的连击只看“同一个礼物、3 秒内”，用不上它们；共用的是 `ChatFeed.replace` 和跳动的小部件。

## 测试

- `apps/pure_live/test/features/live_play/local_gift_combo_test.dart`（11 个）：
  - 队列 2 个（假定时器）：一次一个、按顺序、5 个满了第 6 个是 null；等着的连击在原位改数量（`serial` 不变、`revision` + 1）、正在播的连击重新计时（旧定时器停掉）；播完的改不了；空了又能加；`durationOf` 给每个横幅自己的时间、`clear`。
  - 记录和币 1 个：×520 币不够什么都不扣、`count: 0` 不送；一个连击 ×1 + ×10 = ×11：每次扣自己的币（110）、经验 110、记录一条（11 个、110 币）、“🌶️ 送出 辣条 ×11”、3.x 的一行；存进数据库也是一行；下一个连击另起一条；连击中间清空记录，后面另起一条、连击的数量照样往上加。
  - 直播间 8 个（整个直播间页、假时钟）：
    - 3 秒窗口：第 0 秒和第 2 秒两次 → 一个横幅 ×2（同一个 `serial`、`revision` 1）、列表一行 ×2（`replacements` 1）、币扣两次；减少动态时横幅和列表的数字都不跳；横幅到第 5 秒才走（第二次重新算 3 秒）；离上一次 4 秒再送 → 新横幅、新一行，记录两条（×1、×2）；中间送了别的礼物就另起。
    - 排队：三种礼物连着送，横幅依次播、同时只有一个；等着的大航海连击成 ×2，轮到它时就是 ×2；6 种礼物连着送，队列 5 个，列表 6 行都在，第 6 个没有横幅。
    - 有动态时：横幅的 ×N 从 1.8 倍开始缩回 1，列表那一行的 ×N 放大到 1.2 倍再回 1；数量没变之前不跳。
    - 长按小电视：标题“小电视 · 选择数量”，四档，币 1000（加上签到 1100）时 ×66、×520 灰掉（`enabled` 假、字是 38% 的灰）、点了没反应；“共 6600 电池”；选 ×10 → 扣 1000、横幅 ×10、列表一行、记录一条 10 个 1000 币；再送 10 个币不够 → “体验币余额不足”、不扣。
    - 记录里 ×66 那条的“再发一次”再送 66 个（扣 660），记录多一条 ×66。
    - 横屏全屏：横幅的 `clearance` 和飞过的礼物的 `giftClearance` 上下一样、都 ≥ 52；横幅在上下两条中间、左右居中。
    - 系统字体 2 倍，竖屏小画面和横屏全屏各 1 个：大礼物横幅 ×11 整个在两条中间、不比画面宽、没有溢出（去掉缩小时竖屏这个会失败，试过）。
- `packages/live_store/test/local_events_test.dart` 新增 1 个：连击那一条按 id 改数量和币，时间、直播间不变，只有一行；清空以后改不到。
- `packages/live_ui/test/app_menu_test.dart` 新增 1 个：点不了的一行文字、图标、第二行都是 38% 的灰，点了不关菜单；能点的不变。
- 改：`local_interaction_test.dart` 的 #8（横幅第一行“Pure Live 送出 辣条”、数字“×1”单独一个）。
- 跑过：`apps/pure_live` 的 `test/features/live_play/`（全部）、`test/i18n_test.dart`；`packages/live_store`、`packages/live_ui` 全部；`flutter analyze`（应用和两个包）没有问题。

## 门禁

- （见下面“门禁结果”）

## 真机上要看的

K90（`com.mystyle.purelive.v4dev`，每次点按前确认前台是测试包；不碰 3.x 和正式包）：

1. 进一个在播的直播间 → 右上角菜单 → 本地互动体验，在礼物里快速连点同一个礼物 5 下：画面中间只有一个横幅，右边的数字 ×1 → ×5 每次跳一下（变大再缩回）；最后一下以后 3 秒横幅才走；关掉面板看列表：只有一行“送出 🌶 辣条 ×5”，数字涨的时候跳一下；身份卡的币少了 5 份；记录“礼物”里只有一条 ×5。
2. 停 4 秒以上再点同一个礼物：新横幅从 ×1 开始，列表新的一行。
3. 长按一个礼物：贴着它弹出小菜单，标题“礼物名 · 选择数量”，四行 ×1、×10、×66、×520，每行下面“共 N 电池”（按直播间的币名）；币不够的那几行是灰的、点了没反应；选 ×66：一次扣 66 份，横幅、列表、记录都是 ×66。
4. 连点三种不同的礼物：横幅一个播完（3 秒）再播下一个，不互相顶掉、不叠在一起；连点 6 种：只有前 5 个有横幅，列表里 6 行都有。
5. 连点 A、B，再连点 B：B 的横幅还没轮到时数字已经是 ×2，轮到它时直接是 ×2。
6. 横屏全屏、控制层显示时送一个大礼物（加币后送大航海这类）：横幅在上下两条按钮中间，不压按钮；控制层隐藏时位置一样；打开右边的面板时横幅在左边剩下的地方居中。挖孔在左边时横幅不进挖孔。
7. 竖屏小画面送大礼物：横幅在上下两条中间，放不下时整个变小，不被裁掉。
8. 系统字体调到最大：横幅变小但完整；长按菜单的四行完整。
9. 系统设置 → 无障碍 → 移除动画（或开发者选项的动画缩放关掉）：横幅不放大进场，数字不跳，列表的数字也不跳；连击、排队照样。
10. “本地弹幕显示到画面”开着时连点 5 下：只有第一下飞过一条“Pure Live 送出 辣条 ×1”，后面的不再飞。
11. 关掉“显示本地礼物特效”：没有横幅；连击照样合成一行、一条记录。
12. 记录里 ×66 那条点“再发一次”：再扣 66 份。
13. TalkBack 开着时选中一个礼物格：读名字和价格，提示可以长按选择数量。
14. 电脑（Windows）上右键礼物格：同一个菜单。

## 给 D08.5

- 队列：`LocalRoomSession.giftEffect`（`LocalGiftQueue`）；`durationOf` 给一档特效自己的时间（例如座驾 3 秒以上），不传就是 3 秒。三档都进同一个队列（一次一个），或者小礼物的飘屏不进队列，在 `LocalGiftLayer` 里另画——两种都不用改连击。
- 画法：`LocalGiftLayer.presenter`（`LocalGiftPresenter`，拿到 `LocalGiftShow`），画在已经躲开控制层、挖孔和右边面板的那块地方里（它的约束就是那块地方）；默认 `LocalGiftLayer.banner`（居中、`FittedBox` 缩小的 `LocalGiftBanner`）。连击时同一个横幅（同一个 `serial`）收到新的 `LocalGiftShow`（`revision` + 1、`count` 新数量），用 `ValueKey(show.serial)` 就能保住动效的状态。
- 数据：`LocalGiftShow.gift`（`LocalGiftData`：`id`、`price`、`count`、`big`、`effect`），按价格分档用 `price × count` 或 `price`，看 D08.5 的定义。
- 减少动态：`MediaQuery.disableAnimationsOf`，现在的横幅和 `GiftCountPulse` 都照它。
