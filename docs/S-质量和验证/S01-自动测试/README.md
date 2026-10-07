# S01 自动测试

管自动测试作为一个整体：能稳定通过（不随机失败、不靠重跑）、知道各包测了什么和缺什么、样本和时间不会让测试过期。

## 范围

- 包括：13 个工作区成员的 `test/`（根 `pubspec.yaml` 的 `workspace:` 列表：`apps/pure_live`、11 个 `packages/live_*`、`tools/check_latest`）的稳定性；测试用的公共支撑（假对象、样本、等待辅助）；覆盖清单；时间炸弹检查 `tools/timeshift/run.sh`；测试规则（D-017）的执行情况。
- 不包括（归哪里）：
  - 门禁脚本和检查器本身（`tools/gate/`）归 Z02；本子分类只关心它跑测试那一步（`tools/gate/gate.sh:113-128`）的结果。
  - 某个功能的具体测试由功能任务写（修 bug 时先写改之前会失败的测试，PROCESS 第 8 节第 2 条）。
  - 基准测试 `apps/pure_live/integration_test/`（profile 模式、在手机上跑）归 R01。
  - 平台样本的录制和脱敏规则（`fixtures/`）归各平台任务（E 组），隐私检查归 Z02。

## 现状：做到哪、怎么工作的

- **怎么跑**：`bash tools/gate/gate.sh --all` 依次跑依赖方向、样本隐私、界面结构、文档检查，再对每个成员跑 `dart format --output=none --set-exit-if-changed`、`dart analyze --fatal-infos` 和测试（有 `sdk: flutter` 的成员用 `flutter test`，其余 `dart test`，`gate.sh:120-124`），最后跑 `tools/gate/tests/` 的 Python 测试；日志里有 `gate: passed` 才算通过。不带参数时只跑相对 `origin/master` 改过的成员。同一时间只跑一个（`flock` 锁 `pure_live-gate.lock`）。跑应用测试前会先取 FFmpeg 包（`tools/ffmpeg_kit/fetch.sh linux`，应用的构建钩子要用）。
- **数量**（2026-10-03，按 `test(`、`testWidgets(` 调用粗数，循环生成的不算；运行器实际报的数更多，例如 S02.1 记录里 `live_core` 是 3590 个）：

| 成员 | 测试文件 | 调用处 | `lib/` 行数 |
|---|---:|---:|---:|
| `apps/pure_live` | 78 | 约 848 | 84083 |
| `live_core` | 77 | 约 2922 | 54691 |
| `live_danmaku` | 38 | 约 1165 | 21497 |
| `live_ui` | 18 | 约 178 | 14260 |
| `live_net` | 10 | 约 84 | 4517 |
| `live_cast` | 7 | 约 57 | 1872 |
| `live_vod` | 3 | 约 48 | 4792 |
| `live_store` | 5 | 约 46 | 4637 |
| `live_record` | 6 | 约 43 | 4785 |
| `live_iptv` | 5 | 约 42 | 3094 |
| `live_media` | 6 | 约 40 | 3762 |
| `live_player` | 5 | 约 36 | 2357 |

- **测试规则**（D-017）：定时器至少 1 秒；不访问真实平台（平台测试用 `fixtures/<平台>/` 的录制样本）；用到样本时间的测试把“现在”固定成录制时间。时间炸弹用 `tools/timeshift/run.sh`：用 `LD_PRELOAD` 把时钟拨快 30 天、1 年、5 年，逐个文件跑 `live_net`、`live_core`、`live_danmaku` 的测试（只在 Linux/WSL）。
- **稳定性**：随机失败的测试先找根因、改成按条件等待（PROCESS 第 12 节）。已修：S01.1（`remote_sync_test.dart` 起真实的同步服务后固定等 250 毫秒，机器忙时服务还没起来，6 次并行全失败；改成 `_until` 最多等 10 秒，8 次并行全过）；S02.1 记录里观察到的 `live_play_more_test.dart` “audio only keeps the stream; a sleep session …” 现在用 `until`（`live_play_more_test.dart:77`）按条件等。
- 和 3.x 比：3.x 的测试是一个平铺的 `test/`（464 个文件），CI 里 analyze 不把提示当错误；4.x 按包分测试、`--fatal-infos`、样本录制加脱敏、门禁本地必跑（GitHub Actions 额度用完，不用 CI）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `tools/gate/gate.sh` | 门禁入口；`--all` 跑全部成员和 `tools/gate/tests/`；`--hook` 给 Claude Code 的停止钩子用 |
| `tools/timeshift/run.sh`、`tools/timeshift/shift.c` | 时间炸弹检查：编译一个改时钟的共享库，按天数拨快后逐个文件跑三个纯 Dart 包的测试 |
| `apps/pure_live/test/support.dart` | 应用测试的公共服务：`testServices()`（内存存储、假平台）、`loadStrings()`（读翻译） |
| `apps/pure_live/test/features/live_play/live_play_support.dart` | 直播间测试的假平台、假弹幕、假引擎（`FakeSite`、`FakeDanmaku`、`FakeEngine`），基准测试也复用它 |
| `apps/pure_live/test/features/live_play/local_interaction_support.dart` | 本地互动测试的辅助（`settleLocal`） |
| `apps/pure_live/test/features/settings/settings_harness.dart` | 设置页测试的外壳和 `settleSettings` |
| `apps/pure_live/test/features/remote_receiver/remote_sync_test.dart:237` | `_until`：按条件等真实服务（S01.1） |
| `apps/pure_live/test/features/live_play/live_play_more_test.dart:73-83` | `settle`（固定 20 毫秒）和 `until`（最多 10 秒按条件等） |
| `apps/pure_live/test/features/version/update_dialogs_test.dart:159` | 另一份 `_until`（和上面两处重复） |
| `apps/pure_live/test/shared/fake_qr_camera.dart` | 扫码页测试用的假相机 |
| `packages/live_player/test/support/fake_engine.dart` | 播放会话测试的假引擎 |
| `packages/live_record/test/support/fakes.dart` | 录制测试的假 FFmpeg、假平台 |
| `packages/live_media/test/support/synthetic_flv.dart` | 合成 FLV 数据 |
| `packages/live_net/test/support/digests.dart` | 测试里自己算的 SHA-256、CRC32（校验下载、解压结果） |
| `packages/live_store/test/support.dart` | 内存存储 `memoryStore()`、假加密器 `FakeCipher`、造 3.x 房间数据的 `v3Room()` |
| `packages/live_cast/test/fakes.dart`、`packages/live_cast/test/samples/` | 投屏的假设备和设备描述样本 |
| `packages/live_vod/test/fixture.dart` | 点播测试读样本 |
| `fixtures/`（36 个平台目录）、`fixtures/README.md` | 真实接口的录制样本（脱敏），平台和弹幕测试的期望值来源 |
| `tools/gate/check_fixtures.py` | 门禁的“样本隐私”：样本里不能有真实客户端地址 |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `tools/gate/tests/test_check_deps.py`、`test_check_fixtures.py`、`test_check_ui_structure.py` | 门禁三个检查器自己的测试（`--all` 时跑） |
| `tools/check_latest/test/check_latest_test.dart` | 工具链检查工具 |

## 3.x 基线

- 3.x 的测试在 `v3.2.11:test/`，464 个 `_test.dart` 平铺在一个目录，样本在 `test/fixtures/<平台>/`，辅助在 `test/support/`（3 个文件）。
- CI：`v3.2.11:.github/workflows/feature-build.yml:132-136` 跑 `flutter analyze --no-fatal-infos --no-fatal-warnings` 和 `flutter test --concurrency=12`。4.x 不用 CI，改成本机门禁，analyze 用 `--fatal-infos`。
- 没有要保留的用户操作习惯（测试不面向用户）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 应用测试里有 48 个文件用固定的短等待（`Future<void>.delayed(const Duration(milliseconds: …))`，最多的是 `search_test.dart` 14 处、`live_play_more_page_test.dart` 9 处），之后直接断言的在机器忙时可能来不及 | `apps/pure_live/test/features/` | 门禁偶发失败；S01.1 就是这一类 | S01.2 列出“固定等待后直接断言”的地方，按 S01.1 的做法改成按条件等 |
| 按条件等的辅助写了三份（`remote_sync_test.dart:237`、`update_dialogs_test.dart:159`、`live_play_more_test.dart:77`） | 同上 | 重复，以后还会再抄 | S01.2 建议并到 `apps/pure_live/test/support.dart` |
| 覆盖不均：`live_player`（2357 行，约 36 处）、`live_record`（4785 行，约 43 处）、`live_store`（4637 行，约 46 处）的测试相对少；应用的 `features/about/`、`auth/`、`hot_areas/` 没有自己的测试目录 | 各包 `test/` | 改动这些地方时回归靠真机 | S01.2 出清单，缺口开到对应组 |
| 时间炸弹检查只跑三个纯 Dart 包，`live_iptv`（节目单时间）、`live_record`、应用都没跑 | `tools/timeshift/run.sh:19` | 节目单、录制命名用到“现在”的测试可能到期失败 | S01.2 评估要不要加进去 |
| 3.x 数据导入只用造的 Hive 文件测（`packages/live_store/test/migration_test.dart`），没有真实 3.x 文件的样本 | `live_store` | 真实数据的边角情况测不到 | S04.1、J06.1 覆盖安装时取一份脱敏的真实文件做样本（不进仓库前先脱敏） |

## 相关决定和规范

- D-017：测试里的定时器至少 1 秒；测试不访问真实平台；用到样本时间的把“现在”固定成录制时间。
- [specs/ENGINEERING.md](../../specs/ENGINEERING.md) 第 3 节：门禁、时间炸弹；第 7 节：代码规则。
- [PROCESS.md](../../PROCESS.md) 第 8 节（合并审查第 4、5 条：测试规则、门禁）、第 12 节（随机失败先找根因、`ui_baseline.json` 只减不增）。

## 测试和验证

- 自动：`bash tools/gate/gate.sh --all`（推送前必跑）；单个包 `cd packages/<包> && dart test`，应用 `cd apps/pure_live && flutter test`；时间炸弹 `bash tools/timeshift/run.sh`（发布前）。
- 查随机失败：同一个测试文件并行跑多次（S01.1 用的是 6～8 个并行），机器忙时复现；`flutter test --concurrency=1 <文件>` 单独跑对照。
- 本子分类不需要真机。

## 路线

1. S01.2（第三档）：各包测试数、行覆盖率、没有测试的目录、固定等待的位置，按风险排序，缺口开到对应组。
2. 之后按清单逐步把“固定等待后直接断言”改成按条件等，把三份 `until` 合成一个公共辅助（在清单里登记成新任务）。
3. 新想法（例如给录制、播放加集成测试）写进 V01 提议或在对应组登记，不直接加在这里。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [S 质量和验证](../README.md)。

- 代码：各包的 `test/`
- 进度：`█████████████░░░░░░░` 67%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| S01.1 | 远程同步测试改成等真实服务启动（负载高时随机失败） | 验证 | 完成 | 2026-10-02 | 661fa07ad | [设计或说明](S01.1-远程同步测试改成等真实服务/README.md) |
| S01.2 | 测试覆盖清单：各包测试数和缺口 | 验证 | 未开始 | — | — | [设计或说明](S01.2-测试覆盖清单/README.md)、[任务书](S01.2-测试覆盖清单/brief.md) |

## 还没完成的

- **S01.2 测试覆盖清单：各包测试数和缺口**（未开始，第三档，规模 小）

<!-- docs:生成结束 -->
