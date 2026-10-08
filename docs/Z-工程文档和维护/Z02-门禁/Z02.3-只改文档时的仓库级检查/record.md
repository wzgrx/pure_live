# Z02.3 门禁默认模式在只改文档、样本、脚本时也跑仓库级检查：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区 `ai/Z02.3`（从 master `a12fbd80d` 开始）
- 任务书：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 没选中成员但改了文档等 | 做了 | `gate.sh`：`repo_changed`（`docs/`、`fixtures/`、`tools/`、根目录 `README.md`、`AGENTS.md`、`CLAUDE.md`）；没有成员时不装依赖，只跑四项；什么都没改时说“nothing to check”退出 |
| c2 门禁自己的测试 | 做了 | 改了 `tools/gate/` 或 `tools/docs/` 时默认模式和钩子也跑 `gate tests` |
| c3 文档 | 做了 | `gate.sh` 开头的用法注释；`docs/specs/ENGINEERING.md` 第 3 节“门禁” |

## 测试

在 `origin/master` 的临时工作区里放新 `gate.sh`（标成未改动，免得它自己触发全部成员）：

- 什么都没改：`gate: nothing to check …`，退出 0。
- 只改 `docs/PLAN.md`：四项检查，约 5 秒，`gate: passed (changed, 0 members)`。
- 改 `tools/docs/docs.py`：四项加 `gate tests`。
- 钩子模式、文档里有坏链接：退出 2。
- 不需要真机。
