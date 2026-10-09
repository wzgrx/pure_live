# D08 本地互动

“本地互动体验”的数据和规则：只有自己看得到的本地弹幕和本地礼物、体验币和经验、等级、身份和资源包、本地记录、常用语、本地礼物的连击和特效规则。界面（输入框、互动面板、样式页、礼物横幅、设置页）仍归 [A08](../../A-界面设计/A08-弹幕界面/README.md)（A08.2）。这个子分类是 2026-10-09 按 [V03.6](../../V-需求和反馈/V03-审查和调研/V03.6-弹幕系统和本地互动体验/README.md) 第 5.7 节（E20、P14）新开的（D-040）：以前本地互动的逻辑只在 A08 的“已知问题”里写着“没有功能子分类”。

## 范围

- 包括：
  - `apps/pure_live/lib/features/live_play/local_interaction/logic/`：`local_interaction.dart`（`LocalInteraction`，29 个 3.x `localInteraction.*` 设置上的一层：资料、币、经验、记录、样式）、`local_catalog.dart`（`LocalCatalog`：6 个样式模板、颜色、34 个平台资源包、8 个平台各 3 个礼物和通用 4 个、等级规则）、`local_room_session.dart`（每个直播间一个 `LocalRoomSession`：发弹幕、送礼、礼物横幅的计时）。
  - 本地消息进直播间的入口：`features/live_play/logic/room_controller.dart` 的 `addLocal`（`:1159`，和 D04 共用这个文件）。
  - `localInteraction.*` 一组设置的含义、默认值、迁移（`packages/live_store/lib/src/settings/settings.dart` 的 `localInteraction` 一节，键名不变，D-018），以及以后新加的本地记录表（D08.1）。
- 不包括（归哪里）：
  - 本地互动的全部界面（`local_interaction/` 下 `logic/` 以外的文件）、它们的样子和点按 → [A08](../../A-界面设计/A08-弹幕界面/README.md)。D08 的任务要改界面时，照 A08.2 的设计改，并在 A08.2 的 README 补一条。
  - 本地弹幕在画面上怎么飞（`danmaku_overlay.dart` 的本地分支 `_placeLocal`）→ [D03](../D03-飞行弹幕引擎/README.md)；本地弹幕进聊天列表以后的数据流 → [D04](../D04-数据流和性能/README.md)。
  - 平台礼物（平台推送的、别人送的）→ [D07](../D07-礼物和付费消息/README.md)；长按弹幕面板的“+1（本地）”→ A08.14（用的是本子分类的 `LocalRoomSession.sendChat`）。
  - 备份和设备同步的框架 → J03、J05（D08 的新数据要接进去）。

## 现状：做到哪、怎么工作的

（2026-10-09，读 V03.6 第 1、2 节，代码 master `87dd63729`；行号开工前按名字再核一次。）

- 用户看得到的（V03.6 第 1.1 节 L1～L12）：总开关默认开；三处输入框（竖屏和宽屏列表下面、全屏下栏、互动面板）发出立即进列表、飞过；6 个样式模板 + 自定义；互动面板（身份卡、发送框、礼物中心、加体验币、我的资料、画面上、记录）；点一下送 1 个礼物，扣币、加同样多的经验、写一条记录；礼物横幅 3 秒（新的顶掉旧的）；体验币默认 1000、按钮免费加；等级 = 经验 ÷ 500 + 1；记录最多 30 条，存成拼好的中文句子。
- 内部：

```text
LocalInteraction（logic/local_interaction.dart:113，写入先显示后落库）
  └ 每个直播间一个 LocalRoomSession（logic/local_room_session.dart:32，live_play_page.dart 建，经 LocalRoomScope 找到）
       sendChat（:72）→ interaction.createChat → _deliver → room.addLocal(message, fly: showAsDanmaku)
       sendGift（:80）→ interaction.sendGift（扣币、加经验、写一行记录，count 恒为 1）→ _deliver
                       → effect 时 giftEffect = LocalGiftShow，Timer 3 秒后清掉（新礼物直接顶掉）
LiveRoomController.addLocal（room_controller.dart:1159）：进 ChatFeed，要飞时进 flying 流，立即 flush；不过过滤链
```

- 和 3.x 比（V03.6 第 2.1 节）：功能一项不少，键名、默认值、规则一样；4.x 修了发出要等 2 秒、不进备份、礼物行重复名字。上游 v3.2.11 之后没有新的本地互动功能。
- 完成度：A08.2 登记“完成”，但**整个本地互动没有 K90 结果**（CHECKLIST 第 2 节第 8 条为空，V03.6 P1），排在 S02.6 阶段 4。

## 代码地图

| 文件 | 职责 |
|---|---|
| `features/live_play/local_interaction/logic/local_interaction.dart`（419） | `LocalProfile`（`:12`）、`LocalGiftData`（`:73`）、`LocalInteraction`（`:113`）：`recharge`（`:219`）、`clearHistory`（`:228`）、`createChat`、`sendGift`（扣币、加经验、记录）、`setStyle`（`:365`）、`applyPreset`（`:369`，整套覆盖自定义） |
| `features/live_play/local_interaction/logic/local_catalog.dart`（606） | 样式模板（`:156-225`）、颜色（`:239-252`）、资源包和礼物（`:276-557`）、等级（`:582`）、字体映射（`:593-598`）、`historyLimit` 30 |
| `features/live_play/local_interaction/logic/local_room_session.dart`（112） | `LocalGiftShow`（`:13`）、`LocalRoomSession`（`:32`）：`sendChat`、`sendGift`、`_deliver`（`:97`）、`effectDuration` 3 秒 |
| `features/live_play/logic/room_controller.dart` | `addLocal`（`:1159`） |
| `packages/live_store/lib/src/settings/settings.dart` | `localInteraction.*` 29 个键（`localInteraction.enabled` `:1221` 起，记录 `localInteraction.history` `:1294`，样式 18 个 `:1301-1438`） |
| `packages/live_store/lib/src/local_events.dart` | D08.1：`local_events` 表（`schemaVersion` 2）的 `LocalEvent`、`LocalEventStore`（最多 2000 条、旧记录只转一次、进房放回的查询、备份一节 `localEvents`）；新设置 `localInteraction.replayOnEnter`（默认开，D-040） |
| `packages/live_store/lib/src/settings/settings.dart` 的 `localInteractionPhrases` | D08.2：常用语，一个列表设置（最多 20 条，`StringListSetting` 的 `maxItems`、`tidy`），默认空，随设置进备份和设备同步；`LocalInteraction` 的 `phrases`、`addPhrase`…`movePhrase`、`recentChats`（最近 5 条取自 `local_events`），每条 40 字（`LocalCatalog.clipDanmaku`） |

测试：`local_history_test.dart`（D08.1）、`local_plus_one_test.dart`（A08.14）、`local_phrases_test.dart`（D08.2，21 个）和 `packages/live_store/test/local_phrases_test.dart`；`apps/pure_live/test/features/live_play/local_interaction_test.dart`（15 个：资料库、3.x 键和默认值、送礼扣币、记录 30 条、样式、各处输入框、面板、横幅 3 秒）；`packages/live_store/test/migration_test.dart`、`backup_test.dart`、`settings_defaults_test.dart`（键和迁移）。

## 3.x 基线

- `v3.2.11:lib/modules/live_play/widgets/local_interaction/local_interaction_controller.dart`（911 行）：设置键和默认值（`:86-114`）、模板和颜色（`:116-212`）、资源包和礼物（`:214-716`）、币和经验（`:94`、`:724`、`:832-836`、`:876-884`）、记录 30 条（`:905-910`）；礼物横幅 `pages/live_play_page.dart:47-92`。
- 必须保留：29 个键名和含义（D-018）；等级 = 经验 ÷ 500 + 1；“+500/+2000/+10000”按钮（D-001）；送礼扣币、加同样多的经验。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 整个本地互动没有 K90 结果（P1） | CHECKLIST 第 2 节第 8 条 | 登记“完成”但没人用过一遍 | S02.6 阶段 4（V03.6 E1） |
| 记录存拼好的句子、本地弹幕不进记录、离开直播间就没了（P2、P3） | `local_interaction.dart:223`、`:275-277`；`addLocal` 只进 `ChatFeed` | 换语言后旧记录还是旧语言；没有“我发过的话” | D08.1（2026-10-09 代码做完，待真机） |
| 每次都要重打常说的话 | — | 手机上打字慢 | D08.2（2026-10-09 代码做完，待真机：输入框上方的最近发过和常用语、存为常用语、设置页管理） |
| 币和经验没有意义（P5） | `local_interaction.dart:218-225` | 没有养成感 | D08.3 |
| 礼物一次 1 个、横幅互相顶掉（P6） | `local_interaction.dart` `count: 1`；`local_room_session.dart` 的 `sendGift` | 快速连点只看到最后一条横幅 | D08.4 |
| 特效只有一种横幅（P7） | `local_gift_effect.dart:54-123` | 用户点名要加强 | D08.5 |
| 清空记录没有撤销、星形两种意思、输入框不限长、粗体丢字重、本地弹幕的“屏蔽关键词”不起作用（P4、P8、P9、P12、P16、P17） | 见 V03.6 第 2.2 节 | 小毛病 | A08.13（V03.6 E2，另一个任务） |
| 自定义样式存不下、本地弹幕用不了下载的字体、画面上认不出自己的（P10、P11、P18） | `local_interaction.dart:365-388`、`local_catalog.dart:593-598` | — | 没登记（V03.6 E10，留在报告里，D-040） |
| 只有 8 个平台有自己的本地礼物（P13） | `local_catalog.dart:361-557` | — | 没登记（V03.6 E14，等 D07 的平台礼物做完再看） |

## 相关决定和规范

- D-040：V03.6 甲、乙两档同意做；新设置默认保持现在的样子，任务书写明的例外：D08.1“进房放回本地弹幕”、D08.3“本地成长”默认开。
- D-001（3.x 功能不少）、D-018（键名不改、新设置只加）、D-017（定时器至少 1 秒）、D-036（新设置让老用户感觉不到变化的原则）。
- [specs/UI.md](../../specs/UI.md) 第 7 节（删除类操作要确认或给 4 秒撤销）、第 9.3 节（弹幕和特效不用模糊阴影）。
- 借 flame_barrage（MIT）的代码时保留版权声明（PROCESS 第 9 节）。

## 测试和验证

- 自动：`cd apps/pure_live && flutter test test/features/live_play/local_interaction_test.dart`；存储改动跑 `packages/live_store` 的测试。缺：规则（币、经验、等级）和计时没有单独的单元测试，D08.3 补。
- 真机：S02.6 阶段 4 先把现在的本地互动走一遍（V03.6 E1），D08 的每个任务再按自己的 `verify.md` 看。

## 路线

1. 第一档：S02.6 阶段 4 的本地互动真机（V03.6 E1）；A08.13 的小修（另一个任务）。
2. 第二档，按顺序：**D08.1**（结构化记录，后面三个都用它）→ **D08.2**（常用语）→ **D08.3**（本地成长）→ **D08.4**（连击和数量）→ **D08.5**（三档特效）。A08.14（“+1（本地）”）不依赖它们，可以先做。
3. 留在 V03.6 的（D-040 不登记）：E10 本地弹幕样式、E14 资源包补全、E15 本地粉丝牌、E16 进房欢迎；要做时先在这里登记。
4. 同一组同时只开一个开发（PROCESS 第 5.1 节）：D07、D08、D02 都在 D 组，排队做。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [D 弹幕](../README.md)。

- 代码：`features/live_play/local_interaction/logic/`
- 进度：`███████░░░░░░░░░░░░░` 36%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| D08.1 | 结构化的本地历史：本地弹幕进记录、重进房间放回 | 功能 | 待真机 | 2026-10-09 | — | [设计或说明](D08.1-结构化的本地历史/README.md)、[任务书](D08.1-结构化的本地历史/brief.md)、[记录](D08.1-结构化的本地历史/record.md) |
| D08.2 | 常用语和最近发送 | 功能 | 待真机 | 2026-10-09 | — | [设计或说明](D08.2-常用语和最近发送/README.md)、[任务书](D08.2-常用语和最近发送/brief.md)、[记录](D08.2-常用语和最近发送/record.md) |
| D08.3 | 本地成长：观看时长、签到、等级进度 | 功能 | 未开始 | — | — | [设计或说明](D08.3-本地成长/README.md)、[任务书](D08.3-本地成长/brief.md) |
| D08.4 | 本地礼物连击、数量和横幅队列 | 功能 | 未开始 | — | — | [设计或说明](D08.4-本地礼物连击和数量/README.md)、[任务书](D08.4-本地礼物连击和数量/brief.md) |
| D08.5 | 三档礼物特效：小飘屏、横幅、大礼物座驾动效（参考 flame_barrage） | 功能 | 未开始 | — | — | [设计或说明](D08.5-三档礼物特效/README.md)、[任务书](D08.5-三档礼物特效/brief.md) |

## 还没完成的

- **D08.3 本地成长：观看时长、签到、等级进度**（未开始，第二档，规模 中）
  - 阶段：规则常量和计时（观看、签到、发弹幕，每天上限）、开关“本地成长” → 身份卡进度条、等级段名、升级记进记录
  - 说明：依赖 D08.1（记“升级”）；“本地成长”默认开是任务书写明的例外（D-040），关掉和 3.x 一样只有送礼加经验；定时器至少 1 秒
  - 来源：V03.6 第 4 节 E7、第 5.4 节（P5）；用户 2026-10-09（D-040）
- **D08.4 本地礼物连击、数量和横幅队列**（未开始，第二档，规模 中）
  - 阶段：3 秒内同一礼物连击：横幅 ×N 跳动、列表和记录合成一条 → 长按礼物选数量（1、10、66、520）、不同礼物排队（最多 5 个）
  - 说明：连击的数字动画照 flame_barrage ComboAnimation（MIT）；系统要求减少动态时不跳；记录合并依赖 D08.1（没做完时只合并列表）
  - 来源：V03.6 第 4 节 E8、第 5.5 节第一段（P6）；用户 2026-10-09（D-040）
- **D08.5 三档礼物特效：小飘屏、横幅、大礼物座驾动效（参考 flame_barrage）**（未开始，第二档，规模 中）
  - 阶段：按价格分三档、设置“礼物特效”改成三选一（旧开关照读） → 小礼物的顶部飘屏 → 大礼物的座驾动效（借 flame_barrage effect/motion）和 K90 帧时间
  - 说明：依赖 D08.4（横幅队列）；借的代码保留 MIT 版权声明；只画在 LocalGiftLayer 那一层，不进弹幕层；不用模糊（UI.md 第 9.3 节）
  - 来源：V03.6 第 4 节 E9、第 5.5 节第二、三段（P7）；用户 2026-10-09（D-040）

<!-- docs:生成结束 -->
