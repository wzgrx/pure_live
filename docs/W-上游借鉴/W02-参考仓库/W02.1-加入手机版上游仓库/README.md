# W02.1 把手机版 pure_live 加进参考仓库：主仓库远程 upstream（不拉标签）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（完成，2026-10-03）
- 类型：工程
- 来源：D-027（2026-10-03）定了每周对照上游的五个仓库；之前参考仓库只有电视版、media_core、flame_barrage、flv_lzc 四个（`~/ref/` 下），手机版上游没有本机副本；和第一次对照 [W01.1](../../W01-定期对照/W01.1-2026-10-03上游对照/README.md) 同一天做
- 相关：决定 D-027、D-001；规范 [specs/ENGINEERING.md](../../../specs/ENGINEERING.md) 第 5 节（参考仓库表加了一行）

## 目标

能在本机直接对照手机版上游在 `v3.2.11` 之后的提交：`git log v3.2.11..upstream/master`、`git show <上游提交>`，不用另外克隆一份几百 MB 的仓库。

## 3.x 和现状

| 方面 | 之前 | 之后 |
|---|---|---|
| 手机版上游 | 没有本机副本；只能在 GitHub 网页上看 | 主仓库加远程 `upstream` = `git@github.com:liuchuancong/pure_live.git`，`fetch = +refs/heads/*:refs/remotes/upstream/*` |
| 标签 | — | `remote.upstream.tagopt = --no-tags`：上游的标签不拉进来（上游有和本仓库同名的 `v3.x` 标签，可能指向不同的提交；本仓库的 `v3.2.11`、`v4.0.0` 不能被覆盖） |
| 共享历史 | — | 4.x 是在 3.x 的代码上重构的（D-001），和上游共享到 `v3.2.11` 为止的历史，所以只多拉上游自己的提交 |

## 结果

- 加了远程、拉了一次：`upstream/master` = `20817480d`（2026-10-03 00:17）；`git rev-list --count v3.2.11..upstream/master` = 271（W01.1 看的就是这 271 个）。
- [specs/ENGINEERING.md](../../../specs/ENGINEERING.md) 第 5 节的参考仓库表加了手机版上游一行（“主仓库的远程 `upstream`，不拉标签”）。
- 没有提交号：远程的配置在 `.git/config`，不进仓库；文档的改动随 W01.1 的提交 `d54772d54`。

## 验证

- 2026-10-07 核对：`git remote -v` 有 `upstream`；`git config --get-all remote.upstream.tagopt` 是 `--no-tags`；`git log -1 upstream/master` 是 `20817480d`；`git rev-list --count v3.2.11..upstream/master` 是 271。

## 留下的问题

- `upstream` 的推送地址也指向上游仓库：建议 `git remote set-url --push upstream no_push`，防止误推（W02 子分类说明的已知问题，维护者做）。
- 远程配置只在这台机器上：换机器要重新加（命令：`git remote add upstream git@github.com:liuchuancong/pure_live.git && git config remote.upstream.tagopt --no-tags && git fetch upstream master`）；没有 ssh 密钥时用 https 地址。
