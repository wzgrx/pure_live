# D05.2 同屏最大弹幕条数可以设置（接 V01.4）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：新功能提议 [V01.4](../../../V-需求和反馈/V01-新功能提议/V01.4-同屏最大弹幕条数可以设置/README.md)（D-036 同意做）；上游 pure_live_TV `9a7bb104`
- 相关：决定 D-036（默认 48）、D-003（设计由维护者选）、D-018（新设置只加不改）；弹幕设置界面 A08.5（设置里的弹幕页和直播间同一个组件）；飞行弹幕引擎 [D03](../../D03-飞行弹幕引擎/README.md)；任务书 [brief.md](brief.md)、记录 [record.md](record.md)

## 目标

直播间画面上同时飞的弹幕条数可以调：弹幕设置“流畅度”一组加一行“同屏最大弹幕条数”，滑条 10～120、步长 2，默认 48（和 3.x、改之前一样，老用户感觉不到变化）。热门直播间嫌挡画面的调少，想看满屏的调多，弱机器调少更流畅。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11:lib/`） | 改之前（`apps/pure_live/lib/`） | 要做到 |
|---|---|---|---|
| 直播间画面 | `modules/live_play/widgets/video_player/video_controller_panel.dart:801`：`maxVisibleCount: 48` | `features/live_play/player/player_view.dart` 的 `_danmaku` 不传 `maxVisible`，用 `DanmakuOverlay` 默认 48 | 传 `Settings.danmakuMaxVisibleCount` |
| 多画面 | `modules/multiview/multiview_page.dart:1309`：48 | `features/multiview/multiview_page.dart` 不传，48 | 跟设置（V01.4 c4 选 A） |
| 电视直播间 | —（电视版是另一个仓库） | `tv/room/tv_live_play_page.dart` 的 `_Picture` 不传，48 | 跟设置 |
| 小窗、画中画 | `pipDanmakuMaxVisibleCount` | 同（默认 6，1～20） | 不变 |
| 设置界面 | 没有 | `shared/danmaku/danmaku_settings_content.dart` 的“流畅度”：弹幕帧率跟随、弹幕帧率 | 加一行滑条；设置搜索能找到 |

## 结果

- c1 新设置 `danmakuMaxVisibleCount`（`packages/live_store/lib/src/settings/settings.dart`，`section: 'danmaku'`，默认 48，10～120，超出范围读成 48，例如上游电视版备份里表示“按设备”的 0）；登记在 `Settings.all`、`settings_defaults_test.dart` 的 `newInV4` 和 `ranges`、`tools/docs/settings_audit_notes.py`。备份、恢复、设备同步照所有设置自动带上（`BackupService.exportAll` 遍历 `Settings.all`）；3.x 的备份里没有它，导入后保持 48。
- c2 直播间、多画面、电视直播间的 `DanmakuOverlay(maxVisible:)` 读这个设置，改了立即生效：屏上已经在飞的照飞，调小时新的先等着（队列规则不变：最多 120 条、5 秒），调大时等着的马上进来（每帧最多 4 条）。小窗弹幕层不变（它有自己的“最大同时显示数量”）。
- c3 设置行：`DanmakuSettingsContent` 的“流畅度”一组，“弹幕帧率”下面，`SettingSliderRow`（键 `maxVisible`，56 档，显示“48 条”）；直播间的弹幕设置标签、画面上的弹幕设置面板、设置 → 弹幕三处是同一个组件，一起有了。设置搜索的条目 `danmaku_max_visible`（“弹幕 › 流畅度”，关键字“同屏”“条数”“数量”“密度”），说明“画面上同时飞的弹幕最多几条，默认 48；少一些更清楚、更省电”。
- 翻译键：`danmaku_max_visible`、`danmaku_max_visible_desc`、`danmaku_max_visible_value`（zh、en）。
- 观看模板不带这一项（模板是 3.x 的格式，管样式）。

## 验证

- 自动测试：见 [record.md](record.md)“测试”。
- 真机：record.md“真机上要看的”；待真机。

## 留下的问题

- 没有。上游的“海量模式”（不限条数）不做，理由在 V01.4 的 README。
