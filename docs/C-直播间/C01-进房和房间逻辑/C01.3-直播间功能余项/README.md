# C01.3 直播间功能余项（不做）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（状态“不做”，2026-10-03 由“未开始”改）
- 类型：功能（登记时）；关掉前的内容已经变成核对和真机验证
- 来源：功能清点 [inventory/FEATURES.md](../../../inventory/FEATURES.md) 第 8 节。登记时（docs v0，2026-10-03）照抄了清点第 1 版（2026-10-02）统计表里直播间那一行的“6 项缺失、1 项有问题”
- 旧编号：T05a.4
- 相关：决定 **D-029**（功能清点余项任务 C01.3、D06.1、Q04.1 不再单独做）；核对报告 [V03.3](../../../V-需求和反馈/V03-审查和调研/V03.3-功能清点和已批准升级核对/README.md)；做完这些功能点的任务 [C02.1](../../C02-小窗、画中画、后台播放/C02.1-冷门的播放设置/README.md)、[C03.1](../../C03-直播间工具/C03.1-直播间小项/README.md)、[O05.1](../../../O-Android系统集成/O05-方向、刷新率、常亮/O05.1-屏幕常亮跟随设置/README.md)、G04.1；接过真机验证的 [S02.6](../../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md)

## 这个任务原来要做什么

补齐功能清点第 1 版里直播间部分标成“缺失”的 6 项和“有问题”的 1 项，让 4.x 直播间里 3.x 有的功能都能用、行为对。

## 为什么不做

登记表里这个任务挂着“未开始”的时候，它要补的 7 项其实都已经由别的任务做完了（V03.3 逐条对照代码和记录核对）。按 D-029 关掉，免得同一件事挂两处：

| 功能点 | 功能 | 3.x（`v3.2.11`） | 由哪个任务做完（现在的位置，`apps/pure_live/lib/` 下） | 清点现在的状态 |
|---|---|---|---|---|
| F-ROOM-21 | “播放器强制销毁”关时把播放器留给下一个房间 | `lib/player/core/player_manager.dart:234`、`:3656-3686` | C02.1 c1：`features/live_play/logic/player_standby.dart:15`；`live_play_page.dart:225-229`（取）、`:491`（读 `useHardStopOnExit`） | 完成 |
| F-PORT-05 | 小窗跟随竖屏源的比例 | `lib/player/core/portrait_stream_support.dart:770-778` | C02.1 c2：`features/live_play/logic/mini_window.dart:83` 的 `miniPictureSize` | 完成 |
| F-PORT-06 | 竖屏诊断信息 | `lib/modules/live_play/widgets/video_player/video_controller_panel.dart:704-745` | C02.1 c3：`features/live_play/player/portrait_diagnostics.dart:14` | 完成 |
| F-ROOM-22 | 抖音竖屏流的画面比例预判（起播时不跳） | `lib/player/core/live_stream_geometry_hint.dart:8` | G04.1：`packages/live_core` 的 `LivePlayLine.width`/`height`/`declaredAspectRatio`，`packages/live_player` 的 `PlaybackState.expectedAspectRatio` | 完成 |
| F-RT-05 | 快手 App 跳转 | `lib/modules/live_play/services/room_external_opener.dart:193-200` | C03.1 c1：`features/live_play/buttons/room_menu_button.dart:66`（`kuaishouStreamId`）、`:78`（`kuaishouAppLink`） | 完成 |
| F-RT-07 | 切换直播间里的刷新 | `lib/modules/live_play/dialogs/play_other.dart:117-136` | C03.1 c2，A07.13 搬进新面板：`features/live_play/switch_room/room_switch_panel.dart:22`、`:409` | 完成 |
| F-ROOM-13 | 屏幕常亮跟随设置 | `lib/modules/live_play/controllers/live_play_controller.dart:177`、`:252-260` | O05.1：`packages/live_player/lib/src/screen_wake.dart`、`video_view.dart:79` | 没验证 → S02.6 |

清点表本身（第 8 节的统计行、各行的“依据”、F-ROOM-25 填反的两列、F-RT-06 的旧路径）也由 V03.3 改好了，这个任务登记时写的“c1 清点表更正”不用再做。

## 关掉时没有去处的事

上一轮（2026-10-03）给这个任务写的方案里，除了核对，还有一处读代码发现的 4.x 新问题。任务关掉后它没有登记任务，写在 [C01 的“已知问题”](../README.md)里，请维护者决定是否另开：

- **后台时未开播的房间开播会自动出声**：定时刷新（B-24）在后台照跑，`refreshDetail` 发现开播就 `load()`（`features/live_play/logic/room_controller.dart:775-778`）；`RoomBackgroundPolicy.onHidden`（`logic/background_playback.dart:472-490`）只在离开应用 1.5 秒后判断一次，那时会话没在播就什么都不做，之后才开始的播放没人暂停，也没有媒体通知可以停（`:431-440`）。3.x 没有定时刷新，没有这个问题。读代码得出，未在真机确认。

另外，这个任务原来想顺带在 K90 上看的几项现在的去向：

| 项 | 去向 |
|---|---|
| 屏幕常亮开和关（CHECKLIST 第 1 节第 7 条） | S02.6 第 1 阶段 |
| 投屏到真电视（第 13 条） | S02.6 第 1 阶段 |
| 预测返回、返回键（F-AND-08） | S02.6 第 1 阶段；ColorOS 另见 [O06.1](../../../O-Android系统集成/O06-返回手势、平板和折叠屏/O06.1-预测返回在ColorOS14/README.md) |
| 从画中画回来后的控制条 | [O02.1](../../../O-Android系统集成/O02-画中画/O02.1-画中画复验/README.md) |
| 播放器留给下一个房间、小窗比例、竖屏诊断、媒体键（C02.1）；快手跳转、切换直播间刷新（C03.1） | 按 D-029 判为完成（关键部分不靠原生和系统服务），没有专门的真机任务；日常回归照 CHECKLIST 第 1 节第 8、12、14 条看 |

## 以后什么情况下重新考虑

- 真机回归（S02.5、S02.6 或日常）发现上表任何一个功能点不对：在对应子分类开新任务（例如快手跳转开在 C03、小窗比例开在 C02），不重开本任务。
- 维护者决定修“后台时开播自动出声”：在 C01 开新任务（新编号），不复用 C01.3。

本任务原来的任务书已删除（V03.3 的结论：“不做”的任务只要 README 写去向，不要任务书）；需要时看 git 历史里的 `brief.md`。
