# D04 数据流和性能

弹幕从平台连接收到以后，到聊天列表和醒目留言栏上显示之间的数据流：按类型分发、聊天记录（最多 500 条）、每帧最多通知一次、列表的跟随和定住、每行只建一次、表情只解析一次、昵称颜色的对比度、醒目留言的到期移除、礼物开关；以及弹幕多时这条路上的性能。

## 范围

- 包括：
  - 直播间控制器里和弹幕数据有关的部分：`features/live_play/logic/room_controller.dart` 的 `_onMessage`（按类型分发）、`chat`（`ChatFeed`）、`flying` 和 `retractions` 两个流、醒目留言（`_addSuperChats`、到期定时器）、礼物开关（`showGifts`）、`addLocal`（本地弹幕立即显示）、`_system`（状态行去重）。
  - 聊天记录 `features/live_play/danmaku/chat_feed.dart`（`ChatLine`、`ChatFeed`）。
  - 聊天列表 `features/live_play/danmaku/chat_list.dart` 的**数据和性能部分**：只听 `ChatFeed` 和 `_RoomFacts`、反转、跟随和定住、定住时的撤回和屏蔽、行部件缓存、换布局时保留定住的列表（`ChatListMemory`）、`chatNameColor` 的对比度算法；“弹幕列表”标签的新弹幕数（`chat_panel.dart`）。
  - 表情的切分和缓存：`shared/danmaku/emotes.dart`（`EmoteTable`、`EmoteLibrary`、`chatSegments`）。
  - 测量：`apps/pure_live/test/features/live_play/chat_benchmark_test.dart`（每秒 200 条的基准）。
- 不包括（归哪里）：
  - 聊天列表、醒目留言卡片、空状态、“N 条新弹幕”按钮长什么样 → [A08](../../A-界面设计/A08-弹幕界面/README.md)（A08.1）。这里只管它们拿到什么数据、什么时候重建。
  - 消息从哪来、带什么字段 → [D01](../D01-平台弹幕协议/README.md)；哪些聊天能通过 → [D02](../D02-过滤和屏蔽/README.md)；`flying` 流进了飞行弹幕层以后 → [D03](../D03-飞行弹幕引擎/README.md)。
  - 直播间的其他状态（播放、人数、房间刷新）→ C01；录制面板查文件的 `SavedFileCheck`（D04.1 c3 做的）现在归录制界面和 H 组共用，这里只记来历。
  - 整个应用的帧时间基准和测量工具 → [R01](../../R-性能和流畅度/R01-基准和测量/README.md)。

## 现状：做到哪、怎么工作的

- 用户看得到的：弹幕再多，直播间的播放器控件、标题栏、信息条不跟着动；聊天列表新弹幕从底部进来、旧的往上推；手指一拖就定住，屏幕上的行原地不动，右下角“N 条新弹幕”计数，点了或拖回底部松手恢复跟随；定住时屏蔽某人、平台撤回的行照样消失；横竖屏、全屏来回切换后还停在原来的位置；彩色昵称在浅色、深色主题下都看得清；醒目留言到点自动移除；自己发的本地弹幕立即出现（不等下一帧）；礼物行可以在弹幕设置里关掉。
- 内部怎么工作：

```text
DanmakuReceived(message) → LiveRoomController._onMessage（room_controller.dart:868）
  chat      → 哔哩哔哩打码计数（只在提示翻转时 notify）→ filter.accepts → chat.add(ChatLine.chat) + _flying.add
  online    → _applyAudience → notify（人数）
  superChat → _addSuperChats（按 startTime 排序、去掉已到期、定时器在最早的 endTime 后触发）+ chat.add(ChatLine.superChat) → notify
  retraction→ chat.retract + _retractions.add（飞行层撤下）
  notice    → 3 秒去重 → chat.add(ChatLine.notice)
  gift      → showGifts 开着才 chat.add(ChatLine.gift)
ChatFeed（chat_feed.dart:101）：行立即写入（500 条，超出从旧的一端丢）；_changed → 下一帧开始时 notifyListeners 一次
ChatList（chat_list.dart）听 ChatFeed：
  跟随：_shown = feed.lines（新一批只重建 ListView，行部件按“行 + 样式 + 表情表”缓存，旧行跳过）
  定住：_shown 不变；removalsSince 把之后的撤回和屏蔽也作用到定住的行；_unseen = 新增数
  对控制器只看 _RoomFacts（阶段、连接状态、昵称提示、离线时的房间）
```

- 完成度（和 3.x 对照）：
  - 一致：500 条上限（3.x `live_play_controller.dart:97`）、列表反转和关保活（3.x `danmaku_list_view.dart:329`、`:334`）、定住时用快照（3.x `:96-98`）、拖动不被跳转打断（3.x `DanmakuTailFollowGuard` `:41`）、醒目留言到点移除、飞行弹幕不等批量。
  - 4.x 的改动（D04.1，待真机）：每帧最多通知一次（3.x 是 64 毫秒一批，`live_play_controller.dart:104`）；“拖动就定住、回到底部松手恢复跟随”（3.x 最新版只有点按钮恢复）；昵称颜色按对比度（3.x 只固定亮度）；表情每条消息只解析一次、聊天列表和飞行层共用（A07.11 c7）；换布局保留定住的列表（A07.11 c4）。
  - 还缺：K90 上的 profile 数字（计划书第 9.4 节的界面线程 P90 ≤ 3 毫秒）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/features/live_play/logic/room_controller.dart`（1064 行） | `chat`（`ChatFeed`，`:156`）、`_flying`（`:157`，同步广播流，`flying` `:217`）、`_retractions`（`:158`）、`superChats`（`:214`）、`showGiftsKey`（`:189`，存在 meta，进房读 `:318`，`setShowGifts` `:604-610` 关掉时去掉礼物行）、`_onMessage`（`:868`）、`addLocal`（`:918`，立即 `flush`）、`_system`（`:925`，`DanmakuNoticeThrottle`）、`_addSuperChats`（`:970`）、`_scheduleSuperChatExpiry`（`:978`）、`blockUser`（`:997`）、`blockKeyword`（`:1008`） |
| `apps/pure_live/lib/features/live_play/danmaku/chat_feed.dart`（206） | `ChatLineKind`（`:8`）、`ChatLine`（`:26`，`segments` 缓存 `:69`、`removed`）、`scheduleChatFlushForNextFrame`（`:85`）、`ChatFeed`（`:101`：500 条、`added`、`removals`、`removalsSince` `:135`、`add` `:145`、`retract` `:154`、`removeWhere` `:170`、`flush` `:187`） |
| `apps/pure_live/lib/features/live_play/danmaku/chat_list.dart`（1001） | 数据部分：`chatNameContrast`（`:38`）、`contrastRatio`（`:41`）、`chatNameColor`（`:55`）；`_ChatListState`：`_bottomSlack` 24（`:118`）、`_views`（`:127`）、`_shown`、`_following`（`:133`）、换布局保留（`:148`、`:161`，`ChatListMemory`）、`_onLines`（`:231`）、`_hold`（`:318`）、`_follow`（`:326`）、`ListView`（`:434-448`）；`_RoomFacts`（`:499`） |
| `apps/pure_live/lib/features/live_play/danmaku/chat_panel.dart`（151） | “弹幕列表”标签的新弹幕数听 `ChatFeed.added`（`:55`、`:93`） |
| `apps/pure_live/lib/shared/danmaku/emotes.dart`（161） | `EmoteTable`（`:18`，正则预编一次 `:46`）、`EmoteLibrary`（`:56`，哔哩哔哩、抖音、斗鱼、虎牙、快手的自带表，按需读一次）、`emoteLibraryProvider`（`:108`）、`chatSegments`（`:122`，每条消息每张表只解析一次，`Expando` `:112`） |
| `apps/pure_live/lib/shared/record/saved_file.dart` | `SavedFileCheck`（`:12`）：录制面板和录制中心卡片后台查文件（D04.1 c3 起，A07.11 c6 挪到这里） |
| `apps/pure_live/test/features/live_play/chat_benchmark_test.dart` | 每秒 200 条的基准（默认 3 秒，`--dart-define=CHAT_BENCH_SECONDS=60` 跑完整 60 秒） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/live_play/chat_feed_test.dart`（8） | 每帧一次、本地立即、撤回标记和 `removalsSince`、释放、表情解析一次、颜色对比度（26 色 × 7 套主题 × 2 种底色） |
| `apps/pure_live/test/features/live_play/chat_list_follow_test.dart`（5） | 列表只建一次、控制器监听者不被通知、飞行层当场收到；跟随不跳；定住 600 条不动和撤回；拖回底部恢复；换布局保留（A07.11） |
| `apps/pure_live/test/features/live_play/chat_benchmark_test.dart`（1） | 构建次数和帧耗时上限 |
| `apps/pure_live/test/features/live_play/chat_names_test.dart`（3） | 访客提示条不让列表重建（D01.32） |
| `apps/pure_live/test/shared/emotes_test.dart`（5） | 表情表和切分 |
| `apps/pure_live/test/features/live_play/live_play_tabs_test.dart`、`live_play_more_page_test.dart` | 醒目留言顺序（A08.1）；礼物开关关掉时去掉礼物行（C01.2） |

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/controllers/live_play_controller.dart`：`_maxDanmakuHistory = 500`（`:97`）、待发最多 200 条（`:98`）、64 毫秒一批（`:104`）、`addDanmakuMessage`（`:500`）、`_flushDanmakuMessages`（`:515`）、`addAddSuperChat`（`:330`）、醒目留言到期定时器（`:344-349`）、`addSystemMessage`（`:630`）。
- `lib/modules/live_play/widgets/danmaku/danmaku_list_view.dart`（649 行）：`DanmakuTailFollowGuard`（`:41`）、快照（`:96-98`）、`addAutomaticKeepAlives: false`（`:329`）、`reverse: true`（`:334`）、“N 条新弹幕”（`:361-382`）、名字圆点颜色 HSL 0.52/0.75（`:470`）。
- 表情：`lib/plugins/emoji_manager.dart`（进房预载）、`lib/core/emoji/models/unified_emoji_model.dart:4`。
- 必须保留的：500 条；“N 条新弹幕”点了回到最新；飞行弹幕不等批量；本地弹幕立即显示（3.x 本地弹幕 2 秒后发，A08.2 改成立即）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| K90 profile 数字没测（每秒 200 条界面线程 P90 ≤ 3 毫秒）；基准是 WSL 调试模式，只能前后对比 | `chat_benchmark_test.dart` | D04.1 的核心目标没有真机证据 | [D04.1 的 verify.md](D04.1-弹幕性能和可读性/verify.md) 第 1、2 步 |
| 合并频率每帧一次还是约 15 Hz、“拖动就定住”的跟随规则，等真机数字再定 | `chat_feed.dart:85`、`chat_list.dart:303-330` | — | 需要维护者在 D04.1 真机验证后决定 |
| 礼物开关存在 meta（`live_play.showGifts`），不是设置：设置页改不了、没有监听 | `room_controller.dart:189`、`:318` | 设置的弹幕页没有这一项 | [A08.6](../../A-界面设计/A08-弹幕界面/A08.6-设置的弹幕页补两组/README.md)（G1：改成设置并接管 meta） |
| 定住时只保留最近 64 次删除的判断，超过后只按 `removed` 标记去掉行；被 500 条上限挤出、又在 64 次之前被屏蔽的行会留在定住的列表里 | `chat_feed.dart:114`（`_keptRemovalTests`）、`:135` | 极端情况下定住很久后屏蔽的人还有几行可见 | 影响小，不做；点“N 条新弹幕”即恢复 |
| 屏蔽只改聊天记录，不追已经飞出去的弹幕 | `room_controller.dart:997-1015` | 刚屏蔽的那一条还会飞完 | 照 3.x，不做 |
| `LiveMessageType.gift` 的注释还写“not shown yet” | `packages/live_core/lib/src/live_message.dart:8` | 注释过时 | 没有任务，顺手改 |
| 注释里的旧编号（`B08`、`B09 c7`、`U.2k`） | `chat_feed.dart`、`chat_list.dart`、`emotes.dart` | 按注释找文档要先查 MAPPING | Z 组一次性替换 |

## 相关决定和规范

- [specs/UI.md](../../specs/UI.md) 第 9.2 节（列表局部刷新、只重建变化的行）、第 9.3 节。
- 计划书第 9.4 节的性能目标（界面线程 P90 ≤ 3 毫秒、每秒 200 条）；调研报告 [V03.2](../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md) 的 S5、R5。
- D-017：测试里的定时器至少 1 秒；基准用假弹幕源，不访问真实平台。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/live_play/chat_feed_test.dart test/features/live_play/chat_list_follow_test.dart test/features/live_play/chat_benchmark_test.dart`；完整基准见上。缺的：真机 profile。
- 真机：CHECKLIST 第 2 节第 5 条（上滑新消息提示、长按三项）、第 7 条（醒目留言到时移除、表情）；D04.1 的 [verify.md](D04.1-弹幕性能和可读性/verify.md)（profile 数字、跟随、定住、颜色）。

## 路线

1. D04.1 的真机验证（profile 构建），同时测 D03 的弹幕层数字；按数字决定合并频率和跟随规则，通过后改“完成”。
2. A08.6：礼物开关变成设置（这一组的数据从 meta 搬到设置）。
3. 以后：如果真机上列表仍有卡顿，先看 Timeline 再开任务（例如行的排版缓存、图片头像的解码）；新想法写进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [D 弹幕](../README.md)。

- 代码：`features/live_play/danmaku/`、`logic/room_controller.dart`
- 进度：`██████████████████░░` 90%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| D04.1 | 弹幕性能和可读性：每帧最多刷新一次、聊天列表反转、昵称对比度 | 性能 | 待真机 | 2026-10-02 | 463115797 | [任务书](D04.1-弹幕性能和可读性/brief.md)、[记录](D04.1-弹幕性能和可读性/record.md) |

<!-- docs:生成结束 -->
