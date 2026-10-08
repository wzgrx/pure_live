# D07.2 醒目留言的平台表和价格单位；舰长、会员进醒目留言；六间房飞屏：任务书

## 背景

- 来源：V03.5（`docs/V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md`）第 0 节第 6 条、第 4 节 F-6、F-7、第 6.5、6.6 节、第 7 节 D07.2；用户 2026-10-09（D-040）。
- 现象：CHZZK、YouTube 等 7 个平台明明有醒目留言，醒目留言页空着时却写“这个平台没有醒目留言”；价格一律 `￥`；上舰、开会员只是一行通知，付费飞屏是普通聊天。
- 为什么现在做：第二档；小改动，影响 10 个平台。
- 已经做过的：E05.5（`LiveGift.kind`、`LiveGiftUnit`）——开工前确认已合并。

## 目标和验收

1. `superChatPlatforms` 有 10 个平台；这 7 个平台的醒目留言页空状态不再说“没有醒目留言”。
2. 价格文字按单位（人民币“N 元”、金瓜子、钻石、红豆、Bits、Kicks、치즈、coins、六币…），有平台文字时用平台文字。
3. 新设置 `superChatIncludesMembership`（默认开）：开着时哔哩哔哩上舰、YouTube 会员、Twitch 订阅和送订阅、CHZZK 订阅和送订阅在醒目留言页各一张卡；关掉时和现在一样。
4. CHZZK 订阅（`messageTypeCode` 11）是通知行，不再是普通聊天。
5. 六间房飞屏（108）是醒目留言。
6. 用户看得到的文字走翻译（zh、en，按键名排序）。

## 现状（读代码得出）

- `packages/live_core/lib/src/live_site.dart:60-73`：`hasSuperChats`、`superChatPlatforms`。
- `apps/pure_live/lib/features/live_play/danmaku/chat_list.dart:690-700`（醒目留言行）、`:917-919`（`superChatPrice`）；醒目留言页 `features/live_play/danmaku/super_chats.dart`。
- `room_controller.dart:1134-1138`（`superChat` 分支）、`:1145-1147`（通知）、`:1148-1151`（礼物）。
- 平台：`bilibili.dart:784`（`_guard`）、`:835`（`_superChat`）；`youtube.dart:593`（Super Chat，`price` 0）、`:650`（会员）；`twitch.dart:170`、`:285`（订阅通知）；`chzzk.dart:375`（订阅当聊天）、`:426`（后援）、`:464`（送订阅）；`sixroom.dart:369`（飞屏）。样本：`fixtures/chzzk/danmaku/`（订阅 1 条、送订阅 2 条）、`fixtures/twitch/danmaku/`（`sub` 6、`subgift` 3、`submysterygift` 3）、`fixtures/youtube/danmaku/`（会员 11）、`fixtures/sixroom/danmaku/`。
- 设置组件 `apps/pure_live/lib/shared/danmaku/chat_list_settings.dart:68-74`（`showChatGifts` 一行）。

## 3.x 基线

- 3.x 醒目留言只有哔哩哔哩、斗鱼、虎牙（`v3.2.11:lib/core/danmaku/bilibili_danmaku.dart:415`、`douyu_danmaku.dart:146-148`、`huya_danmaku.dart:252`），价格 `￥`。要保留：这三个平台的醒目留言照旧；醒目留言卡片的样子和到点移除。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 3 节。
3. 本文件夹 `README.md`；`docs/A-界面设计/A08-弹幕界面/A08.1-弹幕列表和弹幕设置页/README.md`（醒目留言卡片）。

## 范围

- 可以改：`live_site.dart`；`live_core` 加价格文字的辅助函数；`chat_list.dart` 的 `superChatPrice`；`room_controller.dart` 的醒目留言、通知、礼物分支；`chat_list_settings.dart`、`features/settings/settings_catalog.dart`（搜索条目）；`packages/live_store/lib/src/settings/settings.dart`（新设置，登记到 `Settings.all`、`settings_defaults_test.dart`、`tools/docs/settings_audit_notes.py`）；`chzzk.dart`、`sixroom.dart`、`youtube.dart` 的相关解析；翻译文件；`docs/inventory/OWNERS.toml`（新设置的归属写 D07）；对应测试。
- 不能改：醒目留言卡片和醒目留言页的布局；3.x 的设置键；版本号。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 平台表、c2 价格按单位 | `live_site.dart`、`live_core` 辅助函数、`chat_list.dart` | 7 个平台空状态的测试、价格文字的测试 |
| 2 | c3 上舰和会员进醒目留言（新设置）、c4 设置行、c5 六间房飞屏、CHZZK 订阅改通知 | 见“范围” | 设置、控制器、平台的测试通过 |

## 测试

- `packages/live_core/test/live_site_test.dart`：10 个平台 `hasSuperChats`。
- 价格文字：人民币分、金瓜子、钻石、Bits、平台文字优先、YouTube 只有文字。
- `packages/live_danmaku/test/sites/`：CHZZK 11 是通知、六间房 108 是醒目留言（用样本）。
- `apps/pure_live/test/features/live_play/`：开关开时上舰进醒目留言页、关时不进；列表里的行两种情况一样；`live_play_tabs_test.dart` 设置行的位置。
- `packages/live_store/test/`：新设置默认开、备份往返、3.x 备份不带它。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. CHZZK 或 YouTube 直播间，醒目留言标签 | 空着时是“还没有醒目留言”一类，不是“平台没有” |
| 2. 有醒目留言时 | 价格是平台的单位 |
| 3. 哔哩哔哩（登录）有人上舰 | 醒目留言页一张卡；关掉开关后不再出卡 |
| 4. 六间房有飞屏 | 是醒目留言 |

## 风险和注意

- 醒目留言页空状态的文字可能还有别的分支用 `hasSuperChats`（例如电视、多画面），全部找出来一起看。
- 新设置默认开是 D-040 允许的例外，README 写清了理由；不要把列表里的行也改掉。

## 环境和提交

- `source ~/tools/purelive-env.sh`；各包 format、analyze、test；`apps/pure_live` 全部 `flutter test`；`python3 tools/docs/docs.py --check`、`python3 tools/docs/owners.py --check`；推送前 `bash tools/gate/gate.sh --all`。
- 分支 `ai/D07.2`；提交信息以 `[D07.2]` 开头（英文）；不推 master。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条做到没有；新设置和翻译键；测试数量；改了哪些文件；真机上要看的。
