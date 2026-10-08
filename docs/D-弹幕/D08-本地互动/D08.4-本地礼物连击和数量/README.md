# D08.4 本地礼物连击、数量和横幅队列

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：[V03.6](../../../V-需求和反馈/V03-审查和调研/V03.6-弹幕系统和本地互动体验/README.md) 第 2.2 节 P6、第 4 节 E8、第 5.5 节第一段（做法 A）；用户 2026-10-09 点名“本地礼物和特效”（D-040）
- 相关：记录合并依赖 [D08.1](../D08.1-结构化的本地历史/README.md)；后续 [D08.5](../D08.5-三档礼物特效/README.md)（三档特效用这里的队列）；平台礼物的连击规则 [D07.1](../../D07-礼物和付费消息/D07.1-礼物过滤连击合并和限速/README.md)（参考，不共用代码）；礼物横幅界面 [A08.2](../../../A-界面设计/A08-弹幕界面/A08.2-本地互动/README.md)（c9）；flame_barrage `ComboAnimation`（MIT）；任务书 [brief.md](brief.md)

## 目标

本地礼物像平台礼物一样能连击、能一次送多个：3 秒内再点同一个礼物，横幅上的数字跳成 ×2、×3…，聊天列表合成一行、记录也是一条；长按礼物选数量（1、10、66、520）；不同礼物排队，一个横幅播完再下一个，不再互相顶掉。

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 数量 | 一次 1 个 | 同：`sendGift` 的 `count: 1`、文字“×1”（`features/live_play/local_interaction/logic/local_interaction.dart`） | 1、10、66、520 |
| 连击 | 没有 | 没有；快速连点每次一行、一条记录 | 3 秒内同一礼物合并 |
| 横幅 | 3 秒，新的顶掉旧的（`v3.2.11:lib/modules/live_play/controllers/live_play_controller.dart:594-598`） | 同：`LocalRoomSession.sendGift` 里 `_effectTimer?.cancel()` 后换成新的（`logic/local_room_session.dart`） | 同一礼物连击改数字；不同礼物排队（最多 5 个） |
| 横幅层 | 整页重建 | `LocalGiftLayer`（`local_interaction/local_gift_effect.dart:13`），画面上单独一层 | 不变 |

## 方案（做法 A，D-003 维护者选 A）

- c1 连击：`LocalRoomSession` 记最后一次送的礼物和时间；**3 秒**内再送同一个礼物 → 不新开横幅，`LocalGiftShow` 的数量加上去，横幅计时重新开始 3 秒；聊天列表里那一行改数量（本地行，用 `ChatFeed` 替换一行的方法——D07.1 会加；没合并时在本任务里加，两边用同一个方法）；D08.1 的记录合成一条（`count` 累加）。每次仍然扣币、加经验。
- c2 数字跳动：“×N”放大到 1.8 倍再回缩（借 flame_barrage `lib/src/animation/combo_animation.dart` 的做法，只借画法、保留 MIT 版权声明；用 Flutter 的隐式动画实现，不引入 Flame）；系统要求减少动态时不跳。
- c3 数量：长按礼物格弹出贴着它的小菜单（A07 的小菜单样子）：1、10、66、520，余额不够的变灰；选了就一次送这么多（扣 `价格 × 数量`）。
- c4 队列：不同礼物的横幅排队，最多 5 个，超出的只进列表不出横幅；一个播完（3 秒）播下一个。
- 不做：特效分档（D08.5）。

## 验证

- 见 brief.md。
