# Z07.3 每季度复查：任务书

## 背景

- 来源：[PROCESS.md](../../../PROCESS.md) 第 12 节“每季度：复查文档和决定：过时的规则、被取代的决定、长期没动的子分类和任务（不做的移到 V04）”，以及“长期没动的任务：第一档超过两周、第二档超过两个月没动的，在季度复查时决定降档、拆小或不做”。docs v1（2026-10-03）登记。
- 现象：项目一个月里换了三次文档结构（v0、v1、v2），规则写在很多地方；已经发现几处写的和实际不一致（见“现状”）；登记表里有 79 个没完成的任务，没人定期看哪些已经过时。
- 为什么现在做：第三档；第一次定在 2026-12 底（季度末），之前不需要做。
- 已经做过的：无。docs v2（2026-10-07 起）重写各组说明时，把发现的不一致写进了各组的“已知问题”。

## 目标和验收

1. 本文件夹 `README.md` 的检查清单（README 方案 c1 的 5 项）每项写清用什么命令或看哪个文件。
2. `record.md` 有这次复查的结果：
   - DECISIONS 每条一行：依据还成立 / 不成立（建议加哪条新决定）；
   - 规则和事实不一致的清单（文件:行、现在写的、实际情况、建议改法或任务编号）；
   - 超期没动的任务（第一档超过两周、第二档超过两个月），每个写建议：留、降档、拆小、不做；
   - 没有任务的子分类，每个写建议。
3. 能直接改的（执行者有权改的文档）改掉；需要维护者改的（PROCESS、PLAN、DECISIONS、specs、AGENTS.md、`tasks.toml`）列成清单交给维护者。
4. `python3 tools/docs/docs.py --check` 通过。

## 现状（2026-10-07 读出，开工时重新读）

- 决定：`docs/DECISIONS.md` 29 条；D-014 状态“编号部分被 D-025 取代”，D-007 状态“有效（例外见 D-008）”，D-008 状态“有效；以后换包一律改版本号”（Y02.1 是它的后续）。
- 已知的不一致：
  - `docs/specs/ENGINEERING.md:68`：上游对照的结论写进“Z 的上游对照”——实际在 `docs/W-上游借鉴/W01-定期对照/`。
  - `docs/specs/ENGINEERING.md:52`、`tools/gate/check_deps.py:34`、`fixtures/README.md:17`：`tools/live_cli` 不存在（E07.1）。
  - `apps/pure_live/android/app/build.gradle.kts:9`：引用 `docs/specs/ENGINEERING.md §9`，ENGINEERING 只有 7 节。
  - 代码注释里 16 处 `docs/README.md/`、`docs/TASKS.md/` 开头的坏路径（[Z06 子分类说明](../../Z06-文档和登记表/README.md)“已知问题”有全表）。
  - `docs/README.md:3`、`docs/tasks.toml:1`：还写 docs v1；`docs/CHANGELOG.md` 没有 v2。
  - `AGENTS.md`“目录”一节：`apps/pure_live` 有 Linux——仓库里没有 `apps/pure_live/linux/`（X02.1）。
  - `~/tools/pl-adb.sh:7` 默认包名 `.next`（Z04.1）。
- 登记表：没完成的 79 个（第一档 8、第二档 32、第三档 37、受阻 2）；没有任务的子分类 9 个：G05、H03、H04、J05、K03、L02、O01、Q02、X05。

## 3.x 基线

- 不适用（流程任务）。3.x 的 `MAINTENANCE_POLICY.md`（`git show v3.2.11:MAINTENANCE_POLICY.md`）讲维护范围和证据，没有定期复查。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（全文，重点第 12、13 节）、`docs/DECISIONS.md`、`docs/PLAN.md`、`docs/README.md`、`docs/specs/ENGINEERING.md`。
2. 本文件夹的 `README.md`；`docs/Z-工程文档和维护/README.md` 和各子分类的“已知问题”；各组说明的“已知问题”和“路线”（`grep -rn '## 已知问题' docs/*/README.md docs/*/*/README.md`）。

## 范围

- 可以改：本文件夹的文档；执行者负责的任务文件夹里过时的事实（例如任务 README 里写错的路径），改动列进 `record.md`。
- 不能改（写建议，维护者改）：`docs/PROCESS.md`、`docs/PLAN.md`、`docs/DECISIONS.md`、`docs/specs/`、`AGENTS.md`、`CLAUDE.md`、`docs/tasks.toml`（档位、状态、新任务）；任何代码。
- 不新增决定（决定只由维护者或用户定）。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 检查清单写进 README | 本文件夹 `README.md` | 验收 1 |
| 2 | c2 按清单走一遍：决定、规则、任务、子分类、文档版本 | `record.md`；能直接改的文档 | 验收 2～4；给维护者的清单 |

## 测试

- 不涉及代码测试；`python3 tools/docs/docs.py --check`。
- 找超期任务：对每个没完成的任务看 `git log -1 --format=%ad --date=short -- <任务文件夹>` 和登记表里最后一次改它的提交（`git log -L` 或 `git log -S'id = "X01.1"' -- docs/tasks.toml`）。

## 真机验证

不适用。

## 风险和注意

- 复查只提建议，不擅自改规则和决定：PROCESS 第 13 节规定决定只加不删，改主意要加新条取代。
- 超期的判断用“最后一次有实质改动”（代码或任务文档），不要只看登记表的日期——很多任务登记后一直没有 `date`。
- 可能冲突的文件：无（只写本文件夹和给维护者的清单）。

## 环境和提交

- 不需要 Flutter。
- 分支 `ai/Z07.3` 或本机工作区；提交信息以 `[Z07.3]` 开头（英文）；不推 master。
- 提交前：`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：在 `record.md` 写清单做到第几项、更新登记表的 `next`。

## 报告（中文，简洁）

决定：多少条依据不成立；规则和事实不一致的清单；超期任务和建议；空子分类的建议；直接改了哪些；需要维护者改的清单。
