# V01.4 同屏最大弹幕条数可以设置

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（新功能提议）
- 来源：上游 pure_live_TV `9a7bb104`（电视版弹幕设置加了“同屏最大弹幕条数”，0 表示按设备自动：弱机 40、富余 64，滑条 0～120、步长 5），W01.1 列为可借鉴的新功能；旧任务清单 T06e.5
- 旧编号：T06e.5
- 相关：决定 D-026、D-018；弹幕设置生效 [D05](../../../D-弹幕/D05-弹幕设置生效/README.md)；飞行弹幕引擎 [D03](../../../D-弹幕/D03-飞行弹幕引擎/README.md)；设置界面 [A08.1](../../../A-界面设计/A08-弹幕界面/A08.1-弹幕列表和弹幕设置页/README.md)、[A08.5](../../../A-界面设计/A08-弹幕界面/A08.5-设置里的弹幕页/README.md)；任务书 [brief.md](brief.md)

## 目标

直播间画面上同时飞的弹幕现在最多 48 条（照 3.x 写死）。热门直播间弹幕多时，有人嫌挡画面想少一点，有人想看满屏；性能弱的机器少一点更流畅。提议：在弹幕设置“流畅度”一组加一项“同屏最大弹幕条数”，默认 48（和 3.x、现在一样，老用户感觉不到变化）。

做不做已由 D-036 定了（同意做，第三档，默认 48）；下面“评估结论和设计（定稿）”一节是 2026-10-08 补完的评估和维护者按 D-003 选的方案，实现任务是 [D05.2](../../../D-弹幕/D05-弹幕设置生效/D05.2-同屏最大弹幕条数可以设置/README.md)。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11:lib/`） | 4.x 现在（`apps/pure_live/lib/`） | 上游电视版 | 提议 |
|---|---|---|---|---|
| 直播间画面 | `modules/live_play/widgets/video_player/video_controller_panel.dart:801`、`video_controller.dart:968`：`maxVisibleCount: 48` 写死 | `shared/danmaku/danmaku_overlay.dart:158`：`maxVisible = 48` 默认值；`features/live_play/player/player_view.dart:469` 没传，用默认；到上限时新的在队列里等（`_place` `:466`），队列最多 120 条（`maxPending` `:213`）、最多等 5 秒（`maxPendingAge` `:216`） | `lib/player/danmaku_config_builder.dart:65`：用户设了非 0 就用它，0 按设备（弱机 40、富余 64）；设置页滑条 0～120、步长 5（`features/settings/pages/danmaku_settings_section.dart:236-247`） | 新设置，默认 48；滑条 10～120、步长 2（或 5） |
| 多画面 | `modules/multiview/multiview_page.dart:1309`：48 | `features/multiview/multiview_page.dart:878` 的 `DanmakuOverlay` 没传，48 | — | 是否跟着这个设置走，要用户选（格子小，建议另算：设置值 × 格子面积比例，或保持 48） |
| 小窗、画中画 | `pipDanmakuMaxVisibleCount`（小窗弹幕设置里有，3.x 也有） | 同：`packages/live_store/lib/src/settings/settings.dart:567`（默认 6、最少 1），`features/live_play/mini/compact_danmaku.dart:195` | — | 不变（已经能设） |
| 设置界面 | 没有 | 弹幕设置正文 `shared/danmaku/danmaku_settings_content.dart`，“流畅度”一组在 `:236` 起（弹幕帧率等） | 有 | 在“流畅度”一组加一行 |

## 方案（评估初稿）

| 编号 | 改什么 | 目标组 |
|---|---|---|
| c1 | 新设置 `danmakuMaxVisibleCount`（整数，默认 48，范围 10～120；新键，3.x 没有，D-018 只加不改） | D05、J01 |
| c2 | 直播间画面的 `DanmakuOverlay` 传这个值（`player_view.dart:469`）；改了立即生效（已经在飞的不受影响，新进的按新上限） | D05 |
| c3 | 设置行：弹幕设置“流畅度”组加“同屏最大弹幕条数”，说明“画面上同时显示的弹幕最多几条，少一些更清楚、更省电”；直播间的弹幕设置标签、画面上的弹幕设置面板、设置 → 弹幕三处同一个组件（A08.1 E1 的规则） | A08 |
| c4 | 多画面：按用户的选择（跟设置 / 保持 48 / 按格子比例） | N01 |

规模：小（一个设置、一行界面、两三个测试）。不需要效果图（照现有设置行的样子），评审页可以只放一张设置截图和说明。

不做：电视版的“0 = 按设备自动”（手机机型差别小，3.x 也没有）；电视版同一组的“高峰排队上限”“排队超时丢弃”（4.x 是常量 120 条、5 秒，没有用户反馈要改）。

## 评估结论和设计（定稿，2026-10-08）

### 核对过的用处（4.x 里 48 在哪）

| 用处 | 文件 | 改之前 | 定稿 |
|---|---|---|---|
| 直播间画面（竖屏、全屏、宽屏、画中画里的主画面都是这一个） | `apps/pure_live/lib/features/live_play/player/player_view.dart` 的 `_danmaku` | 不传 `maxVisible`，用 `DanmakuOverlay` 的默认 48 | 传新设置 |
| 多画面（只有选中的那一格有弹幕） | `apps/pure_live/lib/features/multiview/multiview_page.dart` 的弹幕 `Consumer` | 不传，48 | 传新设置（c4 选“跟设置”） |
| 电视直播间 | `apps/pure_live/lib/tv/room/tv_live_play_page.dart` 的 `_Picture` | 不传，48 | 传新设置（同一个画面弹幕，跟着走） |
| 应用内小窗、系统画中画、桌面小窗的弹幕层 | `apps/pure_live/lib/features/live_play/mini/compact_danmaku.dart` | 传 `pipDanmakuMaxVisibleCount`（默认 6，1～20） | 不变：小窗有自己的“最大同时显示数量”（3.x 就有） |
| 设置页“小窗弹幕”的预览 | `apps/pure_live/lib/features/settings/playback_tiles.dart` | 传 `pipDanmakuMaxVisibleCount` | 不变 |
| 弹幕层本身 | `apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart` 的 `_place` | 平台弹幕数 ≥ 上限时不放，在队列里等（最多 120 条、5 秒）；本地弹幕不算 | 不变（规则照旧，只是上限从设置来） |

### 需要选的和选择（D-003，维护者按建议定）

| 问题 | 选项 | 选了 | 理由 |
|---|---|---|---|
| 默认值 | — | 48 | D-036：老用户感觉不到变化；3.x 直播间、多画面都是 48 |
| 范围 | A 10～120；B 0～120（0 = 按设备，电视版）；C 1～200 | A | 少于 10 条画面几乎没弹幕，不如关掉；120 和等待队列的上限（`maxPending` 120）一样，再多弱机器掉帧（R01.1 的 `danmaku_200` 场景）；手机机型差别小，不做“按设备自动”（3.x 也没有） |
| 步长 | A 滑条步长 2；B 步长 5（电视版）；C 加减按钮步长 1 | A | 步长 5 从 10 起到不了 48（默认值不在滑条上）；步长 2 一共 56 档，48 正好在上面；加减按钮 110 档按不过来 |
| 超出范围的值 | A 读成默认 48；B 夹到 10 或 120 | A | 上游电视版的备份里 0 表示“按设备”，夹到 10 会让人以为弹幕坏了；读成 48 和没设一样 |
| 放在哪 | 弹幕设置“流畅度”一组，弹幕帧率下面 | — | 和帧率一样是“多和流畅”的取舍；直播间的弹幕设置标签、画面上的弹幕设置面板、设置 → 弹幕三处是同一个组件（`DanmakuSettingsContent`，A08.5），加一处三处都有 |
| 说明文字 | 面板里只放标题和数值（“48 条”），说明放在搜索结果里（和速度、帧率一样） | — | 面板里的滑条行都没有副标题（`SettingSliderRow`），保持一致；设置搜索“同屏”“条数”“密度”能找到，说明是“画面上同时飞的弹幕最多几条，默认 48；少一些更清楚、更省电” |
| 多画面（c4） | A 跟设置；B 保持 48；C 按格子面积打折 | A | 各处一致；格子小时轨道数本来就先限住了条数，48 在 2×2 的格子里几乎碰不到，所以跟设置只在用户调小时有区别（用户调小就是嫌多，多画面也该少）；C 规则用户看不出来 |
| 电视 | A 跟设置；B 保持 48 | A | 同一个设置、同一个画面弹幕层；电视没有自己的弹幕设置页，跟手机端的值走 |
| 观看模板要不要带上它 | A 不带；B 带 | A | 三套模板和“我的模板”是 3.x 的格式（`savedDanmakuTemplate` schema 2），带上要改格式；模板管样式，条数是流畅度 |
| 上游 `a7783b525` 的“海量模式”（不限条数） | 不做 | — | 4.x 的上限就是防“弹幕到了全上屏”卡顿的；要“不限”的人把滑条拉到 120 已经接近；以后有人要再在 V01 提 |
| 改了以后 | 立即生效 | — | 屏上已经在飞的不受影响，调小时新的先等着，调大时等着的马上进来（每帧最多 4 条） |

### 存储、备份、同步

- 新键 `danmakuMaxVisibleCount`（`section: 'danmaku'`，`IntSetting`，默认 48，`min: 10`、`max: 120`、`resetOutOfRange: true`）；3.x 没有这个键，D-018 只加不改。
- 备份照其他设置自动带上（`BackupService.exportAll` 遍历 `Settings.all`，写在 `danmaku` 一节）；3.x 读 4.x 的备份时不认识这个键、跳过；3.x 的备份里没有它，导入后保持 48；设备同步走同一份备份格式。
- 设置键的登记：`packages/live_store/test/settings_defaults_test.dart` 的 `newInV4`、`ranges`；`tools/docs/settings_audit_notes.py`；J01.2 的 `settings.md` 重新生成。归属照 `docs/inventory/OWNERS.toml` 的 `danmaku` 一节默认 D05。

## 验证（做了以后怎么验证）

- 自动测试：`apps/pure_live/test/shared/danmaku_overlay_test.dart` 现在没有上限的用例，要加“满 N 条后新的排队、有一条飞出后再进”“上限从设置读、改了以后新进的按新上限”；设置页测试加这一行（三处一样、搜索“同屏”能找到）。
- 真机：热门直播间把上限改成 10 和 120 各看 30 秒，画面上弹幕数量明显不同；改回 48。

## 留下的问题

- 做不做（D-036 同意）、范围和步长、多画面、电视都已定（上一节）；实现在 D05.2。
- 上游 pure_live `a7783b525` 的“海量模式”不做（上一节）；以后有人要再提。
- 本提议在 D05.2 真机看过、改“完成”以后改“完成”（PROCESS 第 6 节第 4 步）。
