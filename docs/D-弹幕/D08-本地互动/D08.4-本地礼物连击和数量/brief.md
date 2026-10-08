# D08.4 本地礼物连击、数量和横幅队列：任务书

## 背景

- 来源：V03.6（`docs/V-需求和反馈/V03-审查和调研/V03.6-弹幕系统和本地互动体验/README.md`）第 2.2 节 P6、第 4 节 E8（乙档）、第 5.5 节第一段做法 A；用户 2026-10-09（D-040）。
- 现象：本地礼物一次只能送 1 个；快速连点每次一行，横幅只看到最后一条（新的直接顶掉旧的）。
- 为什么现在做：第二档；用户点名“礼物和特效”。
- 已经做过的：A08.2（礼物格、横幅 `LocalGiftLayer`）；D08.1（记录）——记录合并要它，没合并时只合并列表和横幅。

## 目标和验收

1. 3 秒内再送同一个礼物：横幅不换新的，“×N”加上去并跳一下（减少动态时不跳），计时重新 3 秒；聊天列表只有一行、数字更新；记录一条（D08.1 合并后）。
2. 每次仍然扣币、加经验；余额不够照旧提示“体验币余额不足”。
3. 长按礼物格：小菜单 1、10、66、520，余额不够的变灰；选了一次送这么多。
4. 不同礼物排队，最多 5 个，播完一个下一个；超出的只进列表。
5. 横幅层不重建直播间（`LocalGiftLayer` 单独一层）。
6. 借的代码保留 MIT 版权声明。

## 现状（读代码得出）

- `apps/pure_live/lib/features/live_play/local_interaction/logic/local_room_session.dart`：`LocalGiftShow`（`:13`）、`sendGift`（`_effectTimer?.cancel()` 后 `giftEffect.value = LocalGiftShow(message, ++_serial)`，3 秒后清空）、`effectDuration`。
- `logic/local_interaction.dart` 的 `sendGift`（`count: 1`、文字“×1”、`data` 带 `giftId`、`price`、`count`、`big`、`effect`）。
- `local_interaction/local_gift_effect.dart`：`LocalGiftLayer`（`:13`）、`LocalGiftBanner`（`:54`，进场 420 毫秒）。
- 礼物格 `local_interaction_panel.dart`（`:225`、`:263`）。
- 列表的本地行 `local_interaction/local_chat_line.dart`；`ChatFeed`（`features/live_play/danmaku/chat_feed.dart`）。
- 参考：`~/ref/flame_barrage/lib/src/animation/combo_animation.dart`（“×N”放大到 1.8 倍再回 1，0.8 秒后淡出）。

## 3.x 基线

- 3.x 横幅 3 秒、新的顶掉旧的（`git show v3.2.11:lib/modules/live_play/controllers/live_play_controller.dart` 的 `:594-598`）。要保留：横幅 3 秒、大礼物更大；送礼扣币加经验。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 9 节借代码）。
2. `docs/specs/UI.md` 第 9.3 节（动画）。
3. 本文件夹 `README.md`；D08.1、A08.2 的 README。

## 范围

- 可以改：`local_interaction/logic/`；`local_gift_effect.dart`、`local_interaction_panel.dart`（礼物格的长按）、`local_chat_line.dart`；`chat_feed.dart`（只加替换一行，和 D07.1 用同一个方法）；翻译文件；对应测试。
- 不能改：平台礼物（D07）；弹幕层；3.x 键；版本号。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 连击（横幅、列表、记录）、c2 数字跳动 | logic、`local_gift_effect.dart`、`local_chat_line.dart`、`chat_feed.dart` | 测试通过 |
| 2 | c3 长按选数量、c4 队列 | 礼物格、logic | 测试通过 |

## 测试

- `apps/pure_live/test/features/live_play/local_interaction_test.dart`（假时钟，间隔用秒）：3 秒内两次同一礼物 → 一个横幅 ×2、列表一行、币扣两次；第 4 秒再送 → 新横幅；减少动态时没有缩放动画；长按菜单的四档和变灰；送 10 个扣 10 倍；三种礼物排队依次播；第 6 个不出横幅。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 互动面板快速连点同一个礼物 5 下 | 一个横幅 ×5、数字跳；列表一行 |
| 2. 长按一个礼物，选 66 | 一次扣 66 份 |
| 3. 连点三种不同礼物 | 横幅依次播 |

## 风险和注意

- `ChatFeed` 的替换方法和 D07.1 共用：先做的那个加，后做的复用，不要加两份。
- 连击和 D08.1 的记录合并：没有 D08.1 时只合并列表和横幅。

## 环境和提交

- `source ~/tools/purelive-env.sh`；`apps/pure_live` 全部 `flutter test`；推送前 `bash tools/gate/gate.sh --all`。
- 分支 `ai/D08.4`；每个阶段一次提交，信息以 `[D08.4]` 开头（英文）；不推 master。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条做到没有；借了哪些代码（来源和许可证）；测试数量；改了哪些文件；真机上要看的。
