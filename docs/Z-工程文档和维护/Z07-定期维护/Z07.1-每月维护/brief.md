# Z07.1 每月维护：任务书

## 背景

- 来源：[PROCESS.md](../../../PROCESS.md) 第 12 节“每月：清理已合并的分支和工作区、确认暂停任务的旧工作区还要不要、本机中间文件”。docs v1（2026-10-03）登记。
- 现象：本机仓库已经有 26 个本地分支、23 个代理工作区（约 14 GB），多数是做完的；三个暂停任务（A03.3、A04.1、E06.2）的半成品在工作区的未提交改动里，它们的分支看起来“已合并”；远程有云端会话留下的 `claude/nice-bell-erx7d9`；`~/.gradle-purelive-v4/` 16 GB。
- 为什么现在做：第二档；工作区越积越多，分不清哪些有用，按“已合并就删”随手清理会把暂停任务的半成品删掉。
- 已经做过的：无。

## 目标和验收

1. `record.md` 有清理前的完整清单：每个本地分支和工作区的最后提交日期、是否合并进 master、有没有未提交改动、登记表里有没有提到、结论（删 / 留 / 问维护者）。
2. 本文件夹 `README.md` 的“方案”下加一节“每月步骤和规则”（能直接删、必须先问、永远不删），以后照做。
3. 只删“能直接删”的；“必须先问”的列给维护者，维护者回答后再处理。
4. 清理后 `python3 tools/docs/docs.py --check` 没有新问题；登记表 `branch` 写的工作区都还在；`git worktree list` 里没有失效的条目（`git worktree prune` 只清已经不存在的目录）。
5. `record.md` 写清理前后的分支数、工作区数、占用空间。

## 现状（2026-10-07 读出，开工时重新读）

- `git worktree list`：主仓库 `~/projects/pure_live`（master）、23 个 `.claude/worktrees/agent-*`（其中正在被会话使用的标着 `locked`）、`~/ref/pure_live_archive`（`archive/v4`）、`~/ref/v3ref`（`v3.2.11`，分离头）。
- `git branch --merged master`：`archive/v4`、`worktree-agent-a39fe9339ffb138a9`（A04.1，“做了大半，未提交”）、`worktree-agent-a770fdd52c3109749`（A03.3，“刚开始，未提交”）、`worktree-agent-af6f5e80c4e19804f`（E06.2，“半成品，未提交”）。
- 没合并、有内容的例子：`worktree-agent-ab1a5d264e55120e5`（`0dc0df759`，2026-10-01，M12.6 Linux 桌面外壳，36 个文件，X02.1 要用）；`worktree-agent-a3224b95b79a5b0be`（`e6dd43c8f`，M14.3 的 WIP）、`worktree-agent-a38e678e236092db4`（`f712f2bd9`，M14.4 的 WIP）、`worktree-agent-af79805552a6c7d0e`（`69f12f418`，A17.2 的 `note` 里提到的电视半成品）。
- `git branch -r`：`origin/master`、`origin/archive/v4`、`origin/claude/nice-bell-erx7d9`（`4855570b0`，2026-10-02）、`upstream/master`。
- 本机：`~/ref/notes/`（97 个日志）、`~/.gradle-purelive-v4/`（16 GB）、`~/.cache/pure_live/`（73 MB）、`~/ref/release/v4.0.0/`、`v4.0.0-5001/`。

## 3.x 基线

- 不适用（流程任务）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5.2 节停下时半成品放哪、第 12 节维护、第 14 节规则）。
2. 本文件夹的 `README.md`；`docs/Z-工程文档和维护/Z07-定期维护/README.md`；`docs/STATUS.md` 的“暂停”“正在做的”两节；`docs/tasks.toml` 里所有 `branch`、`note` 字段（`grep -n 'branch =\|note =' docs/tasks.toml`）。
3. Claude Code 的工作区规则：`git stash` 是所有工作区共用的，不要用裸的 `git stash`/`git stash pop`。

## 范围

- 可以：删除符合“能直接删”规则的本地分支（`git branch -d`）和工作区（`git worktree remove <路径>`，不加 `--force`）；`git worktree prune`；删 `~/ref/notes/` 里超过一个月的日志；本文件夹的文档。
- 不能（必须先问维护者）：任何远程分支（`git push origin --delete` 要维护者确认，D-007）；登记表 `branch`、`note` 里提到的分支和工作区；有未提交改动或没合并的；`locked` 的工作区；`git branch -D`、`git worktree remove --force`。
- 永远不删：`master`、`archive/v4`、`~/ref/v3ref`、`~/ref/pure_live_archive`、`~/ref/release/`、`~/.cache/pure_live/`、`~/.android-purelive/`（签名密钥，D-006）、`~/tools/`。
- 不改：任何代码、`docs/tasks.toml`（`branch` 字段要改时写进报告）。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 列清单、c2 定规则 | `record.md`、本文件夹 `README.md` | 验收 1、2；“问维护者”的清单交给维护者 |
| 2 | c3 删“能直接删”的、c4 本机中间文件、c5 收尾；维护者回答后处理“问维护者”的 | （本机，不改仓库文件）`record.md` | 验收 3～5 |

## 测试

- 不涉及代码测试。清理后跑 `python3 tools/docs/docs.py --check`，并 `git worktree list` 核对。

## 真机验证

不适用。

## 风险和注意

- **最大的坑**：暂停任务的分支“已合并”但工作区里有未提交的半成品；`git worktree remove` 遇到未提交改动会拒绝（不要加 `--force`），这是保护，不是障碍。
- 另一个会话正在用的工作区标着 `locked`，不要动。
- `git branch -d` 拒绝删没合并的分支时，不要改成 `-D`，列进“问维护者”。
- 清 Gradle 缓存前先 `gradle --stop`（或 `./gradlew --stop`），并且不要在门禁或构建运行时清。
- 删远程分支会影响别人，必须维护者确认。

## 环境和提交

- 在主仓库 `~/projects/pure_live` 里操作（工作区的增删要在主仓库做）。
- 文档改动：分支 `ai/Z07.1` 或本机工作区；提交信息以 `[Z07.1]` 开头（英文）；不推 master。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：清单写到哪、删了哪些写进 `record.md`；更新登记表的 `next`。删除做到一半停下也安全（每个删除都是独立的）。

## 报告（中文，简洁）

清理前后的分支数、工作区数、占用空间；删了哪些；“问维护者”的清单（每个写建议）；发现登记表里 `branch` 不准的地方；以后每月的步骤写在哪。
