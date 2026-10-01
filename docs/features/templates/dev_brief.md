你在 pure_live 仓库（Flutter/Dart pub workspace）的独立 git worktree 里工作，任务是 **F.xx 名称**：按已确认的改动清单把功能补齐（只管 Android）。最终报告用中文，简洁。

## 必读（先读完再动手）
1. `docs/features/PROCESS.md`（你负责第 6 步）、`docs/features/FEATURE_PLAN.md` 第 3 节（原则）和第 8 节（验收）。
2. **`docs/features/F.xx/README.md`（改动清单，逐条照做）**；`docs/features/INVENTORY.md` 里 F-XXX-NN 这几行。
3. v3 代码（只读 `~/ref/v3ref/lib/`，标签 `v3.2.11`）：……（列文件和行）。
4. v4 现在：……（列文件）；相关记录 `docs/modules/……`、`docs/ui/records/……`。
5. 有界面的：`docs/ui/compare/U.x/README.md` 已确认的设计（照做，不重新设计）。
6. 半成品（如有）：分支 `……` 的提交 `……`，只读；按文件对照搬到现在的目录，不直接合并。
7. `AGENTS.md`（含“加速”一节）。

## 要做的（逐条照 README 的改动清单）
- c1 ……
- c2 ……

## 测试（主要路径）
每条 c 至少一个测试；修 bug 的先写一个改之前会失败的测试。原有测试和改动冲突的照实改，原因写进记录。

## 门禁和规则
- 只改：……（列目录）。别的功能目录不动；需要跳转用路由。
- 3.x 的设置键名和含义不变；新设置加进 `packages/live_store`（只添加），写清 3.x 迁移。
- 代码、注释、提交信息用英文；文档和用户看到的文字用中文（i18n 的 zh 和 en 都加，按键名排序、4 空格缩进）。分几次提交。
- 不往手机安装、不动 3.x。测试里的定时器至少 1 秒；结束前关掉自己开的后台进程（包括 Gradle/Kotlin 守护进程）。临时文件放 `scratchpad/F.xx/`。
- 先 `git merge --ff-only master`；worktree 里先在根目录 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。提交前：改过的包跑 analyze 和测试；`apps/pure_live` 跑 `flutter analyze` 和相关测试；`python3 tools/gate/check_ui_structure.py`；改了原生的后台跑一次 `flutter build apk --debug`。不跑完整门禁。只提交到 worktree 分支，不推送；提交信息结尾加 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。
- 文档：`docs/features/records/F.xx.md`（逐条对照表、根因、v3 文件 → v4 文件、新设置和迁移、测试数量、没验证的部分、冲突点）；不改 `docs/PLAN.md`、`docs/features/TASKS.md`（合并的人改）。

## 报告（中文，简洁）
提交；改动清单逐条做到没有（没做的写原因）；测试数量；需要真机看的；冲突点。
