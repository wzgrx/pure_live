# D04.1 弹幕性能和可读性：每帧最多刷新一次、聊天列表反转、昵称对比度：任务书

> 本任务的开发已经合并（`a640d9b84`、`7541bfdbf`、`f7f8b00b9`，合并 `f9c7b3a97`，2026-10-02），现在是“待真机”：剩下的是维护者按 [verify.md](verify.md) 在 K90 上用 profile 构建看，以及看出问题时的修补（例如合并频率改成约 15 Hz）。下面保留开工时的全部要求（原任务单，旧编号 B08），按任务书模板 v2 重排；“现状”一节是合并后读代码写的。

## 背景

- 来源：审查报告 B-5、B-6、B-20（[V03.1 全面审查](../../../V-需求和反馈/V03-审查和调研/V03.1-全面审查/README.md)）；调研报告 S5、R5（[V03.2](../../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md) 2.5 节、1.7 节）。
- 现象：热门直播间（每秒几十上百条弹幕）中端机掉帧；弹幕多时往上翻聊天常常翻不动（拖动被下一帧的 `jumpTo` 打断）；浅色主题下黄色、青色、绿色昵称看不清；录制中打开录制面板约每秒一次同步查文件；可变刷新率机型上飞行弹幕偶尔一顿一跳。
- 为什么做：直播间是最常用的页面；计划书第 9.4 节的目标是每秒 200 条时界面线程 P90 ≤ 3 毫秒。
- 依赖：无；和直播间组改同一批文件（`room_controller.dart`、`chat_list.dart`）时错开。

## 目标和验收

1. c1（B-6、S5）：房间控制器收到弹幕后批量通知（每帧最多一次，或约 15 Hz），聊天列表单独监听；列表 `reverse: true`，去掉每条消息后的 `jumpTo`；跟随最新时不跳，往上翻时列表不动；表情只解析一次；飞行弹幕的时序不受影响。
2. c2（B-5）：昵称颜色按相对亮度逐步加深（浅色主题）或提亮（深色主题），直到对背景 ≥ 4.5:1。
3. c3（B-20）：录制面板不在界面线程同步 `File.existsSync()`，改成异步检查并缓存。
4. c4（R5）：飞行弹幕层遇到时间差为 0 的帧时这一帧不走，下一帧不补双步。
5. 每秒 200 条时 K90 profile 界面线程 P90 ≤ 3 毫秒；所有昵称颜色在两种主题下 ≥ 4.5:1。
6. 测试：批量合并的条数和时序；跟随和往上翻两种状态；相同时间戳的帧位移；颜色对比度（多种颜色 × 两种主题）；录制面板不调同步文件接口；一个每秒 200 条的基准。

## 现状（读代码得出，写文件:行）

合并后的代码（2026-10-07 核对，`apps/pure_live/lib/` 省略）：

- `features/live_play/danmaku/chat_feed.dart`（206 行）：`ChatLine.segments`（`:69`）、`scheduleChatFlushForNextFrame`（`:85`）、`ChatFeed`（`:101`，500 条 `:104`、`removalsSince` `:135`、`add` `:145`、`retract` `:154`、`flush` `:187`、`_changed` `:189`）。
- `features/live_play/danmaku/chat_list.dart`（1001 行）：`chatNameContrast`（`:38`）、`contrastRatio`（`:41`）、`chatNameColor`（`:55`）、`_bottomSlack` 24（`:118`）、`_views`（`:127`）、`_onLines`（`:231`）、`_hold`（`:318`）、`_follow`（`:326`）、`ListView`（`reverse` `:434`、`addAutomaticKeepAlives: false` `:440`、`findChildIndexCallback` `:442`）、`_RoomFacts`（`:499`）。
- `features/live_play/danmaku/chat_panel.dart:55`、`:93`：新弹幕数听 `ChatFeed.added`。
- `features/live_play/logic/room_controller.dart`：`_onMessage`（`:868`）不再为聊天通知，昵称提示翻转时通知（`:881-886`）；`addLocal`（`:918`）立即 `flush`。
- `shared/record/saved_file.dart:12`（`SavedFileCheck`，A07.11 c6 从录制面板挪出）；`features/live_play/record/record_panel.dart:201`、`:206`。
- `shared/danmaku/danmaku_overlay.dart:398-417`（R5）。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/controllers/live_play_controller.dart:97-104`：最多 500 条、待发最多 200 条、64 毫秒一批，飞行弹幕直接发。
- `lib/modules/live_play/widgets/danmaku/danmaku_list_view.dart`：`reverse: true`（`:334`）、`addAutomaticKeepAlives: false`（`:329`）、`DanmakuTailFollowGuard`（`:41`，拖动时作废排队的跳转）、暂停时的快照（`:96-98`）、“N 条新弹幕”（`:361-382`）、圆点颜色 HSL 0.52/0.75（`:470`）。
- 要保留：500 条上限；“N 条新弹幕”点了回到最新；双击复制、长按面板；飞行弹幕不等批量。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 9.2 节（列表局部刷新）。
3. 本文件夹的 `README.md`、`record.md`；`docs/V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md` 的 S5、R5；`docs/A-界面设计/A08-弹幕界面/A08.1-弹幕列表和弹幕设置页/README.md`（列表的样子）。

## 范围

- 可以改：`features/live_play/logic/room_controller.dart`、`features/live_play/danmaku/`、`features/live_play/record/record_panel.dart`、`shared/danmaku/danmaku_overlay.dart`、`shared/record/`；对应测试。
- 不能改：聊天列表的样子（A08.1 已确认）；`shared/danmaku/emotes.dart`（当时不在范围，A07.11 后来改了）；其他组的界面和逻辑；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1（已合并） | c4 重复时间戳 | `danmaku_overlay.dart`、`danmaku_overlay_test.dart` | 位移序列测试改之前失败、改之后 1、0、1、1… |
| 2（已合并） | c1 批量、反转、定住和跟随、每行一次；c2 对比度 | `chat_feed.dart`、`chat_list.dart`、`chat_panel.dart`、`room_controller.dart`；`chat_feed_test.dart`、`chat_list_follow_test.dart`、`chat_benchmark_test.dart` | 基准每帧部件 < 150、`ChatList` ≤ 2 次；颜色全部 ≥ 4.5:1 |
| 3（已合并） | c3 录制面板 | `record_panel.dart`、`live_play_popups_test.dart` | `IOOverrides` 下只看到 `exists` |
| 4（待做） | 真机 profile 和观感 | `verify.md` | 每一步有结果；P90 达标后登记表改“完成”；不达标按“风险”里的办法开修补 |

## 测试

- 已有：见 [README](README.md)“验证”（`chat_feed_test.dart` 8 个、`chat_list_follow_test.dart` 5 个、`danmaku_overlay_test.dart:131`、`live_play_popups_test.dart` 录制面板、`chat_benchmark_test.dart`）。
- 真机数字不达标要改时：先用 `chat_benchmark_test.dart` 量改前改后（`--dart-define=CHAT_BENCH_SECONDS=60`），再上 K90。
- 测试里的定时器至少 1 秒；不访问真实平台（基准用假弹幕源）。

## 真机验证（维护者在 K90 上做）

步骤和期望见 [verify.md](verify.md)：profile 帧时间、跟随不跳、往上翻不动、定住时屏蔽、昵称颜色、录制面板、飞行弹幕匀速。

## 风险和注意

- 每帧一次时，120 Hz 下每帧进一两行；改成约 15 Hz 会让每 8 帧里有一帧一次建十几行，正好落在 P90 上（record“需要维护者决定的”1）。真机数字不理想时先看是哪一帧慢（Timeline 里的 Build 还是 Layout），再决定。
- 定住时的列表要处理撤回和屏蔽：被 500 条上限挤出记录的行靠 `removalsSince`（只保留最近 64 次删除）；超过 64 次时返回 null，只按 `removed` 标记去掉。
- 可能冲突的文件：`chat_list.dart`（A08.6、E06.2 也改）、`room_controller.dart`（C01.4、E06.2）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- profile 构建：`cd apps/pure_live && flutter run --profile`（或维护者平时的 profile 构建），DevTools 的 Performance 和 Rebuild Stats。
- 修补走分支 `ai/D04.1` 或本机工作区；提交信息以 `[D04.1]` 开头（英文）；不推 master。
- 提交前：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `next`、`branch`。

## 报告（中文，简洁）

verify.md 每一步的结果和 profile 数字（P50、P90、P99、最差帧）；两处待定（合并频率、跟随规则）的结论；修补改了哪些文件、改前改后的基准数字。
