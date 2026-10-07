# V01.4 同屏最大弹幕条数可以设置：任务书

## 背景

- 来源：上游 pure_live_TV `9a7bb104`（电视版的“同屏最大弹幕条数”），W01.1 列为可借鉴的新功能，按 D-027 进 V01；旧任务清单 T06e.5。
- 现象：直播间画面上同时最多 48 条弹幕，写死（3.x 也是 48）；热门直播间弹幕铺满时有人嫌挡画面，弱机器上多了会卡。
- 为什么是第三档：新功能（D-026），规模小。
- 已经做过的：本文件夹 `README.md` 的评估初稿（默认 48、范围 10～120、只改直播间画面、多画面待选）。

## 目标和验收

本任务是**提议**：做到“用户能拍板”为止。

1. 评估补完：核对 README 的文件:行；确认 48 在 3.x 和 4.x 的所有用处（直播间、多画面、电视直播间 `apps/pure_live/lib/tv/room/tv_live_play_page.dart:464`）；写清默认值、范围、步长的建议和理由。
2. 示意：设置“流畅度”一组加一行后的样子（一张竖屏、一张宽屏右栏），可以用现有组件截图改字，不用整套效果图。
3. 评审页（或在维护者同意下直接给用户一段文字说明加图）：需要你选的：做不做 / 范围和步长 / 多画面跟不跟 / 电视跟不跟；维护者改“待确认”。
4. 用户回复后：确认 → 建议的 DECISIONS 条目和目标组任务（D05 生效 c1、c2；A08 界面 c3；N01 c4）；否决 → V04 的说明。

## 现状（读代码得出，写文件:行）

- `apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart`：构造参数 `maxVisible = 48`（`:158`，注释“3.x 48; the mini windows' 最大同时显示数量”）；`_place`（`:463`）里 `remote >= limit` 就不放（`:466`，本地弹幕不算）；等的队列 `_pending` 最多 `maxPending = 120`（`:213`），超过丢最早的（`:364-366`），等超过 `maxPendingAge = 5 s`（`:216`）的丢掉。
- 用处：直播间 `features/live_play/player/player_view.dart:469`（不传，48）；多画面 `features/multiview/multiview_page.dart:878`（不传，48）；小窗 `features/live_play/mini/compact_danmaku.dart:190-195`（传 `pipDanmakuMaxVisibleCount`）；设置页的小窗预览 `features/settings/playback_tiles.dart:711`；电视直播间 `tv/room/tv_live_play_page.dart:464`。
- 设置：小窗的 `pipDanmakuMaxVisibleCount`（`packages/live_store/lib/src/settings/settings.dart:567`，默认 6、最少 1）；主画面没有。
- 设置界面：`shared/danmaku/danmaku_settings_content.dart` 的“流畅度”组（`:236` 起：弹幕帧率、跟随屏幕刷新率）；三处（直播间标签、画面面板、设置 → 弹幕）都用它。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/widgets/video_player/video_controller_panel.dart` 的 `:801`、`video_controller.dart:968`、`lib/modules/multiview/multiview_page.dart:1309`：都是 `maxVisibleCount: 48`；小窗 `lib/modules/live_play/widgets/danmaku/compact_danmaku_overlay.dart:33` 读 `pipDanmakuMaxVisibleCount`。
- 要保留：默认 48（老用户不变）；小窗的设置键和含义（D-018）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 6 节）。
2. `docs/A-界面设计/A08-弹幕界面/A08.1-弹幕列表和弹幕设置页/README.md`（弹幕设置的分组和 E1“各处一样”）；`docs/D-弹幕/D05-弹幕设置生效/README.md`。
3. 本文件夹 `README.md`；上游 `~/ref/pure_live_TV/lib/player/danmaku_config_builder.dart:15-70`（只读）。

## 范围

- 可以改：本文件夹。
- 不能改：代码；`docs/tasks.toml`、`docs/DECISIONS.md`；其他组文档。

## 方案和阶段

登记表没有阶段（规模小），按两步做：

| 步 | 做什么 | 怎么算做完 |
|---|---|---|
| 1 | 补完评估、做示意、发评审页或说明 | 报告给维护者改“待确认” |
| 2 | 用户回复后按 PROCESS 第 6 节第 3 步处理；实现任务完成后本任务改“完成” | 目标组任务登记好（或改“不做”） |

## 测试

- 本任务不写测试；README“验证”一节写了实现任务要加的测试（`apps/pure_live/test/shared/danmaku_overlay_test.dart` 的上限用例；设置页三处一样、能搜到）。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 无（提议阶段不上机） | — |

## 风险和注意

- 上限太大（120）时弱机器掉帧：评估里引用 R01.1 的 `danmaku_200` 基准场景（`apps/pure_live/integration_test/perf_test.dart:138`），建议上限不超过 120。
- 上限改小后，等的队列会更快到 120 条、更多弹幕被丢：说明里写“弹幕多时会少显示一些”。
- 多画面四格各自 48 条可能太挤：c4 要用户选。

## 环境和提交

- 本机工作区或分支 `ai/V01.4`；提交信息以 `[V01.4]` 开头（英文）；不推 master。提交前 `python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：已写的先提交；README 末尾写“停在哪”。

## 报告（中文，简洁）

建议的默认值、范围、步长；多画面和电视的建议；评审页或说明的地址；建议的 DECISIONS 条目和目标组任务。
