# D04.1 记录：弹幕性能和可读性（批量通知、反转列表、昵称对比度、录制面板、相同时间戳）

- 任务单：[`docs/D-弹幕/D04-数据流和性能/D04.1-弹幕性能和可读性/brief.md`](brief.md)；审查报告 B-5、B-6、B-20；调研报告 [`research-smoothness-2026-10-02.md`](../../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md) S5、R5。
- 本地 worktree 任务（不推送、不开 PR），提交在当前分支；开始和提交前各合并了一次本地 master（最后一次带进 A03.2）。
- 保留了 D01.32（访客提示、粉丝牌、头像）和 A07.10（弹幕运行状态）的行为，相关测试都通过。

## 根因

- **B-6：每条弹幕通知整个直播间页面。** `LiveRoomController._onMessage` 每收到一条聊天、通知、礼物、撤回都调一次 `notifyListeners()`。页面上挂在控制器上的 `ListenableBuilder`/`ListenableSelector`/监听者有二十个左右（播放器控件、标题栏、信息条、竖屏切房间、后台播放通知……），所以每秒 200 条弹幕时，这些部件每一帧都要跟着重建，和聊天毫无关系。基准里改之前每帧要建 301 个部件。
- **聊天列表每条消息都把所有可见行重建一遍，再 `jumpTo` 一次。** `ChatList` 每条消息 `setState`，`itemBuilder` 每次新建 `ChatLineView`，每行重新跑 `chatSegments`（每次现编一个正则）、重新排版；列表是正向的，每条消息之后还要在帧后 `jumpTo(maxScrollExtent)`。`jumpTo` 会打断正在进行的拖动：手指从底部刚拖出去、还没离开底部 24 dp 时，下一帧的 `jumpTo` 就把拖动取消了，所以弹幕多的时候往上翻常常翻不动。往上翻的时候，聊天记录到 500 条上限后从开头删旧行，屏幕上的内容也会跟着往上移。
- **B-5：** 昵称颜色只把 HSL 亮度固定成 0.42（浅色）/ 0.72（深色），不看对比度：黄色在白底上约 1.6:1，青、绿也不到 3:1。
- **B-20：** 录制面板在 `build` 里同步调用 `File(path).existsSync()`，界面线程等磁盘。
- **R5：** 弹幕层按每帧时间差累加。可变刷新率下引擎会把倒退的时间戳夹住，于是连续两帧时间戳相同（Flutter #190372）：这一帧不动，下一帧时间差是两个周期，走双步，看起来是一顿一跳。

## 逐条对照

| 条 | 做到没有 | 怎么做的 |
|---|---|---|
| c1 批量通知：每帧最多一次，聊天列表单独监听 | 做了 | `ChatFeed` 改成 `ChangeNotifier`：行**立即**写入（`lines`、`added` 马上可读），监听者在**下一帧开始时**最多听到一次（`scheduleFrameCallback`，同一帧内就建好新行）。本机发的弹幕（`addLocal`）调 `flush()` 立即显示。控制器不再为聊天、通知、礼物、撤回、系统行通知；只在醒目留言变化和 D01.32 的哔哩哔哩昵称提示**状态翻转**时（第 3 条打码昵称、之后第一条全名）通知。弹幕页签上的未读数（`chat_panel.dart`）改为监听 `ChatFeed`。选了“每帧一次”而不是约 15 Hz，原因见“需要维护者决定的” |
| c1 聊天列表单独监听；`reverse: true`；去掉每条后的 `jumpTo` | 做了 | `ChatList` 只监听 `ChatFeed`，对控制器只看它显示的几样（阶段、连接状态、昵称提示、离线时的房间）——其余变化（人数、音量、播放器）不再让列表重建。列表反转，索引 0 是最新一行、在底部；新行从下面进来，跟随时位置一直是 0，**不需要任何 `jumpTo`**。新一批只重建列表本身（`ValueListenableBuilder`），上面的 D01.32 提示条不跟着重建 |
| c1 跟随最新时不跳；往上翻时列表不动 | 做了 | 手指一拖动（或位置离开底部 24 dp 以上），列表就**定住**当前显示的行（3.x 的快照做法）：新行只计数，“N 条新弹幕，点击回到底部”；撤回和屏蔽掉的行照样去掉（包括已经被 500 条上限挤出记录、但还在快照里的行，`ChatFeed.removalsSince`）。滚动在底部结束时，或点按钮，回到跟随。改之前刚开始拖动会被 `jumpTo` 打断、往上翻时到上限后内容会上移，这两个问题都没有了 |
| c1 每行只建一次 | 做了 | `findChildIndexCallback` 按行 id 找新位置，行的元素保留；每行的 `ChatLineView` 按“行 + 样式 + 表情表”缓存成同一个实例，列表重建时旧行直接跳过；关掉了每行的保活包装（`addAutomaticKeepAlives: false`，3.x 也是关的），它们原来每一批都要为每个可见行重建 |
| c1 表情只解析一次（缓存在消息上） | 做了 | `ChatLine.segments(table)`：第一次解析后缓存在行上，表情表换了才重新解析。见偏差 2 |
| c1 不影响飞行弹幕的时序 | 做了 | `flying` 流原样同步发出，每条消息到达时就发；测试断言 30 条消息在下一帧之前已全部发给飞行层 |
| c2 昵称颜色对比度 ≥ 4.5:1 | 做了 | `chatNameColor(颜色, 背景)`：原色对背景已有 4.5:1 就用原色；不够就按 HSL 亮度每次 1% 加深（背景离黑更远时）或提亮，直到 ≥ 4.5:1（方向按背景对纯黑、纯白哪边对比度更高来定，两边总有一边能到 4.6:1）。色相、饱和度不变。紧凑行按页面底色 `surface` 算，卡片和长按卡片按 `surfaceContainerLowest` 算；按“颜色 + 背景”缓存。白色、黑色弹幕照旧用主题色 |
| c3 录制面板不在界面线程同步查文件 | 做了 | `_saved(path)`：构建时用上一次的结果，同时在后台 `File.exists()` 再看一次（同一时间最多一个），结果变了才重建。结果按路径缓存，路径变了先当“没有”。项目的 `avoid_slow_async_io` 规则在这一处用注释说明后忽略（这里就是要异步） |
| c4 相同时间戳的帧跳过、不补双步 | 做了 | `DanmakuOverlay._tick`：时间差 ≤ 0（ticker 启动后的第一帧除外）的帧不移动、不重绘（这一帧仍可放新弹幕进场）；下一帧的时间差不超过上一次正常的步长，不补双步。代价是弹幕时钟每遇到一次重复帧慢一个周期，弹幕本来就不和视频对时，看不出来 |

### 偏差

1. **跟随的规则比原来多了一条“手指一拖就定住”。** 原来是“在底部就跟随”，拖动开始时还在底部的 24 dp 内仍算跟随，新行一进来内容就在手指下面移动。现在拖动一开始就定住，松手后滚动在底部结束才恢复跟随（3.x 最新版是只有点按钮才恢复，这里保留了 v4 原来“回到底部自动跟随”的习惯）。
2. **飞行弹幕层还是自己解析一次表情。** 聊天列表的解析缓存在 `ChatLine` 上；飞行层（`danmaku_overlay.dart`）对每条消息本来就只解析一次，两边共用一份需要改 `shared/danmaku/emotes.dart`（不在可改文件里）。另外 `chatSegments` 每次调用都现编正则，表情表那部分可以在 `EmoteTable` 里预编好，建议以后顺手做。
3. **改了两个已有测试的找法**（不改断言内容）：列表反转后，部件树里最新一行排在最前。`chat_names_test.dart` 的卡片测试改成按文字找卡片，`live_play_popups_test.dart` 的 D02.1 长按测试 `.last` 改 `.first`。
4. 列表本身仍然每帧重建一次（有新行的帧）。每次只建新进来的行，旧行全部跳过；见“需要维护者决定的”1。

## 基准（每秒 200 条、持续 60 秒）

`apps/pure_live/test/features/live_play/chat_benchmark_test.dart`：在整个直播间页面（竖屏 400×900，带飞行弹幕层）里，假弹幕源每秒 200 条、共 12000 条（6 种颜色、8 种文字，含表情代码），帧按 120 Hz 推进（7200 帧），用 `debugOnRebuildDirtyWidget` 统计部件构建，用秒表量每帧（`tester.pump`）耗时。平时跑 3 秒并断言上限；完整 60 秒：

```bash
cd apps/pure_live
flutter test test/features/live_play/chat_benchmark_test.dart --dart-define=CHAT_BENCH_SECONDS=60
```

| 指标 | 改之前（合并 D01.32 后的 master） | 改之后 |
|---|---|---|
| 聊天列表重建（`ChatList` 整个部件） | 7200 次（120 次/秒，每帧一次） | 0 次（只有提示、空状态变化时才建） |
| 列表本身重建（`ListView`） | 7200 次（和上面是同一次） | 7200 次（有新行的帧一次） |
| 聊天行构建（`ChatLineView`） | 143505 次（2392 次/秒） | 12002 次（200 次/秒，每行一次） |
| 全部部件构建 | 2167816 次（每帧 301 个） | 324066 次（每帧 45 个，其中约 21 个是列表给每个可见行套的 `KeyedSubtree`） |
| 每帧耗时 平均 / P50 / P90 / P99 / 最大（ms） | 28.62 / 26.25 / 43.34 / 69.87 / 132.05 | 5.56 / 4.86 / 9.09 / 14.32 / 74.19 |
| 整个 60 秒跑完用时 | 3 分 34 秒 | 43 秒 |

注意：这是 WSL 上 `flutter test` 的**调试模式**（JIT、断言全开、无光栅化），只能前后对比，不能和计划书 9.4 的“UI 线程 P90 ≤ 3 ms”直接比；那个要在 K90 上用 profile 构建看（见下面第 1 步）。两次都是单独跑的（没有别的测试同时占 CPU）。

## 改了哪些文件

- `apps/pure_live/lib/features/live_play/danmaku/chat_feed.dart`：`ChatFeed` 每帧最多通知一次、`flush`、`removals`/`removalsSince`；`ChatLine.removed`、`ChatLine.segments`；`scheduleChatFlushForNextFrame`。
- `apps/pure_live/lib/features/live_play/danmaku/chat_list.dart`：列表反转、定住和跟随、行部件缓存、`_RoomFacts`；`chatNameColor` 改按背景算对比度，新增 `contrastRatio`、`chatNameContrast`；长按卡片里的名字颜色改按卡片底色（`showChatMessageActions` 里只改了这一行）。
- `apps/pure_live/lib/features/live_play/danmaku/chat_panel.dart`：未读数监听 `ChatFeed`。
- `apps/pure_live/lib/features/live_play/logic/room_controller.dart`：聊天类消息不再通知；昵称提示翻转时通知；`addLocal` 立即 `flush`；释放时释放 `ChatFeed`。
- `apps/pure_live/lib/features/live_play/record/record_panel.dart`：后台查文件。
- `apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart`：相同时间戳的帧。
- 测试：新增 `test/features/live_play/chat_feed_test.dart`、`chat_list_follow_test.dart`、`chat_benchmark_test.dart`；`test/shared/danmaku_overlay_test.dart`、`test/features/live_play/live_play_popups_test.dart` 各加一个；`chat_names_test.dart`、`live_play_popups_test.dart` 各改一处找法（偏差 3）。

## 新设置和翻译

没有新设置，没有新翻译键。

## 测试

新增 15 个，改了 2 个：

- `chat_feed_test.dart`（8）：两帧之间 50 次改动只排一次、只通知一次，行立即可读；本机弹幕立即通知、之后那一帧不再通知；撤回标记、上限挤掉的不标记，`removalsSince` 给出被挤掉的行也能用的判断、只保留最近 64 次；释放后不通知；表情按表解析一次（同一表返回同一个列表，换表重新解析）；26 种平台颜色 × 7 套主题（浅色、深色、品牌蓝浅/深、纯黑、橙色浅/深）× 两种底色全部 ≥ 4.5:1；够亮的原色不变，黄色在白底上只加深到 4.5～5.2:1、色相不变，深蓝在黑底上提亮；白、黑弹幕用主题色。
- `chat_list_follow_test.dart`（4，整个直播间页面）：两帧之间 30 条消息——飞行层当场收到 30 条，列表在下一帧只建一次，控制器的监听者一次也没被通知；跟随时 40 条新消息分 10 帧进来，滚动位置一次都没动、始终是 0，只建了新行、每行一次，最新一行在底部；往上翻后再来 600 条（超过 500 条上限），屏幕上的行位置完全不变，按钮显示“600 条新弹幕”，撤回的行（包括已被挤出记录的）从定住的列表里去掉，点按钮回到底部看到最新一行；拖回底部松手后恢复跟随，期间来的行都在。
- `danmaku_overlay_test.dart`（+1）：120 Hz 下插入两次“重复时间戳 + 下一帧隔两个周期”，每帧位移依次是 1、0、1、1、0、1、1 px（改之前是 1、0、2、…），重复帧不重绘。
- `live_play_popups_test.dart`（+1）：录制面板用 `IOOverrides` 换掉 `File`，文件出现后“播放”按钮出现，期间只调用了 `exists`、没有 `existsSync`。
- 新增的 R5 和录制面板两个测试在改之前的代码上跑过，都失败（R5 断言位移序列不符；录制面板断言只看到 `existsSync`）。
- `chat_benchmark_test.dart`（1）：3 秒版，断言 `ChatList` 构建 ≤ 2 次、列表每帧最多一次、每行只建一次、全部部件每帧 < 150 个。
- 跑了：`apps/pure_live` 下 `dart format --set-exit-if-changed`（无改动）、`flutter analyze`（无问题）、全部 `flutter test`（817 个全部通过）；根目录 `python3 tools/gate/check_ui_structure.py`（通过）。没有跑完整门禁（本地任务约定）。没有改 Android 原生代码。

## 要在 K90 上看的

1. **热门直播间不卡**：`flutter run --profile` 装 profile 版（或用维护者平时的 profile 构建），进一个人多的英雄联盟比赛直播间（哔哩哔哩或斗鱼），竖屏开着聊天列表放 5 分钟。DevTools 的 Performance 里看 UI 线程：目标 P90 ≤ 3 ms、没有红帧；Rebuild Stats（Track widget builds）里播放器控件、标题栏、信息条不应该随弹幕重建，`ChatLineView` 每条只建一次。
2. **跟随不跳**：放着不动，新弹幕从底部进来，旧的往上推，列表不闪、不跳。
3. **往上翻不动**：手指按住往下拖翻旧弹幕，拖动过程中不被打断；停下来后屏幕上的弹幕原地不动（哪怕过了几十秒、弹幕已经刷过上百条），右下角显示“N 条新弹幕，点击回到底部”且数字在涨；点它回到最新；或者手动拖回底部松手，也恢复跟随。
4. **长按、双击**：定住时长按一条弹幕、屏蔽这个观众，这个观众的弹幕从定住的列表里消失。
5. **昵称颜色**：浅色和深色主题各看一遍彩色昵称（黄、青、浅绿、深蓝最明显），都能看清；卡片样式（设置里“弹幕列表样式”）也看一下。
6. **录制面板**：录完一段后打开录制面板，“播放”按钮出现，点了能播；面板打开、录制中没有卡顿。
7. **飞行弹幕**：开发者选项里看“显示刷新率”，在 120 Hz 和自动降刷新率时，飞行弹幕匀速、没有一顿一跳（R5 的效果在可变刷新率机型上用 Perfetto 看更准）。

## 需要维护者决定的

1. **合并频率：每帧一次还是约 15 Hz。** 现在是每帧一次：200 条/秒、120 Hz 时每帧进来一两行，每帧的工作量平均、P90 低；改成 15 Hz 列表重建次数降到 1/8，但每 8 帧里有一帧要一次建十几行，按 120 Hz 算这样的帧占 12.5%，正好落在 P90 上。建议保持每帧一次；真机 profile 数据不理想再改。
2. **“拖动就定住、回到底部松手才跟随”**（偏差 1）是否就这样；另一种是 3.x 最新版的“只有点按钮才恢复跟随”。
3. 后续（不在本任务可改范围）：录制中心任务卡 `features/recorder/recorder_task_card.dart:275` 也在构建时 `File(output).existsSync()`，同样的问题；`EmoteTable` 可以预编正则（偏差 2）。

## 可能和别的任务冲突的文件

- `danmaku/chat_list.dart`：A07.12 改屏蔽关键词输入和长按弹幕表单两处弹窗；本任务在 `showChatMessageActions` 里只改了名字颜色那一行（`chatNameColor(message.color, scheme.surfaceContainerLowest)`），其余改动都在列表、`chatNameColor` 和 `ChatLineView` 里。冲突时两边都保留，名字颜色那行用新签名。
- `logic/room_controller.dart`：`_onMessage`、`addLocal`、`_system`、`dispose` 几处。
- `danmaku/chat_panel.dart`：未读数那一行（A03.2 改了同文件的翻页手感，已合并，无冲突）。
