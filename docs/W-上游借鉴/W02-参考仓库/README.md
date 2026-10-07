# W02 参考仓库

上游和参考仓库的清单、本机副本放在哪、怎么更新、许可证和借鉴规则。W01 每周对照时从这里拿仓库。

## 范围

- 包括：
  - 五个上游仓库（liuchuancong）和之前从零写的 v4 存档：地址、许可证、用途、本机位置、怎么更新。
  - 主仓库的远程 `upstream`（手机版上游，不拉标签）。
  - 3.x 的只读副本 `~/ref/v3ref`（对照用）。
  - 借鉴规则：AGPL-3.0 注明来源仓库和提交；MIT 保留版权声明；不照搬架构（PROCESS 第 9 节第 5 条）。
- 不包括（归哪里）：
  - 每次对照的内容和结论 → [W01](../W01-定期对照/README.md)。
  - 设计参考（`~/ref/design/`，评审页导出用）→ A 组和 `tools/ui/`。
  - 发布的安装包副本（`~/ref/release/`）→ Y01、S04。

## 现状：做到哪、怎么工作的

| 仓库 | 许可证（本机 `LICENSE` 核对） | 本机位置 | 当前（2026-10-07） | 用途 |
|---|---|---|---|---|
| [liuchuancong/pure_live](https://github.com/liuchuancong/pure_live)（手机和桌面版） | AGPL-3.0 | 主仓库远程 `upstream`（`git@github.com:liuchuancong/pure_live.git`，`tagopt = --no-tags`） | `upstream/master` = `20817480d`（2026-10-03），`v3.2.11` 之后 271 个提交 | 3.x 的上游，在 `v3.2.11` 上接着开发：平台、录制、播放的修复 |
| [liuchuancong/pure_live_TV](https://github.com/liuchuancong/pure_live_TV)（电视版） | AGPL-3.0 | `~/ref/pure_live_TV`（`main`） | `37660afc`，最后拉取 2026-10-03 00:21 | 电视端的代码基础（X03、A17）；平台层的新修复（E、D），例如 Kick、哔哩哔哩多账号 |
| [liuchuancong/media_core](https://github.com/liuchuancong/media_core)（播放核心） | AGPL-3.0 | `~/ref/media_core`（`main`） | `69af860`，同上 | 播放器会话、恢复、池化、系统媒体控制、画中画（G、N、C02） |
| [liuchuancong/flame_barrage](https://github.com/liuchuancong/flame_barrage)（弹幕引擎） | MIT（Copyright (c) 2026 bobobo） | `~/ref/flame_barrage`（`main`） | `3eddae8`，同上 | 弹幕渲染和交互（D03、A08） |
| [liuchuancong/flv_lzc](https://github.com/liuchuancong/flv_lzc) | MIT（Copyright (c) 2019 Befovy） | `~/ref/flv_lzc`（`main`） | `162030d`，同上 | FLV 和 H.265 的低延迟经验（G） |
| 之前从零写的 v4（分支 `archive/v4`、标签 `v4-archive`） | AGPL-3.0 | 主仓库；`~/ref/pure_live_archive`（副本） | — | 已写好并测过的各包实现，按任务借鉴（D-002） |
| 3.x（标签 `v3.2.11`） | AGPL-3.0 | `~/ref/v3ref`（只读副本）；主仓库 `git show v3.2.11:<路径>` | — | 功能基线（D-001） |

- 完成的任务：[W02.1](W02.1-加入手机版上游仓库/README.md)（2026-10-03，把手机版加进来：主仓库远程 `upstream`、不拉标签）。
- 更新方式：主仓库 `git fetch --no-tags upstream master`；`~/ref/<仓库>` 各自 `git pull --ff-only`（W01 每周做）。

## 代码地图

| 位置 | 职责 |
|---|---|
| 主仓库 `.git/config` 的 `[remote "upstream"]` | 手机版上游：`fetch = +refs/heads/*:refs/remotes/upstream/*`、`tagopt = --no-tags` |
| `~/ref/pure_live_TV`、`media_core`、`flame_barrage`、`flv_lzc` | 四个上游的本机克隆（`origin` 指向 GitHub 的 https 地址） |
| `~/ref/v3ref` | 3.x 的只读副本 |
| `~/ref/pure_live_archive` | 之前从零写的 v4 的副本 |
| `~/ref/notes/` | 本机笔记（门禁日志、旧提示词；不进仓库） |
| [specs/ENGINEERING.md](../../specs/ENGINEERING.md) 第 5 节 | 参考仓库的正式清单和许可证 |

## 3.x 基线

- 3.x 本身就在主仓库（标签 `v3.2.11`），手机版上游是它的延续；4.x 不照搬上游在 3.x 之后的新架构（D-001），只借鉴修复。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| `upstream` 的推送地址也是上游仓库（`git remote -v` 两行都是 `liuchuancong/pure_live`） | 主仓库 `.git/config` | 误敲 `git push upstream` 会往别人的仓库推（没有权限会被拒，但不该发生） | 建议维护者执行 `git remote set-url --push upstream no_push`（写进报告） |
| [specs/ENGINEERING.md](../../specs/ENGINEERING.md) 第 5 节写“每次对照的结论写进 Z 的上游对照（例如 `upstream-2026-10-03.md`）” | 规范 | 和 PROCESS 第 9 节、W01 不一致（对照记录现在是 W01.n） | 写进报告，建议改成“写进 W01 的对照任务” |
| 本机副本 2026-10-03 之后没拉过 | `~/ref/*/.git/FETCH_HEAD` | 看到的不是最新 | W01.2 |
| 四个副本的 `origin` 是 https 地址，没有登录也能拉；主仓库的 `upstream` 是 ssh 地址 | — | 没有 ssh 密钥的机器拉不到手机版上游 | 换机器时改成 https（只读） |

## 相关决定和规范

- D-027（每周对照上游）、D-002（v4 存档只借鉴工程工具和写好的包）、D-001（3.x 是基线）。
- [PROCESS.md](../../PROCESS.md) 第 9 节第 5 条（借鉴代码的许可证规则）；[specs/ENGINEERING.md](../../specs/ENGINEERING.md) 第 5 节。

## 测试和验证

- 没有测试；检查方法：`git remote -v`、`git config --get remote.upstream.tagopt`（应是 `--no-tags`）、`git rev-list --count v3.2.11..upstream/master`；`~/ref/<仓库>` 里 `git status` 干净、`git log -1`。

## 路线

1. 维护者关掉 `upstream` 的推送地址；ENGINEERING 第 5 节改成指向 W01。
2. 有新的参考仓库（例如上游拆出新包）时在这里登记 W02.n：加进清单、写许可证和用途、更新 ENGINEERING 第 5 节。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [W 上游借鉴](../README.md)。

- 代码：`~/ref/`、主仓库的远程 `upstream`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| W02.1 | 把手机版 pure_live 加进参考仓库：主仓库远程 upstream（不拉标签） | 工程 | 完成 | 2026-10-03 | — | [设计或说明](W02.1-加入手机版上游仓库/README.md) |

<!-- docs:生成结束 -->
