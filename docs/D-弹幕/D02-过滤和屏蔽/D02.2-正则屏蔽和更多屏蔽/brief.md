# D02.2 正则屏蔽、屏蔽纯表情和超长弹幕、本场屏蔽计数：任务书

## 背景

- 来源：V03.6（`docs/V-需求和反馈/V03-审查和调研/V03.6-弹幕系统和本地互动体验/README.md`）第 3.3 节、第 4 节 E11（乙档）、第 5.6 节做法 A；用户 2026-10-09（D-040）。
- 现象：屏蔽词只能“包含”，屏蔽不了一类写法；刷屏的纯表情、超长复制粘贴挡画面；不知道屏蔽有没有起作用。
- 为什么现在做：第二档；常见客户端的标配。
- 已经做过的：D01.1（过滤链）、D02.1（打码昵称）、A08.3（屏蔽管理界面）。

## 目标和验收

1. `/…/` 的屏蔽词按正则匹配（不分大小写）；普通词照旧包含匹配；编译不过的不加进去并提示；正则最长 200 字、每条只匹配前 200 个字。
2. 屏蔽表的存储格式、备份、3.x 导入不变。
3. 两个新开关（默认关）：屏蔽只有表情的弹幕、屏蔽超过 N 字（默认 30）的弹幕；关着时和现在一样。
4. 直播间“屏蔽管理”标签显示本场已屏蔽的条数（不存，换直播间清零）。
5. 基准：20 条正则 + 相似度一起开，每秒 200 条的耗时前后对比写进 record.md。
6. 文字走翻译；设置搜索能找到新开关。

## 现状（读代码得出）

- `packages/live_danmaku/lib/src/filters/block_list.dart:13-40`（`DanmakuBlockList.blocks`）；`message_filter.dart:104-110`（`accepts`：闸门 → 屏蔽表 → 重复 → 相似度）。
- `apps/pure_live/lib/shared/danmaku/block_manager.dart:14`（`blockKeywordMaxLength = 40`）、`:243`（输入框 `maxLength`）；长按面板的第二页 `features/live_play/danmaku/message_panel.dart` 的 `_KeywordPage`（`:219`）。
- 存储 `packages/live_store/lib/src/block_lists.dart`；设置 `packages/live_store/lib/src/settings/settings.dart` 的 `danmaku` 一节。
- 基准 `apps/pure_live/test/features/live_play/chat_benchmark_test.dart`。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/controllers/danmaku_controller.dart` 的 `:252-269`：包含匹配。要保留：普通词的行为、40 字上限、屏蔽表格式（D-018）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`。
2. `docs/specs/ENGINEERING.md`。
3. 本文件夹 `README.md`；`docs/D-弹幕/D02-过滤和屏蔽/README.md`；`docs/A-界面设计/A08-弹幕界面/A08.3-弹幕屏蔽页/README.md`。

## 范围

- 可以改：`block_list.dart`、`message_filter.dart`；`block_manager.dart`、`message_panel.dart` 的 `_KeywordPage`（只加正则提示和长度）；`room_controller.dart`（计数）、弹幕设置面板的“屏蔽管理”标签（`features/live_play/danmaku/danmaku_settings_panel.dart` 或 `chat_panel.dart`）；`settings.dart`（新设置，登记 `Settings.all`、`settings_defaults_test.dart`、`tools/docs/settings_audit_notes.py`）、`settings_catalog.dart`；`docs/inventory/OWNERS.toml`；翻译文件；对应测试；A08.3 的 README 补一条。
- 不能改：屏蔽表的存储格式；相似度、合并重复的规则；D-013；版本号。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 正则（编译、提示、200 字）、c2 格式不变；基准 | `block_list.dart`、`block_manager.dart`、`message_panel.dart`、基准 | 测试和基准通过 |
| 2 | c3 两个新开关、c4 本场计数 | 过滤链、设置、控制器、标签 | 测试通过 |

## 测试

- `packages/live_danmaku/test/message_filter_test.dart`（或新 `block_list_test.dart`）：`/^\d+$/` 拦纯数字；`/abc/` 不分大小写；普通词照旧包含；坏正则 `/[/` 跳过不抛；超过 200 字的弹幕只匹配前 200 字；纯表情（只有表情代码）被拦、带一个字的不拦；超长开关和长度。
- `apps/pure_live/test/features/live_play/`：添加坏正则时有提示、没加进去；计数随屏蔽涨、换直播间清零。
- `packages/live_store/test/`：新设置默认关、备份往返；屏蔽表备份里正则原样。
- 基准：20 条正则 + 相似度。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 屏蔽管理加 `/^[0-9]+$/` | 纯数字弹幕不见了，计数在涨 |
| 2. 加 `/[/` | 提示写法不对，没加进去 |
| 3. 打开屏蔽只有表情的弹幕 | 纯表情的弹幕不见了 |

## 风险和注意

- 慢正则（回溯爆炸）：限制长度、只匹配前 200 字；Dart 的 `RegExp` 没有超时，所以长度限制是主要手段，写进说明。
- 普通词里本来就以斜杠开头和结尾的（极少）会被当成正则：在说明里写清。

## 环境和提交

- `source ~/tools/purelive-env.sh`；`packages/live_danmaku` `dart test`；`apps/pure_live` 全部 `flutter test`；推送前 `bash tools/gate/gate.sh --all`。
- 分支 `ai/D02.2`；提交信息以 `[D02.2]` 开头（英文）；不推 master。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条做到没有；新设置和翻译键；基准数字；测试数量；改了哪些文件；真机上要看的。
