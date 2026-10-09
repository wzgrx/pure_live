# A08.15 聊天列表字号和行距：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区 `worktree-agent-a79cce3fe723e6eb4`，从 master `7e93d6f77` 开始，含 A08.10、A08.11、A08.12、A08.13、D07.1、D07.3、D08.1）
- 分支和提交：`worktree-agent-a79cce3fe723e6eb4`，提交见文末
- 任务书：[brief.md](brief.md)；设计：[README.md](README.md)（S1～S10 按 D-003 由维护者定）；真机步骤：[verify.md](verify.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 1 两个新设置 | 做了：`danmakuListFontSize`（默认 0，12～22，超出和 0 都读成 0）、`danmakuListLineSpacing`（默认 `standard`，`compact`、`loose`，别的值读成 `standard`），`danmaku` 一节，备份和设备同步都带；登记 `Settings.all`、`settings_defaults_test.dart`（`newInV4`、`ranges`）、`settings_audit_notes.py`、`OWNERS.toml`，重新生成了 J01.2 的 `settings.md` | 没有 |
| 2 默认像素一致 | 做了：先用改之前的代码量了 9 种行（普通、带头像、长名字、礼物、本地、本地礼物、醒目留言、提示、系统）× 紧凑和卡片 × 360、280 宽 × 1、1.3、2 倍系统字号的大小和各块位置，存成 `chat_list_sizing_baseline.json`；新代码在三套主题下逐项相等（差不超过 0.01） | 卡片圆点原来想按系统字号对齐第一行，量出来系统字号放大时位置会变，改成只按列表字号算（S7），默认下就完全一样 |
| 3 一起变 | 做了：紧凑、卡片、本地弹幕和本地礼物、礼物行、醒目留言行、提示行；粉丝牌、“对方”“本地”“之前发的”、本地徽章、平台徽章、头像、圆点、礼物图、礼物价值按比例；系统字号照样乘上去 | 系统标签只跟间距（S5） |
| 4 不溢出 | 做了：280 宽、12 和 22 号、紧密和宽松、1.3 和 2 倍系统字号、三套主题、两种样式、9 种行都没有溢出，长名字完整换行；直播间竖屏、手机横着拿（右边 280 的列表）、宽屏右栏在 22 号 + 宽松 + 卡片 + 2 倍系统字号下没有溢出 | 没有 |
| 5 设置行、搜索、翻译 | 做了：“弹幕列表样式”下面，三处是同一个 `ChatListSettings`；搜索“字号”“文字大小”“行距”“间距”能找到；文字走翻译 | 值写“默认”，三档叫“紧密、标准、宽松”（S2、S3） |

## 根因（为什么以前改不了）

- `ChatText.content/name`（`chat_text.dart`）直接取主题的 `bodyLarge`，各行的上下间距（`chat_list.dart` 紧凑行和卡片的 `EdgeInsets.symmetric(vertical: 4)`、卡片里的 8，`gift_line.dart`、`local_chat_line.dart` 同样）和标签、徽章、礼物图的大小（`ChatChip.styleOf` 的 12、`ChatBadge.height` 16、`GiftIcon.size` 16、头像半径 12）都是常量，没有参数。
- 顺带发现：D08.1 的“之前发的”标签是普通 `WidgetSpan`（`local_chat_line.dart`），系统字号放大时被乘了两次（A08.11 G14 修过的同一个问题）；改成 `chatInline`。

## 改了哪些文件

- `apps/pure_live/lib/features/live_play/danmaku/chat_text.dart`：`ChatSizing`；`ChatText.content/name` 的 `sizing` 参数。
- `apps/pure_live/lib/shared/danmaku/chat_list_settings.dart`：`ChatSpacing`；“列表文字大小”滑条和“行间距”分段按钮；`chatListFontSizeText`、`chatListFontSizeOf`、`chatListFontSizeDefaultStop`。
- `apps/pure_live/lib/features/live_play/danmaku/chat_list.dart`：`ChatList` 读两个设置、行缓存认 `sizing`；`ChatLineView.sizing`（紧凑、卡片、提示、醒目留言、系统的间距，标签、徽章、头像、圆点）；`ChatBadge` 的 `height` 参数；圆点加了键 `live-play-chat-dot`。
- `apps/pure_live/lib/features/live_play/danmaku/gift_line.dart`：`GiftLine.sizing`、`giftLineOf(sizing:)`；`GiftIcon` 的 `size` 参数。
- `apps/pure_live/lib/features/live_play/local_interaction/local_chat_line.dart`（只改大小）：`LocalChatLine.sizing`；`ChatChip.styleOf(theme, sizing)`，圆角跟高度；“之前发的”用 `chatInline`。
- `apps/pure_live/lib/features/settings/settings_catalog.dart`：搜索两条。
- `packages/live_store/lib/src/settings/settings.dart`：两个设置。
- 翻译：`apps/pure_live/assets/translations/zh.json`、`en.json`。
- 文档工具：`tools/docs/settings_audit_notes.py`、`docs/inventory/OWNERS.toml`。
- 测试：见下。
- 文档：本文件夹 README、record、verify；A08 的 README（手写部分）；`docs/tasks.toml`；生成的 STATUS、TASKS、A 组和 A08 的 README、OWNERS.md、J01.2 的 settings.md。
- 没改：`message_panel.dart`（长按卡片不跟，A08.14 在改它）、`local_composer.dart`、飞行弹幕、醒目留言标签页。

## 新设置、翻译键、门禁基线

- 新设置（`danmaku` 一节、同步）：`danmakuListFontSize`（默认 0，12～22）、`danmakuListLineSpacing`（默认 `standard`）。
- 新翻译键（8 个，zh / en）：`danmaku_list_font_size`（列表文字大小 / Chat text size）、`danmaku_list_font_size_default`（默认 / Default）、`danmaku_list_font_size_desc`（搜索结果的说明）、`danmaku_list_spacing`（行间距 / Line spacing）、`danmaku_list_spacing_desc`、`danmaku_list_spacing_compact`（紧密 / Tight）、`danmaku_list_spacing_standard`（标准 / Standard）、`danmaku_list_spacing_loose`（宽松 / Loose）。没有删键（D-024）。
- 门禁基线：没改。

## 测试

- `packages/live_store/test/chat_list_sizing_test.dart`（新，4 个）：默认 0 和 `standard`、`danmaku` 一节、同步、新装不存；12～22 原样，0、11、23、-5、100、文字、空、NaN 读成 0，“16”读成 16、15.6 读成 16；三档原样、别的读成 `standard`；备份往返，3.x 的备份不带它们，备份里的 40 读成 0。`settings_defaults_test.dart` 的 `newInV4` 和 `ranges` 加了它们。
- `apps/pure_live/test/features/live_play/chat_list_sizing_test.dart`（新，15 个）：
  - 默认：`ChatSizing.standard` 就是两个设置的默认值，原样返回样式（同一个对象）；9 种行 × 两种样式 × 两种宽 × 三档系统字号 × 三套主题和基线一致（108 × 3）；14 号（等于主题字号）+ 标准和默认一样。
  - 每一档字号 12～22：名字和内容同字号、名字仍是 600；粉丝牌、“对方”的字按比例且不小于 12、粉丝牌高度；行越来越高；徽章、头像、圆点的大小和位置；礼物行（送礼人、礼物名、礼物图、小一号的价值）、本地弹幕（名字、内容、“本地”、徽章胶囊）、本地礼物、醒目留言行、提示行跟着变，系统标签不变。
  - 每一档行间距：0、12、22 号下紧凑行和卡片的高度等于“间距 × 0.5/1/1.5 + 字号 × 行高 1.4/1.5/1.7”（文字高度取整，差不超过 1），紧密 < 标准 < 宽松；换行的长弹幕每行的高度也跟着变。
  - 系统字号：280 宽，0、12、22 号 × 1.3、2 倍 × 紧密、宽松 × 三套主题 × 两种样式 × 9 种行，不溢出、宽 280；内容只放大一次（一行高 = 字号 × 行高 × 倍数）；“对方”只放大一次；长名字完整、换行。“之前发的”标签放大一次、和“本地”一样高。
  - 直播间：行缓存——改字号后显示着的行都带新字号重建，改行间距同样；之后来一条新弹幕只建它一行；改回默认后和以前一样。竖屏、手机横着拿（280 列表）、宽屏右栏：22 号 + 宽松 + 卡片 + 2 倍系统字号，再换紧凑样式，都不溢出、字号是 22。
  - 设置行：在“弹幕列表样式”下面、“显示用户名”上面；滑条 11～22 共 11 档、起点是“默认”；拖到 16 存 16、写“16 px”，拖回最左存 0、写“默认”；三档按钮存 `compact`、`loose`；值的文字和滑条档位的换算。
- `apps/pure_live/test/features/settings/settings_danmaku_test.dart`（加 3 个）：设置 → 弹幕的“弹幕列表”里有两行、在样式下面、默认“默认”，点“宽松”生效；2 倍字 360 宽不出界；搜索“字号”“文字大小”“行距”“间距”找到，在“弹幕 › 弹幕列表”下。
- `apps/pure_live/test/features/live_play/live_play_tabs_test.dart`（加 1 个）：直播间标签和画面面板都有“列表文字大小”“行间距”，顺序一样，标签里选的在面板里也是选中的。
- 合计新加 23 个。改之前的代码上，除了“默认和基线一样”的几个，都会失败（没有设置、没有参数）。
- 聊天基准 `chat_benchmark_test.dart`（3 秒，200 条/秒，120 Hz）：600 条聊天 `ChatLineView` 建 602 次（= 加进来的行数，每行一次），整页 48.6 次构建/帧；加 50 个礼物/秒时 708 次（= 662 行 + 46 次合并），52.9 次/帧；`ChatList` 0 次、列表每帧最多一次。和 A08.12 的断言一样，没有多建。
- 全部：`flutter test`（apps/pure_live）、`dart test`（live_store）通过；门禁见下。

## 真机上要看的

- 默认设置下列表和改之前完全一样（verify.md 第 1 步）。
- 12 号 + 紧密时一屏能多看很多行、仍然看得清；22 号 + 宽松时字大、行与行分得开（第 3、4 步）。
- 手机横着拿（右边 280 宽的列表）、22 号、系统字体最大时不截断、不溢出；粉丝牌、头像、礼物图跟着变大，对得齐第一行（第 5、6 步）。
- 礼物行、本地弹幕、醒目留言行跟着变；飞行弹幕不变（第 7、8 步）。
- 改字号时已经显示的弹幕马上变（第 4 步）。

## 门禁

- 见下一次提交。

## 提交

- `bc6d9228e` 代码和测试；文档和登记表的提交；记录门禁结果的提交。合并提交由维护者补。
