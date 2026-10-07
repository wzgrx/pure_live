# D04.1 弹幕性能和可读性：每帧最多刷新一次、聊天列表反转、昵称对比度

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为待真机，2026-10-02，合并 `f9c7b3a97`）；当时定的规模中
- 类型：性能
- 来源：审查报告 B-5、B-6、B-20（[V03.1 全面审查](../../../V-需求和反馈/V03-审查和调研/V03.1-全面审查/README.md)）；调研报告 S5、R5（[V03.2 流畅度、刷新率、分辨率调研](../../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md) 2.5 节、1.7 节）
- 旧编号：B08、T06d.3
- 相关：计划书第 9.4 节的目标（每秒 200 条时界面线程 P90 ≤ 3 毫秒）；保留了 [D01.32](../../D01-平台弹幕协议/D01.32-哔哩哔哩访客昵称和粉丝牌/README.md)（访客提示）和 [A07.10](../../../A-界面设计/A07-直播间界面/A07.10-暂停状态/README.md)（暂停时的弹幕）的行为；之后 [A07.11](../../../A-界面设计/A07-直播间界面/A07.11-直播间小问题合集/README.md) c4、c6、c7 接着做（换布局保留定住的列表、录制中心卡片也后台查文件、表情每条消息只解析一次）；飞行弹幕层的 R5 属于 [D03](../../D03-飞行弹幕引擎/README.md)；聊天列表的样子 [A08.1](../../../A-界面设计/A08-弹幕界面/A08.1-弹幕列表和弹幕设置页/README.md)
- 任务书 [brief.md](brief.md)；记录 [record.md](record.md)（根因、逐条对照、基准数字）；真机验证 [verify.md](verify.md)

## 目标

热门直播间每秒上百条弹幕时，4.0.0 的直播间整页跟着每条弹幕重建，聊天列表每条弹幕都重建所有可见行再 `jumpTo` 一次，中端机掉帧，往上翻旧弹幕时常常被打断；彩色昵称在浅色主题下看不清（黄色约 1.6:1）；录制面板在界面线程同步查文件；可变刷新率下飞行弹幕一顿一跳。做完以后：

1. 弹幕再多，直播间的其他部分（播放器控件、标题栏、信息条）不跟着重建；聊天列表每帧最多更新一次，每行只建一次；
2. 跟随最新时列表不跳；手指一拖就定住，翻旧弹幕不被打断，定住时屏幕上的行原地不动，右下角计数；
3. 所有昵称颜色在两种主题下对背景至少 4.5:1；
4. 录制面板不在界面线程查文件；
5. 两帧时间戳相同时飞行弹幕不补双步。

## 3.x 和现状

| 方面 | 3.x（`git show v3.2.11:lib/...`，文件:行） | 4.0.0（改之前） | 现在（文件:行） | 要做到 |
|---|---|---|---|---|
| 弹幕进列表的节奏 | 64 毫秒一批（`modules/live_play/controllers/live_play_controller.dart:104`，待发最多 200 条 `:98`），飞行弹幕不等 | 每条弹幕 `notifyListeners()` 一次，整页二十来个监听者重建 | `ChatFeed`（`apps/pure_live/lib/features/live_play/danmaku/chat_feed.dart:101`）：行立即写入，监听者在下一帧开始时最多听到一次（`scheduleChatFlushForNextFrame` `:85`、`_changed` `:189`）；本机弹幕 `flush()` 立即（`:187`）；控制器不再为聊天通知，只在醒目留言变化和访客提示翻转时通知（`features/live_play/logic/room_controller.dart:868-905`） | 每帧最多一次（做到，比 3.x 的 64 毫秒更细） |
| 列表方向和跟随 | `reverse: true`（`modules/live_play/widgets/danmaku/danmaku_list_view.dart:334`），关保活（`:329`），拖动时作废排队的 `jumpTo`（`DanmakuTailFollowGuard` `:41`），暂停时用快照（`:96-98`） | 正向列表，每条后 `jumpTo(maxScrollExtent)`，拖动刚开始就被打断；到 500 条上限后屏幕内容上移 | `ChatList`：`reverse: true`（`chat_list.dart:434`），关保活（`:440`），`findChildIndexCallback` 按行 id 找位置（`:442`）；跟随时不需要 `jumpTo`；手指一拖 `_hold`（`:318`）定住当前的行，滚动在底部结束或点按钮 `_follow`（`:326`）；定住时撤回和屏蔽的行照样去掉（`ChatFeed.removalsSince` `chat_feed.dart:135`） | 照 3.x 的快照做法（做到） |
| 每行建几次 | 每次重建都建可见行 | 每条消息所有可见行重建一遍，每行重新解析表情（每次现编正则） | 每行的 `ChatLineView` 按“行 + 样式 + 表情表”缓存（`_views` `chat_list.dart:127`）；表情在 `ChatLine.segments` 缓存（`chat_feed.dart:69`），A07.11 c7 起和飞行层共用一次解析（`shared/danmaku/emotes.dart:112`） | 每行一次（做到） |
| 列表只听自己要的 | 列表是 `Obx`，听整个消息列表 | 列表跟着控制器的所有变化重建（人数、音量……） | 列表只听 `ChatFeed`，对控制器只看 `_RoomFacts`（`chat_list.dart:499`：阶段、连接状态、昵称提示、离线时的房间）；“弹幕列表”标签的新弹幕数改听 `ChatFeed`（`chat_panel.dart:55`、`:93`） | 做到 |
| 昵称颜色 | 卡片左边圆点的颜色固定成 HSL 亮度 0.52 / 0.75（`danmaku_list_view.dart:470`），不看对比度 | 名字的 HSL 亮度固定成 0.42 / 0.72，不看对比度 | `chatNameColor`（`chat_list.dart:55`）：原色对背景已经 4.5:1（`chatNameContrast` `:38`，`contrastRatio` `:41`）就用原色，否则按 HSL 亮度每次 1% 往背景的反方向调，色相和饱和度不变；紧凑行按 `surface`、卡片和长按卡片按 `surfaceContainerLowest` 算；白、黑弹幕用主题色 | ≥ 4.5:1（做到） |
| 录制面板查文件 | — | `build` 里同步 `File(path).existsSync()` | `SavedFileCheck`（`apps/pure_live/lib/shared/record/saved_file.dart:12`，A07.11 c6 从录制面板挪出来，录制中心卡片也用）：构建时用上次的结果，后台 `File.exists()` 同一时间最多一个，结果变了才重建；录制面板 `features/live_play/record/record_panel.dart:201`、`:206` | 做到 |
| 重复时间戳的帧 | 3.x 用引擎时钟，同样会受影响 | 时间差 0 的下一帧走两倍 | `DanmakuOverlayState._tick`（`shared/danmaku/danmaku_overlay.dart:398`，`:399-417`）：这一帧不走、不重画，下一帧的时间差不超过上一次正常的步长 | 做到 |

## 结果

- 改动清单（任务书 c1～c4，全部做到，详见 [record.md](record.md)“逐条对照”）：c1 每帧最多一次、列表单独监听、`reverse: true`、去掉每条后的 `jumpTo`、定住和跟随、每行只建一次、表情只解析一次、飞行弹幕时序不变；c2 昵称对比度；c3 录制面板后台查文件；c4 重复时间戳。
- 偏差（record“偏差”）：
  1. 跟随规则多了一条“手指一拖就定住”，松手后滚动停在底部才恢复跟随（3.x 最新版只有点按钮才恢复；保留了 4.x 原来“回到底部自动跟随”的习惯）。
  2. 当时飞行层还是自己解析一次表情（`emotes.dart` 不在可改范围）；A07.11 c7 后来改成两边共用一次、`EmoteTable` 预编正则。
  3. 改了两个已有测试的找法（列表反转后最新一行排在部件树最前），断言不变。
  4. 有新行的帧列表本身仍重建一次，但只建新进来的行。
- 基准（`apps/pure_live/test/features/live_play/chat_benchmark_test.dart`，整个直播间 400×900，每秒 200 条共 60 秒，120 Hz 推进 7200 帧；WSL 上 `flutter test` 的调试模式，只能前后对比）：

| 指标 | 改之前 | 改之后 | 怎么测 |
|---|---|---|---|
| `ChatList` 整个部件重建 | 7200 次（每帧一次） | 0 次 | `debugOnRebuildDirtyWidget` 计数 |
| 聊天行 `ChatLineView` 构建 | 143505 次（2392 次/秒） | 12002 次（每行一次） | 同上 |
| 全部部件构建 | 每帧 301 个 | 每帧 45 个 | 同上 |
| 每帧耗时 平均 / P50 / P90 / P99 / 最大（毫秒） | 28.62 / 26.25 / 43.34 / 69.87 / 132.05 | 5.56 / 4.86 / 9.09 / 14.32 / 74.19 | 秒表量每次 `tester.pump` |
| 60 秒跑完用时 | 3 分 34 秒 | 43 秒 | — |
| K90 profile 界面线程 P90 | 没测 | **待真机**（目标 ≤ 3 毫秒） | DevTools 或 `addTimingsCallback`，见 verify.md |

  完整 60 秒：`cd apps/pure_live && flutter test test/features/live_play/chat_benchmark_test.dart --dart-define=CHAT_BENCH_SECONDS=60`；平时跑 3 秒并断言上限。
- 没有新设置、没有新翻译键。
- 提交：`a640d9b84`（R5）、`7541bfdbf`（批量、反转、对比度）、`f7f8b00b9`（录制面板），合并 `f9c7b3a97`（2026-10-02）；登记表写的 `463115797` 是记录提交。

## 验证

- 自动测试（新增 15 个、改 2 个，record“测试”）：
  - `apps/pure_live/test/features/live_play/chat_feed_test.dart`（8）：两帧之间 50 次改动只排一次、只通知一次（`:37`）；本机弹幕立即（`:67`）；撤回标记和 `removalsSince`（`:81`）；释放后不通知（`:113`）；表情按表解析一次（`:124`）；26 种颜色 × 7 套主题 × 两种底色都 ≥ 4.5:1（`:194`）；够亮的原色不变、只改亮度（`:210`）；白黑用主题色（`:226`）。
  - `chat_list_follow_test.dart`（现在 5 个，D04.1 加 4 个，A07.11 加 `:245` 一个）：飞行层当场收到、列表下一帧只建一次、控制器监听者一次也没被通知（`:106`）；跟随时位置始终是 0、只建新行（`:145`）；往上翻后再来 600 条屏幕不动、计数、撤回照样去掉、点按钮回到最新（`:182`）；拖回底部恢复跟随（`:299`）。
  - `apps/pure_live/test/shared/danmaku_overlay_test.dart:131`：R5 每帧位移 1、0、1、1、0、1、1 像素（改之前是 1、0、2）。
  - `live_play_popups_test.dart`：录制面板只调 `exists`、不调 `existsSync`。
  - `chat_benchmark_test.dart`（1）：3 秒版断言 `ChatList` 构建 ≤ 2 次、每行一次、每帧部件 < 150 个。
  - R5 和录制面板两个测试在改之前的代码上跑过，都失败。
- 真机：**待真机**，步骤在 [verify.md](verify.md)（record“要在 K90 上看的”7 条，加上 D03.1 留下的弹幕层 profile 数字）。

## 留下的问题

- 合并频率每帧一次还是约 15 Hz：记录建议保持每帧一次，真机 profile 不理想再改（需要维护者看了真机数字再定）。
- “拖动就定住、回到底部松手才跟随”是否就这样（偏差 1）：需要维护者在真机上看了再定。
- 录制中心任务卡也在构建时 `existsSync`：A07.11 c6 已改用 `SavedFileCheck`（做完）。
- `EmoteTable` 预编正则、两边共用一次解析：A07.11 c7 已做完。
