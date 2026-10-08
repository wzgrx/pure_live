# A08.13 本地互动小问题修复：任务书

## 背景

- 来源：调研 V03.6“弹幕系统和本地互动体验”的增强 E2（第一档“甲”）；用户 2026-10-09 同意加强本地互动；设计选择由维护者按 D-003 定。
- 现象：V03.6 第 2.2 节的 P4（清空记录没有确认也没有撤销）、P8（同一个星形两种意思）、P9（输入框没有长度上限）、P12（本地礼物行不能长按、双击）、P15（`holdDanmakuOnPress` 的注释还写默认关）、P16（“粗体”丢掉原来的字重）、P17（本地弹幕的“屏蔽关键词”不起作用）。
- 为什么现在做：第一档；都是小改，做完再做 E3（“+1（本地）”）、E5、E6（记录和常用语）时长按面板和输入框是对的。
- 已经做过的：A08.2（本地互动的界面和逻辑）、A07.17 c3（竖屏列表右下角的按钮）、A08.1 c15 和 A02.4（带“撤销”的提示条）、A01.3（`AppIcons`）。

## 目标和验收

1. 互动面板和设置页清空“本地互动记录”后，底部提示条写“已清空 N 条本地互动记录”并带“撤销”（4 秒）；点“撤销”记录回来，清空以后新加的排在最上面，总数不超过 30。
2. 星形只表示“本地弹幕样式”；竖屏列表右下角和窄全屏下栏打开输入框的按钮换成新图标（`AppIcons` 里一个新名字），位置、大小、颜色、提示文字不变。
3. 本地弹幕输入框（三处同一个组件）最多 40 字（按字算），超出的打不进去；30 字起框里显示“n / 40”，到 40 变成错误色。
4. 列表里的本地礼物行能长按、右键打开长按弹幕面板，能双击复制；复制和面板里都只写一次名字。
5. “粗体”来回切换回到原来的字重（六个模板都是）。
6. 本地弹幕和本地礼物的长按面板没有“屏蔽关键词…”（也没有“屏蔽此用户”），平台弹幕的面板不变。
7. `holdDanmakuOnPress` 的注释和 D03.4 的 README 写“默认开”（D-039）。

## 现状（读代码得出）

- `apps/pure_live/lib/features/live_play/local_interaction/local_interaction_panel.dart:519`：`onPressed: interaction.clearHistory`。
- `local_composer.dart:336`（样式的星形）、`:413`（窄全屏按钮）、`:509`（竖屏列表按钮）都是 `AppIcons.localStyle`；`:279` 的 `TextField` 没有 `maxLength`。
- `apps/pure_live/lib/features/live_play/danmaku/chat_list.dart:337`（只有聊天行有 `onActions`、`onCopy`）、`:613`（本地非聊天行不包手势）、`:73`（复制“名字: 内容”）。
- `local_style_panel.dart:393`：粗体 `>= 700 ? 500 : 800`。
- `apps/pure_live/lib/features/live_play/danmaku/message_panel.dart:206`：“屏蔽关键词…”对谁都显示；`logic/room_controller.dart:1159` 的 `addLocal` 不过 `_filter`。
- `packages/live_store/lib/src/settings/settings.dart:584`：注释“Off by default”。

## 3.x 基线

- 3.x 的本地互动：`v3.2.11:lib/modules/live_play/widgets/local_interaction/`；粗体同样是 800、500（`local_danmaku_style_editor.dart:544-549`）；本地弹幕的长按同样给“屏蔽关键词”（`widgets/danmaku/danmaku_message_actions.dart:46-56`）。要保留：功能、设置键和默认值、样式各项。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`、`docs/specs/UI.md` 第 3、7、8.4 节、`docs/DECISIONS.md`（D-003、D-018、D-038、D-039）。
2. V03.6 的 README（P4、P8、P9、P12、P15、P16、P17 和 E2）；A08 子分类 README；A08.2 README。

## 范围

- 可以改：`apps/pure_live/lib/features/live_play/local_interaction/`、`danmaku/chat_list.dart`、`danmaku/message_panel.dart`；`packages/live_ui/lib/src/icons/app_icons.dart`；`packages/live_store/lib/src/settings/settings.dart` 的注释；翻译文件；对应测试；A08、A08.2、D03、D03.4 的 README 文字。
- 不能改：设置键、默认值和范围（D-018）；过滤规则（D02）；平台弹幕的长按面板；登记表 D03.4 那一段（登记的人改）；版本号。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 七条一起（都是小改，一次合并） | 见“范围” | 测试和门禁通过；`record.md` 写好 |

## 测试

- `apps/pure_live/test/features/live_play/local_interaction_test.dart`：清空和撤销（面板、设置页、逻辑）；40 字和计数；礼物行长按、双击、复制的文字；粗体来回（逻辑、样式面板）；本地弹幕的面板没有“屏蔽关键词”；窄全屏按钮的图标。
- `live_play_layouts_test.dart`、`room_on_phone_test.dart`：两个按钮是新图标、不是星形。
- `packages/live_ui/test/design_system_test.dart`：图标对照表。
- 每条测试在改之前的代码上会失败（礼物行、粗体、清空、计数、图标、面板）。

## 真机验证（维护者在 K90 上做）

见 [record.md](record.md)“真机上要看的”。

## 风险和注意

- 输入框的计数放在框里，不能把框撑高（48、40 高不变）；画面上的框最窄约 90 宽。
- 中文输入法打字时（还在拼音）Android 的长度限制按“打完再截”还是“直接截”由 Flutter 决定，真机上看一下 40 字附近打拼音的手感。

## 环境和提交

- `source ~/tools/purelive-env.sh`；新工作区先 `bash tools/ffmpeg_kit/fetch.sh android`、`linux`。
- 提交信息以 `[A08.13]` 开头（英文）；不推 master。

## 报告（中文，简洁）

每条做到没有；根因；测试；改了哪些文件；新图标和翻译键；真机上要看的；可能冲突的文件。
