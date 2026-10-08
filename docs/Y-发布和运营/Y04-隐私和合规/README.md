# Y04 隐私和合规

对用户和对外的承诺是否属实：应用不收集数据、账号和密码怎么存、应用会连哪些地方；仓库里的平台样本不带真实的地址和账号；许可证（AGPL-3.0）和第三方许可；免责声明。

## 范围

- 包括：
  - 根目录 `README.md` 的“隐私”（`:218-223`）、“开源许可”（`:400`）、“免责声明”（`:406`）三节的内容和代码是否一致。
  - `LICENSE`（AGPL-3.0，661 行）；应用“关于”页的第三方许可（`apps/pure_live/lib/features/about/about_page.dart:59` 的 `showLicensePage`，自带 emoji 字体的许可另外登记 `features/live_play/local_interaction/local_interaction_scope.dart:79`）。
  - 样本隐私：`fixtures/` 的脱敏规则（`fixtures/README.md`）和门禁检查 `tools/gate/check_fixtures.py`（脚本本身归 Z02，规则和承诺归这里）。
  - 日志里的秘密：`apps/pure_live/lib/app/app_log.dart` 的 `redactSecrets`（`:127`，Cookie、令牌、密码、签名不写进日志）。
- 不包括（归哪里）：
  - Cookie 和 WebDAV 密码加密存储的实现（`apps/pure_live/lib/platform/secret_cipher.dart`、`packages/live_store/lib/src/secrets.dart`）→ J（存储）、K（账号）；这里只核对 README 的说法。
  - 备份和设备同步带不带账号 → J03、J05；同上。
  - 签名文件和密钥不进 git → Y01（D-006）。
  - 代理设置 → Q。

## 现状：做到哪、怎么工作的

- README“隐私”一节（Y03.1 写的，2026-10-02）四条，和代码对照：

| README 的说法 | 代码 | 一致吗 |
|---|---|---|
| 不需要注册账号；不收集任何数据，没有广告、统计、崩溃上报 | 13 个成员的 `pubspec.yaml` 里没有 Firebase、Sentry、统计或崩溃上报的包（3.x 有 `firebase_core`、`firebase_auth`，`git show v3.2.11:pubspec.yaml:51-52`，用于 3.x 的云账号，4.x 去掉了） | 一致 |
| 关注、历史、设置保存在本机；Cookie、WebDAV 密码用 Android Keystore 加密保存，备份文件里不含这两样 | `secret_cipher.dart:12-14`：Android 用 Keystore（AES-256-GCM，`:20`），Windows 用 DPAPI（`:45`），其他平台没有；备份页 `features/backup/backup_page.dart:241` 调 `exportAll()`（默认不带账号，`packages/live_store/lib/src/backup/backup_service.dart:32-34`）；**设备同步可以勾选带上账号**（`features/remote_receiver/remote_sync_service.dart:122` `includeAccounts`，默认关） | 基本一致；设备同步那一条没写 |
| 应用直接和各直播平台通信；检查更新读本仓库在 GitHub 上的版本文件（启动检查可以关）；下载安装包从 GitHub 或国内加速镜像；下载字体访问 GitHub 上的字体仓库 | `apps/pure_live/lib/features/version/update_feed.dart:12`、`:340-346`（`version.json` 同时问 GitHub 和 `packages/live_net/lib/src/race.dart:92` 的十几个镜像：`cdn.gh-proxy.org`、`gh-proxy.com`、kkgithub、jsDelivr 等第三方）；设置 `enableAutoCheckUpdate`、`useGitHubOriginForUpdates`；虎牙的播放器配置也走这些镜像（`race.dart` 的注释） | 基本一致；没写“检查更新时也会请求第三方镜像”（它们能看到请求的 IP） |
| 应用代理和播放代理分开 | `Settings` 里两组代理设置（Q 组） | 一致 |

- 日志：`app_log.dart:52` 起的 `_secretNames` 和 `redactSecrets`（`:127`）把 Cookie、`authorization`、平台的令牌字段（哔哩哔哩 `SESSDATA`、`bili_jct`，斗鱼 `acf_auth`、`LTP0`，虎牙 `udb_biztoken`，Twitch `auth-token`……）替换掉；测试 `apps/pure_live/test/services_test.dart:112`。
- 样本隐私：`fixtures/` 下 36 个平台目录、1751 个 JSON、83 个 JSONL；门禁“fixture privacy”拦住保留段和文档段以外的 IPv4（响应头默认拒绝、正文按字段名、整数和 Base64 写法都查，Z02）。2026-09-28 发现归档时的脱敏漏了响应头回显的真实出口地址，已换成 `203.0.113.7` 并加了这道检查。README 没有提样本和脱敏。
- 许可：AGPL-3.0（`LICENSE`，Z01.1 提交时放入）；README 写了分发修改版要公开源码；借鉴上游 AGPL 代码注明来源、MIT 的保留版权声明（PROCESS 第 9 节第 5 条）。
- 完成度：README 已有隐私、许可、免责声明三节；Y04.1（隐私说明写完整：补设备同步、第三方镜像、日志、样本脱敏规则）未开始。

## 代码地图

| 文件 | 职责 |
|---|---|
| 根目录 `README.md:218-223`、`:400-411` | 隐私、开源许可、免责声明 |
| `LICENSE` | AGPL-3.0 全文 |
| `apps/pure_live/lib/platform/secret_cipher.dart` | 平台的加密器：Android Keystore（`:20`）、Windows DPAPI（`:45`） |
| `packages/live_store/lib/src/secrets.dart` | 加密存储的 Cookie、令牌、WebDAV 密码 |
| `packages/live_store/lib/src/backup/backup_service.dart:32` | `exportAll(includeSensitiveData: false)`：备份默认不带账号 |
| `apps/pure_live/lib/features/remote_receiver/remote_sync_service.dart:122` | 设备同步的 `includeAccounts`（默认关） |
| `apps/pure_live/lib/app/app_log.dart:52-127` | 日志里的秘密字段和 `redactSecrets` |
| `packages/live_net/lib/src/race.dart:92` | `GitHubMirror`：更新、字体、虎牙配置用的镜像 |
| `fixtures/README.md` | 样本格式和脱敏规则（部分引用已失效，见“已知问题”） |
| `tools/gate/check_fixtures.py` | 样本隐私检查（Z02） |
| `apps/pure_live/lib/features/about/about_page.dart:59` | “关于”页打开第三方许可 |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `tools/gate/tests/test_check_fixtures.py`（13 个） | 样本里客户端地址的各种写法 |
| `apps/pure_live/test/services_test.dart:112` | 日志去掉 Cookie、令牌、密码、签名 |
| `packages/live_store/test/backup_test.dart` | 备份导出和恢复；`:119-121` 默认导出不含 `cookie` 一节，`:128` 用 `includeSensitiveData: true` 时带上并能恢复 |

## 3.x 基线

- 3.x 有 Firebase（`git show v3.2.11:pubspec.yaml:51-52` 的 `firebase_core`、`firebase_auth`，`android/app/google-services.json`）用于云账号登录；Cookie 明文存在 Hive 里（Y01.1 第 2 条、发布说明“Cookie 和 WebDAV 密码用 Android Keystore 加密保存（3.x 是明文）”）。
- 3.x 有 `SECURITY.md`（安全问题私密提交）和 `.gitleaks.toml`（提交前扫描密钥）。
- 4.x 去掉了 Firebase 和云账号（发布说明“3.x 的云账号登录已经停用”），加密存储账号，日志去秘密，样本有门禁检查。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| README“隐私”没写：检查更新和下载时会同时请求十几个第三方镜像；设备同步可以选择带上账号；日志会去掉秘密；仓库里的样本怎么脱敏 | `README.md:218-223` | 承诺不完整（说法本身没错） | Y04.1 |
| `fixtures/README.md` 引用的 `docs/adr/0009-fixture-format.md`、`spec/sites/<平台>.md`、`docs/modules/M4.*.md`、`tools/live_cli/...`、`test/fixtures_expected/` 都不存在 | `fixtures/README.md:3`、`:17`、`:24`、`:32`、`:43` | 脱敏规则说明里的链接全部失效 | Z06 已知问题；内容由 E07.1 取回 `tools/live_cli` 时一起改；Y04.1 在 README 里只写规则摘要，不链到失效的文件 |
| 没有提交前的密钥扫描（3.x 有 `.gitleaks.toml`） | — | 密钥误提交只靠 `.gitignore` 和合并审查 | Z02 已知问题，需要维护者决定 |
| 没有 `SECURITY.md`（3.x 有） | 仓库根目录 | 安全问题没有私密提交的说明 | Y04.1 可以在 README 里写一句（用 GitHub 的 Security Advisory） |

## 相关决定和规范

- D-006（签名文件和密钥不进 git）、D-005（README 等用户看的文字中文）。
- ENGINEERING 第 3 节“安全”：签名文件和密钥不进 git；Cookie 和密码加密存储、不写进日志；样本里的客户端地址必须脱敏（门禁检查）。
- PROCESS 第 7 节（不给其他执行者：签名文件、密钥、Cookie、用户的 3.x 数据）、第 9 节第 5 条（借鉴上游代码的许可）、第 14 节（不把真实 Cookie、账号、IP 写进仓库）。

## 测试和验证

- 门禁的“fixture privacy”一步（Z02）；`services_test.dart` 的日志去秘密；备份测试。
- 承诺的核对是人工的（上面的对照表）；每次改到网络请求的目的地（新镜像、新服务）时回来看 README 这一节。

## 路线

1. Y04.1（第三档，小）：把 README 的“隐私”写完整（第三方镜像、设备同步、日志、样本脱敏规则摘要、安全问题怎么报告），每条有代码依据。
2. Windows 发布时（X01.3）：README 的加密存储说法加上 Windows DPAPI；如果有安装包签名证书，写明发布者。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [Y 发布和运营](../README.md)。

- 代码：`tools/gate/check_fixtures.py`、`LICENSE`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| Y04.1 | 隐私说明写进 README：不收集数据、样本脱敏规则 | 发布 | 完成 | 2026-10-08 | — | [设计或说明](Y04.1-隐私说明写进README/README.md)、[任务书](Y04.1-隐私说明写进README/brief.md)、[记录](Y04.1-隐私说明写进README/record.md) |

<!-- docs:生成结束 -->
