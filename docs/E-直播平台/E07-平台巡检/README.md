# E07 平台巡检

定期用真实接口把各平台的推荐、分类、分区、搜索、房间详情、清晰度、线路、链接跑一遍，平台改了接口或加了风控时，在用户发现之前知道；以及做这件事的工具（`tools/live_cli` 的平台探针和 `patrol` 命令）。

## 范围

- 包括：
  - 巡检工具：`tools/live_cli/`（E07.1，2026-10-08）：`probe`（单个房间从链接到媒体开头字节）、`patrol`（多个平台按检查项跑、出报告）。
  - 检查项和对象表：本文件夹的 `CHECKS.md`（E07.1 第 1 阶段写）。
  - 每一轮的结果：E07.1 的 `runs/` 和 record.md；以后定期的轮次也记在这里（新任务或 E07.1 的 record 追加）。
- 不包括（归哪里）：
  - 修复：国内五大平台的失效由 [E01.6](../E01-国内五大平台/E01.6-国内五大平台巡检和修复/README.md) 修（它是用这个工具的持续任务）；其他平台的失效在 [E02](../E02-其他国内平台/README.md)、[E03](../E03-海外平台/README.md) 开修复任务。
  - 弹幕协议失效 → [D01](../../D-弹幕/D01-平台弹幕协议/README.md)：工具的 `--danmaku` 只看连得上、有没有消息，解析和修复归 D01。
  - 录样本（`live_cli fixture capture`，`fixtures/README.md:17`）：归档里有，这次不取回，以后另开任务（S 组或本子分类）。
  - 自动测试和门禁（不访问真实平台，D-017）→ S01；巡检永远不进门禁。

## 现状：做到哪、怎么工作的

- 做到哪（2026-10-08）：工具 `tools/live_cli` 的 `patrol` 和检查项 [CHECKS.md](CHECKS.md) 做好了（E07.1），第一轮的报告在 [E07.1 的 runs/](E07.1-平台巡检工具/record.md)，国内五大平台的修复在 [E01.6](../E01-国内五大平台/E01.6-国内五大平台巡检和修复/README.md)。之前唯一一轮真实接口检查是各平台重构时（2026-09-28～10-01）用临时程序跑的，结果分散在 34 个平台 record.md 的“真实环境检查”一节，那一轮发现并修了：哔哩哔哩分区对游客 -352、虎牙搜索 403、抖音游戏直播间没有分区。
- 怎么工作（E07.1）：
  1. 工具按平台建适配器（和应用同样的构造参数，但 Cookie 为空、只用 `IoLiveHttp`）；国内直连，海外按 `--proxy` 走代理；
  2. 每个平台按 `CHECKS.md` 跑 P1～P12（推荐、分类、分区、搜索房间和主播、在播 3 个和未开播、不存在的房间、清晰度、每条线路前 64 KB、租期、链接），`--danmaku` 时加 P13；
  3. 每项判成“正常 / 失败 / 没测到 / 不支持”，出 Markdown 报告（格式同 record.md 的“真实环境检查”表，已脱敏）和 JSON；
  4. 维护者看报告，失败项开到修复任务。
- 和 3.x 比：3.x 没有巡检，靠 issue；4.x 新增。

## 代码地图

E07.1 建的和它依赖的：

| 文件 | 职责 |
|---|---|
| `tools/live_cli/` | `bin/live_cli.dart`、`lib/src/sites.dart`（工厂表）、`lib/src/probe/probe_command.dart`、`lib/src/patrol/`（`targets.dart`、`checks.dart`、`media.dart`、`report.dart`、`patrol_command.dart`）、`test/` |
| `git show v4-archive:tools/live_cli/` | 归档的工具：`probe_command.dart`（207 行，接口是归档 v4 的，要重写）、`sites.dart`（33 个平台的工厂表）、`fixture/`（录样本和脱敏规则，这次不取回） |
| `packages/live_core/lib/src/live_site.dart` | 工具调用的平台接口（`:30`～`:59`）和扩展 `resolvePlayUrls`（`:421`）、`discoverPlayQualities`（`:468`）、目录分页 `LiveSiteDirectoryPager`（`:375`） |
| `packages/live_core/lib/src/play_line.dart`、`site_error.dart`、`links.dart` | 线路和租期、9 种错误、链接解析 |
| `packages/live_net/lib/src/io_http.dart`、`proxy.dart`、`cookies.dart` | `IoLiveHttp`（`:17`）、`FixedProxyPolicy`（`proxy.dart:56`，按平台的代理）、`MemoryCookieVault`（`cookies.dart:15`） |
| `apps/pure_live/lib/app/platforms.dart` | 应用的工厂（`:135-188`）和弹幕表（`:196-239`）：工具照它的参数，不引用它 |
| `tools/gate/check_deps.py` | 已有 `tools/live_cli` 的依赖规则（`:34`）和纯 Dart 规则（`:41`） |

测试：E07.1 的 `tools/live_cli/test/`（判定、容器识别、报告和脱敏、参数），全部不联网。

## 3.x 基线

- 3.x 没有巡检和探针。3.x 的 `test/fixtures_expected/` 只回放样本（`fixtures/README.md`“生成和比对期望值”），3.x 已经不能构建。
- 没有要保留的 3.x 行为；工具不改变任何平台的行为。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 录样本的 `fixture capture` 不在 master | 归档 `v4-archive` 的 `tools/live_cli/lib/src/fixture/`；`fixtures/README.md` “录制” | 样本只能手工补录 | 以后另开任务取回（E07.1 只取回了探针和巡检） |
| Kick、Twitch 在应用里走 Android 系统 TLS，电脑上的工具没有这个通道 | `apps/pure_live/lib/app/platforms.dart:119-126` | 这两个平台的巡检结果可能是“被拒”而应用正常 | 报告单独标出；真机验证归 S02.4 |
| 没有定期巡检的约定 | `docs/PROCESS.md` 第 12 节的维护表没有巡检这一行 | 巡检会被忘掉 | 写进本组报告：建议每两周一次、发布前一次，由维护者加进 PROCESS 第 12 节 |
| 上一轮的临时程序和结果分散在 34 个 record.md | 各平台 record.md“真实环境检查” | 下一轮没有基准可比 | E07.1 第 3 阶段的报告成为基准 |

## 相关决定和规范

- D-002（借用归档 v4 写好的工具）、D-014（不使用云端会话：巡检在本机手动跑，不做云端定时任务）、D-017（测试不访问真实平台：巡检不进门禁和自动测试）。
- [specs/ENGINEERING.md](../../specs/ENGINEERING.md)：工作区成员和依赖方向；`fixtures/README.md`：隐私规则（客户端地址、令牌、设备号不进仓库）。

## 测试和验证

- 自动测试：E07.1 写好后 `cd tools/live_cli && dart test`；门禁 `tools/gate/gate.sh --all` 包含它（不联网）。
- 真实接口：就是巡检本身；每轮的报告是证据。
- 真机：不需要；修复任务各自有真机步骤。

## 路线

1. [E07.1](E07.1-平台巡检工具/README.md)（第一档，中，3 个阶段）：定检查项 → 写工具 → 全部平台跑一遍。
2. 同时或紧接着 [E01.6](../E01-国内五大平台/E01.6-国内五大平台巡检和修复/README.md)：用工具跑国内五大平台并修复。
3. 以后：每两周一轮、发布前一轮（维护者定后写进 PROCESS 第 12 节）；取回 `fixture capture` 录样本命令；新想法写进 V01 提议，不直接加任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [E 直播平台](../README.md)。

- 代码：`tools/live_cli/`
- 进度：`████████████░░░░░░░░` 60%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| E07.1 | 平台巡检工具：定期用真实接口跑播放地址、搜索、分区，失效报出来 | 平台 | 开发中 | — | — | [设计或说明](E07.1-平台巡检工具/README.md)、[任务书](E07.1-平台巡检工具/brief.md)、[记录](E07.1-平台巡检工具/record.md) |

## 还没完成的

- **E07.1 平台巡检工具：定期用真实接口跑播放地址、搜索、分区，失效报出来**（开发中，第一档，规模 中）
  - 阶段：✓ 定检查项 → ✓ 写工具 → 跑一遍并记录
  - 接着做：第 3 阶段：全部平台跑一遍，报告存 runs/

## 资料

- [CHECKS.md](CHECKS.md)

<!-- docs:生成结束 -->
