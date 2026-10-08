# Y04.1 隐私说明写进 README：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（从 master `d34ad44d1` 开始，在 Z04.1、S01.2 之后）
- 设计或说明：[README.md](README.md)、[brief.md](brief.md)

## 做了什么

- 根目录 `README.md`“隐私”一节（`:218-228`）按目标 1～5 重写成六条：不收集数据、账号信息、应用会连哪些地方（四小条）、代理、仓库里的平台样本。原来的四条说法都保留（都属实），补上设备同步可选带账号、Windows 的 DPAPI、日志去秘密、第三方镜像、自己填写的地址、样本脱敏规则和门禁。
- “反馈和参与”（`:403`）加一条：安全问题用 GitHub Security Advisory 私密提交。仓库已经打开私密漏洞报告（`gh api repos/wzgrx/pure_live/private-vulnerability-reporting` 回答 `{"enabled":true}`）。
- 没有改代码、`fixtures/README.md` 和 README 的其他章节。

## 对照表

| README 的说法（改后） | 改前 | 代码依据（文件:行） |
|---|---|---|
| 不需要注册账号，不收集数据，没有广告、统计、崩溃上报、云服务 | 有（没写云服务） | 14 个成员的 `pubspec.yaml` 没有统计、上报、云服务的包（`grep -i 'firebase\|sentry\|analytics\|crash\|bugly\|umeng'` 没有结果）；3.x 有 `firebase_core`、`firebase_auth`（`git show v3.2.11:pubspec.yaml:51-52`）；“旧版云端账号基于 Firebase，新版不再提供”（`apps/pure_live/assets/translations/zh.json:131`） |
| 日志只保存在本机，自己导出才离开设备 | 无 | `apps/pure_live/lib/app/app_log.dart:209-226`（本地日志文件，`enableLocalLog` 默认关，`packages/live_store/lib/src/settings/settings.dart:1447`）、`:311`（导出到用户选的位置）；文件里没有上传 |
| 关注、历史、设置保存在本机 | 有 | `packages/live_store/lib/src/database.dart`（本机 SQLite） |
| Cookie 和 WebDAV 密码加密：Android Keystore、Windows DPAPI（当前用户） | 只写了 Android Keystore | `apps/pure_live/lib/platform/secret_cipher.dart:9-14`（其他平台抛错，不存明文）、`:17-20`（AES-256-GCM、不可导出的 Keystore 密钥）、`:42-45`（DPAPI，当前用户） |
| 本地备份和 WebDAV 备份不含这两样 | 有（“备份文件里不含这两样”） | `packages/live_store/lib/src/backup/backup_service.dart:32-34`（`includeSensitiveData = false`）；本地备份 `apps/pure_live/lib/features/backup/backup_page.dart:241`；WebDAV 备份经 `apps/pure_live/lib/shared/backup/backup_data.dart:47` 调默认的 `exportAll()`；测试 `packages/live_store/test/backup_test.dart:119-121` |
| 设备同步默认不带，手动打开“同步账号 Cookie”才发给对方 | 无 | `apps/pure_live/lib/features/remote_receiver/remote_sync_service.dart:122`（`includeAccounts = false`）、`:352`、`:380`；开关 `remote_receiver_page.dart:505-506`；文字 `zh.json:1661` |
| 写日志时自动去掉 Cookie、令牌、密码、签名 | 无 | `apps/pure_live/lib/app/app_log.dart:56-68`（`_secretNames`）、`:127`（`redactSecrets`）、`:248`（每条日志都过一遍）；测试 `apps/pure_live/test/services_test.dart:112` |
| 连直播平台：页面、弹幕、图片、直播流 | 有（“直接和各直播平台通信”） | `packages/live_core`、`packages/live_danmaku` 各平台 |
| 自己填写的地址：网络电视播放列表和节目单、WebDAV、代理；设备同步和投屏只在局域网 | 无 | `packages/live_iptv`（用户添加的来源）；`apps/pure_live/lib/features/web_dav/`；设置 `appProxyHost`（`settings.dart:894`）；`packages/live_cast`（DLNA）；`remote_sync_service.dart`（局域网扫码配对） |
| 检查更新、下载安装包、字体、虎牙播放器配置会同时请求 GitHub 和十几个第三方镜像，镜像能看到 IP 和请求的文件 | 只写了“检查更新读 GitHub 上的版本文件”“下载安装包从 GitHub 或国内加速镜像” | `packages/live_net/lib/src/race.dart:85-140`（`GitHubMirror`：`raw.githubusercontent.com` 加 14 个前缀、kkgithub、两个 jsDelivr 节点）；更新 `apps/pure_live/lib/features/version/update_feed.dart:13`、`:376`；安装包 `:304-333`（`downloadSources`）；字体 `apps/pure_live/lib/app/fonts.dart:74`、`:343-345`；虎牙 `packages/live_core/lib/src/sites/huya/huya_site.dart:110-120` |
| “使用 GitHub 官方更新源”后检查更新和安装包只连 GitHub；字体和虎牙配置仍走镜像；自动检查可以关 | 只写了“启动时检查可以关掉” | `update_feed.dart:376`（`githubOrigin` 时只问 `raw`）、`:333`；`update_prompt.dart:81`；设置 `settings.dart:36-42`（`enableAutoCheckUpdate` 默认开、`useGitHubOriginForUpdates` 默认关）；文字 `zh.json:2498-2499`；`fonts.dart:343` 和 `huya_site.dart:117` 不看这个设置 |
| 没有自己的服务器 | 无 | 出站地址只有平台、用户填写的地址和上面的 GitHub 镜像（`apps/pure_live/lib` 里写死的地址清点：平台、`github.com`、镜像、坚果云帮助页） |
| 应用代理和播放代理分开 | 有 | Q 组；`settings.dart:894` 起的 `appProxy*` 和播放代理设置 |
| 平台样本只用于测试；地址换成 `203.0.113.x`；访客编号、设备编号、令牌、Cookie 换成同形合成值；门禁 fixture privacy 扫描全部样本（Base64、整数、弹幕帧） | 无 | `fixtures/README.md` 的规则；`tools/gate/check_fixtures.py:52`（放过的保留段和文档段）、`:130`（`leaks`，明文、Base64、整数）、`:210-219`（扫 `fixtures/*.json`、`*.jsonl`，失败时提示换成 `203.0.113.x`）；门禁 `tools/gate/gate.sh` 的 `fixture privacy` 一步 |
| 安全问题用 Security Advisory 私密提交 | 无 | 仓库设置（上文 `gh api`）；3.x 的 `SECURITY.md`（`git show v3.2.11:SECURITY.md`）作参考 |

## 发现的问题（不在本任务范围）

- `fixtures/README.md` 的失效引用（brief 列的 `:3`、`:17`、`:24`、`:32`、`:43`）：第 3 行指向 ENGINEERING 第 3 节和 E 组说明，录制工具和规则在归档标签 `v4-archive`，master 上没有（Z06、E07.1 处理）。README 只写规则摘要，没有链过去。
- `apps/pure_live/lib/platform/secret_cipher.dart:13` 在 Linux 上抛错：Linux 构建如果对外发布，需要先定加密方案，README 现在只写 Android 和 Windows。
- README“备份恢复、WebDAV 和设备同步”一节（`:206`）已经写了“同步账号 Cookie 需要手动打开”，和隐私一节一致。

## 留给维护者

- 要不要加 `SECURITY.md`（3.x 有）：README 已经写了提交方式，GitHub 的“安全”页会显示仓库的私密报告入口；加一个文件能在“安全策略”里显示同样的话。
