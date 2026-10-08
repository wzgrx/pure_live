# Z06.4 修坏的文档路径，补上 docs.py 的检查漏洞和测试：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区 `ai/Z06.4`（从 master `fc9ee0ea4` 开始）
- 任务书：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 路径在 `/` 处断行 | 做了 | `check_code_paths`：匹配到的路径后面紧跟 `/` 加换行就报“在注释里换行了，写成一行完整路径” |
| c2 `fixtures/` 加进检查 | 做了 | 只查 `fixtures/` 下的 `.md`；多查出 3 个弹幕向量说明里的 `docs/modules/M5.*` |
| c3 `test_docs.py` | 做了 | 在临时目录里造一个小仓库跑 `docs.py`：生成后通过、生成区被手改、链接找不到、代码路径不存在、路径断行、样本说明、子分类文件夹名、没登记的任务文件夹，共 8 个 |
| c4 16 处注释和 `build.gradle.kts` | 做了 | 每处换成新位置的完整路径（单独一行或括号里一行写完），旧的 U、B、M 编号去掉；`popups_test.dart` 删掉后半截；`dialog_buttons_theme.dart` 指向 `docs/specs/UI.md` 第 7 节（弹窗和面板）；签名注释指向 Y01 |
| c5 `fixtures/README.md` | 做了 | ADR 0009、`spec/sites/` 改成 ENGINEERING 第 3 节“安全”、`check_fixtures.py` 和 E 组各平台任务；`test/fixtures_expected/` 写明在归档标签 `v4-archive`（master 上没有）；`tools/live_cli` 的部分 E07.1 已经改过 |

## 测试

- c1 做完、c4 之前：`docs.py --check` 报 20 个问题（16 处断行 + 4 处样本说明），和 Z06 说明的表一致。
- 之后 0 个问题；`python3 -m unittest discover -s tools/gate/tests` 31 个全过（新增 8 个）。
- 不需要真机。
