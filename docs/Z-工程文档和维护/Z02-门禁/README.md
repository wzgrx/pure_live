# Z02 门禁

推送前必须通过的那条命令 `bash tools/gate/gate.sh --all`：它检查什么、按什么顺序、哪些规则是“只减不增”的基线，以及门禁自己的测试和 Claude Code 钩子。

## 范围

- 包括：`tools/gate/gate.sh`（三种模式）、`check_deps.py`（依赖方向）、`check_fixtures.py`（样本隐私）、`check_ui_structure.py`（界面结构）和基线 `ui_baseline.json`、门禁自己的测试 `tools/gate/tests/`、钩子 `tools/gate/hooks/format_dart.sh` 和 `.claude/settings.json`。门禁里“docs”一步调用的 `tools/docs/docs.py --check`（脚本本身归 Z06）。
- 不包括（归哪里）：
  - 各成员的测试内容 → 各功能组和 S01；门禁只负责跑它们。
  - 样本的录制和脱敏规则 → E 组和 `fixtures/README.md`；门禁只检查结果里有没有客户端地址。
  - 文档检查的规则（链接、代码里的文档路径、文件夹名）→ Z06。
  - 时间炸弹检查 `tools/timeshift/run.sh` 不在门禁里，发布前手动跑（ENGINEERING 第 3 节）→ S01。

## 现状：做到哪、怎么工作的

- 三种模式（`gate.sh:3-6`、`:11-17`）：
  - 默认（`changed`）：和 `origin/master` 的合并基点比，加上未提交的文件，只检查改过的成员；改了 `pubspec.yaml`/`pubspec.lock`/`toolchain.env`/`gate.sh`/`check_deps.py` 时检查全部（`:45-63`）。
  - `--all`：全部 13 个成员，最后再跑门禁自己的测试（`:129-131`）。**每次推送前必跑**，日志里有 `gate: passed (all, 13 members)` 才算通过（D-007）。
  - `--hook`：Claude Code 的 Stop 钩子（`.claude/settings.json`，超时 1800 秒），没改成员时什么都不输出；失败返回 2 让 Claude 继续修，第二次失败（`stop_hook_active`）只报告不再拦（`:21-28`、`:133-141`）。
- 顺序：找 Dart（没有就 `source ~/tools/purelive-env.sh`，`:30-38`）→ 读 workspace 成员（`:40-43`）→ 全局锁 `${TMPDIR:-/tmp}/pure_live-gate.lock`，最多等 3600 秒（`:65-68`）→ `package_config.json` 比锁文件旧时先 `flutter pub get`（`:92-104`）→ 改了应用时准备 Linux 的 FFmpeg 包（`:108-111`）→ 四个仓库级检查：依赖方向、样本隐私、界面结构、文档（`:113-116`）→ 每个成员：`dart format --set-exit-if-changed`、`dart analyze --fatal-infos`、`flutter test` 或 `dart test`（`:117-127`）→ `--all` 时 `python3 -m unittest discover -s tools/gate/tests`（`:130`）。失败的步骤打印出错的测试（`grep ' \[E\]$'` 后 40 行）和日志最后 60 行（`:76-88`）。
- 三个检查脚本（都只用标准库，钩子里能直接跑）：
  - **依赖方向** `check_deps.py`：每个成员只能依赖分层表 `ALLOWED`（`:18-36`）里列的 `live_*` 包；纯 Dart 成员（`PURE_DART`，`:39-43`）不能依赖或引用 Flutter；不在表里的成员直接报错，逼着先定方向。同时查 `pubspec.yaml` 和 `lib/`、`bin/`、`test/`、`tool/`、`integration_test/` 里的 `import`。
  - **样本隐私** `check_fixtures.py`：`git ls-files` 列出 `fixtures/` 下全部 `*.json`、`*.jsonl`（`:210-214`，现在 1751 个 JSON、83 个 JSONL，36 个平台目录），响应头按“默认拒绝”查保留段和文档段以外的 IPv4（明文或 Base64），正文只查名字表示客户端地址的字段（包括 32 位整数写法、字符串里套的 JSON、gzip/zlib 的 Base64 载荷）；失败时提示换成 `203.0.113.x`。
  - **界面结构** `check_ui_structure.py`：三条规则（`:1-16`）——功能目录之间只能引用对方的入口页 `<b>/<b>_page.dart`；`features/` 和 `tv/` 里不直接写 `Color(0x…)`、`Colors.*`、`Icons.*`、`Remix.*`（注释不算）；`logic/` 下不引 `material.dart`。前两条是棘轮：基线 `ui_baseline.json` 记着已有的违规，**多了报错，少了也报错**（要求同时把基线改小）。`--write-baseline` 重写基线（只在维护者同意时用）。
- 基线的变化：Z02.1（`4e8e9998f`，2026-10-01）建立时跨功能引用 24 条、直接写的颜色图标 891 处分布在 25 个区；之后界面任务逐个清掉，A08.5（`10bbcabe1`，10-02）把最后一个区（settings 的 25 处）清零。现在跨功能引用 17 条（多是 `home/home_menu.dart`、`home/menu_button.dart`、`version/` 的几个文件），`raw_styles` 为空。`ui_baseline.json` 一共被 40 个提交改过。
- 完成度：Z02.1、Z02.2 完成。3.x 没有对应的东西（3.x 的 CI 只跑 `flutter analyze --no-fatal-infos --no-fatal-warnings` 和 `flutter test`，见 `git show v3.2.11:.github/workflows/feature-build.yml:132-136`）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `tools/gate/gate.sh`（139 行） | 模式、锁、依赖刷新、FFmpeg 包、四个仓库级检查、逐成员格式/分析/测试、门禁测试 |
| `tools/gate/check_deps.py`（138 行） | `ALLOWED`（`:18`，14 项，含不存在的 `tools/live_cli`）、`PURE_DART`（`:39`）、`workspace_members`（`:50`）、`pubspec_dependencies`（`:65`）、`check`（`:95`） |
| `tools/gate/check_fixtures.py`（225 行） | `CLIENT_HEADER`、`SERVER_HEADERS`、`KEYED`、`ALLOWED` 地址段；`leaks`（`:130`）、`_walk`（`:139`）、`_documents`（`:164`，`.jsonl` 逐行）、`check`（`:181`）、`main`（`:210`） |
| `tools/gate/check_ui_structure.py`（86 行） | `FEATURE_IMPORT`、`RAW_STYLE`、`MATERIAL`（`:26-28`）、`scan`（`:36`）、`check`（`:55`，棘轮两个方向）、`--write-baseline`（`:81-84`） |
| `tools/gate/ui_baseline.json` | `cross_feature_imports`（17 条）、`raw_styles`（空） |
| `tools/gate/hooks/format_dart.sh`（17 行） | PostToolUse 钩子：改的是 `packages/`、`apps/`、`tools/` 下的 `.dart` 就 `dart format` |
| `.claude/settings.json` | 两个钩子：Edit/Write 后格式化，Stop 时 `gate.sh --hook` |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `tools/gate/tests/test_check_deps.py`（5 个） | 仓库现状通过；纯 Dart 包不能用 Flutter；`live_record` 是纯 Dart；向上依赖被拒；新成员要先定方向 |
| `tools/gate/tests/test_check_fixtures.py`（13 个） | 响应头默认拒绝、服务端地址放过、版本号不算、Base64、正文字段、整数地址两种字节序、JSONL 帧、嵌套 JSON、gzip/zlib 载荷 |
| `tools/gate/tests/test_check_ui_structure.py`（5 个） | 入口页可引、内部不可引；按区计数、注释不算；`logic/` 不能引 material；棘轮两个方向；干净的树通过 |
| （没有） | `gate.sh` 本身、`tools/docs/docs.py` 都没有测试 |

## 3.x 基线

- `git show v3.2.11:.github/workflows/feature-build.yml:132-136`：`flutter analyze --no-fatal-infos --no-fatal-warnings`、`flutter test --concurrency=12`，只在手动触发的工作流里跑；没有格式检查、依赖方向、样本隐私、界面结构。
- 3.x 的 `.gitleaks.toml` 做密钥扫描（4.x 没有对应的检查，靠 `.gitignore` 和样本隐私检查）。
- 要保留的：无（3.x 的门禁不是基线；4.x 的规则来自 ENGINEERING 第 3、7 节）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 默认模式和 `--hook` 在“没有成员改动”时直接退出（`gate: no workspace member changed`），连依赖方向、样本隐私、界面结构、文档四个仓库级检查也不跑 | `tools/gate/gate.sh:58-62`（在 `:113-116` 之前） | 只改文档或样本的提交，Stop 钩子和默认模式都发现不了文档、样本的问题；只有 `--all` 会查 | 推送前必须 `--all`（D-007），所以不会漏进 master；登记为 Z02.3（第二档）：只改文档、样本、脚本时默认模式和钩子也跑四项仓库级检查 |
| `docs.py` 没有测试；代码里的文档路径检查按行匹配，注释里换行的路径会被截短（16 处坏路径没被拦） | `tools/docs/docs.py:502`、`:523` | 文档检查有漏洞 | Z06 已知问题；修脚本时加 `tools/gate/tests/test_docs.py` |
| `check_deps.py` 的分层表有不存在的 `tools/live_cli` | `check_deps.py:34`、`:41` | 规则表和仓库不一致 | E07.1（取回工具）；不取回就删掉 |
| `gate.sh` 的锁文件放在 `${TMPDIR:-/tmp}`；Claude Code 会话的 `TMPDIR` 和普通终端不同时，两边的门禁拿的是不同的锁 | `gate.sh:66` | 两个门禁可能同时跑、互相改 `.dart_tool/` | 没有任务；同一时间只开一个门禁（PROCESS 第 8 节） |
| 没有密钥扫描（3.x 有 `.gitleaks.toml`） | — | 密钥误提交只靠 `.gitignore` 和人工审查 | 需要维护者决定是否加（Y04 相关） |

## 相关决定和规范

- D-007：推送前门禁必须通过；不强推。
- D-017：测试里的定时器至少 1 秒、不访问真实平台（门禁跑的测试要遵守）。
- ENGINEERING 第 3 节（门禁的步骤）、第 4 节（分层，`check_deps.py` 的依据）、第 7 节（代码规则，`check_ui_structure.py` 的依据）；specs/UI.md 第 5.2 节（界面结构）；PROCESS 第 8 节第 5 条（门禁运行时不构建正式包）、第 12 节（基线只减不增、随机失败先找根因）。

## 测试和验证

- 门禁自己的测试：`python3 -m unittest discover -s tools/gate/tests`（23 个，`--all` 最后一步）。
- 改了门禁脚本时：先在一个故意违规的分支上跑，确认报出来；再在干净的 master 上跑 `--all`，确认通过。
- 不涉及真机。

## 路线

- 本子分类登记的两个任务都已完成，没有排着的任务。
- 待维护者决定、可以开新任务的：仓库级检查在默认模式也跑（上表第 1 行）；`docs.py` 的测试和换行路径（和 Z06 一起）；密钥扫描。
- E07.1 取回 `tools/live_cli` 时，它会成为第 14 个成员，`check_deps.py` 的表已经写好它的方向。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [Z 工程文档和维护](../README.md)。

- 代码：`tools/gate/`
- 进度：`████████████████░░░░` 80%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| Z02.1 | 搬目录：界面代码按 v3 模块分目录，门禁加“界面结构”检查 | 工程 | 完成 | 2026-10-01 | 4e8e9998f | [设计或说明](Z02.1-界面代码搬目录/README.md) |
| Z02.2 | 门禁加“文档”检查：生成文件是否最新、链接和代码里的文档路径是否有效 | 工程 | 完成 | 2026-10-02 | c613b73f9 | [设计或说明](Z02.2-门禁加文档检查/README.md) |
| Z02.3 | 门禁默认模式在只改文档、样本、脚本时也跑仓库级检查 | 工程 | 未开始 | — | — | [设计或说明](Z02.3-只改文档时的仓库级检查/README.md)、[任务书](Z02.3-只改文档时的仓库级检查/brief.md) |

## 还没完成的

- **Z02.3 门禁默认模式在只改文档、样本、脚本时也跑仓库级检查**（未开始，第二档，规模 小）
  - 来源：docs v2 写作时发现（Z02 已知问题）

<!-- docs:生成结束 -->
