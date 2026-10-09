# D02 过滤和屏蔽

决定哪些弹幕能上屏的规则：重复包去重、屏蔽关键词、屏蔽用户、合并重复弹幕、相似弹幕过滤、斗鱼“疑似机器人”过滤，以及打码昵称不能被屏蔽；屏蔽表的存储。

## 范围

- 包括：
  - 过滤逻辑（纯 Dart）：`packages/live_danmaku/lib/src/filters/` 的 7 个文件（D01.1 建的）：去重闸门、屏蔽表、重复合并、相似度和它的打分、过滤链、状态提示去重。
  - 打码昵称：判断和一次性清理（`apps/pure_live/lib/shared/danmaku/masked_blocks.dart`，D02.1）。
  - 屏蔽表的存储：`packages/live_store/lib/src/block_lists.dart`（`BlockListStore`、`BlockKind`），3.x 的 `shieldList`、`blockedDanmakuUsers` 迁移进来同一张表 `block_rules`。
  - 过滤怎么接到直播间、多画面、录制：三处的 `_reloadFilter` 和 `DanmakuFilterSettings`；“屏蔽此用户”“屏蔽关键词”之后把列表里已有的行去掉（`room_controller.dart` 的 `blockUser`、`blockKeyword`）。
  - 斗鱼“疑似机器人”过滤：判断在 `packages/live_danmaku/lib/src/sites/douyu.dart:216`，设置经 `app/platforms.dart:204-208` 传进去（协议本身归 D01.3）。
- 不包括（归哪里）：
  - 屏蔽管理页、长按弹幕面板、设置里的“弹幕屏蔽”页长什么样、怎么点（输入框、标签、×、4 秒撤销、打码昵称清理的说明条的样子）→ [A08](../../A-界面设计/A08-弹幕界面/README.md)（A08.1、A08.3、A07.11 c8 的关键词第二页）。这里只管规则和数据。
  - 平台在协议层就丢掉的消息（例如斗鱼包里的 `rid` 和房间不同、抖音聊天的房间号不符）→ D01 各平台。
  - 撤回（平台删掉的消息从列表和画面上撤下）→ 数据在 D01，列表在 D04，画面在 D03。
  - 设置的存储和范围限制（`live_store` 的 `Settings`）→ J 组（J02.1）；这里只用这些设置。

## 现状：做到哪、怎么工作的

- 用户看得到的：
  - 屏蔽关键词（最多 40 字；以 `/` 开头和结尾的按正则匹配，最多 200 字，写错的不加进去，D02.2）和屏蔽用户：加了以后立即生效，已经在列表里的匹配行也去掉（`room_controller.dart:997`、`:1008`）；画面上已经飞出去的不追。屏蔽是全局、持久的，所有平台、所有直播间共用一张表。
  - 合并重复弹幕（默认关，窗口 5 秒）、相似弹幕过滤（默认关，阈值 85、比较 3 秒内最多 100 条）：在弹幕设置和屏蔽管理里开关，改了下一条就生效，不用重连。
  - 斗鱼“疑似机器人弹幕”过滤（默认关）：没有 `dms` 且 `if` 不是 1 的聊天被丢。
  - 哔哩哔哩访客看到的打码昵称（“观***”）没有“屏蔽此用户”；升级前存的打码屏蔽在第一次启动时清掉，屏蔽管理顶上说一次（D02.1，待真机）。
  - 同一条状态提示（“开始连接弹幕服务器”等）3 秒内只出现一次。
- 内部怎么工作：

```text
DanmakuReceived(message)
  └─ 只有聊天过滤（醒目留言、人数、通知、礼物、撤回直接走）
     DanmakuMessageFilter.judge / accepts（message_filter.dart:150、:147）
       1 DanmakuMessageGate（总是开）：平台时间早于 45 s 或晚于本机 10 分钟丢；同 id 10 分钟一次；
         没有 id 按（类型、用户、文字）2.5 s 一次；replayed 放宽到 135 s；醒目留言到 endTime 前不按年龄丢
       2 DanmakuBlockList（总是开）：整名相同（去空白、小写，打码昵称除外）或文字包含屏蔽词；
         /…/ 的按正则（不分大小写，只看前 200 字，D02.2）；
         然后“只有表情”“超过 N 字”（开关，默认关，本地消息不拦，D02.2）；被这一步拦下的直播间计数
       3 RepeatedDanmakuFilter（开关）：同文字（空白合并、小写）在窗口内再出现就隐藏，每次出现重新计时
       4 DanmakuSimilarityFilter（开关，本地消息不比）：和缓存里完全相同，或和最新 96 条之一 partialRatio ≥ 阈值
     → 通过的进 ChatFeed 和飞行层
设置或屏蔽表变化 → store.*.watch → _reloadFilter → filter.settings = DanmakuFilterSettings(...)
```

  - 直播间（`features/live_play/logic/room_controller.dart`：`_filter` `:102`、订阅屏蔽表和 6 个设置 `:307-312`、`_reloadFilter` `:340`、使用 `:888`）、多画面（`features/multiview/logic/multiview_controller.dart`：`:164`、`:272-277`、`_reloadFilter` `:290`、换房间时新建 `:889`、使用 `:908`）同一套；录制弹幕 XML（`app/recording.dart:53`）只用闸门和屏蔽表，重复和相似度保持关（文件要记下说过的话），屏蔽表在开始录制时读一次。
  - 换房间时过滤器 `clear()` 或新建，去重记录不跨房间。
- 完成度（和 3.x 对照）：
  - 一致：四步的顺序、默认值、范围和规则（3.x `danmaku_controller.dart:191-222`）；相似度分数和 3.x 的 fuzzywuzzy 完全一样（30 万对差分，见 [D01.1 记录](../D01-平台弹幕协议/D01.1-弹幕框架和过滤/record.md)“过滤”）；屏蔽表规则（去空白、不分大小写去重、保留第一次的写法，3.x `_normalizeDanmakuBlockValues`）；设置键名（D-018）。
  - 确认过的改动：打码昵称不能屏蔽（D-013、D02.1）；补回消息和醒目留言的年龄规则（附录 B-22、B-26）；撤回和通知不受过滤（D01.1 模型追加）。
  - 还缺：D02.1 的真机验证；屏蔽和过滤没有 K90 记录（CHECKLIST 第 2 节第 4 条）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_danmaku/lib/src/filters/message_gate.dart`（96 行） | `DanmakuMessageGate`（`:24`）：重复包和过期消息的闸门，最多记 4096 条 |
| `packages/live_danmaku/lib/src/filters/block_list.dart`（71） | `DanmakuBlockList`（`:18`）：屏蔽用户、关键词和正则（D02.2）；打码昵称不进集合；`matchesText` |
| `packages/live_danmaku/lib/src/filters/block_pattern.dart`（230） | `DanmakuBlockPattern`：`/…/` 正则的判断、编译和添加时的检查（长度、嵌套重复、试跑），D02.2 |
| `packages/live_danmaku/lib/src/filters/text_shape.dart`（50） | `DanmakuTextShape`：“只有表情”和字数的判断（D02.2；应用里用 `shared/danmaku/emotes.dart` 的 `chatTextShaper`） |
| `packages/live_danmaku/lib/src/filters/repeated_filter.dart`（53） | `RepeatedDanmakuFilter`（`:18`）：合并重复文字，最多记 1024 条 |
| `packages/live_danmaku/lib/src/filters/similarity_filter.dart`（121） | `DanmakuSimilarityFilter`（`:18`）：相似弹幕过滤（阈值、缓存时长、条数，每条最多比较最新 96 条） |
| `packages/live_danmaku/lib/src/filters/partial_ratio.dart`（142） | `partialRatio`（`:30`）：和 fuzzywuzzy 1.2.0 同分的部分匹配打分（自己实现，许可证干净） |
| `packages/live_danmaku/lib/src/filters/message_filter.dart`（179） | `DanmakuFilterSettings`（`:13`，对应 3.x 的 8 个设置和 D02.2 的 3 个）、`DanmakuVerdict`、`DanmakuMessageFilter`（`:100`，过滤链 `judge` `:150`、`accepts` `:147`、`clear` `:174`） |
| `packages/live_danmaku/lib/src/filters/notice_throttle.dart`（24） | `DanmakuNoticeThrottle`（`:4`）：同一句提示 3 秒内一次 |
| `packages/live_danmaku/lib/src/sites/douyu.dart` | `isSuspectedAutomated`（`:216`）和读设置的回调（`:163`、`:225`） |
| `packages/live_store/lib/src/block_lists.dart`（78） | `BlockKind`（`:4`，`keyword` = 3.x `shieldList`、`user` = 3.x `blockedDanmakuUsers`）、`BlockListStore`（`:15`：`list`、`watch`、`add`（不分大小写去重）、`remove`、`replaceAll`，关键词上限 40 `:26`） |
| `packages/live_store/lib/src/settings/settings.dart` | `collapseRepeatedDanmaku`（`:497`，默认关）、`repeatedDanmakuWindowSeconds`（`:504`，5）、`filterDouyuSuspectedAutomatedMessages`（`:584`，关）、`enableDanmakuSimilarityFilter`（`:591`，关）、`danmakuSimilarityThreshold`（`:598`，85，50～100）、`danmakuSimilarityCacheDuration`（`:607`，3，1～60）、`danmakuSimilarityMaxCacheSize`（`:616`，100，20～1000） |
| `apps/pure_live/lib/shared/danmaku/masked_blocks.dart`（49） | `isMaskedViewerName`（`:7`）、`MaskedNameBlocks`（`cleanOnce` `:24`、`takeNotice`；meta 键 `:16`、`:19`）（D02.1） |
| `apps/pure_live/lib/app/startup.dart` | 启动时 `MaskedNameBlocks.cleanOnce`（`:79`） |
| `apps/pure_live/lib/features/live_play/logic/room_controller.dart` | 过滤接线（见上）；`blockUser`（`:997`）、`blockKeyword`（`:1008`）：存进屏蔽表并去掉列表里已有的行 |
| `apps/pure_live/lib/features/live_play/danmaku/message_panel.dart` | “屏蔽此用户”的条件（`:169`，本地弹幕和打码昵称没有） |
| `apps/pure_live/lib/features/multiview/logic/multiview_controller.dart`、`apps/pure_live/lib/app/recording.dart` | 多画面和录制弹幕的过滤（见上） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_danmaku/test/message_gate_test.dart`（20） | 3.x 的 4 个用例；45 s、10 分钟边界；id 窗口；无 id 不滑动；满时逐出；`replayed` 135 s；醒目留言到 `endTime` |
| `packages/live_danmaku/test/repeated_filter_test.dart`（7） | 3.x 的 2 个；空白和大小写、窗口边界和滑动、本地消息、逐出 |
| `packages/live_danmaku/test/similarity_test.dart`（16） | 40 组 fuzzywuzzy 分数；3.x 的 4 个；阈值、过期、只比最新、设置限制 |
| `packages/live_danmaku/test/message_filter_test.dart`（14） | 屏蔽规则、顺序、设置即时生效、其他类型不过滤、打码昵称（`:31`）、提示去重 |
| `packages/live_danmaku/test/douyu_test.dart:244` 起 | 3.x 的疑似机器人判断；开关按条读取 |
| `apps/pure_live/test/shared/masked_blocks_test.dart`（3） | 打码判断、一次性清理 |
| `apps/pure_live/test/features/shield/shield_page_test.dart`（7） | 屏蔽管理（A08.3）和清理说明（`:158`、`:184`） |
| `apps/pure_live/test/features/live_play/live_play_popups_test.dart:980`、`live_play_page_test.dart:327` | 打码昵称没有“屏蔽此用户” |
| `packages/live_store/test/stores_test.dart`、`migration_test.dart`、`backup_test.dart` | 屏蔽表的去重和顺序、3.x 的 `shieldList`/`blockedDanmakuUsers` 迁移、备份恢复 |

## 3.x 基线

- 过滤链：`git show v3.2.11:lib/modules/live_play/controllers/danmaku_controller.dart`：`_installCallbacks`（`:191`，闸门 → 屏蔽 → 重复 → 相似度，本地消息不比 `:203-208`）、`_isBlocked`（`:252`）、`_refreshFilters`（`:259`）、`_updateSimilarityFilterConfig`（`:271`）、`_addStatusMessage`（`:284`，3 秒去重）。
- 各过滤器：`lib/modules/live_play/controllers/danmaku_message_gate.dart:9`、`repeated_danmaku_filter.dart:11`、`danmaku_similarity_filter.dart:9`（打分用 fuzzywuzzy 1.2.0 的 `partialRatio`，GPL-2.0）。
- 设置和范围：`lib/common/services/settings/danmaku_settings_controller.dart:125-127`（阈值 50～100、缓存 1～60 秒、条数 20～1000；重复窗口在使用处限制 1～30 秒）；屏蔽表在 `favorite_room_controller.dart`（`shieldList` `:16`、`blockedDanmakuUsers` `:18`，关键词最多 40 字 `:10`，加词时不分大小写去重 `:449`）。
- 斗鱼过滤：`lib/core/danmaku/douyu_danmaku.dart:128`（同一个判断）、`lib/core/site/douyu/douyu_site.dart:70` 把设置传进去。
- 必须保留的：规则和默认值；屏蔽对所有平台生效；改设置不用重连；本地弹幕不参与相似度比较。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| D02.1 合并后没有在 K90 上看 | [D02.1 的 verify.md](D02.1-打码昵称不能屏蔽/verify.md) | 登记为待真机 | D02.1 |
| 屏蔽、合并重复、相似过滤、斗鱼机器人过滤都没有 K90 记录 | [CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 2 节第 4 条 | D01.1（登记完成）里的过滤部分没有真机结果 | 建议和 D02.1 同一轮看，或并入 S02.6 |
| `blockUser` 本身不判断打码昵称，只靠面板不给入口 | `features/live_play/logic/room_controller.dart:997` | 以后新加入口（例如多画面长按）时可能漏 | 没有任务；新入口时一起判断（过滤层仍兜底，不会误伤，只是表里会多一条） |
| 录制弹幕的屏蔽表只在开始录制时读一次 | `app/recording.dart:53-58` | 录制中途加的屏蔽词对这次录制不生效 | 不做：录制的文件要记下说过的话，影响小 |
| 屏蔽对画面上已经飞出去的弹幕不追 | `room_controller.dart:997-1015` 只改 `chat` | 刚屏蔽的人那一条还会飞完 | 照 3.x，不做 |
| 打码昵称的观众不能单独屏蔽（审查 B-1 另一个建议：按发送者摘要只在本场屏蔽） | — | 访客想屏蔽某个刷屏的打码观众只能用关键词 | 没有任务；有需要在 V01 提议 |
| 屏蔽表全局，不能按平台或直播间分 | `block_lists.dart` | 和 3.x 一样 | 照 3.x，不做 |

## 相关决定和规范

- D-013：打码昵称不能“屏蔽此用户”。
- D-017：过滤测试用固定的时钟（`clock:` 参数），不用真实时间。
- D-018：`shieldList`、`blockedDanmakuUsers` 和 6 个过滤设置的键名、含义不变。
- [specs/UPGRADES.md](../../specs/UPGRADES.md) 附录 B-22、B-26（去重闸门的补回消息规则）。
- [specs/UI.md](../../specs/UI.md) 第 3 节第 8 条（直播间和设置页是同一个屏蔽组件，A08.3）。

## 测试和验证

- 自动测试：`cd packages/live_danmaku && dart test test/message_gate_test.dart test/repeated_filter_test.dart test/similarity_test.dart test/message_filter_test.dart`；应用侧 `cd apps/pure_live && flutter test test/shared/masked_blocks_test.dart test/features/shield/`。过滤都用注入的时钟，边界（含、不含）都有用例。缺的：直播间里“改设置下一条就生效”只在 `live_danmaku` 测了，应用侧没有端到端用例。
- 真机：CHECKLIST 第 2 节第 4 条（加屏蔽词、屏蔽一个用户、打开合并重复、斗鱼打开机器弹幕过滤）、第 5 条（长按三项）；D02.1 的 [verify.md](D02.1-打码昵称不能屏蔽/verify.md)。

## 路线

1. D02.1 的真机验证，同一轮补看 CHECKLIST 第 2 节第 4 条（屏蔽和三种过滤），把结果写进 CHECKLIST，让 D01.1 的过滤部分有真机结果。
2. 以后：有新的屏蔽入口时在 `blockUser` 里加打码判断；“本场屏蔽打码观众”等新想法写进 V01 提议，不直接加任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [D 弹幕](../README.md)。

- 代码：`packages/live_danmaku/lib/src/filters/`、`shared/danmaku/`
- 进度：`███████████████████░` 95%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| D02.1 | 哔哩哔哩打码昵称不能“屏蔽此用户”，清理已存的打码屏蔽 | 功能 | 完成 | 2026-10-02 | 40dc22279 | [设计或说明](D02.1-打码昵称不能屏蔽/README.md)、[任务书](D02.1-打码昵称不能屏蔽/brief.md)、[记录](D02.1-打码昵称不能屏蔽/record.md)、[真机验证](D02.1-打码昵称不能屏蔽/verify.md) |
| D02.2 | 正则屏蔽、屏蔽纯表情和超长弹幕、本场屏蔽计数 | 功能 | 待真机 | 2026-10-09 | — | [设计或说明](D02.2-正则屏蔽和更多屏蔽/README.md)、[任务书](D02.2-正则屏蔽和更多屏蔽/brief.md)、[记录](D02.2-正则屏蔽和更多屏蔽/record.md) |

<!-- docs:生成结束 -->
