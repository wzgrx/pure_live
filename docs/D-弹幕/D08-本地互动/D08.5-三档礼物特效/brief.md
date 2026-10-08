# D08.5 三档礼物特效：小飘屏、横幅、大礼物座驾动效：任务书

## 背景

- 来源：V03.6（`docs/V-需求和反馈/V03-审查和调研/V03.6-弹幕系统和本地互动体验/README.md`）第 2.1、2.2 节 P7、第 4 节 E9（乙档）、第 5.5 节第二、三段做法 A；用户 2026-10-09（D-040）。
- 现象：本地礼物的特效只有一种横幅（大礼物大一点），没有飘屏、没有全屏特效。
- 为什么现在做：第二档；用户点名“特效”。
- 已经做过的：A08.2 c9（横幅单独一层、去掉模糊）；D08.4（横幅队列）——开工前确认已合并。

## 目标和验收

1. 三档：小（< 100）飘屏；中（100～999）现在的横幅；大（≥ 1000 或 `big`）横幅 + 2～3 秒座驾动效。
2. 新设置 `localInteraction.giftEffectLevel`（`all`、`bigOnly`、`off`，默认 `all`）；旧键 `localInteraction.enableGiftEffects` 照读照写（没有新值时按旧值；改新值同时写旧值）；设置页的开关换成三选一。
3. 座驾动效借 flame_barrage 的 2～3 种（火箭、飞机、流星），重写成 `CustomPainter`，文件头保留 MIT 版权声明和来源；不引入 Flame。
4. 只画在 `LocalGiftLayer`，不进弹幕层；不用模糊；减少动态时只有横幅。
5. K90 profile 构建：大礼物动效期间界面线程、光栅线程 ≤ 8 毫秒/帧（120 Hz），记进 verify.md。
6. 文字走翻译。

## 现状（读代码得出）

- `apps/pure_live/lib/features/live_play/local_interaction/local_gift_effect.dart`：`LocalGiftLayer`（`:13`）、`LocalGiftBanner`（`:54-123`）；画面上的位置 `features/live_play/player/player_view.dart`（V03.6 写 `:829`）。
- `logic/local_interaction.dart` 的 `sendGift`：`data['effect']` = `full` / `ticker` / `none`、`big`。
- 设置 `packages/live_store/lib/src/settings/settings.dart:1264`（`localInteraction.enableGiftEffects`）；设置页 `local_interaction/local_interaction_settings_page.dart` 的“画面上”一组。
- 参考 `~/ref/flame_barrage/lib/src/effect/motion/`（见 README 的表）。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/pages/live_play_page.dart` 的 `:47-92`：一种横幅。要保留：`enableGiftEffects` 的键和含义（D-018）、横幅 3 秒。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 9 节借代码的许可证）。
2. `docs/specs/UI.md` 第 9.3 节；`docs/specs/ENGINEERING.md` 第 5 节（上游清单和许可证）。
3. 本文件夹 `README.md`；D08.4、A08.2 的 README。

## 范围

- 可以改：`local_gift_effect.dart`（和新的动效文件，放 `local_interaction/effects/`）；`local_interaction/logic/`；设置页的一行；`settings.dart`（新设置）、`settings_catalog.dart`、`tools/docs/settings_audit_notes.py`；翻译文件；对应测试；A08.2 README 补一条。
- 不能改：弹幕层（`danmaku_overlay.dart`）；平台礼物；3.x 键的含义；不加依赖（不引入 Flame）；版本号。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 分档、c2 设置三选一（新旧键兼容） | logic、设置、设置页 | 测试通过 |
| 2 | c3 小档飘屏 | `local_gift_effect.dart` | 测试通过 |
| 3 | c4 座驾动效、c5 减少动态、c6 K90 帧时间 | `effects/`、`local_gift_effect.dart` | 测试通过；verify.md 有帧时间 |

## 测试

- `local_interaction_test.dart`：三档各送一个，看到对应的组件；`bigOnly` 时小、中只进列表；`off` 时什么都没有；减少动态时只有横幅。
- `packages/live_store/test/`：新键没有值时按旧键；改新键同时写旧键；3.x 备份导入后的值。
- 座驾 painter 的测试：能画、不抛异常（`paint` 到假画布）；动画结束后层清空。
- 定时器至少 1 秒；动画测试用 `pump` 推进时间。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 送一个小礼物 | 画面上方一条飘屏 |
| 2. 送一个大礼物 | 横幅 + 座驾动效 2～3 秒，平台弹幕不卡 |
| 3. 设置改成“只要大礼物”“关” | 照着变 |
| 4. 系统打开“移除动画” | 只有横幅 |
| 5. profile 构建量帧时间 | ≤ 8 毫秒/帧 |

## 风险和注意

- 粒子数量控制住（每个动效几十个以内），不要每帧分配对象。
- 借代码：只借画法，许可证声明放文件头；不要复制 flame_barrage 的引擎类。

## 环境和提交

- `source ~/tools/purelive-env.sh`；`apps/pure_live` 全部 `flutter test`；推送前 `bash tools/gate/gate.sh --all`；profile 构建在门禁不跑的时候做。
- 分支 `ai/D08.5`；每个阶段一次提交，信息以 `[D08.5]` 开头（英文）；不推 master。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条做到没有；借了哪些文件（来源、提交、许可证）；新设置和翻译键；帧时间；测试数量；改了哪些文件；真机上要看的。
