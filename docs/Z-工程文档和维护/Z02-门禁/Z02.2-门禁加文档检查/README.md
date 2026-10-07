# Z02.2 门禁加“文档”检查：生成文件是否最新、链接和代码里的文档路径是否有效

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：工程
- 来源：2026-10-02 文档整理（Z06.1）时发现旧文档里四套编号、手写的状态互相对不上，代码注释里引用的文档路径大量失效；整理成一个登记表加生成的索引以后，需要门禁保证“生成的东西不手改、链接和路径不坏”。
- 旧编号：T00b.2
- 相关：Z06.1（同一个提交：docs 重写为 20 组、`tools/docs/docs.py`）；Z06.2（docs v1，加了文件夹名检查）；[PROCESS.md](../../../PROCESS.md) 第 13 节（链接和代码注释里的文档路径）

## 目标

推送前的门禁多一步“docs”：`docs/tasks.toml` 改了却没重新生成、文件夹名和登记表不一致、文档里的相对链接打不开、代码注释里写的 `docs/...` 路径不存在，任何一条都让门禁失败。

## 3.x 和现状

| 方面 | 3.x | 加之前（4.x，到 2026-10-02） | 加之后（`c613b73f9`） | 现在 |
|---|---|---|---|---|
| 文档的进度 | 手写在各报告里 | 四份手写的 `TASKS.md`（模块、界面、功能、4.0.x），状态互相对不上 | 一个登记表 `docs/tasks.toml`，STATUS、TASKS、MAPPING 和组、子分类的 README 由脚本生成，门禁查是否最新 | 同左；v1（`9dfbb424d`）加了文件夹名检查，v2 骨架（`64046b98b`）把组和子分类 README 分成手写部分 + 生成区 |
| 链接 | 不检查 | 不检查 | `docs/` 下全部 `.md` 的相对链接（模板除外） | 同左 |
| 代码里的文档路径 | 不检查 | 不检查（整理时发现很多失效） | `apps/`、`packages/`、`tools/` 下 `.dart`、`.py`、`.sh`、`.kt`、`.md`、`.yaml`、`.json`、`.kts`、`.xml` 文件，加根目录的 `README.md`、`AGENTS.md`、`CLAUDE.md`、`toolchain.env`、`pubspec.yaml` 里出现的 `docs/...` 路径都要存在 | 同左；有漏洞（见“留下的问题”） |

## 结果

- 提交：`c613b73f9`（北京时间 2026-10-03 00:13，登记表写 10-02，和 Z06.1 是同一个提交）：新文件 `tools/docs/docs.py`（当时 493 行，现在 571 行）；`tools/gate/gate.sh` 加一行 `step "docs" python3 tools/docs/docs.py --check`（现在第 116 行）。
- 检查的内容（`docs.py --check`，`main` 在 `:545`）：
  - 登记表本身（`Project.validate`，`:155`）：编号格式、组的字母不用 B、F、M、P、T、U、状态和类型在允许的列表里、规模和档位的取值、没完成的要写档位、完成和待真机要写日期、暂停要写 `next`、`done` 不超过阶段数、`to` 指向的任务存在；文件夹名等于“编号-去掉空格括号的标题”（组、子分类）；`docs/?-*/???-*/` 下每个任务文件夹都登记了。
  - 生成的文件是不是最新（`generated` `:484`，和磁盘比较）。
  - 链接（`check_links` `:508`）：`](...)` 里的相对路径都存在，模板文件夹跳过。
  - 代码里的文档路径（`check_code_paths` `:523`）：正则 `PATH_RX`（`:502`）在上面列的文件里找 `docs/...`，含 `<` 的（占位）和以 `.`、`-` 结尾的跳过；`docs.py` 自己跳过（它有意写着旧文档名）。
- 测试：没有为 `docs.py` 写测试（`tools/gate/tests/` 只有另外三个检查脚本的测试）。

## 验证

- 门禁 `bash tools/gate/gate.sh --all` 日志里有 `gate: ok   docs`。
- 真机：不适用（工程任务）。

## 留下的问题

- **换行的路径漏检**：`PATH_RX`（`:502`）按字符匹配，注释里路径换行时只匹配到行尾，末尾的 `/` 被正则回退掉，剩下的 `docs/README.md`、`docs/TASKS.md` 恰好存在，于是 16 处坏路径没被拦住，例如 `apps/pure_live/lib/platform/display_mode.dart:140-141` 的 `docs/README.md/` + 下一行 `research-smoothness-2026-10-02.md`（原文是 `docs/4.0.x/research-smoothness-2026-10-02.md`，`c613b73f9` 改路径时把 `docs/4.0.x/` 换成了 `docs/README.md/`；现在应该指向 V03.2 的文件夹）。清单和处理见 [Z06 子分类说明](../../Z06-文档和登记表/README.md)“已知问题”。
- **不查的文件**：`fixtures/README.md` 不在 `CODE_DIRS`（`apps`、`packages`、`tools`）和根目录文件列表里，它写的 `docs/adr/0009-fixture-format.md`、`docs/modules/M4.*.md` 都不存在，门禁看不到（Z06 已知问题）。
- **不查章节号**：代码里的“`docs/specs/ENGINEERING.md §9`”（`apps/pure_live/android/app/build.gradle.kts:9`）指向不存在的第 9 节（ENGINEERING 只有 7 节），脚本只查文件存在（Z06 已知问题）。
- `docs.py` 没有测试 → 修上面的漏洞时一起加（Z06）。
