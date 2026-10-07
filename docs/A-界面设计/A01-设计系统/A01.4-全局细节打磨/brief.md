# A01.4 全局细节打磨：任务书

## 背景

- 来源：2026-10-08 K90 真机对照第二轮（V03.4 R2-05～R2-10），截图在 `docs/V-需求和反馈/V03-审查和调研/V03.4-界面真机对照/shots/r2-*.jpg`；用户要求“提高质感”。
- 为什么做：第二档；每个页面都有的细节，统一改一次比逐页改省事。
- 已经做过的：A01.1～A01.3（设计系统）、A02.1（通用组件）。

## 目标和验收

1. 说明文字（设置行说明、面板说明、状态页说明、提示条）在 393 宽下不出现只有一个字的最后一行。
2. 设置行说明不再被截断（最多 3 行，超长的改短）。
3. 空状态标题都不带句号。
4. “手机端默认音量”“启用应用层代理”的图标换掉；设置页图标清单写进 `record.md`，没有一个图标表达两个意思。
5. 用户看得到的文字不小于 12 号（`docs/specs/UI.md` 第 4 节记下这条规则）。
6. 屏蔽关键词的“0/40”在输入框右下角。

## 现状（读代码得出，写文件:行）

- 设置行：`apps/pure_live/lib/shared/danmaku/setting_rows.dart`（直播间面板）和设置页的设置行组件（`apps/pure_live/lib/features/settings/` 里的 `settings_catalog.dart` 生成的行、`live_ui` 的设置行组件），找 `maxLines`。
- 多画面小格：`apps/pure_live/lib/features/multiview/multiview_page.dart:731`（“点击选台”现在 12 号的那一处之外还有小格里的另一处，开工先 `grep -n "multiview_pick" -r apps/pure_live/lib`）。
- 屏蔽关键词：`apps/pure_live/lib/shared/danmaku/block_manager.dart:243`（`maxLength: blockKeywordMaxLength`）。
- 空状态标题：`apps/pure_live/assets/translations/zh.json:2195`（`tags_empty_title`）等。
- 图标：`apps/pure_live/lib/features/settings/playback_tiles.dart`（手机端默认音量）、网络代理页。

## 3.x 基线

- 不涉及行为；文字只改说明的长短，不改设置键（D-018）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5、8、14 节）；`docs/specs/UI.md`（第 4 节字号）。
2. 本文件夹的 `README.md`；V03.4 的 `record.md` 第二轮。

## 范围

- 可以改：`packages/live_ui`（文字组件、设置行）、`apps/pure_live/lib/shared/`、设置页图标、多画面小格字号、屏蔽关键词输入框、翻译文件（只改说明文字和空状态标题的标点，新加键要 zh、en 都加）、测试、`docs/specs/UI.md` 第 4 节。
- 不能改：设置键名和含义（D-018）；翻译键不删（D-024）；功能目录之间不互相引用（门禁“界面结构”）。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 单字行、c2 说明不截断、c3 标点 | `live_ui` 文字组件和设置行、翻译文件、测试 | 验收 1～3 |
| 2 | c4 图标、c5 字号、c6 计数 | 设置页、多画面、屏蔽管理、`UI.md` | 验收 4～6；门禁 `--all` 通过 |

## 测试

- `packages/live_ui/test/`：固定宽度下中文说明最后一行不止一个字。
- `apps/pure_live/test/i18n_test.dart`：`*_empty_title` 不以“。”结尾。
- 已有的设置页、多画面、屏蔽管理布局测试不能坏。

## 真机验证（K90）

| 步骤 | 期望 |
|---|---|
| 1. 设置 → 平台显示与授权 | “首选直播平台”说明没有单字行 |
| 2. 热门 → ⌄ | 面板说明没有单字行 |
| 3. 设置 → 视频 | 说明都完整；“手机端默认音量”是音量图标 |
| 4. 标签管理（空） | 标题没有句号 |
| 5. 多画面 1+3 | 小格文字清楚 |
| 6. 直播间 → 屏蔽管理 | “0/40”在输入框右下角 |

## 风险和注意

- c1 改的是共用组件，所有说明都会受影响；先在设置页、面板、状态页各截一张对照。
- 翻译键排序和 4 空格缩进（门禁检查）。

## 环境和提交

- `source ~/tools/purelive-env.sh`；分支 `ai/A01.4` 或本机工作区；提交信息以 `[A01.4]` 开头（英文）；不推 master。
- 提交前：改过的包跑 format、analyze、测试；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条验收做到没有；改了哪些文件；改短的说明清单；图标清单；测试数量。
