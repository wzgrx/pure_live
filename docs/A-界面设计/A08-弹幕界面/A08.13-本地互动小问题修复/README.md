# A08.13 本地互动小问题修复

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：界面
- 来源：调研 V03.6“弹幕系统和本地互动体验”的增强 E2（第一档“甲”），对应问题 P4、P8、P9、P12、P15、P16、P17；用户 2026-10-09 同意加强本地互动（V03.6 的 README 第 2.2 节、第 4 节）
- 相关：[A08.2](../A08.2-本地互动/README.md)（本地互动的设计，c4、c10、c12、c14）；A07.17 c3（竖屏直播间列表右下角的按钮）；A08.1 c15、A02.4（带“撤销”的提示条 4 秒）；A01.3（一个意思一个图标）；D03.4、D-039（按住停住默认开）；D-003（设计由维护者定）
- 设计：按 D-003 由维护者定，不另出评审页（都是小改，样子和位置不变）；每一条的选择和理由见下面“设计”

## 界面清点

| 编号 | 界面 | 怎么打开 | 改了什么 |
|---|---|---|---|
| A08.13-01 | 互动面板和设置页的“本地互动记录” | 右上角菜单 → 本地互动体验，拉到最下；设置 → 本地用户与互动 → 本地体验币与记录 | 清空后底部提示条“已清空 N 条本地互动记录”带“撤销”（P4） |
| A08.13-02 | 竖屏直播间列表右下角的圆按钮、窄全屏下栏中间的圆按钮 | 竖屏直播间（A07.17 c3）；横屏全屏、下栏中间窄于 180 | 图标从星形换成“写弹幕”（P8） |
| A08.13-03 | 本地弹幕输入框（三处同一个组件） | 列表下、互动面板里、全屏下栏中间 | 最多 40 字，30 字起框里右边显示“n / 40”，到 40 变红（P9） |
| A08.13-04 | 列表里的本地礼物行 | 送一个本地礼物 | 能长按、右键打开面板，能双击复制（P12） |
| A08.13-05 | 本地弹幕样式的“粗体” | 输入框的星形，或面板“本地弹幕样式 ›” | 关掉粗体回到原来的字重（P16） |
| A08.13-06 | 长按本地弹幕、本地礼物的面板 | 列表里长按，或画面上点按、长按飞过的本地弹幕 | 去掉“屏蔽关键词…”，只留“复制”（P17） |

## 3.x 的样子和问题

- P4：清空记录一点就清（`local_interaction_panel.dart:519` 的 `onPressed: interaction.clearHistory`，设置页 `local_interaction_settings_page.dart:159` 同一个组件），违反规范第 7 节（删除类的操作要能撤销）。3.x 也是一点就清。
- P8：同一个星形 `AppIcons.localStyle` 有两种意思：输入框左边的星形打开“本地弹幕样式”（`local_composer.dart:336`），竖屏列表右下角（`:509`）和窄全屏栏（`:413`）的星形却打开**输入框**。违反规范第 3 节第 6 条和 A01.3 c1“一个用途一个图标”。这是 4.x 自己带进来的（3.x 没有收起的按钮）。
- P9：输入框的 `TextField`（`local_composer.dart:279`）没有 `maxLength`，粘贴一大段就飞出一条几屏宽的弹幕，聊天列表里也占很多行。
- P12：列表里的本地礼物行不能长按、不能双击：`chat_list.dart:337` 只给聊天行接 `onActions`、`onCopy`，`:613` 的本地分支对非聊天行直接返回 `LocalChatLine`、不包手势。3.x 的本地礼物和本地弹幕是同一种卡片，可以长按。
- P15：`holdDanmakuOnPress` 的注释（`packages/live_store/lib/src/settings/settings.dart:584`）还写“Off by default”，D03.4 的 README 也还写“默认关”，和 D-039（默认开）不一致。
- P16：“粗体”开 = 800、关 = 500（`local_style_panel.dart:393`），选中的判断是 ≥ 700：默认“清爽”是 600，点开再点关就成了 500，原来的字重丢了。3.x 同样（`v3.2.11:lib/modules/live_play/widgets/local_interaction/local_danmaku_style_editor.dart:544-549`）。
- P17：长按本地弹幕给“屏蔽关键词…”（`message_panel.dart:206`），可是本地消息不过过滤：平台弹幕在 `room_controller.dart:1129` 过 `_filter.accepts`，本地消息走 `addLocal`（`:1159`）直接进列表。屏蔽只删掉了当前列表里的行（`:1254`），下一条一样的本地弹幕照样出来。3.x 同样（`v3.2.11:lib/modules/live_play/widgets/danmaku/danmaku_message_actions.dart:46-56`）。

## 设计

都按 D-003 由维护者定（选下面的 A），用户随时可以推翻。

| 编号 | 问题 | 定的（A） | 没选的 | 理由 |
|---|---|---|---|---|
| c1 | P4 | **清空后给 4 秒“撤销”**，不先问：提示条“已清空 N 条本地互动记录 · 撤销”（`AppToast` 带操作，4 秒，开着无障碍服务 30 秒）；撤销时清掉的记录放回去，清空以后新加的记录排在最上面，总数仍不超过 30 | B：先弹确认框 | 应用里同类操作都是“先做、给撤销”（A08.1 c15 删屏蔽词、取消关注，规范第 7 节）；互动面板常在全屏里，居中的确认框会压住画面（A07.6、D-021 的理由）；清空的只是记录，币和等级不动，撤销足够 |
| c2 | P8 | **星形只表示“本地弹幕样式”**；打开输入框的两个圆按钮换成新图标 `AppIcons.localCompose` = Material `rate_review_rounded`（带笔的气泡：“写一条”）；提示文字仍是“发送本地弹幕”；按钮的位置、大小、颜色不变 | B：用发送按钮的纸飞机 `localSend`（V03.6 的提议） | 纸飞机在同一个输入框里已经表示“发出去”，按圆按钮并不会发送，用它又是一个图标两种意思；“写”和“发”分开，三个图标（样式、写、发）各一个意思 |
| c3 | P9 | **最多 40 字**（按字算，一个 emoji 算一个），超出的打不进去、粘贴的截掉；**30 字起**在框里右边显示“n / 40”（和“我的资料”昵称框“n / 20”同一种写法），到 40 变成错误色 | B：100 字（V03.6 的提议）；C：一直显示计数 | 平台一条弹幕一般限 20～40 字（按公开说明和常识，没有逐个核对：哔哩哔哩直播默认 20 字、等级或身份高的更长；其他平台也是几十字），本地弹幕照平台的样子取这一档的上限 40；默认 19 号字时 40 个汉字约 760 宽，横屏手机（852）差不多一屏，再长就要好几秒才飞完、列表里占两三行。计数只在最后 10 个字出现：画面上的输入框最窄只有约 90 宽，一直显示计数会挤掉打字的地方 |
| c4 | P12 | 本地礼物行和本地弹幕行一样：长按、右键打开长按弹幕面板，双击复制；复制的是“Pure Live 送出 辣条 ×1”，面板卡片里也只写这一句（不在前面再加名字） | — | 3.x 的礼物和弹幕是同一种卡片；礼物那句话里已经有名字（A08.2 c10“礼物不重复名字”），复制“Pure Live: Pure Live 送出…”就重复了 |
| c5 | P16 | **“粗体”开 = 字重加 200（至少 700），关 = 字重减 200（最多 600）**：500 ⇄ 700，600 ⇄ 800；六个模板的字重（500～800）来回切换都回到原来的值；不加新设置 | B：新加一个设置记住“打开粗体前的字重”；C：放出字重滑块 | A 不用新键（D-018 只加不改也要进备份、设置清单）就能让面板能做出来的所有字重来回不丢；字重滑块是新功能，V03.6 没列进 E2。限制：400（面板做不出来，只可能来自手改的备份）开再关是 500 |
| c6 | P17 | **本地弹幕、本地礼物的长按面板去掉“屏蔽关键词…”**，只留“复制”（本来就没有“屏蔽此用户”） | B：让关键词屏蔽也过滤本地消息 | 本地消息是自己发的，只有自己看得到，屏蔽自己的话没有意义；B 还会让“本地互动”和平台屏蔽搅在一起（屏蔽词改了，自己发的也看不到）。去掉以后面板说的都做得到。V03.6 的 E3、E6 以后会在这里加“再发一次”“存为常用语” |
| c7 | P15 | `holdDanmakuOnPress` 的注释改成“默认开（D-039，D-036 的例外）；关掉和 3.x 一样”；D03.4 README 和 D03 子分类 README 里的“默认关”改成“默认开” | — | 只是文字；登记表 D03.4 的 `note` 由登记的人改（任务书要求，避免两边改同一段） |

- 不变的：各处的位置、大小、颜色、顺序、键名；`localInteraction.*` 设置键和默认值（D-018）；平台弹幕的长按面板。
- 测试里的键名 `local-composer-star`、`local-composer-chat-star`、类名 `LocalComposerChatStar` 是 A07.17 起的名字，没有跟着改（改名会碰很多别的测试，只是名字，用户看不到）。

## 实现和验证

- 做完（待真机），逐条见 [record.md](record.md)：
  - c1：`LocalInteraction.clearHistory` 返回清掉的记录、新加 `restoreHistory`（`local_interaction/logic/local_interaction.dart:229`、`:237`）；`LocalHistory._clear`（`local_interaction_panel.dart:462`）弹提示条；新文字 `local_history_cleared`。
  - c2：`AppIcons.localCompose`（`packages/live_ui/lib/src/icons/app_icons.dart:420`）；`local_composer.dart:472`（窄全屏）、`:570`（竖屏列表）。
  - c3：`LocalCatalog.danmakuLimit` 40、`danmakuCountFrom` 30（`logic/local_catalog.dart:278`、`:282`）；`TextField.maxLength`（`local_composer.dart:306`），计数 `_LocalComposerCount`（`:331`）。
  - c4：`chatLineActionable`、`chatSenderName`（`danmaku/chat_list.dart:79`、`:84`），本地分支都包手势。
  - c5：`LocalCatalog.boldWeight`、`regularWeight`（`logic/local_catalog.dart:593`、`:597`），`local_style_panel.dart:398`。
  - c6：`danmaku/message_panel.dart:211`。
  - c7：`packages/live_store/lib/src/settings/settings.dart:584`。
- 测试：`apps/pure_live/test/features/live_play/local_interaction_test.dart` 新增 4 个、改了 5 个；`live_play_layouts_test.dart`、`room_on_phone_test.dart` 各补图标的断言；`packages/live_ui/test/design_system_test.dart` 图标对照表加一行。
- 真机：见 [record.md](record.md)“真机上要看的”。
