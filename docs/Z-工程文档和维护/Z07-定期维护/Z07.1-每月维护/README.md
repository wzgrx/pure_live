# Z07.1 每月：清理已合并的分支和工作区（含暂停任务确认后的旧工作区）、本机中间文件

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：工程
- 来源：[PROCESS.md](../../../PROCESS.md) 第 12 节维护表“每月”一行（docs v1 新增，D-028 同一批）。
- 相关：Z01.2（同一天做的依赖检查）；PROCESS 第 5.2 节（暂停任务的半成品在哪）；登记表里有 `branch` 的任务（现在 A03.3、A04.1、E06.2）；D-007（删远程分支要维护者确认）

## 目标

每月一次把本机和远程收拾干净：已经合并、没有用的分支和工作区删掉；暂停任务的工作区确认还要不要；本机的日志、构建产物、缓存里能删的删掉，要留的写明为什么。第一次做时把“哪些能删、哪些必须先问”的规则写进本 README，以后每月照做，每次的结果追加到 `record.md`。

## 3.x 和现状

| 方面 | 3.x | 现在（2026-10-07） | 要做到 |
|---|---|---|---|
| 本地分支 | — | 26 个：`master`、`archive/v4`（归档，D-002，要留）、`local-v2-before-cloud`、23 个 `worktree-agent-*` | 只剩 master、归档、正在用的和登记表 `branch` 里写的 |
| 工作区 | — | `~/projects/pure_live/.claude/worktrees/` 下 23 个，约 14 GB；另有 `~/ref/v3ref`（`v3.2.11` 的只读工作区，要留）、`~/ref/pure_live_archive`（`archive/v4`，要留） | 只留正在用的、登记了的和两个参考工作区 |
| 已合并的分支 | — | `git branch --merged master`：`archive/v4` 和 A03.3、A04.1、E06.2 三个暂停任务的分支——它们“已合并”是因为半成品**没提交**，改动在工作区里 | 规则：登记表 `branch` 里有的一律不删，先问维护者 |
| 远程分支 | — | `origin/master`、`origin/archive/v4`、`origin/claude/nice-bell-erx7d9`（2026-10-02 云端会话留下的，D-014 后不用）；`upstream/master`（W01 用） | 没用的远程分支经维护者确认后删 |
| 本机中间文件 | — | `~/ref/notes/` 97 个日志（6.5 MB）；`~/.gradle-purelive-v4/` 16 GB；`~/.cache/pure_live/` 73 MB（FFmpeg 包缓存，要留）；各工作区 `apps/pure_live/build/`；`~/ref/release/`（4.0.0 两次发布的安装包，要留） | 删超过一个月的日志和不用的构建产物；缓存按需 |

## 方案

- c1 列清单：`git worktree list`、`git branch -vv`、`git branch --merged master`、`git branch -r`、各工作区 `git -C <工作区> status --short | wc -l`（有没有未提交的改动）和最后提交日期；对照登记表的 `branch` 字段和 STATUS 的“暂停”“开发中”。
- c2 定规则（第一次做时写进本 README）：
  - 能直接删：已合并进 master、工作区没有未提交改动、登记表没提到、不是当前会话在用（`locked` 的不动）的代理工作区和分支（`git worktree remove`、`git branch -d`，不用 `-D`）。
  - 必须先问维护者：登记表 `branch` 里写的（暂停任务的半成品）；有未提交改动的；没合并的（例如 `worktree-agent-ab1a5d264e55120e5` 里没合并的 Linux 桌面外壳，X02.1 要用）；任何远程分支。
  - 永远不删：`master`、`archive/v4`、`~/ref/v3ref`、`~/ref/pure_live_archive`、`~/ref/release/`、`~/.cache/pure_live/`、`~/.android-purelive/`（签名密钥）。
- c3 清理：按规则删，删之前把清单和理由写进 `record.md`。
- c4 本机中间文件：`~/ref/notes/` 超过一个月的日志移走或删；`apps/pure_live/build/` 在不用的工作区里随工作区删除；`~/.gradle-purelive-v4/` 只在磁盘紧张时 `gradle --stop` 后清 `caches/`（下次构建会重新下载，较慢）。
- c5 收尾：`python3 tools/docs/docs.py --check`；登记表 `branch` 写的工作区都还在。

## 验证

- 不涉及自动测试。证据是 `record.md` 里清理前后的清单（分支数、工作区数、占用空间）。
- 真机：不适用。

## 留下的问题

- 还没做过。第一次做时 A03.3、A04.1、E06.2 的三个工作区要请维护者决定：保留（继续做）、把半成品提交到 `wip/<任务编号>` 分支推上去（PROCESS 第 5.2 节第 4 条）、还是放弃。
- `worktree-agent-ab1a5d264e55120e5`（`0dc0df759`，2026-10-01）里是没合并的 M12.6 Linux 桌面外壳，登记表没有记；X02.1 开工前不能删，建议维护者在 X02.1 的 `branch` 或 `note` 里登记。
