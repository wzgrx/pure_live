# Y04.1 隐私说明写进 README：不收集数据、样本脱敏规则

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：发布
- 来源：docs v0（2026-10-02）整理发布和运营时登记（旧编号 T16e.1）：用户和贡献者应该能在项目首页看到“应用收集什么、会连哪些地方、仓库里的样本怎么脱敏”。同一天 Y03.1 的新 README 已经写了一节“隐私”（4 条），但没有覆盖样本脱敏，也有几处没说全。
- 旧编号：T16e.1
- 相关：Y03.1（README）；Z02（样本隐私检查 `tools/gate/check_fixtures.py`）；J03、J05（备份和设备同步带不带账号）；K（账号）；Q（镜像和代理）

## 目标

README 的“隐私”一节说得完整、每一条都有代码依据：

1. 不收集数据、没有统计和崩溃上报（已有）。
2. 账号信息怎么存：Android Keystore、Windows DPAPI 加密；普通备份文件不含账号；**设备同步可以选择带上账号**（默认不带）；日志里自动去掉 Cookie、令牌、密码。
3. 应用会连哪些地方：直播平台；检查更新、下载安装包和字体时访问 GitHub **和若干第三方加速镜像**（列出类别，说明可以在设置里只用 GitHub）；不连我们自己的服务器（没有）。
4. 仓库里的平台样本：只为测试，脱敏规则摘要（客户端地址换成文档段 `203.0.113.x`，访客编号、设备编号、令牌、Cookie 换成同形的合成值），门禁自动检查。
5. 安全问题怎么报告（GitHub Security Advisory，私密提交）。

## 3.x 和现状

| 方面 | 3.x | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 隐私说明 | 3.x 的 README 没有专门一节；有 `SECURITY.md`（`git show v3.2.11:SECURITY.md`） | `README.md:218-223` 四条：不收集、本机保存和 Keystore 加密且备份不含、直接和平台通信、两种代理 | 补齐上面 2～5 |
| 数据收集 | `firebase_core`、`firebase_auth`（`git show v3.2.11:pubspec.yaml:51-52`），云账号登录 | 没有任何统计、上报、云服务的依赖 | 不变 |
| 账号存储 | Hive 明文 | `apps/pure_live/lib/platform/secret_cipher.dart:12-14`（Android Keystore、Windows DPAPI）；备份 `packages/live_store/lib/src/backup/backup_service.dart:32-34` 默认不带；设备同步 `apps/pure_live/lib/features/remote_receiver/remote_sync_service.dart:122` 的 `includeAccounts`（默认关，界面 `remote_receiver_page.dart:505`） | README 写全 |
| 日志 | — | `apps/pure_live/lib/app/app_log.dart:52-127` `redactSecrets`；测试 `apps/pure_live/test/services_test.dart:112` | README 写一句 |
| 第三方镜像 | 3.x 同样用 `GitHubMirror` | `packages/live_net/lib/src/race.dart:92`：`raw.githubusercontent.com` 加 `cdn.gh-proxy.org`、`edgeone.gh-proxy.org`、`hk.gh-proxy.org`、`gh.noki.eu.org`、`gh-proxy.com`、`slink.ltd`、`ghproxy.link`、`gh-proxy.net`、`gitproxy.click`、kkgithub、jsDelivr 等；设置“只从 GitHub 检查更新”（`useGitHubOriginForUpdates`） | README 写清 |
| 样本 | 3.x 的样本工具在归档里 | `fixtures/README.md`（规则，部分链接失效）；`tools/gate/check_fixtures.py` | README 写规则摘要和门禁 |

## 方案

- c1 核对：逐条把 README“隐私”的说法和代码对一遍（上表），有新的出站请求（例如字体仓库、虎牙播放器配置）也列出来。
- c2 改 README：“隐私”一节按目标 1～5 重写（中文、写给用户看，不写代码路径）；“反馈和参与”加一句安全问题走 Security Advisory。
- c3 样本：README 只写规则摘要和“门禁检查”，不链到 `fixtures/README.md` 里失效的文件；`fixtures/README.md` 本身的失效引用列进报告（Z06、E07.1 处理）。

## 验证

- 不涉及自动测试。证据是 README 每一条在 `record.md` 里有对应的文件:行。
- 真机：不需要（文档）；可选：K90 上用 `adb shell dumpsys netstats` 或抓包看启动时只访问更新文件的地址（不强求）。

## 留下的问题

- 还没开始。是否加 `SECURITY.md` 文件（3.x 有）由维护者决定；本任务只在 README 里写一句。
