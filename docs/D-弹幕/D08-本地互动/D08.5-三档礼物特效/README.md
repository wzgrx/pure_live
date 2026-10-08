# D08.5 三档礼物特效：小飘屏、横幅、大礼物座驾动效（参考 flame_barrage）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：[V03.6](../../../V-需求和反馈/V03-审查和调研/V03.6-弹幕系统和本地互动体验/README.md) 第 2.1 节（flame_barrage 一行）、第 2.2 节 P7、第 4 节 E9、第 5.5 节第二、三段（做法 A）；用户 2026-10-09 点名“特效”（D-040）
- 相关：依赖 [D08.4](../D08.4-本地礼物连击和数量/README.md)（横幅队列）；礼物横幅界面 [A08.2](../../../A-界面设计/A08-弹幕界面/A08.2-本地互动/README.md)（c9）；飞行弹幕 D03（不进弹幕层）；决定 D-018、D-040；规范 specs/UI.md 第 9.3 节；任务书 [brief.md](brief.md)

## 目标

本地礼物的特效按价格分三档：小礼物一条从右往左飞过画面上方的飘屏；中礼物现在的横幅；大礼物横幅 + 一段 2～3 秒的“座驾”动效（火箭、飞机、流星这类，纯 Canvas 画）。设置里的“礼物特效”从开关改成“全部 / 只要大礼物 / 关”。

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 特效 | 一种横幅（大礼物更大）、模糊光晕（`v3.2.11:lib/modules/live_play/pages/live_play_page.dart:47-92`） | 一种横幅、去掉了模糊（`local_interaction/local_gift_effect.dart:54-123`，A08.2 c9）；`data['effect']` 只有 `full`、`ticker`、`none`（`logic/local_interaction.dart` 的 `sendGift`） | 三档 |
| 设置 | `localInteraction.enableGiftEffects`（开关） | 同（`packages/live_store/lib/src/settings/settings.dart:1264`） | 键保留；新键存三选一 |
| 可借的 | — | flame_barrage 的八种座驾（`~/ref/flame_barrage/lib/src/effect/motion/`：`rocket_launch_effect.dart`、`airplane_effect.dart`、`meteor_streak_effect.dart`、`ufo_effect.dart`、`dragon_swim_effect.dart`、`horse_riding_effect.dart`、`ghost_drift_effect.dart`、`magic_carpet_effect.dart`，加 `barrage_fx_particle.dart`；9 个文件 1841 行，MIT），3.x 和上游都没接上 | 借其中 2～3 种的画法 |

## 方案（做法 A，D-003 维护者选 A）

- c1 分档按价格（不按平台）：小 < 100；中 100～999；大 ≥ 1000 或礼物标了 `big`（`LocalCatalog` 的常量）。
- c2 设置：新键 `localInteraction.giftEffectLevel`（`all`、`bigOnly`、`off`）；旧的 `localInteraction.enableGiftEffects` 不改不删（D-018）：新键没有值时按旧键读（开 = `all`、关 = `off`），改新键时同时写旧键（`off` → 关，其余 → 开），覆盖回 3.x 照样对。默认 = 现在的样子（`all`）。设置页的开关换成三选一。
- c3 小档飘屏：一行“🌶 Pure Live 送出 辣条 ×N”从右往左飞过画面上方（用本地弹幕已有的顶部轨道，`LiveMessagePlacement.top` 的滚动版，或在 `LocalGiftLayer` 里自己画一条），只在画面上。
- c4 大档座驾：横幅 + 2～3 秒的动效，借 flame_barrage `effect/motion/` 里火箭、飞机、流星三种的画法（重写成 `CustomPainter`，不引入 Flame；文件头保留 MIT 版权声明和来源提交），按礼物选（例如火箭礼物用火箭，其他大礼物轮流）。画在 `LocalGiftLayer` 自己那一层，不进弹幕层，不影响平台弹幕的帧时间。
- c5 规范：只用合成层动画和描边，不用模糊（UI.md 第 9.3 节）；系统要求减少动态时三档都只有横幅。
- c6 性能：K90 120 Hz 下 profile 构建量帧时间（大礼物动效期间界面线程和光栅线程 ≤ 8 毫秒/帧），数字记进 verify.md。

## 验证

- 见 brief.md。
