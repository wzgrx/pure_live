# Y04.1 隐私说明写进 README：任务书

## 背景

- 来源：docs v0（2026-10-02）登记（旧编号 T16e.1）：项目首页要写清“不收集数据、样本怎么脱敏”。同日 Y03.1 的 README 写了“隐私”一节（`README.md:218-223`），但没覆盖样本脱敏、设备同步带账号、第三方镜像、日志去秘密、安全问题怎么报告。
- 现象：README 说“检查更新时读取本仓库在 GitHub 上的版本文件”“下载安装包时从 GitHub 或国内加速镜像下载”，实际检查更新时也会**同时**请求十几个第三方镜像（`packages/live_net/lib/src/race.dart:92`）；说“备份文件里不含这两样（Cookie、WebDAV 密码）”，备份确实不含，但设备同步可以勾选带上账号（`remote_sync_service.dart:122`），README 没写。
- 为什么现在做：第三档；说法不是错的，只是不完整。
- 已经做过的：Y03.1（README）；Z02 的样本隐私检查；日志去秘密（`app_log.dart:127`）。

## 目标和验收

1. `record.md` 有一张对照表：README“隐私”每一条（改之前和改之后）对应的文件:行。
2. README“隐私”一节覆盖：不收集数据（没有统计、崩溃上报、云服务）；账号信息的存储（Android Keystore、Windows DPAPI；普通备份不含；设备同步可选择带上，默认不带）；日志自动去掉 Cookie、令牌、密码；应用会连哪些地方（直播平台；GitHub 和第三方加速镜像用于检查更新、下载安装包和字体、虎牙播放器配置；可以在设置里只用 GitHub）；两种代理。
3. README 有“仓库里的平台样本”一小段：只用于测试；客户端地址换成文档段 `203.0.113.x`，访客编号、设备编号、令牌、Cookie 换成同形的合成值；门禁 `fixture privacy` 自动检查。
4. “反馈和参与”一节写明安全问题用 GitHub 的 Security Advisory 私密提交。
5. 文字是写给用户看的中文，不出现代码路径和英文术语（GitHub、Keystore、DPAPI 这类专有名词除外）。

## 现状（读代码得出，写文件:行）

- README：`README.md:218-223` 隐私四条；`:395-398` 反馈和参与；`:400-404` 开源许可；`:406-411` 免责声明。
- 加密：`apps/pure_live/lib/platform/secret_cipher.dart:9-14`（Android `AndroidKeystoreCipher` `:20`，AES-256-GCM、不可导出的密钥；Windows `WindowsDpapiCipher` `:45`，当前用户；其他平台没有）。
- 备份：`packages/live_store/lib/src/backup/backup_service.dart:20-21`（账号只在要求时带上）、`:32-34` `exportAll({bool includeSensitiveData = false})`；`apps/pure_live/lib/features/backup/backup_page.dart:241` 调默认的 `exportAll()`；测试 `packages/live_store/test/backup_test.dart:119-121`（默认不含 `cookie`）。
- 设备同步：`apps/pure_live/lib/features/remote_receiver/remote_sync_service.dart:122` `bool includeAccounts = false;`、`:352`、`:380` 传给 `exportAll(includeSensitiveData: includeAccounts)`；界面开关 `remote_receiver_page.dart:505`。
- 日志：`apps/pure_live/lib/app/app_log.dart:52-60` `_secretNames`（cookie、set-cookie、authorization、proxy-authorization 和各平台的令牌字段）、`:104` 请求头行的正则、`:127` `redactSecrets`；测试 `apps/pure_live/test/services_test.dart:112`。
- 出站：`apps/pure_live/lib/features/version/update_feed.dart:12`（`updateRepository`）、`:340-346`（`githubOrigin` 时只问 GitHub，否则问 `mirrors`）；`packages/live_net/lib/src/race.dart:92-140`（`GitHubMirror` 的前缀列表）；设置 `useGitHubOriginForUpdates`、`enableAutoCheckUpdate`（`packages/live_store/lib/src/settings/settings.dart:36-40`）。字体下载 `apps/pure_live/lib/app/fonts.dart`。
- 依赖：13 个成员的 `pubspec.yaml` 没有统计、上报、云服务的包（用 `grep -i 'firebase\|sentry\|analytics\|crash' */pubspec.yaml packages/*/pubspec.yaml` 核对）。
- 样本：`fixtures/README.md`（规则；`:3`、`:17`、`:24`、`:32`、`:43` 的引用已失效）；`tools/gate/check_fixtures.py`（`main` `:210`，失败时提示换成 `203.0.113.x`）。

## 3.x 基线

- `git show v3.2.11:pubspec.yaml:51-52`（`firebase_core`、`firebase_auth`）、`android/app/google-services.json`：3.x 有云账号；4.x 没有。
- `git show v3.2.11:SECURITY.md`：3.x 的安全问题提交说明（参考写法）。
- 要保留的：README 现有的四条说法（都属实）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 7 节、第 14 节）、`docs/specs/ENGINEERING.md` 第 3 节“安全”。
2. 本文件夹的 `README.md`；`docs/Y-发布和运营/Y04-隐私和合规/README.md`（对照表）；根目录 `README.md`；`fixtures/README.md`。

## 范围

- 可以改：根目录 `README.md` 的“隐私”“反馈和参与”两节；本文件夹的文档。
- 不能改：任何代码；`fixtures/README.md`（失效引用列进报告）；README 的其他章节（发现问题列进报告，Y03 处理）；版本号、`assets/version.json`、`assets/releases.json`。
- 不写：任何真实的 Cookie、账号、地址、密钥（包括举例）。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 核对、c2 改“隐私”和“反馈和参与”、c3 样本一段 | `README.md`、`record.md` | 验收 1～5 |

规模小，一个阶段。

## 测试

- 不涉及代码测试；`python3 tools/docs/docs.py --check`（README 里写的 `docs/` 路径要存在）。

## 真机验证

不需要（文档）。

## 风险和注意

- 不要过度承诺：例如不要写“不连任何第三方”（镜像就是第三方），不要写“所有平台都加密”（Linux 等平台现在没有加密器）。
- 可能冲突的文件：根目录 `README.md`（Y03、Z07.2 也改；合并时两边都保留）。

## 环境和提交

- 不需要 Flutter。
- 分支 `ai/Y04.1` 或本机工作区；提交信息以 `[Y04.1]` 开头（英文）；不推 master。
- 提交前：`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `next`。

## 报告（中文，简洁）

改了哪几条、每条的代码依据；新增的说法；发现的不一致（`fixtures/README.md` 的失效引用等）；需要维护者决定的（要不要加 `SECURITY.md`）。
