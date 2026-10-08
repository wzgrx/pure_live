# D05.2 同屏最大弹幕条数可以设置（接 V01.4）：任务书

## 背景

- 来源：新功能提议 V01.4（D-036 同意做，默认 48）；上游 pure_live_TV `9a7bb104`（电视版的“同屏最大弹幕条数”）。
- 现象：直播间画面上同时最多 48 条平台弹幕，写死（3.x 也是 48）；热门直播间铺满时挡画面，弱机器上多了会卡。
- 为什么现在做：第三档；D-036 的路线顺序第一个（同屏条数 → 按住停住 → …）。
- 已经做过的：V01.4 的评估和设计（`docs/V-需求和反馈/V01-新功能提议/V01.4-同屏最大弹幕条数可以设置/README.md`“评估结论和设计”）。

## 目标和验收

1. 新设置 `danmakuMaxVisibleCount`：整数，默认 48，10～120，超出范围读成 48；在 `Settings.all` 里，跟备份和设备同步走。
2. 直播间、多画面、电视直播间的飞行弹幕层按它限条数，改了立即生效；默认时和改之前完全一样。
3. 小窗、画中画的弹幕层不变（`pipDanmakuMaxVisibleCount`）。
4. 弹幕设置“流畅度”一组在“弹幕帧率”下面多一行滑条“同屏最大弹幕条数”（步长 2，显示“N 条”）；三处（直播间标签、画面面板、设置 → 弹幕）是同一个组件；设置搜索“同屏”能找到。
5. 用户看得到的文字走翻译（zh、en，按键名排序）。

## 现状（读代码得出）

- `apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart`：`maxVisible` 参数默认 48；`_place` 里平台弹幕数到上限就不放，在 `_pending` 里等（`maxPending` 120、`maxPendingAge` 5 秒）；本地弹幕不算。
- 用处：`features/live_play/player/player_view.dart` 的 `_danmaku`、`features/multiview/multiview_page.dart` 的弹幕 `Consumer`、`tv/room/tv_live_play_page.dart` 的 `_Picture`（都不传）；`features/live_play/mini/compact_danmaku.dart`、`features/settings/playback_tiles.dart`（传小窗的设置）。
- 设置界面：`shared/danmaku/danmaku_settings_content.dart` 的“流畅度”组；搜索条目在 `features/settings/settings_catalog.dart` 的 `danmaku_group_smoothness`。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/widgets/video_player/video_controller_panel.dart` 的 `:801`、`lib/modules/multiview/multiview_page.dart:1309`：`maxVisibleCount: 48`。
- 要保留：默认 48；小窗设置的键和含义（D-018）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5、8、14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 3 节。
3. 本文件夹 `README.md`；V01.4 的 README。

## 范围

- 可以改：上面列的文件；`packages/live_store/lib/src/settings/settings.dart`；翻译文件；对应测试；`tools/docs/settings_audit_notes.py`；本文件夹和 V01.4、D05 的说明。
- 不能改：弹幕层的排队和轨道规则；小窗的设置；观看模板的格式（`savedDanmakuTemplate`）；3.x 的设置键名和含义。

## 方案和阶段

规模小，不分阶段：c1 设置 → c2 三处弹幕层 → c3 设置行和搜索 → 测试 → 文档。

## 测试

- `apps/pure_live/test/shared/danmaku_overlay_test.dart`：上限 10 时只飞 10 条、其余等；调到 24 等着的进来；调到 12 屏上的不拿掉、新的等。
- `apps/pure_live/test/features/live_play/live_play_page_test.dart`：直播间默认 48；改成 10、120 立即传给弹幕层。
- `apps/pure_live/test/features/multiview/multiview_page_test.dart`、`apps/pure_live/test/tv/tv_test.dart`：多画面、电视跟设置。
- `apps/pure_live/test/features/live_play/live_play_popups_test.dart`：面板里的行、位置、范围、默认“48 条”、改了是设置。
- `apps/pure_live/test/features/settings/settings_danmaku_test.dart`：设置 → 弹幕有这一行；搜索“同屏”在“弹幕 › 流畅度”下。
- `packages/live_store/test/danmaku_on_screen_test.dart`：默认、范围、超出读成 48、备份往返、3.x 备份不带它、电视版的 0。

## 真机验证（维护者在 K90 上做）

见 [record.md](record.md)“真机上要看的”。

## 风险和注意

- 调到 120 时弱机器掉帧：上限不超过 120（和等待队列一样长）。
- 调小以后队列更快满、更多弹幕被丢：说明里写了“少一些”。

## 环境和提交

- 本机工作区；提交信息以 `[D05.2]` 开头（英文）；不推 master；`bash tools/gate/gate.sh --all` 通过。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条做到没有；测试数量；改了哪些文件；新设置和翻译键；要在真机上看的。
