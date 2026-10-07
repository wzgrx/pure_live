# Z07.2 每次发布后维护：任务书

## 背景

- 来源：[PROCESS.md](../../../PROCESS.md) 第 12 节“每次发布后：STATUS 里‘待真机’的逐项看完；版本路线、发布说明和 README 更新；回复相关 issue”。docs v1（2026-10-03）登记。
- 现象：4.0.0 发布了两次（2026-10-02 构建号 5000、同日覆盖成 5001，D-008），之后没有专门的整理：STATUS 里“待真机”18 个（多数随 5001 发出），`docs/PLAN.md` 第 5 节的版本路线没标出 4.0.0 已发布，`releases/v4.0.0.md` 和根目录 README 的“以后要做的”还是发布当天的样子。
- 为什么现在做：第二档；用户已经在用这些功能，没有真机结果的越积越多；每次发布后都要做一遍，先把清单固定下来。
- 已经做过的：Y03.1（README 和 4.0.0 发布说明）、V02.1（回复并关闭 #36、#37）、S02.5 登记了 5001 这一批的真机验证（未开始）。

## 目标和验收

1. 本文件夹 `README.md` 有一张“发布后清单”（README 方案 c1 的 6 步），每步写清用什么命令、改哪个文件、谁做（执行者 / 维护者）。
2. 对 4.0.0（构建号 5001）补做一遍，结果逐步写进 `record.md`：
   - 这个版本包含的任务清单（从 `git log` 的提交和合并读出）；
   - 18 个待真机的任务和 S02.5 的清单是否一致（不一致的列出来）；
   - PLAN 第 5 节、README“路线图”、`releases/v4.0.0.md`“以后要做的”要改的地方（执行者写建议，PLAN 由维护者改）；
   - 这个版本修了的 issue 是否都已回复。
3. `python3 tools/docs/docs.py --check` 通过。

## 现状（读出来的，开工时重新读）

- 版本：`apps/pure_live/pubspec.yaml:5` `version: 4.0.0+5001`；`apps/pure_live/lib/features/version/app_version.dart:5`、`:8`（`pubspecVersion`、`pubspecBuild`）；标签 `v4.0.0` 指向 `4b039e0c7`（覆盖发布后移过去的，原来在构建号 5000 的提交上）；`assets/version.json` 的 `build_number` 5001（`e3f644d67`）。
- 待真机 18 个（`docs/STATUS.md` 的“待真机”一节）：A02.1、A02.2、A02.3、A03.1、A03.2、A07.10、A07.11、A07.12、A07.13、A08.5、A10.3、D01.32、D02.1、D04.1、H05.1、O05.2、R01.1、R02.2。
- S02.5（第一档、未开始）：`docs/S-质量和验证/S02-真机验证/S02.5-4.0.0构建号5001/`。
- 版本路线：`docs/PLAN.md:43-55`。
- 发布说明：`docs/Y-发布和运营/Y03-发布说明和README/releases/v4.0.0.md`（136 行：开头、“更新（2026-10-02，构建号 5001）”、主要变化、从 3.x 升级、已知问题、以后要做的）；发布页正文多两节“下载哪个”“SHA-256”（`gh --repo wzgrx/pure_live release view v4.0.0`）。
- README：根目录 `README.md`“路线图”（`:383`）、“下载和安装”（`:303`）、“隐私”（`:218`）。

## 3.x 基线

- `git show v3.2.11:MAINTENANCE_POLICY.md` 第 1 节：“每次 Release 必须如实标明本轮实际构建和验证的平台，不以‘源码可编译’代替运行证据”——4.x 沿用这个精神：发布说明的“已知问题”写明哪些还没在真机上走过。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 3.2 节状态、第 11 节发布、第 12 节维护）。
2. 本文件夹的 `README.md`；`docs/Y-发布和运营/README.md`、`Y01`、`Y03` 的子分类说明；`docs/S-质量和验证/S02-真机验证/README.md` 和 `S02.5` 的任务书；`docs/PLAN.md` 第 5 节。

## 范围

- 可以改：本文件夹的文档；`docs/Y-发布和运营/Y03-发布说明和README/releases/v4.0.0.md` 的“以后要做的”（只按现在的事实更新，不改已发布的内容描述）；根目录 `README.md` 的“路线图”（同上）。
- 不能改：`docs/PLAN.md`、`docs/tasks.toml`（写建议，维护者改）；S 组的文档（清单不一致写进报告）；版本号、`assets/version.json`、`assets/releases.json`；GitHub 发布页（改发布页要维护者确认）；签名配置。
- 回复 issue 要维护者确认后再发（用 `gh --repo wzgrx/pure_live issue comment`）。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 写发布后清单 | 本文件夹 `README.md` | 验收 1 |
| 2 | c2 对 4.0.0 补做一遍 | `record.md`；（有改动时）`releases/v4.0.0.md`、`README.md` | 验收 2、3 |

## 测试

- 不涉及代码测试；`python3 tools/docs/docs.py --check`。

## 真机验证

不适用（真机验证在 S02.5）。

## 风险和注意

- 发布说明和发布页是用户看到的，已发布的部分不要改写，只更新“以后要做的”这类会过时的内容；改动在报告里列出来请维护者看。
- `assets/version.json`、`assets/releases.json` 只在发布时改（D-007、D-015），本任务不碰。
- 可能冲突的文件：根目录 `README.md`（Y04.1 也改，加隐私说明）。

## 环境和提交

- 不需要 Flutter；需要 `gh`（一律 `--repo wzgrx/pure_live`）。
- 分支 `ai/Z07.2` 或本机工作区；提交信息以 `[Z07.2]` 开头（英文）；不推 master。
- 提交前：`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：在 `record.md` 写做到清单的第几步、更新登记表的 `next`。

## 报告（中文，简洁）

发布后清单写在哪；4.0.0 包含的任务数；待真机和 S02.5 的差异；PLAN、README、发布说明要改的地方（建议）；没回复的 issue；需要维护者做的事。
