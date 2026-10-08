# S01.2 测试覆盖清单：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（从 master `d34ad44d1` 开始，在 Z04.1 之后）
- 设计或说明：[README.md](README.md)（“结果”一节）、[brief.md](brief.md)

## 做了什么

- 带覆盖率跑了全部 14 个工作区成员（应用、11 个包、`tools/check_latest`、`tools/live_cli`），输出放在仓库外的 scratchpad；结果写进 README“结果”一节：各成员的测试文件数、用例数、行覆盖率，应用按目录，低于 30% 的目录，最低的 10 个目录，0% 的文件，固定等待的位置，时间炸弹，缺口去向。
- 派活时允许在 `tools/` 下加脚本（brief 原来写“不改 `tools/`”），所以把临时脚本做成了可以重跑的工具：
  - `tools/coverage/run.sh OUT [成员...]`：按 `pubspec.yaml` 分 Flutter 和纯 Dart 成员跑带覆盖率的测试，`OUT` 必须在仓库外（拒绝仓库里的目录）。
  - `tools/coverage/report.py OUT [--json]`：读 lcov 和运行日志，出 README 里的表；只用标准库。
  - `tools/gate/tests/test_coverage_report.py`（8 个用例）：工作区成员解析、lcov 两种写法（有没有 LF/LH、相对和绝对路径）、`+N` 解析、目录分组、只有导出语句的文件、0% 和没加载的文件、固定等待的识别（辅助函数、固定轮数、按条件等的辅助、循环里查截止时间的等待）。
  - `docs/inventory/OWNERS.toml`：`tools/coverage/` 归 S01。
- 没有改任何测试和应用代码；仓库里没留覆盖率文件。

## 过程里发现的

- brief 的命令把 `live_player` 当成纯 Dart 包：它依赖 `flutter_test`，`dart test` 每个文件都加载失败（“dart:ui is not available”）。`run.sh` 按 `pubspec.yaml` 判断，用 `flutter test` 重跑通过（58 个用例）。
- `flutter test --coverage` 和 `format_coverage --report-on=lib` 只写测试加载过的文件；只有常量或抽象接口的文件没有可执行的行，也不在 lcov 里，所以“没加载”要人看一眼（README 里写了）。
- 固定等待第一次按“`Future.delayed` 加 `settle()`”数，会把 `audio_focus_test.dart` 的 `settle()`（其实是 `pumpEventQueue()`）算进去，也漏掉各文件自己的 `_settle()`、`_wait()`；改成按本文件里的辅助函数定义判断，按条件等的辅助（`until` 这类、循环里查条件或截止时间的）排除。
- 覆盖率插桩下全部通过，没有暴露随机失败。
- 时间炸弹实测：`live_iptv`、`live_store`、`live_record` 照 `tools/timeshift/run.sh` 的办法跑（仓库外的临时脚本，没改 `run.sh`），结果见 README。

## 用时

- 覆盖率：应用 331 秒，`live_core` 218 秒，其他各包 8～64 秒（机器上同时有别的会话在跑测试）。
