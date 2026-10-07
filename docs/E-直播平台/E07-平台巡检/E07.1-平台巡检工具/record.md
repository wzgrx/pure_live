# E07.1 平台巡检工具：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（`[E07.1]` 提交）
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)；检查项和对象表：[CHECKS.md](../CHECKS.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 验收 1 工作区成员、依赖方向 | 做了 | `tools/live_cli` 加进根 `pubspec.yaml` 的 `workspace`（`pubspec.lock` 不变：`args` 已经在锁里）；依赖只有 `args`、`live_core`、`live_net`、`live_danmaku`、`meta`。`check_deps.py` 的规则收窄到实际用的三个 `live_*` 包 |
| 验收 2 `CHECKS.md` | 做了 | P1～P13 的做法和判定、34 行对象表；代码里同一份表是 `lib/src/patrol/targets.dart`。等维护者看 |
| 验收 3 `patrol` 命令 | 做了 | 平台名、`--domestic`、`--overseas`、`--all`、`--proxy`、`--danmaku`、`--out`、`--json`；退出码 0/1/64 |
| 验收 4 报告格式和隐私 | 做了 | 见下“报告” |
| 验收 5 单元测试 | 做了 | 55 个，全部用假的 `LiveSite`、`LiveHttp`，`head()` 只连本机回环 |
| 验收 6 跑一遍 | 见“第一轮” | |

## 做了什么

- `bin/live_cli.dart`：`CommandRunner` 注册 `probe`、`patrol`，保留归档的 `exit(exitCode)`。
- `lib/src/sites.dart`：34 个平台的工厂表（参数照 `apps/pure_live/lib/app/platforms.dart` 的默认值：空的 `MemoryCookieVault`、`preferH264` 默认开、Twitch 不给后备、Kick 的接口用 dart:io）、弹幕连接表（同 `buildDanmakuRegistry`，设置取默认）、`patrolProxyPolicy`（国内一律直连，海外走 `--proxy`，`FixedProxyPolicy(perSite: …)`）。
- `lib/src/probe/probe_command.dart`：按现在的接口重写归档的探针：链接经 `LinkParser` → `getRoomDetail` → `discoverPlayQualities` → `resolvePlayUrls` → 每条线路开头 64 KB。
- `lib/src/patrol/`：`targets.dart`（对象表）、`checks.dart`（`PlatformPatrol`，P1～P13 每项一个方法；错误转成说明；每项超时；遇到 `RiskControl` 停这个平台）、`media.dart`（`head()` 经 `LiveHttp.open` 读够 64 KB 就断开，`container()` 识别 FLV、`#EXTM3U`、TS、fMP4、DASH、HTML）、`danmaku.dart`（P13 只听不发）、`report.dart`（Markdown、JSON、`redact`、`scrub`）、`patrol_command.dart`（参数和 `runPatrol`，网络、媒体、链接、弹幕都能注入）。
- 和归档的不同：归档的 `fixture`、`danmaku`、`lease`、`record`、`remux` 命令没有取回（任务书范围外）；`head()` 不再自己开 `HttpClient`，走 `IoLiveHttp`，所以代理规则和请求头与应用一致。
- 悬空引用：`docs/specs/ENGINEERING.md`（目录图加上 `tools/live_cli` 和它的依赖，删掉“还没有”的说明）、`tools/gate/check_deps.py:34`（规则收窄并注明用途）、`fixtures/README.md`“录制”（写明 `fixture capture` 还在 `v4-archive`，现在手工补录，脱敏规则在归档里）；Z02、Z01.1、Z07.3、Z 组 README 和 E 组 README 里“`tools/live_cli` 不存在”的说法一并改掉。

## 报告

- 开头一行：开始和结束时间（UTC）、国内直连 / 海外经代理或没有代理、匿名、弹幕秒数、总用时；一张总表（每个平台网络、用时、四种结果各几项）；每个平台一张 `| 检查项 | 结果 | 说明 |`。
- 说明里的地址经 `redact` 只留主机和路径前两段（没有查询参数和签名）；保留段和文档段以外的 IPv4 换成 `x.x.x.x`（同 `check_fixtures.py`）；表格里的 `|` 转义。JSON 同样脱敏。

## 测试

- 新增 55 个（`checks_test.dart` 35、`media_test.dart` 5、`report_test.dart` 5、`patrol_command_test.dart` 10），全部通过；`dart analyze --fatal-infos` 无问题。
- 判定：第 2 页重复超过一半、空页、卡片缺房间号、没有第 2 页、空分类、只搜直播中搜出未开播、按房间号查用推荐的房间号、不支持的项、详情缺标题（卡片补标题）、要求分区时先挑分区房间、开播时间晚于现在、固定房间状态不对或已不存在、P8 报错类型不对（含 `RiskControl`）或不报错、清晰度重复或为空、配方取流、HLS 线路开头是 FLV、HTTP 403 和降档、租期已过和未到、链接认错、大小写不敏感的平台、弹幕没就绪和正常、超时（1 秒）、平台自己的超时、遇到风控后停下、整行跳过（Kick）。
- `head()`：本机回环的原始套接字只给 128 KB 且不结束回答，断言只读到 64 KB 并且是客户端先断开；404 不读正文。
- 参数：平台顺序、`--domestic` 18、`--overseas` 16、`--all` 34、代理和弹幕参数、各种错参数（命令里是用法错误，退出码 64）；没有代理时海外平台全部“没测到”不算失败；国内失败使报告失败（退出码 1）；工厂表和 `SiteIds.supported` 一致。

## 真机上要看的

- 不需要：工具在电脑上跑。修复任务各自有真机步骤。

## 停在哪（没做完时写）

- 做完的阶段：1 定检查项、2 写工具。
- 正在做的阶段做到：第 3 阶段（跑一遍并记录）。
