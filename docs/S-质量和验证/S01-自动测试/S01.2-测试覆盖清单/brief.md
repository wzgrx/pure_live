# S01.2 测试覆盖清单：任务书

## 背景

- 来源：模块重构和界面重构都合并之后，没人统计过测试覆盖（旧任务 T15a.2）。S01.1（`661fa07ad`）修随机失败时发现，“起真实服务或等异步，然后固定等几十毫秒再断言”的写法在应用测试里很普遍。
- 现象：门禁偶发失败要靠重跑（违反 PROCESS 第 12 节）；改到没测过的代码（例如 `packages/live_player`、`packages/live_record`）时只能靠真机发现回归。
- 为什么是第三档：不影响已发布版本的功能，但它决定以后补测试的顺序；适合在两个大任务之间做。
- 已经做过的：S01.1 把 `remote_sync_test.dart` 的四处固定等待改成 `_until`；`live_play_more_test.dart:77` 已有 `until`。

## 目标和验收

1. 13 个工作区成员每个都有：测试文件数、运行器报的用例数（`+N`）、行覆盖率（`LH/LF`）。
2. 应用 `apps/pure_live/lib/` 按目录（`features/<每个目录>`、`shared/`、`app/`、`platform/`、`routes/`、`tv/`）有行覆盖率；列出覆盖率为 0 的文件、低于 30% 的目录。
3. 列出“固定短等待之后直接断言”的位置（文件:行），至少覆盖 `apps/pure_live/test/` 全部；标出已经用按条件等的（`_until`、`until`、`settleSettings`）。
4. 时间炸弹：说明 `live_iptv`、`live_record`、`live_store` 的测试里有没有用到“现在”且没固定的地方，建议要不要加进 `tools/timeshift/run.sh`。
5. 每个缺口给出建议的去向（组、是否新任务、规模）；结果写进本文件夹 `README.md` 的“结果”一节（替换“方案”或加在后面），表格形式。
6. 没有改任何测试和代码；仓库里不留覆盖率文件。

## 现状（读代码得出）

- 门禁跑测试：`tools/gate/gate.sh:113-128`，Flutter 成员 `flutter test`、其余 `dart test`，不带覆盖率。
- 已知的等待写法：`apps/pure_live/test/features/live_play/live_play_more_test.dart:73`（`settle([int ms = 20])` 固定 20 毫秒）和 `:77`（`until`，最多 10 秒）；`remote_sync_test.dart:237` 和 `update_dialogs_test.dart:159` 各一份 `_until`；`settings_harness.dart:112` 的 `settleSettings`。48 个测试文件里有 `Future<void>.delayed(const Duration(milliseconds: …))`，最多的是 `features/search/search_test.dart`（14 处）、`live_play/live_play_more_page_test.dart`（9 处）、`live_play_popups_test.dart`、`live_play_page_test.dart`（各 8 处）。
- 没有测试目录的应用功能：`lib/features/about/`、`auth/`、`hot_areas/`（`area_rooms/` 的可能在 `test/features/areas/` 里，要核对）。
- `.gitignore` 没有忽略 `coverage/`：覆盖率输出必须写到仓库外。

## 3.x 基线

- 3.x 没有覆盖率统计，测试在 `v3.2.11:test/`（464 个文件）。本任务不对照 3.x 的覆盖，只在清单里写一句“3.x 的哪些测试在 4.x 没有对应”时可以引用（可选）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 12 节测试和门禁的维护、第 14 节规则）。
2. `docs/specs/ENGINEERING.md` 第 3 节。
3. 本文件夹的 `README.md`；`docs/S-质量和验证/S01-自动测试/README.md`（代码地图、已知问题）；`docs/S-质量和验证/S01-自动测试/S01.1-远程同步测试改成等真实服务/README.md`。

## 范围

- 可以改：`docs/S-质量和验证/S01-自动测试/S01.2-测试覆盖清单/` 下的文件（README、record.md）。
- 不能改：任何代码和测试；`tools/`；其他组的文档；版本号、`assets/version.json`、`assets/releases.json`；`docs/tasks.toml`（新任务的登记由维护者做，报告里列出建议）。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1、c2：跑覆盖率，汇总成表 | 本文件夹 `README.md`“结果”一节、`record.md` | 13 个成员都有数字；应用按目录有数字；写明提交号 |
| 2 | c3、c4：扫固定等待、评估时间炸弹，写去向 | 同上 | 验收 3、4、5 做到 |

两个阶段可以一次做完（规模“小”）。

命令（WSL，`source ~/tools/purelive-env.sh`；根目录先 `bash tools/ffmpeg_kit/fetch.sh linux`、`flutter pub get`）。输出放仓库外，例如 `OUT=${TMPDIR:-/tmp}/s012`：

```bash
# Flutter 成员（应用、live_ui）
cd apps/pure_live && flutter test --coverage --coverage-path="$OUT/app.lcov" ; cd -
cd packages/live_ui && flutter test --coverage --coverage-path="$OUT/live_ui.lcov" ; cd -
# 纯 Dart 成员：先收集，再转成 lcov
dart pub global activate coverage 1.15.1
for p in live_cast live_core live_danmaku live_iptv live_media live_net live_player live_record live_store live_vod; do
  (cd packages/$p && dart test --coverage="$OUT/$p" && \
   dart pub global run coverage:format_coverage --lcov --in="$OUT/$p" --out="$OUT/$p.lcov" --report-on=lib --package=.)
done
```

- 汇总：读每个 `.lcov` 的 `SF:`、`LF:`、`LH:`，按文件和目录加总（写一个临时 Python 脚本放 `$OUT`，不进仓库）。
- 用例数：取每次运行最后一行的 `+N`（全部通过时是 `+N: All tests passed!`）。
- 固定等待：`grep -rn "delayed(const Duration(milliseconds" apps/pure_live/test` 和 `grep -rn "await settle()" apps/pure_live/test`，逐个看后面几行是不是直接 `expect`。
- `live_core` 很大，单独跑可能要十几分钟；不要和门禁、正式包构建同时跑。

## 测试

- 本任务不写测试。清单里每个数字都写明是哪条命令、哪次提交跑出来的，别人能重跑对上。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 无（本任务只在电脑上跑测试） | — |

## 风险和注意

- 覆盖率跑法会改变测试的时间（插桩变慢），可能把潜在的随机失败暴露出来：记下来（这正是清单要的），不要顺手改。
- `flutter test --coverage` 默认写 `coverage/lcov.info` 到包目录，忘了加 `--coverage-path` 会在仓库里留下没被忽略的文件；做完 `git status` 确认干净。
- `dart pub global activate` 装在用户目录，不影响仓库的 `pubspec.lock`。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter 3.47.5、Dart 3.13.4；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/S01.2` 或本机工作区；提交信息以 `[S01.2]` 开头（英文），例如 `[S01.2] test coverage inventory by package and directory`；不推 master。
- 提交前：`python3 tools/docs/docs.py --check`（只改了文档）。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：已经跑出的数字先写进 `record.md`（写明哪些成员还没跑），提交到分支，在报告里写清下一步从哪个成员接着跑。

## 报告（中文，简洁）

每条验收做到没有；13 个成员的用例数和覆盖率（一张表）；覆盖率最低的 10 个目录；固定等待的位置数和最危险的 5 处；时间炸弹的结论；建议登记的新任务（组、标题、规模、档位）；需要维护者决定的。
