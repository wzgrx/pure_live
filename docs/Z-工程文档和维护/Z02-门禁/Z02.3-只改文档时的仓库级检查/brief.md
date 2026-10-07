# Z02.3 门禁默认模式在只改文档、样本、脚本时也跑仓库级检查：任务书

## 背景

- 来源：docs v2 写作时 X、Y、Z 组代理读 `tools/gate/gate.sh` 发现（Z02 子分类说明的“已知问题”）。
- 现象：只改了 `docs/` 的提交，跑 `tools/gate/gate.sh`（或 Stop 钩子）输出 `gate: no workspace member changed` 就结束，坏链接、生成区过期、代码里的坏文档路径都要等推送前的 `--all` 才发现。
- 为什么现在做：第二档；文档改得多（docs v2 之后每个任务都要改文档），越早报错越省事；改动小。
- 已经做过的：Z02.2 加了“docs”一步（`c613b73f9`）。

## 目标和验收

1. 只改 `docs/`、`fixtures/`、`tools/`、根目录 `README.md`、`AGENTS.md`、`CLAUDE.md` 时，默认模式和 `--hook` 跑“dependency direction”“fixture privacy”“ui structure”“docs”四项，不跑 `pub get`、不跑成员的格式、分析和测试。
2. 改了 `tools/gate/` 或 `tools/docs/` 时还跑 “gate tests”。
3. 什么都没改时行为不变（输出 `gate: no workspace member changed`，退出 0；钩子模式不出声）。
4. `--all` 行为不变；有成员改动时行为不变。
5. ENGINEERING 第 3 节和 `gate.sh` 开头注释写明新的行为。

## 现状（读代码得出，写文件:行）

- `tools/gate/gate.sh:11-17` 三种模式；`:40-43` 读工作区成员；`:45-57` 计算 `changed` 和 `selected`；`:58-62` 没选中成员时退出；`:65-68` 全局锁；`:74-87` `step`；`:92-105` `pub get`（`package_config.json` 过期时）；`:109-111` FFmpeg 包；`:113-116` 四项仓库级检查；`:117-127` 成员循环；`:129-131` `gate tests`；`:133-141` 结果和钩子的退出码。
- `.claude/settings.json:14` 的 Stop 钩子。

## 3.x 基线

- 不涉及。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md` 第 3 节。
3. 本文件夹的 `README.md`；`tools/gate/gate.sh` 全文。

## 范围

- 可以改：`tools/gate/gate.sh`、`docs/specs/ENGINEERING.md` 第 3 节、本文件夹的文档和登记表。
- 不能改：四项检查脚本本身（`check_deps.py`、`check_fixtures.py`、`check_ui_structure.py`、`docs.py`）；`--all` 的行为；`.claude/settings.json`。

## 方案和阶段

| 阶段 | 做什么（README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1、c2、c3 | `tools/gate/gate.sh`、`docs/specs/ENGINEERING.md` | 验收 1～5；`gate.sh --all` 通过 |

## 测试

- 门禁脚本没有 shell 测试；在一个临时工作区里手动跑三种情况并把输出贴进 `record.md`：只改 md 放坏链接（应 FAIL docs）、只改 md 不出错（passed）、什么都不改（no workspace member changed）。
- 如果把判断“仓库级改动”的逻辑写成一个小的 Python 函数，就在 `tools/gate/tests/` 加单元测试。

## 真机验证

- 不需要。

## 风险和注意

- `set -uo pipefail` 下空数组展开要小心（`"${selected[@]}"` 在 bash 4.4 以下会报未定义）。
- 钩子有 1800 秒超时，四项检查只要几秒；不要在仓库级分支里触发 `pub get`。
- 和 Z06.4 都改门禁相关的东西，但文件不重叠（Z06.4 改 `docs.py` 和测试）。

## 环境和提交

- `source ~/tools/purelive-env.sh`；分支 `ai/Z02.3` 或本机工作区；提交信息以 `[Z02.3]` 开头（英文）；不推 master。
- 提交前：`tools/gate/gate.sh --all`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

三种情况的实际输出；改了哪几行；ENGINEERING 改了什么。
