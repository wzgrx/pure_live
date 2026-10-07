# Z06.1 docs 重写为 20 组：登记表、总进度、生成脚本、模板

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：文档
- 来源：2026-10-02 用户决定不再使用云端会话（D-014），并要求把文档整理清楚；当时 docs 里有四套平行的任务体系（模块重构 M、界面重构 U、功能任务 F、4.0.x 更新的 B/P/U01/U02/F01/F02），各自手写的状态互相对不上。
- 旧编号：T00f.1
- 相关：决定 D-014；Z02.2（同一个提交加了门禁的“docs”检查）；Z06.2（第二天的 v1 重排）；[CHANGELOG.md](../../../CHANGELOG.md) 的 v0

## 目标

全部文档变成一棵树：一个登记表记全部任务的编号、状态、阶段；总进度、任务表、旧编号对照、每个组和子分类的页面都由脚本生成；每个做完的任务的设计、任务书、记录放进它自己的文件夹；有一套做法（PROCESS）和每类文档的模板；门禁保证生成的东西是最新的、链接不坏。

## 3.x 和现状

| 方面 | 整理之前（到 2026-10-02） | 整理之后（`c613b73f9`，v0） | 现在 |
|---|---|---|---|
| 任务体系 | 四套：`docs/PLAN.md` + `docs/modules/`（M）、`docs/ui/TASKS.md`（U）、`docs/features/TASKS.md`（F）、`docs/4.0.x/`（B、P…），状态手写、互相冲突 | 一个登记表 `docs/tasks.toml`：20 组（T00～T19）、109 个子分类、246 个任务 | v1 改成字母编号（Z06.2）；现在 20 组、107 个子分类、283 个任务 |
| 进度 | 各 TASKS.md 手写 | `tools/docs/docs.py` 生成 STATUS（全项目、按档位、按组的进度条；正在做的、暂停的、待真机的、下一步）、TASKS、MAPPING 和每个组、子分类的 README | 同左；v2 骨架起组和子分类 README 上半部分手写 |
| 任务文件 | `docs/ui/compare/<编号>/`、`docs/ui/records/`、`docs/features/<编号>/`、`docs/modules/<编号>.md` 分散 | 每个做完的任务一个文件夹 `docs/Txx/Txxy/Txxy.n/`，编号和链接改写 | v1 改成 `docs/<字母>-<组名>/<子分类>/<任务>/` |
| 做法和规范 | 各套各自的 PROCESS、FEATURE_PLAN、UI_PLAN | 新的 PLAN、PROCESS（阶段和接手、交给其他 AI、合并审查）、DECISIONS、GLOSSARY、`specs/ENGINEERING.md`；UI_PLAN 变成 `specs/UI.md`；清点放 `docs/inventory/`；每类任务的模板 | 同左（后来加了新功能、上游借鉴、维护、文档版本） |
| 旧文档 | — | 全文存档在标签 `docs-archive-2026-10-02`；对照写在 MAPPING 最后一节 | 同左 |
| 代码里的文档路径 | 指向旧文件 | 代码注释、`AGENTS.md`、`CLAUDE.md`、`README.md`、`toolchain.env`、`pubspec.yaml` 改指新文件；门禁检查它们存在 | 有 16 处改坏了（见“留下的问题”） |

## 结果

- 提交：`c613b73f9`（北京时间 2026-10-03 00:13，登记表的日期写 10-02；登记表没写 `commit`），4028 个文件（多数是移动）；同一个提交还是 Z02.2（门禁加“docs”一步）。前一个提交 `305c0e414`（10-02 23:21）先去掉了云端工作流、把 4.0.x 的任务卡和记录放进 `docs/4.0.x`。
- 新文件：`docs/tasks.toml`、`tools/docs/docs.py`（当时 493 行）、`docs/STATUS.md`、`TASKS.md`、`MAPPING.md`（生成）、`docs/README.md`、`PLAN.md`、`PROCESS.md`、`DECISIONS.md`、`GLOSSARY.md`、`specs/ENGINEERING.md`、`specs/UI.md`、`docs/inventory/`、`docs/templates/`。
- 事实更正：测试包名从过时的 `.next` 改成 `.v4dev`；多语言从过时的 slang 说法改成应用自带的 JSON 翻译。
- 测试：没有为 `docs.py` 写测试；门禁 `--all` 通过。

## 验证

- `python3 tools/docs/docs.py --check` 没有问题；门禁 `--all` 日志有 `gate: ok   docs`。
- 真机：不适用（文档任务；PROCESS 第 2 节“文档”的证据是文档检查通过）。

## 留下的问题

- 改代码注释里的文档路径时，路径在 `/` 处换行的 16 处被改成了 `docs/README.md/`、`docs/TASKS.md/` 加下一行的旧文件名（例如 `apps/pure_live/lib/platform/display_mode.dart:140-141`）；同时 `docs.py` 的路径检查因为换行没能拦住。清单和修法见 [Z06 子分类说明](../README.md)“已知问题”，建议开一个小任务（Z06.4）。
- `apps/pure_live/android/app/build.gradle.kts:9` 原来是“docs/PLAN.md §9”（旧计划的签名一节），换文件时没换节号，成了“docs/specs/ENGINEERING.md §9”（ENGINEERING 只有 7 节，签名在 Y01 和 D-006）→ 同上。
- 20 组的 T 编号只用了一天，第二天被 v1 的字母编号取代（Z06.2、D-025）。
