# A08.13 本地互动小问题修复：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区，没有推送、没有合并）
- 分支和提交：工作区分支 `worktree-agent-a30bf7a17b19c8839`，提交 `[A08.13] …`
- 任务书：[brief.md](brief.md)；设计和每条选择的理由：[README.md](README.md)“设计”c1～c7（维护者按 D-003 定）；来源：V03.6 的 P4、P8、P9、P12、P15、P16、P17 和 E2

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 1 清空可撤销（P4） | 做了 | 选的是“4 秒撤销”，不是确认框（c1）；面板和设置页同一个组件 |
| 2 星形只表示样式（P8） | 做了 | 新图标 `AppIcons.localCompose` = `rate_review_rounded`，不是 V03.6 提议的“发送”纸飞机（c2：纸飞机已经是“发出去”） |
| 3 输入框 40 字（P9） | 做了 | V03.6 提议 100 字；按任务书照平台 20～40 字取 40（c3）；计数 30 字起才出现 |
| 4 礼物行长按、双击（P12） | 做了 | 复制和面板卡片里礼物那句话不再在前面加名字（c4） |
| 5 粗体不丢字重（P16） | 做了 | ±200 的规则，不加新设置（c5） |
| 6 本地消息没有“屏蔽关键词”（P17） | 做了 | 选“去掉”，不是“让过滤也管本地消息”（c6） |
| 7 默认开的文字（P15） | 做了 | 注释、D03.4 README、D03 子分类 README；登记表 D03.4 的 `note` 按任务书留给登记的人 |

## 根因

- P4：`apps/pure_live/lib/features/live_play/local_interaction/local_interaction_panel.dart:519` 的清空按钮直接接 `interaction.clearHistory`（`logic/local_interaction.dart:228` 写空列表），既不问也不留旧的；设置页用同一个 `LocalHistory`（`local_interaction_settings_page.dart:159`）。
- P8：`local_composer.dart:336`（样式）、`:413`（窄全屏的收起按钮）、`:509`（竖屏列表的收起按钮）三处都用 `AppIcons.localStyle`；A07.17 c3 和 U.2k #27 收起输入框时沿用了输入框里的星形。
- P9：`local_composer.dart:279` 的 `TextField` 没有 `maxLength`，`LocalRoomSession.sendChat`（`logic/local_room_session.dart:71`）也不限长度。
- P12：`apps/pure_live/lib/features/live_play/danmaku/chat_list.dart:337` 只给 `ChatLineKind.chat` 的行接长按和双击；`:613` 本地分支对礼物行 `return local`，不包 `GestureDetector`。复制的文字 `chatCopyText`（`:73`）是“名字: 内容”，本地礼物的内容（`logic/local_interaction.dart:283`）已经以名字开头，会重复。
- P15：`packages/live_store/lib/src/settings/settings.dart:584` 的注释是 D03.4 第一版写的，D-039 改默认值（`bf0415330`）时没有改注释；D03.4 README 第 10、18、35 行同样。
- P16：`local_style_panel.dart:393` 写死 `>= 700 ? 500 : 800`，没有看原来的字重。
- P17：`danmaku/message_panel.dart:206` 的“屏蔽关键词…”不看 `message.isLocal`；本地消息走 `logic/room_controller.dart:1159` 的 `addLocal` 直接进列表，不过 `:1129` 的 `_filter.accepts`，所以屏蔽只删掉了列表里现有的行（`:1254`）。

## 改了哪些文件

- `apps/pure_live/lib/features/live_play/local_interaction/logic/local_catalog.dart`：`danmakuLimit`（40）、`danmakuCountFrom`（30）、`boldWeight`、`regularWeight`。
- `apps/pure_live/lib/features/live_play/local_interaction/logic/local_interaction.dart`：`clearHistory` 返回清掉的记录；新 `restoreHistory`。
- `apps/pure_live/lib/features/live_play/local_interaction/local_interaction_panel.dart`：`LocalHistory._clear`（提示条和撤销）。
- `apps/pure_live/lib/features/live_play/local_interaction/local_composer.dart`：`maxLength`、计数 `_LocalComposerCount`；两个收起按钮用 `AppIcons.localCompose`（`_LocalComposerStar` 改名 `_LocalComposerButton`）；注释。
- `apps/pure_live/lib/features/live_play/local_interaction/local_style_panel.dart`：粗体。
- `apps/pure_live/lib/features/live_play/danmaku/chat_list.dart`：`chatSenderName`、`chatLineActionable`；本地分支都包手势。
- `apps/pure_live/lib/features/live_play/danmaku/message_panel.dart`：本地消息不给“屏蔽关键词…”；本地礼物的卡片不重复名字。
- `packages/live_ui/lib/src/icons/app_icons.dart`：`localCompose`。
- `packages/live_store/lib/src/settings/settings.dart`：`holdDanmakuOnPress` 的注释（只改注释）。
- `apps/pure_live/assets/translations/zh.json`、`en.json`：`local_history_cleared`。
- 测试：`apps/pure_live/test/features/live_play/local_interaction_test.dart`、`live_play_layouts_test.dart`、`room_on_phone_test.dart`；`packages/live_ui/test/design_system_test.dart`。
- 文档：本文件夹；`docs/tasks.toml`（A08.13）；A08 子分类 README（现状一行、去掉“礼物行没有长按”的已知问题）；A08.2 README“留下的问题”；D03 子分类 README、D03.4 README 的“默认关”。

## 新图标、翻译键、门禁基线

- 新图标：`AppIcons.localCompose`（`Icons.rate_review_rounded`），用在两个收起按钮。
- 新翻译键（zh、en，按键名排序）：`local_history_cleared`（“已清空 {count} 条本地互动记录”）。
- 设置键、默认值没有变；门禁基线不变。

## 测试

- `apps/pure_live/test/features/live_play/local_interaction_test.dart` 新增 4 个（“A08.13 small fixes”一组）：
  - P4：面板里送礼、加币后清空：记录空了，提示条“已清空 2 条本地互动记录”，4 秒（`AppToast.actionDuration`）；点“撤销”两条回来，提示条关掉。
  - P9：29 字没有计数；30 字“30 / 40”；粘贴 10 个 emoji + 50 个字只留 40 个字（emoji 算一个），“40 / 40”是错误色，计数在框里、在字的右边；发出的是截后的 40 个字，发出后计数消失。
  - P12：送一个礼物，长按礼物行打开面板：卡片“Pure Live 送出 辣条 ×1”，只有“复制”；复制和双击复制都是“Pure Live 送出 辣条 ×1”。
  - P16：“清爽”600，点粗体 800（选中），再点 600（不选中）。
- 改了 5 个：
  - 资料库：六个模板的字重开关来回都回到原来的值；400、500、600 → 700、700、800；700、800、900 → 500、600、600；`danmakuLimit` 是 40。
  - 设置和逻辑：清空返回 30 条、记录空；加一条再撤销：新的一条在最上面，总数 30，存进设置。
  - 附录 A 第 6 条：长按本地弹幕只有“复制”，没有“屏蔽关键词”“屏蔽此用户”。
  - U.2k-b：窄全屏的收起按钮是 `localCompose`、没有星形；宽的输入框里没有 `localCompose`。
  - 设置页 c15：清空后提示条“已清空 1 条本地互动记录”，撤销后那一条回来。
- `live_play_layouts_test.dart`（窄横屏 740）、`room_on_phone_test.dart`（竖屏直播间）：收起按钮是 `localCompose`，不是星形。
- `packages/live_ui/test/design_system_test.dart`：对照表加 `localCompose`。
- **改之前会失败**：把五个界面文件（`local_composer.dart`、`local_interaction_panel.dart`、`local_style_panel.dart`、`chat_list.dart`、`message_panel.dart`）换回改之前的版本、保留逻辑和图标（测试要编译），上面 9 个界面用例全部失败（P4 两个、P8 三个、P9、P12、P16、P17），换回新代码全部通过。
- 跑过：`apps/pure_live/test/features/live_play/` 全部（388 个）、`packages/live_ui` 全部（217 个）通过。

## 门禁

- 见下一次提交的说明（`bash tools/gate/gate.sh --all`）。

## 真机上要看的

K90（`com.mystyle.purelive.v4dev`，每次点按前确认前台是测试包）：

1. 竖屏直播间（普通布局）：弹幕列表右下角的圆按钮是“带笔的气泡”，不是星形；点它弹出贴键盘的输入行，输入行左边仍是星形，点星形打开“本地弹幕样式”。
2. 横屏全屏、把窗口或手机弄到下栏中间窄于 180（窄横屏，如分屏）：中间的圆按钮同样是“带笔的气泡”；点开的输入行里星形是样式。
3. 在输入框里打字：打到 30 个字时框里右边出现“30 / 40”，打到 40 变红、再打不进去；粘贴一大段只留前 40 个字；发出后计数消失。用中文拼音输入法在 38～40 字附近打字，看会不会吞字或跳光标。看画面上那条 40 字的弹幕飞过的样子和列表里占几行。
4. 送一个本地礼物，在列表里长按礼物那一行：打开长按弹幕面板，卡片写“Pure Live 送出 辣条 ×1”，只有“复制”；点复制、或双击那一行，剪贴板里是这一句。
5. 长按一条本地弹幕：只有“复制”，没有“屏蔽关键词…”；长按一条平台弹幕：“复制”“屏蔽此用户”“屏蔽关键词…”照旧。控制层显示时点一条飞过的本地弹幕：同样只有“复制”。
6. 右上角菜单 → 本地互动体验，拉到“本地互动记录”，点“清空”：底部提示条“已清空 N 条本地互动记录 · 撤销”，4 秒后消失；再做一次，点“撤销”：记录回来。全屏（横屏）里做一次，看提示条的位置（画面中下部，不压下栏）。设置 → 本地用户与互动 → 本地体验币与记录：同样。
7. 本地弹幕样式：模板“清爽”下“粗体”不亮；点亮后发一条，比原来粗；再点灭后发一条，和最开始一样粗（不是更细）。换“霓虹”（粗体亮着）点灭再点亮，回到原样。
8. 设置 → 弹幕 →“画面弹幕交互”：“按住飞行弹幕让它停住”是开的（D-039，这次只改了注释和文档，行为不变）。
