# D08.6 平台体验资源包的图标和资源跟上现在的平台：任务书

## 背景

- 来源：用户 2026-10-09 原话：“3.设置-本地用户与互动 平台资源体验包，没有同步更新图标和资源”。4.1.0（Y01.5）等这个修复再发布。
- 现象：设置 → 本地用户与互动 → 平台体验资源包：选择片和预览卡的徽章是 emoji 或两个字母（📺、🐟、YT、KG…），不是应用里别处用的平台图标；Kick 没有包（Kick 直播间用通用包）；只有 8 个平台有自己的币名、等级名和礼物，其余都是“本地体验币”和爱心、鲜花、火箭、城堡；主题色有的和平台图标不是一个颜色。直播间的互动面板、列表里的本地弹幕徽章、礼物横幅同样。
- 为什么现在做：第一档，4.1.0 等它。
- 已经做过的：A08.2（资源包界面，3.x 的 34 个包照搬）；D07.1～D07.7 和 V03.5（各平台的礼物体系、`LiveGiftUnit`、`superChatUnits`）；D08.1（`local_events.gift_id`）；D08.5（三档、座驾）。

## 目标和验收

1. `SiteIds.supported` 的每个平台都有资源包（补 Kick）。
2. 有平台图标的地方都画图标：设置页选择片和预览、互动面板的身份卡、列表里本地弹幕和礼物的徽章、礼物横幅、记录；emoji 只是后备（没有平台的旧消息、只能是文字的地方）。
3. 平台颜色只有一个来源，和图标一致。
4. 有礼物体系的平台按 V03.5 用自己的币名、等级名、徽章名和礼物（名字和本地币价格，说得通即可）。
5. 3.x 的礼物 id 一个不改（D08.1 的记录、D-018）；`giftById` 找得到所有礼物。
6. 新礼物有合理的档位（D08.5）和座驾。
7. 用户看得到的字都进 zh.json、en.json（按键排序、4 空格），不删键（D-024）。

## 现状（读代码得出）

- `apps/pure_live/lib/features/live_play/local_interaction/logic/local_catalog.dart`：`packs`（改之前 `:367-402`，34 个 `_pack(id, nameKey, accent, badge, [own])`）、`_platformGifts`（8 个平台）、`badgeKeyFor`（8 个平台的 switch）。
- 平台图标：`packages/live_ui/lib/src/icons/platform_logo.dart` 的 `PlatformLogos`、`PlatformLogo`（35 个，含 Kick、IPTV）；房间卡片 `packages/live_ui/lib/src/widgets/live_room_card.dart:283`、`:723`。
- 平台颜色：应用里只有资源包的 `accent`；`features/live_play/danmaku/gift_line.dart` 的 `giftPlatformInk` 读 `LocalCatalog.packFor(...).accent`。
- 徽章画在：`local_interaction_settings_page.dart`（选择片 `ChoiceChip.avatar` ~`:148-175`、`_PackPreview`）、`local_interaction_panel.dart`（`LocalIdentityCard`、`_GiftGrid`、`LocalHistory`）、`local_chat_line.dart`（徽章胶囊）、`local_gift_effect.dart`（横幅第二行）；徽章文字存在消息数据里（`LocalProfile.badge`）。
- 座驾：`local_interaction/effects/local_gift_vehicle.dart` 的 `_byGift`；档位 `logic/local_gift_tier.dart`。
- emoji 用自带的子集字体 `apps/pure_live/assets/fonts/emoji/NotoColorEmoji-Subset.ttf`（40 个，A08.2 K4）。

## 3.x 基线

- `v3.2.11:lib/modules/live_play/widgets/local_interaction/local_interaction_controller.dart:214-716`：34 个包、8 个平台的礼物和通用 4 个。要保留：礼物 id 和价格、8 个平台的币名和等级名、“送礼扣币、加同样多的经验”、记录的句子（`localInteraction.history`，D-018）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`、`docs/specs/UI.md`、`docs/DECISIONS.md`（D-001、D-003、D-018、D-040）。
2. D08 的 README、D08.1～D08.5 的 README、A08.2 的 README。
3. V03.5 第 2 节的表。

## 范围

- 可以改：`local_interaction/`（logic 和界面）、`gift_line.dart` 的颜色一行、`packages/live_ui` 的 `platform_logo.dart`、翻译文件、emoji 子集字体和 NOTICE、对应测试。
- 不能改：菜单和弹出层（A07.23 在改）、后台播放（另一个任务在改）；3.x 的设置键和礼物 id；版本号。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 每个平台一个包（补 Kick）；颜色一张表；各处徽章画图标（`LocalPackBadge`），旧消息照旧 | `local_catalog.dart`、`platform_logo.dart`、`gift_line.dart`、界面 5 个文件、`local_interaction.dart`（`LocalProfile.platform`） | 测试通过 |
| 2 | 19 个平台的币、等级、徽章、礼物；新大礼物的座驾；字体加 emoji；翻译 | `local_catalog.dart`、`local_gift_vehicle.dart`、字体、翻译 | 测试通过 |

## 测试

- 每个 `SiteIds` 平台有包；每个包画真实图标，emoji 只是后备；
- 3.x 的礼物 id 都找得到（`giftById`），价格不变；id 不重复；
- 新礼物的档位（小、中、大各一个）和座驾；emoji 都在字体里；
- 设置页选择片和预览，1 倍和 2 倍字；
- 互动面板竖屏和横屏；
- 旧礼物 id 的记录照样显示。

## 真机验证（维护者在 K90 上做）

见 record.md 的“真机上要看的”。

## 风险和注意

- 消息数据多了 `platform`：以前的消息没有，必须照旧显示 emoji 徽章。
- 礼物格一行 4 个：每个平台 3 个礼物不换行。
- 可能冲突的文件：`local_interaction_panel.dart`（A07.23 的菜单可能动“更多”菜单）、翻译文件。

## 环境和提交

- `source ~/tools/purelive-env.sh`；根目录先 `bash tools/ffmpeg_kit/fetch.sh android` 和 `linux`。
- 本机工作区；提交信息以 `[D08.6]` 开头（英文）；不推送、不合并。
- `python3 tools/docs/docs.py`、`owners.py`、`settings_audit.py` 和它们的 `--check`；`tools/gate/gate.sh --all`。

## 报告（中文，简洁）

每条做到没有；根因；每个平台改了什么；兼容；测试数量；改了哪些文件；真机上要看的；可能冲突的文件。
