# D03.4 按住飞行弹幕让它停住，松手继续（接 V01.3）：任务书

## 背景

- 来源：新功能提议 V01.3（D-036 同意做）；上游 flame_barrage `3eddae8`（`pauseItemAt`、`resumeAllPaused`）、pure_live `2d2ad2039`（长按时定住那一条）。
- 现象：飞得快的弹幕看不清；长按要 500 毫秒，这期间那一条飞走了约 60 像素，长按常常点不中它。
- 为什么现在做：第三档；D-036 路线的第二个（同屏条数 → 按住停住 → …）。
- 已经做过的：V01.3 的评估、和现有手势的冲突分析、设计（`docs/V-需求和反馈/V01-新功能提议/V01.3-按住弹幕让它停住/README.md`“评估结论和设计”，维护者按 D-003 选做法 A、开关默认关）；A08.4（长按面板）、A07.14（双击）、A08.9（D-038 单击）。

## 目标和验收

1. 弹幕层能钉住一条：钉着时它不走、不过期、画在最上面；其他照飞，从它下面穿过；它那条轨道暂不进新弹幕；放开后从原位、原速度接着飞，不跳。
2. 新开关 `holdDanmakuOnPress`，默认关；关着时画面上的一切和以前一样。
3. 开着时：手指按在一条飞行弹幕上（不在显示着的上下栏上、没锁定）它就停住；抬手、取消、拖动超过触摸容差时放开。
4. 单击、双击、长按的结果不变（D-038、A07.14、A08.4）：长按打开的是按住的那一条，面板开着时整层停住。
5. 开关在弹幕设置“画面弹幕交互”组（三处同一个组件），有说明，设置搜索能找到；文字走翻译。

## 现状（读代码得出）

- `apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart`：每条 `_Flying` 的位置 = 速度 × (它那条时钟 − `start`)；`held` 整层停住；`messageAt` 找手指下那一条；`_place` 选轨道用每条轨道列表里的最后一条。
- `apps/pure_live/lib/features/live_play/player/player_view.dart`：画面 `GestureDetector` 的 `onTapDown`、`onTap`（`_onTap`）、`onLongPressStart`；`_danmakuAt` 看开关、锁定、`danmakuTapAllowed`；`_openMessage` 打开面板、整层停住。

## 3.x 基线

- 3.x 没有单条停住；长按打开菜单、菜单开着整层暂停（`git show v3.2.11:lib/modules/live_play/widgets/video_player/video_controller.dart` 的 `triggerItemAt` `:262`）。要保留：长按开面板、面板开着整层停住。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 附录 A 第 2、6 条。
3. 本文件夹 `README.md`；V01.3 的 README；A08.4、A07.14、A08.9 的 README。

## 范围

- 可以改：上面两个文件；`shared/danmaku/danmaku_settings_content.dart`、`features/settings/settings_catalog.dart`；`packages/live_store/lib/src/settings/settings.dart`；翻译文件；`docs/inventory/OWNERS.toml`、`tools/docs/settings_audit_notes.py`；对应测试；本文件夹和 V01.3、D03 的说明。
- 不能改：单击、双击、长按的判定和结果；点按、长按开关的键和含义；小窗和多画面。

## 方案和阶段

规模小，不分阶段：c1 弹幕层钉住 → c2 同轨 → c3 手势（`Listener`）→ c4 设置 → 测试 → 文档。

## 测试

- `apps/pure_live/test/shared/danmaku_overlay_test.dart`：钉住的那一条 2 秒不动、另一条照飞 240 像素；`messageAt` 还能找到它；放开后 0.5 秒走 60 像素；整层停住时钉住再放开不跳；撤回后不再钉着；一条轨道时钉着它新弹幕不进、放开后马上进。
- `apps/pure_live/test/features/live_play/live_play_page_test.dart`：默认关时按住它照飞；开了以后按住它不动、别的照飞、整层不停；抬手放开，单击照旧（等双击时间过了打开面板）；长按打开面板、整层停住、抬手后不再钉着；拖动 40 像素放开；双击只切全屏、面板不出。
- `apps/pure_live/test/features/live_play/live_play_popups_test.dart`、`apps/pure_live/test/features/settings/settings_danmaku_test.dart`：开关的位置、说明、默认关、改了是设置；搜索“按住”。
- `packages/live_store/test/danmaku_new_settings_test.dart`、`settings_defaults_test.dart`：默认关、跟备份、3.x 备份没有它时保持关。

## 真机验证（维护者在 K90 上做）

见 [record.md](record.md)“真机上要看的”。

## 风险和注意

- 和 A07.14、A08.9 改的是同一段手势代码：这次只加了 `Listener` 和拆出 `_flyingPoint`，单击、双击、长按的回调没动。
- 手指按住期间画面重排（例如双击切全屏）时，抬手事件仍送到按下时的那一层，`_unpin` 找当前的弹幕层放开。

## 环境和提交

- 本机工作区；提交信息以 `[D03.4]` 开头（英文）；不推 master；`bash tools/gate/gate.sh --all` 通过。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条做到没有；测试数量；改了哪些文件；新设置和翻译键；要在真机上看的。
