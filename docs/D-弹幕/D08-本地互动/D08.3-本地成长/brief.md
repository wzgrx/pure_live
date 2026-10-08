# D08.3 本地成长：观看时长、签到、等级进度：任务书

## 背景

- 来源：V03.6（`docs/V-需求和反馈/V03-审查和调研/V03.6-弹幕系统和本地互动体验/README.md`）第 2.2 节 P5、第 4 节 E7（乙档）、第 5.4 节做法 A；用户 2026-10-09（D-040）。
- 现象：体验币点按钮就能免费加，经验只来自送礼，等级没有“离下一级还差多少”，没有养成感。
- 为什么现在做：第二档；用户点名。
- 已经做过的：D08.1（记录，记“升级”）——开工前确认已合并。

## 目标和验收

1. 新开关“本地成长”（`localInteraction.growthEnabled`，默认开）；关掉时经验和币的规则和 3.x 一样（只有送礼加经验、按钮加币）。
2. 开着时：播放中每满 10 分钟 +10 经验 +20 币（每天最多 300 经验）；每天第一次进直播间 +20 经验 +100 币；发本地弹幕 +1 经验（每天最多 50）。
3. 等级公式不变（经验 ÷ 500 + 1）；身份卡有进度条和“还差 N 经验到 Lv.M”；每 10 级一个段名（翻译文件）。
4. 升级时短提示“升到 Lv.N”，并在记录里写一条 `level`。
5. “+500/+2000/+10000”还在（身份卡的“更多”里）。
6. 退到后台不计时；离开直播间结算；每天的计数跨日清零。
7. 规则数字是 `LocalCatalog` 的常量，有单元测试。

## 现状（读代码得出）

- `apps/pure_live/lib/features/live_play/local_interaction/logic/local_interaction.dart`：`recharge`（`:219`）、`sendGift`（加经验）、`statusLine`、`level`。
- `logic/local_catalog.dart`：等级（`:582`）。
- `logic/local_room_session.dart`：每个直播间一个会话，有 `room`（`LiveRoomController`，知道播放状态）。
- 身份卡 `local_interaction/local_interaction_panel.dart` 的 `LocalIdentityCard`（`:151`、`:205-211`）、`LocalRechargeRow`（`:322`）。
- 设置 `packages/live_store/lib/src/settings/settings.dart`：`localInteraction.coins`（`:1278`）、`localInteraction.experience`（`:1286`）。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/widgets/local_interaction/local_interaction_controller.dart`：币 1000 起（`:94`）、加币（`:724`）、送礼加经验（`:832-836`）、等级（`:876-884`）。要保留：公式、按钮、键名（D-001、D-018）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 3 节。
3. 本文件夹 `README.md`；D08.1 的 README；`docs/A-界面设计/A08-弹幕界面/A08.2-本地互动/README.md`。

## 范围

- 可以改：`local_interaction/logic/`；`local_interaction_panel.dart`（身份卡、加币按钮的位置）、设置页（开关）；`settings.dart`（新设置）、`settings_catalog.dart`；翻译文件；对应测试；A08.2 README 补一条。
- 不能改：等级公式；3.x 键的含义；播放器；版本号。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 规则常量、开关、计时（观看、签到、发弹幕、每天上限） | logic、设置 | 规则和计时的单元测试通过 |
| 2 | 身份卡进度条、段名、升级提示和记录、加币按钮进“更多” | 面板、设置页 | 界面测试通过 |

## 测试

- 单元测试（假时钟，D-017）：播放 10 分钟加一次、暂停不计、后台不计；每天 300 上限；签到一天一次、跨日清零；发弹幕 50 上限；关掉开关后只有送礼加经验。
- `local_interaction_test.dart`：进度条文字；段名；升级提示；“更多”里的三个按钮照旧加币。
- `packages/live_store/test/`：新设置默认、备份往返。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 今天第一次进直播间 | 币 +100、经验 +20（身份卡看得到） |
| 2. 播放 10 分钟 | 经验 +10、币 +20 |
| 3. 退到后台 10 分钟 | 不加 |
| 4. 关掉“本地成长” | 只有送礼加经验 |

## 风险和注意

- 计时器每分钟一次，不要每秒；离开直播间时取消。
- 时区和跨日：用本机日期，测试覆盖 23:59 → 00:00。

## 环境和提交

- `source ~/tools/purelive-env.sh`；`apps/pure_live` 全部 `flutter test`；推送前 `bash tools/gate/gate.sh --all`。
- 分支 `ai/D08.3`；每个阶段一次提交，信息以 `[D08.3]` 开头（英文）；不推 master。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条做到没有；规则常量；新设置和翻译键；测试数量；改了哪些文件；真机上要看的。
