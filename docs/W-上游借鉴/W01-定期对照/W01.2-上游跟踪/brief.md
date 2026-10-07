# W01.2 上游跟踪：任务书

## 背景

- 来源：D-027（2026-10-03，用户：“新增参考借鉴上游的模块”）：每周对照一次上游（liuchuancong 的五个仓库），4.x 也有的问题开到目标组，可借鉴的新功能进 V01。
- 现象：只在 2026-10-03 对照过一次（W01.1）；之后一直没拉取（主仓库 `upstream/master` 停在 `20817480d`，`~/ref/` 四个仓库的 `FETCH_HEAD` 停在 2026-10-03 00:21）。上游在那之前一天就有几十个提交，W01.1 从里面找出了 5 个 4.x 也有的问题（其中一个第一档：H01.5 录制无限重试）。
- 为什么是第二档：不对照就会错过上游已经修好的同类问题；每次约 1 小时，规模小。
- 已经做过的：W02.1（主仓库加远程 `upstream`，不拉标签）、W01.1（第一次对照，写了格式）。

## 目标和验收

1. 拉取完成：主仓库 `upstream/master` 和 `~/ref/` 四个仓库都是本周的最新。
2. 新登记一个对照任务 W01.n（维护者加登记表；执行者在报告里给出 `id`、`title`、`date`），文件夹 `docs/W-上游借鉴/W01-定期对照/W01.n-<日期>上游对照/`，README 照 W01.1 的格式：
   - “看了哪些”表：每个仓库的起止提交（从 W01 子分类说明“上次看到的提交”接着）和提交数；
   - 四类结论：4.x 也有的问题（每条写上游提交、问题、4.x 的位置文件:行、建议的任务）、可以借鉴的新功能（建议的 V01 提议）、已经有的（4.x 的位置）、不适用（原因）；
   - “结果”“验证”“留下的问题”三节。
3. 每条“4.x 也有的问题”在报告里给出建议登记的任务（目标组、标题、规模、档位、`from = "上游 <仓库> <提交>"`）；可借鉴的新功能给出 V01 提议的标题和来源。
4. W01 子分类说明的“上次看到的提交”表更新成这次的终点。
5. 第一次按本流程做完后，在报告里写一句节奏建议（每周一？多长时间），维护者决定后本任务改“完成”。

## 现状（读代码得出）

- 主仓库的远程：`upstream` = `git@github.com:liuchuancong/pure_live.git`，`remote.upstream.tagopt = --no-tags`（上游的标签和 4.x 的 `v4.0.0` 等冲突，不拉）；`upstream/master` 现在在 `20817480d`（2026-10-03 00:17，“chore(architecture): 校验脚本成为 CI 门禁”）；`git rev-list --count v3.2.11..upstream/master` 是 271。
- 本机副本（各自 `main`）：`~/ref/pure_live_TV`（`37660afc`）、`~/ref/media_core`（`69af860`）、`~/ref/flame_barrage`（`3eddae8`）、`~/ref/flv_lzc`（`162030d`）；许可证：pure_live、pure_live_TV、media_core 是 AGPL-3.0，flame_barrage、flv_lzc 是 MIT（[specs/ENGINEERING.md](../../../specs/ENGINEERING.md) 第 5 节）。
- 4.x 里对应的位置：平台 `packages/live_core/lib/src/sites/`、弹幕 `packages/live_danmaku/lib/src/sites/`、播放 `packages/live_player/`、录制 `packages/live_record/`、应用 `apps/pure_live/lib/`；3.x 的原代码 `git show v3.2.11:lib/...` 或 `~/ref/v3ref/lib/`。
- 上游不适用的大方向（W01.1 已判断，下次不用再分析）：上游把播放换成 media_core（kernel player）以及由此修的一串问题；Windows 画中画和原生窗口；点播、音乐、壁纸、电视样式（等 X 组）；Anime4K（V04.2）。

## 3.x 基线

- 手机版上游的提交都在 `v3.2.11` 之后（同一条线），所以对照时先 `git show <上游提交>` 看改了 3.x 的哪个文件，再 `git show v3.2.11:<那个文件>` 看原来的样子，再找 4.x 里对应的实现（4.x 的文件和 3.x 不一一对应，用功能清点 `docs/inventory/FEATURES.md` 的“3.x 位置 → 4.x 位置”查）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md` 第 9 节（上游借鉴）、第 6 节（新功能进 V01）。
2. `docs/W-上游借鉴/W01-定期对照/README.md`（流程、上次看到的提交）；`W01.1-2026-10-03上游对照/README.md`（格式和上次的结论）。
3. `docs/specs/ENGINEERING.md` 第 5 节（参考仓库和许可证）。

## 范围

- 可以改：`docs/W-上游借鉴/W01-定期对照/` 下的新对照文件夹、W01 子分类说明的“上次看到的提交”表；本机的 `upstream` 远程跟踪分支和 `~/ref/` 下的副本（只拉取）。
- 不能改：任何代码（借鉴的修复由目标组任务做）；`docs/tasks.toml`（维护者登记）；其他组文档；上游仓库（不推送，`upstream` 只读）。
- 不能做：`git fetch` 拉上游的标签（会和 4.x 的标签冲突）；在 `~/ref/` 的副本里提交或改文件；把上游的代码整段复制进对照记录。

## 方案和阶段

一次对照的步骤（约 1 小时）：

| 步 | 做什么 | 命令 | 怎么算做完 |
|---|---|---|---|
| 1 拉取 | 手机版上游；其余四个 | 主仓库根目录：`git fetch --no-tags upstream master`；`for r in pure_live_TV media_core flame_barrage flv_lzc; do git -C ~/ref/$r pull --ff-only; done` | 没有报错；`~/ref/*/.git/FETCH_HEAD` 是今天 |
| 2 列提交 | 从上次看到的接着列 | `git log --oneline --no-merges 20817480d..upstream/master`；`git -C ~/ref/pure_live_TV log --oneline 37660afc..HEAD`（media_core 从 `69af860`、flame_barrage 从 `3eddae8`、flv_lzc 从 `162030d`） | 每个仓库的提交数记下 |
| 3 筛 | 只看修复（`fix`）和新功能（`feat`）；`chore`、`docs`、`style`、纯电视界面的跳过（记数量） | `git show --stat <提交>`、`git show <提交> -- <文件>` | 留下要看的提交清单 |
| 4 对照 | 每条在 4.x 里找对应位置（文件:行），判断四类之一；“4.x 也有”的写清根因 | `grep -rn` 4.x 代码；`git show v3.2.11:<路径>` | 每条都有结论 |
| 5 写记录 | 新文件夹的 README（照 W01.1）；更新 W01 子分类说明的“上次看到的提交” | — | `python3 tools/docs/docs.py --check` 通过（新任务没登记前会报文件夹和登记表不一致，在报告里说明，由维护者登记后再跑） |
| 6 报告 | 建议登记的任务、V01 提议 | — | 报告发给维护者 |

## 测试

- 本任务不写测试。“4.x 也有的问题”开出的修复任务，任务书里要写“先写改之前会失败的测试”。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 无（对照不需要真机） | — |

## 风险和注意

- **只读上游**：`upstream` 的推送地址也是上游仓库，绝对不要 `git push upstream`（建议先 `git remote set-url --push upstream no_push`）；`~/ref/` 下的副本只 `pull --ff-only`。
- **不拉标签**：上游的 `v3.x` 标签和本仓库的同名标签可能指向不同的提交；`remote.upstream.tagopt` 已设 `--no-tags`，命令里再写一遍 `--no-tags`。
- **许可证**：借鉴 AGPL-3.0 的代码要在提交里注明来源仓库和提交；MIT 的保留版权声明（对照记录里只写思路，不贴代码）。
- **不照搬架构**：上游的 media_core 播放层、GetX 路由等和 4.x 不同，借鉴的是“修了什么问题、怎么判断”，不是代码结构。
- 工作区隔离：在 git worktree 里做的话，`git fetch upstream` 会更新共享的远程跟踪分支（所有工作区都看得到），这是想要的；不要在 worktree 里改 `~/ref/`。

## 环境和提交

- 本机主仓库或工作区；只提交文档：提交信息 `docs(W01.n): upstream review of <日期>`（英文），结尾照惯例加署名；不推 master（维护者合并）。
- 提交前：`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：已经对照完的仓库先写进对照记录并提交，在 README 末尾写“停在哪”（哪个仓库对照到哪个提交）；“上次看到的提交”只更新已经对照完的仓库。

## 报告（中文，简洁）

每个仓库看了多少提交（范围）；4.x 也有的问题（上游提交、4.x 位置、建议的任务：组、标题、规模、档位、`from`）；可借鉴的新功能（建议的 V01 标题）；已经有的、不适用的数量；节奏建议；需要维护者决定的。
