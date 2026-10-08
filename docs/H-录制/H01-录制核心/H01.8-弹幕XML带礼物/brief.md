# H01.8 录制的弹幕 XML 带礼物（新开关，默认关）：任务书

## 背景

- 来源：V03.5（`docs/V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md`）第 0 节第 2 条、第 4 节 F-3、第 6.7 节、第 7 节 H0x.x；用户 2026-10-09（D-040）。
- 现象：录制的弹幕 XML 只有聊天，没有礼物。
- 为什么现在做：第三档；小改动，等 E05.5 做完。
- 已经做过的：E05.5（`LiveGift`）——开工前确认已合并；H01.4（弹幕 XML 的真机验证）。

## 目标和验收

1. 新设置（建议键名 `recordDanmakuGifts`，默认关，跟备份和设备同步）；关着时 XML 和现在逐字一样。
2. 开着时礼物写成 `<gift ts="…" user="…" giftname="…" giftcount="…" price="…" unit="…"/>`，和 `<d>` 在同一个文件、按时间排；屏蔽的用户的礼物不写。
3. 设置行在录制设置里，文字走翻译，设置搜索能找到。

## 现状（读代码得出）

- `apps/pure_live/lib/app/recording.dart:53`（录制也用弹幕连接和过滤）、`:63`（只收 `chat`）。
- `packages/live_record/lib/src/chat.dart:321`（写入器只认 `chat`）。
- 录制设置在 `packages/live_store/lib/src/settings/settings.dart` 的录制一节；设置页见 A10、H03 的 README。

## 3.x 基线

- `git show v3.2.11` 的录制弹幕只写聊天。要保留：`<d>` 的格式和时间算法。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`。
2. `docs/specs/ENGINEERING.md`。
3. 本文件夹 `README.md`；E05.5 的 README；`docs/H-录制/H01-录制核心/README.md`。

## 范围

- 可以改：`recording.dart`、`packages/live_record/lib/src/chat.dart`；录制设置页的一行；`settings.dart`（登记 `Settings.all`、`settings_defaults_test.dart`、`tools/docs/settings_audit_notes.py`）；`docs/inventory/OWNERS.toml`；翻译文件；对应测试。
- 不能改：`<d>` 的格式；录制的其他行为；版本号。

## 方案和阶段

规模小，不分阶段：c1 设置 → c2 录制接收礼物 → c3 写 `<gift>` → 测试。

## 测试

- `packages/live_record/test/`：开关关时输出和改之前逐字一样（用现有的用例）；开时有 `<gift>`、转义、时间偏移；连击只写最终一条（有合并时）。
- `apps/pure_live/test/`：录制接礼物、屏蔽的用户不写。
- `packages/live_store/test/`：默认关、备份往返。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 默认设置录 1 分钟热门直播间 | XML 只有 `<d>` |
| 2. 打开开关再录 | XML 里有 `<gift>`，名称、数量对 |

## 风险和注意

- 礼物多时文件变大：免费礼物照 D07.1 的限速，录制也只写合并后的。

## 环境和提交

- `source ~/tools/purelive-env.sh`；各包测试；推送前 `bash tools/gate/gate.sh --all`。
- 分支 `ai/H01.8`；提交信息以 `[H01.8]` 开头（英文）；不推 master。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条做到没有；新设置和翻译键；测试数量；改了哪些文件。
