# Z02.3 门禁默认模式在只改文档、样本、脚本时也跑仓库级检查

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：工程
- 来源：docs v2 写作时发现（[Z02 子分类说明](../README.md)的“已知问题”）
- 相关：[Z02.2](../Z02.2-门禁加文档检查/README.md)（文档检查）、[Z06.4](../../Z06-文档和登记表/Z06.4-修坏的文档路径/README.md)、`docs/specs/ENGINEERING.md` 第 3 节、D-007

## 目标

只改 `docs/`、`fixtures/`、`tools/` 的脚本时，`tools/gate/gate.sh`（不带参数）和 Claude Code 的 Stop 钩子（`--hook`）也会跑仓库级的四项检查：依赖方向、样本隐私、界面结构、文档。现在只有 `--all` 会跑，日常改文档要等推送前才发现问题。

## 3.x 和现状

| 方面 | 现在（文件:行） | 要做到 |
|---|---|---|
| 选成员 | `tools/gate/gate.sh:45-57`：对比 `origin/master` 的改动，`pubspec`、`toolchain.env`、`gate.sh`、`check_deps.py` 变了选全部成员，否则只选有改动的成员 | 不变 |
| 提前退出 | `:58-62`：一个成员都没选中时直接 `exit 0`（钩子模式不出声），后面的 `dependency direction`、`fixture privacy`、`ui structure`、`docs`（`:113-116`）都不跑 | 没选中成员但改了 `docs/`、`fixtures/`、`tools/`、根目录的 `README.md`、`AGENTS.md`、`CLAUDE.md` 时，只跑这四项再退出 |
| 钩子 | `.claude/settings.json:14`：Stop 时 `gate.sh --hook`，超时 1800 秒 | 只改文档时四项检查几秒钟，钩子照样适用；失败时 exit 2 |
| 工具自己的测试 | `:129-131`：`gate tests` 只在 `--all` 跑 | 改了 `tools/gate/` 或 `tools/docs/` 时默认模式也跑 |

## 方案

- c1：把“没有成员改动”的分支改成：算出 `repo_changed`（上面的路径前缀），为真时跳过依赖安装和成员循环，只跑四项检查；为假时照旧退出。
- c2：`tools/gate/` 或 `tools/docs/` 有改动时加跑 `gate tests`。
- c3：`docs/specs/ENGINEERING.md` 第 3 节和 `gate.sh` 开头的用法注释写明默认模式包括这些检查。

## 验证

- 手动：只改一个 `docs/` 下的 md（放一个坏链接）跑 `tools/gate/gate.sh`，应该报 `gate: FAIL docs`；改回后 `gate: passed`；什么都不改时仍然输出 `gate: no workspace member changed` 并退出 0。
- `--all` 的结果不变。
- 不需要真机。

## 留下的问题

- 无。
