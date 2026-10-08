# E07.1 平台巡检工具：定期用真实接口跑播放地址、搜索、分区，失效报出来

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：docs v0 登记（旧编号 T02e.1）。2026-09-28～10-01 各平台重构时都用临时程序跑过一次真实接口（结果在各平台 record.md 的“真实环境检查”），程序放在 scratchpad 没进仓库；那一轮当场查出三处已经失效（哔哩哔哩分区对游客全部 -352、虎牙搜索 403、抖音游戏直播间没有分区）。说明平台会悄悄改接口，要有一个能反复跑的工具
- 旧编号：T02e.1
- 相关：国内五大平台巡检 [E01.6](../../E01-国内五大平台/E01.6-国内五大平台巡检和修复/README.md)（用这个工具）；平台任务 [E01](../../E01-国内五大平台/README.md)～[E03](../../E03-海外平台/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；弹幕连接是否还能用归 [D01](../../../D-弹幕/D01-平台弹幕协议/README.md)；样本隐私门禁 S 组；决定 D-002（借用归档 v4 的工具）、D-017（测试不访问真实平台）
- 任务书：[brief.md](brief.md)

## 目标

一条命令把 34 个平台（国内直连、海外走代理）的推荐、分类、分区、搜索、房间详情、清晰度、每条线路的开头字节、租期、链接解析跑一遍，几分钟内给出一张表：每个平台每一项是“正常 / 失败 / 没测到 / 不支持”，失败的写原因（错误类型、HTTP 状态、平台的错误码）。维护者每两周跑一次、发布前跑一次、用户说“某平台打不开”时跑那一个平台；结果存进文档，失败项开到对应平台的修复任务。

工具本身不进应用、不进门禁的联网部分：它的单元测试（判定规则、报告格式）用假数据，跟门禁一起跑；联网只在人手动运行时发生（D-017）。

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 巡检 | 没有；靠 issue | 没有工具。`tools/live_cli/` 在 master 上**不存在**（2026-09-28 master 清空重来，D-002），只在归档标签 `v4-archive` 里：`tools/live_cli/bin/live_cli.dart`（6 个命令：`probe`、`fixture`、`danmaku`、`lease`、`record`、`remux`）、`lib/src/probe/probe_command.dart`（207 行）、`lib/src/probe/sites.dart`（33 个平台的工厂表） | `tools/live_cli` 回到 master，加 `patrol` 命令 |
| 仓库里对它的引用 | — | 已经当它存在：`docs/specs/ENGINEERING.md:52`（目录图写“tools/live_cli（平台探针、样本录制）”）、`tools/gate/check_deps.py:34`、`:41`（依赖方向规则里有它）、`fixtures/README.md:17`、`:24`（录样本的命令和脱敏规则的位置） | 这些引用重新成立 |
| 归档的探针 | — | `probe_command.dart` 用的是归档 v4 的平台接口（`LinkResolver.resolve`、`RoomSource.detail`、`StreamSource.streams`、`Quality`、`LiveState`），和现在的 `LiveSite` 对不上，不能直接搬 | 按现在的接口重写：`getRoomDetail`、`getPlayQualities`、扩展 `resolvePlayUrls`（`packages/live_core/lib/src/live_site.dart:421`）、`LivePlayLine`（`play_line.dart:41`）、链接 `LiveSiteLinks.roomIdFromUrl`（`links.dart:56`） |
| 平台工厂 | 3.x `Sites.supportSites` | 应用的 `buildSiteRegistry`（`apps/pure_live/lib/app/platforms.dart:135-188`）依赖 Flutter 应用的存储，工具不能用 | 工具自己的工厂表：`IoLiveHttp(proxy: FixedProxyPolicy(perSite: …))`（`packages/live_net/lib/src/io_http.dart:17`、`proxy.dart:56`）、空的 `MemoryCookieVault`（`cookies.dart:15`），参数照 `platforms.dart` 的默认值 |
| 媒体开头字节 | — | 归档探针的 `_head`（读前 64 KB 后断开）和 `_container`（FLV、`#EXTM3U`、TS 同步字节 0x47、fMP4 `ftyp`）可以照搬 | 每条线路都读，不只第一条 |
| 结果记录 | — | 各平台 record.md 的“真实环境检查”表（例如 [E01.1 记录](../../E01-国内五大平台/E01.1-哔哩哔哩/record.md)第 177 行起），手写 | 工具直接输出同样格式的 Markdown 表 |

## 方案

- c1 检查项和对象表：本子分类文件夹放 `CHECKS.md`（检查项 P1～P13、判定标准、每个平台用哪个关键词、固定的未开播房间、不存在的房间号、平台特有的情况、要不要代理、请求间隔、哪些项平台本来不支持）；代码里同一份表放 `tools/live_cli/lib/src/patrol/targets.dart`。
- c2 工具：从 `v4-archive` 取回 `tools/live_cli` 的骨架（`pubspec.yaml`、`analysis_options.yaml`、`bin/live_cli.dart`）加进根目录 `pubspec.yaml` 的 `workspace`；重写 `probe` 和工厂表；新命令 `patrol`；`fixture` 等其他命令这次不取回（另开任务）。
- c3 跑一遍：全部平台跑一次，报告存进本任务的 `runs/`，结果和失败项写进 record.md；失败项按平台开修复任务（国内五大平台并进 E01.6）。

## 验证

- 自动测试：`tools/live_cli/test/` 的判定规则、报告格式、容器识别、命令行参数，全部用假的 `LiveSite` 和 `LiveHttp`（D-017）；门禁 `tools/gate/gate.sh --all` 跑到它。
- 真实接口：c3 的那一次运行就是验证（报告和 record.md）。
- 真机：不需要（工具在电脑上跑）。

## 留下的问题

- 2026-10-08 做完（[record.md](record.md)）：工具、CHECKS.md、第一轮报告；失败项开到 E02.14、E02.15、E03.17、E03.18。CHECKS.md 等维护者看过；固定房间里标了“任意状态”的、和没有固定房间的几项待补。
- Kick 的接口只能走 Android 的系统 TLS（Cloudflare 按 TLS 指纹拦 `dart:io`，`platforms.dart:123-126`），Twitch 的 GraphQL 在应用里也有 Android TLS 和浏览器两个后备（`platforms.dart:119-121`）；电脑上的工具没有这些通道，这两个平台的结果可能是“被拒”而应用里正常，报告里要单独标出来（不算平台失效）。
- 弹幕是否还能连（就绪时间、聊天条数）放在 `--danmaku` 选项里，结果归 D01 处理；默认不跑，免得占用太久。
- 登录后才有的行为（哔哩哔哩原画、斗鱼续期、快手和 CC 的登录 Cookie）不在巡检里：工具只用匿名。
