# C01.1 直播间（主要流程）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（模块重构）
- 来源：模块重构计划的直播间页面，在 3.x `lib/modules/live_play/` 上逐块重写（D-001）；页面取服务的约定来自 I01.1
- 旧编号：M13.3、T05a.1
- 相关：依赖 I01.1（应用骨架）、G02.1（播放会话 `PlaybackSession`）、D01.1（弹幕连接和过滤）、J02.1（设置和存储）；后续 C01.2（第二部分）、A07.1～A07.9（直播间界面）；记录 [record.md](record.md)

## 目标

把 3.x 直播间的主要流程搬到 4.x：进房、播放、弹幕、关注、人数。逻辑和界面分开，所有依赖从构造参数传入，能用假平台、假弹幕、假引擎测试；顺带改掉审查出来的 3.x 问题（四个互相矛盾的状态标志、状态用 Toast 报、封禁说“服务器错误”、开播后不会自己开始等）。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在 | 结果 |
|---|---|---|---|
| 房间逻辑 | `modules/live_play/controllers/live_play_controller.dart`（1178 行）+ `player_controller.dart`（908）+ `danmaku_controller.dart`（389），GetX | `features/live_play/logic/room_controller.dart` 的 `LiveRoomController`（`ChangeNotifier`，依赖从构造传入） | 行为一致，可测 |
| 房间状态 | 四个标志 `isLoading`、`success`、`isLiving`、`loadError`（`states/room_state.dart`，`live_play_controller.dart:925-934`） | `RoomStage` 五个阶段（`logic/room_controller.dart:20-37`），播放细节看会话 | 改（记录问题 1） |
| 晚到的回答 | `_roomLoadEpoch`（`live_play_controller.dart:81`、`:694`） | `_epoch`、`_current`（`room_controller.dart:163`、`:396`） | 一致 |
| 默认清晰度 | `_setDefaultResolution`（`player_controller.dart:611`） | `defaultQualityIndex`（`shared/rooms/play_quality.dart`），`_startStream`（`room_controller.dart:413`） | 一致；移动数据的偏好当时缺网络类型服务，后来由 O03.1 接上 |
| 切清晰度 | `switchStreamSelection`（`player_controller.dart:686`），旧流不断 | `selectQuality`（`room_controller.dart:715`），旧流不断，平台降级时提示（C-4） | 一致 + 增强 |
| 状态提示 | Toast（`live_play_controller.dart:881`、`:913`） | 画面区说明原因和按钮（后来 A07.7 做成 18 种状态，`logic/room_status.dart`） | 改（问题 10） |
| 封禁 | “服务器错误,请稍后获取”（`:881-883`） | “该直播间已被平台封禁或关闭” | 改（问题 2） |
| 未开播后开播 | 要手动刷新 | 每 60 秒刷新详情，开播自动播放、弹幕结束后重连（`refreshDetail` :758，B-24） | 增强（问题 5） |
| 人数 | 一个数，标签随设置变（`audience_info.dart:22-50`） | 在线、热度、累计分开（`_applyAudience` :931） | 增强（问题 3） |
| 观看历史 | 发现清晰度后就记（`live_play_controller.dart:841-846`） | 流打开后才记（`room_controller.dart:438`） | 改（问题 12） |
| 弹幕首连超时 | 20 秒（`danmaku_controller.dart:22`），正好等于快手换备用主机前的等待 | 30 秒（`room_controller.dart:100`） | 改（问题 6） |
| 飞行弹幕 | flame_barrage（游戏引擎 + 本地补丁） | 自绘（`Ticker` + `TextPainter`；现在是 `shared/danmaku/danmaku_overlay.dart`） | 改 |

## 结果

- 提交：`0249e830e`（2026-10-01，`feat(app): live room main flow — entry, playback, danmaku, follow, audience (M13.3)`）。
- 做了：当时 `apps/pure_live/lib/features/live_play/` 8 个文件约 3000 行。进房（详情 → 合并卡片信息 → 更新关注快照 → 发现清晰度 → 默认档 → 取地址 → `PlaybackPlan` → `session.open`）、画质和线路、出错和重试（详情失败保留卡片、按错误类型说原因）、定时刷新、弹幕事件逐条处理（状态行、过滤、人数、醒目留言、撤回、通知）、飞行弹幕、手机和宽屏布局、全屏（手机沉浸 + 转横屏，返回先退出全屏）、关注、房间信息。审查出 3.x 的 12 个问题，处理见 [record.md](record.md) 的“审查发现的 v3 问题”。
- 偏差：屏幕常亮当时交给 media_kit 的默认值（设置关了也常亮），后来 O05.1 修好；`danmakuTopArea`、`danmakuBottomArea` 因为 J02.1 当时把像素当成比例，本任务没用，J02.1 改范围后由 C01.2 接上。
- 测试：新增 14 个（`live_play_controller_test.dart` 9 个、`live_play_page_test.dart` 5 个），另改了 `home_test.dart` 1 处断言。
- 之后的变化：A07 的界面任务把文件拆进了 `buttons/`、`danmaku/`、`dialogs/`、`layout/`、`logic/`、`player/`；当时的 `room_controller.dart` 现在是 `logic/room_controller.dart`，测试搬到 `test/features/live_play/`（现在两个文件分别 13、12 个用例，含后来加的）。

## 验证

- 自动测试：`apps/pure_live/test/features/live_play/live_play_controller_test.dart`、`live_play_page_test.dart`。
- 真机：[S02.2](../../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md)（2026-10-02，K90）进直播间、画质降级提示、横屏全屏和返回通过；[S02.3](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md) 七个国内平台能播（清点 F-ROOM-01）。

## 留下的问题

- 记录“留给后续”各项的去向：投屏、录制按钮、分享、外部打开、定时关闭、音量和亮度手势、画中画、后台播放和媒体通知、网络电视节目单和回看、切换直播间 → C01.2；竖屏流和竖屏全屏 → A07.2；本地互动 → A08.2；弹幕次要设置 → D05.1、A08.5；画面弹幕的点按和长按 → A08.4；表情图片 → D03.2；Windows 窗口全屏和移动数据清晰度 → O03.1；屏幕常亮跟随设置 → O05.1；预测返回 → C03.1。
- 后来读代码发现、由本任务的定时刷新（B-24）带出来的三个问题，现在都**没有任务**，写在 [C01 的“已知问题”](../README.md)，等维护者决定是否开任务：
  - 后台时未开播的房间开播会自动出声（`logic/room_controller.dart:775-778` 的 `load()` 加上 `logic/background_playback.dart:472-490` 只在离开时判断一次）。原来归 C01.3，C01.3 按 D-029 改“不做”后没有去处。
  - 主播换场后弹幕参数变了不重连（TwitCasting、克拉克拉、SHOWROOM）：`refreshDetail` 只在弹幕连接已经结束时重连（`:785`），不比较参数；轻量刷新接口也不带新参数（`LiveRoom.mergeFrom` 保留旧的 `danmakuData`，`packages/live_core/lib/src/live_room.dart:619`）。
  - 定时刷新在后台也每 60 秒请一次详情（`:325-327`）。
- 刷新时“平台实际给的清晰度不在列表里”显示成“原画?”（升级 C-4 的显示规则）→ [C01.4](../C01.4-直播间清晰度显示实际档/README.md)。
