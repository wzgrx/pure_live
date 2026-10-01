你在 pure_live 仓库（Flutter/Dart pub workspace）的独立 git worktree 里工作，任务是 **U.x 名称**：按用户已确认的设计（第 N 版）实现。最终报告用中文，简洁。

## 必读（先读完再动手）
1. `docs/ui/PROCESS.md`（你负责第 9 步）、`docs/ui/UI_PLAN.md` 第 3 节（原则，尤其第 7 条各客户端一致）、第 10 节（代码结构和门禁）。
2. **`docs/ui/compare/U.x/README.md`（已确认的设计，逐条照做）**；同目录 `page/` 的章节图和 `v4-*.jpg`、`v4-*-n.jpg`（用 Read 工具看图）。标“否决”的图不要照做。
3. v3 代码（只读 `~/ref/v3ref/lib/`，标签 `v3.2.11`）：……（列文件）；文字在 `assets/translations/zh.json`。
4. v4 现在：`apps/pure_live/lib/features/<模块>/`……；相关包……
5. 已有的组件：`packages/live_ui`（`AppIcons`、颜色角色、弹窗组件……），先用已有的，缺的在 `live_ui` 里加。
6. `AGENTS.md`（含“加速”一节）、`tools/gate/check_ui_structure.py`。

## 要做的（逐条照 README 的“确认的改动”）
- c1 ……
- c2 ……
- 各客户端：竖屏……；横屏和宽屏……；桌面的悬停、右键、快捷键……

## 测试（主要路径）
widget 测试固定：按钮顺序、图标、位置；各状态；竖屏、横屏、宽屏布局。原有测试和新设计冲突的照实改，原因写进记录。

## 门禁和规则
- 只改：……（列目录）。不改其他功能目录的界面；需要跳转用路由。
- `check_ui_structure.py`：直接写的颜色和图标只减不增，改完把 `tools/gate/ui_baseline.json` 降到实际值；不新增跨功能引用；`logic/` 不引 material。
- 代码、注释、提交信息用英文；文档和用户看到的文字用中文（i18n zh 和 en 都加，按键名排序、4 空格缩进）。分几次提交。
- 不往手机安装、不动 3.x。测试里的定时器至少 1 秒；结束前关掉自己开的后台进程（包括 Gradle/Kotlin 守护进程）。临时文件放 `scratchpad/<编号>/`。
- worktree 里先在根目录 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。提交前：改过的包跑 analyze 和测试；`apps/pure_live` 跑 `flutter analyze` 和全部 `flutter test`；跑 `python3 tools/gate/check_ui_structure.py`。不跑完整门禁。只提交到 worktree 分支，不推送；提交信息结尾加 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。
- 文档：`docs/ui/records/U.x.md`（逐条对照表、偏差和原因、v3 文件 → v4 文件、新设置、基线变化、测试数量）；`docs/ui/TASKS.md` 的状态、计划书附录 B、`docs/PLAN.md` 的 U.x 行。

## 报告（中文，简洁）
提交；README 逐条做到没有（没做的写原因）；直接颜色和图标的变化；测试数量；冲突点。
