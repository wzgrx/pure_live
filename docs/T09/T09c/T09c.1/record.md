# T09c.1 页面：备份与 WebDAV

- 日期：2026-10-01
- 目录：`apps/pure_live/lib/features/backup/`（路由 `RoutePath.kBackup`）、`apps/pure_live/lib/features/web_dav/`（路由 `RoutePath.kWebDavPage`），类名 `BackupPage`、`WebDavPage` 和构造参数不变
- v3 来源：标签 `v3.2.11` 的 `lib/modules/backup/`（`backup_page.dart` 317 行、`scan_page.dart` 325 行）、`lib/modules/web_dav/`（6 个文件：`web_dav_page.dart` 779、`web_dav_controller.dart` 452、`web_dav_help.dart` 382、`webdav_service.dart` 31、`webdav_config.dart` 49、binding），以及它们调用的 `lib/plugins/backup_recovery_service.dart`（131 行，选目录和文件、同步电视）
- 用到的模块：T09b.1（`BackupService`、`LegacySnapshot`、`WebDavStore`、设置 `backupDirectory`、`MetaStore`）、T03a.1（`LiveHttp`）、T01a.1（设置卡片、`AppStatusView`、`EmptyView`、文字样式、图标）、T07a.1（provider、`AppNavigator`、`i18n`）、T07f.1（搜索记录的键 `SearchHistory.key`）

## 做法

| 文件 | 内容 |
|---|---|
| `backup/backup_page.dart` | 备份页：本地备份（完整、仅关注）、从文件恢复、备份目录、目录中的备份列表、WebDAV / 设备同步 / 同步到电视入口。页面内 provider：时钟、默认目录、文件选择器（测试替换） |
| `backup/backup_data.dart` | 导出和恢复（包一层 `BackupService`，加上搜索记录）、恢复预览 `previewRestore`；`backupServiceProvider` 让备份页和 WebDAV 页共用一个 `BackupService`，它的“同一时间一个恢复”锁对两页都有效 |
| `backup/backup_preview_dialog.dart` | 预览对话框和两页共用的恢复流程 `restoreWithPreview`（读取 → 预览 → 确认 → 恢复 → 提示，各种失败分开提示） |
| `backup/backup_files.dart` | 文件名（沿用 3.x 的 `purelive_<时间>.txt`、`purelive_favorites_<时间>.txt`，重名加 `_2`）、默认目录、列出目录中的备份、应用内的目录/文件浏览框（应用还没有系统文件选择器时的本地替代） |
| `backup/tv_sync.dart` | 同步到电视：地址规范化（同 3.x 扫码地址规则，另接受不带 `http://` 的 `IP:端口`）、3.x 的扁平文档 `exportToTVSettings`、发送 |
| `web_dav/web_dav_page.dart` | WebDAV 页：服务器列表（右侧抽屉）、目录浏览和面包屑、上传、恢复、删除。页面内 provider：HTTP 客户端、时钟（测试替换） |
| `web_dav/web_dav_client.dart` | 最小的 WebDAV 客户端（`PROPFIND`、`GET`、`PUT`、`DELETE`，Basic 认证），走应用的 `LiveHttp`；多状态回答的解析不依赖命名空间前缀 |
| `web_dav/web_dav_config_dialog.dart` | 添加/编辑服务器，测试连接，错误按类型翻译 |
| `web_dav/web_dav_help.dart` | WebDAV 帮助（3.x 的坚果云教程文字） |

- **数据都在 `live_store`**：服务器和当前选择用 `store.webdav`（密码在密钥库，T09b.1），备份目录是设置 `backupDirectory`（3.x 的值由 T09b.1 原样导入），恢复走 `BackupService.restoreAll` / `restoreFollows`，文件格式就是 3.x 的分区布局（`backupVersion: 4`，3.x 能读回）。
- **恢复前预览**：用 `LegacySnapshot.fromBackup` 读出文件（和 `BackupService` 同一套解析，格式错误在这里就报出来），和当前数据逐项比较：设置（文件中几项、几项与当前不同）、关注的直播间、关注的分区、观看历史、关注分组、屏蔽词、屏蔽用户、WebDAV 服务器、搜索记录（“现在 → 恢复后（新增 N，移除 M）”，按身份比较）、账号信息条数；文件里没有的部分列成“保持不变”；读不了的条目数；文件来源（早期无版本、3.x 版本 N、v4、仅关注）。用户确认后才写入。
- **搜索记录进备份（T07f.1 留下的问题）**：决定**进完整备份**。理由：观看历史本来就在备份里，搜索记录同属使用记录、体积很小，换设备的人希望一起带走；它不含账号信息。做法：完整备份多一个分区 `"search": {"history": [...]}`（3.x 和 `BackupService` 都忽略不认识的分区，所以 3.x 仍能恢复这个文件）；恢复完整备份时文件里有这个分区就替换搜索记录（同搜索页的清理规则：去空白、截断、不分大小写去重、最多 20 条），3.x 的备份没有它，搜索记录保持不变；仅关注备份不带。
- **账号**：本地备份、WebDAV 上传、同步到电视都不带 Cookie 和 WebDAV 密码（同 3.x）；恢复的文件里有账号（3.x 局域网同步导出的那种）时照写，预览里列出条数。

## 与 v3 的功能对照

| v3 | v4 | 说明 |
|---|---|---|
| 备份页“云端备份”：Firebase 账号（登录 / 我的、连接中、初始化失败重试） | 去掉 | T07a.1 已去掉 Firebase（T07a.1 问题 10），账号页另议 |
| WebDAV 入口 | 有 | |
| 设备同步入口（`kRemoteSync`） | 有 | 远程同步页本身是后面的 M13 页面 |
| 同步 TV 数据：扫电视的二维码，把关注、历史、弹幕设置、IPTV UA 发给电视（仅手机） | 有，改为输入地址 | 扫码要 mobile_scanner，应用还没有（见“留给后续”）；所有平台都能用 |
| 创建备份（选目录，第一次成功后记住目录） | 有 | 直接写入备份目录，不用每次选 |
| 恢复备份（选 `.txt` 文件） | 有 | 应用内选文件（`.txt`、`.json`），先预览 |
| 仅导出关注列表 / 仅导入关注列表 | 有 | 都有预览 |
| 备份目录设置 | 有 | 另加默认目录、改回默认、桌面上打开目录 |
| 每个操作显示转圈，同一时间只做一个 | 有 | |
| 日志管理（本地日志开关、浏览器查看日志、打开日志目录） | 没有 | 日志服务还没有（T07a.1 记为 M13），留给设置或工具箱页 |
| Android 申请“所有文件访问”权限（`MANAGE_EXTERNAL_STORAGE`） | 没有 | 默认目录不需要权限；选到不能写的目录时提示换目录（缺权限申请接口，见“留给后续”） |
| WebDAV：服务器列表（侧栏），选择、编辑、删除（确认）、添加 | 有 | 标题栏按钮打开侧栏，标题下显示当前服务器 |
| WebDAV：配置对话框（名称编辑时不可改、地址校验、用户名、密码必填，名称重复提示） | 有 | 加显示密码、测试连接 |
| WebDAV：打开页面恢复上次的服务器；保存的地址无效时提示 | 有 | |
| WebDAV：目录浏览、面包屑、返回上一级 | 有 | 系统返回键也回到上一级 |
| WebDAV：上传完整备份（悬浮按钮）、仅上传关注列表（菜单） | 有 | |
| WebDAV：文件菜单（恢复全部设置、仅恢复关注列表、删除并确认） | 有 | 点文件也打开菜单；恢复前预览 |
| WebDAV：刷新、使用帮助教程（坚果云步骤、复制地址、打开官方帮助） | 有 | 帮助页暂时没有截图（见“留给后续”） |
| WebDAV：加载中、出错重试、空目录、没有配置、未选择配置 | 有 | |
| WebDAV：文件图标按 MIME 类型（图片、视频、音频、文本） | 简化 | 文件夹、备份文件、其他文件三种，不再依赖 mime 包 |
| WebDAV：Digest 认证（webdav_client 支持） | 没有 | 只做了 Basic（坚果云、Nextcloud、Alist 都用 Basic），见“留给后续” |

## v3 问题及处理

| # | 问题 | 位置 | 处理 |
|---|---|---|---|
| 1 | 同一秒内创建两次完整备份，后一次覆盖前一次（完整备份的文件名只到秒；仅关注备份和 WebDAV 上传都加了 uuid） | `backup_recovery_service.dart:28` | 重名时加 `_2`、`_3`，名字仍是 3.x 的格式 |
| 2 | 恢复前只问“确定覆盖吗”，不说会改什么；用户不知道一个旧备份会把关注列表换掉多少 | `web_dav_page.dart:194-204`，本地恢复连确认都没有（`backup_recovery_service.dart:79-92`） | 恢复前预览，确认后才写入（本地恢复也要确认） |
| 3 | 用“恢复备份”选了仅关注的文件，只提示“恢复备份失败” | `backup_controller.dart`（`restoreAllSettings` 拒绝仅关注文件）+ `backup_page.dart` 的笼统提示 | 自动改为只恢复关注，预览里说明 |
| 4 | 失败一律“恢复备份失败”：不是备份文件、文件读不了、另一个恢复正在进行，用户分不清 | `backup_recovery_service.dart:88-91` | 分开提示 |
| 5 | 同步电视把整份数据放在 URL 查询参数里，关注和历史多时超过 URL 长度限制 | `backup_recovery_service.dart:122-125` | 放进请求体 `{"settings": …}`（电视版 `/api/setSettings` 两种都读） |
| 6 | WebDAV 文件按服务器返回的顺序显示，备份多了很难找最新的 | `web_dav_controller.dart` `loadFiles` | 文件夹在前，文件按修改时间新到旧 |
| 7 | WebDAV 文件时间显示 `DateTime.toString()` 的原始格式（UTC、带毫秒），没有大小 | `web_dav_page.dart:502` | 本地时间 `yyyy-MM-dd HH:mm` 加大小 |
| 8 | WebDAV 填错地址或密码，要等列表加载失败才知道；错误直接显示异常文本（英文的 DioException） | `web_dav_controller.dart:222`、`:355` | 对话框加“测试连接”；错误按类型翻译：账号密码错误、找不到目录、连不上、服务器状态码 |
| 9 | WebDAV 用 webdav_client 自带的 Dio，不经过应用的 HTTP 客户端，应用代理对它无效 | `webdav_service.dart:17` | 走应用的 `LiveHttp`（应用代理生效） |
| 10 | WebDAV 下载的文件不是 UTF-8 时 `utf8.decode` 抛异常，提示成“下载失败” | `web_dav_controller.dart:410` | 宽松解码，解析不了时提示“不是备份文件” |
| 11 | Android 为了存一个备份文件申请“所有文件访问”权限 | `file_utils.dart:69-86` | 默认目录不需要权限 |

T09b.1 已解决的相关问题（这里不再重复）：WebDAV 当前配置多存一份带明文密码的 JSON（T09b.1 问题 2）、恢复只含部分分区的备份会重置其他设置（T09b.1 问题 3）、恢复没有事务（T09b.1 问题 4）。

## 界面改进

（2026-10-01 用户授权：界面、操作、视觉反馈可以改进；数据仍在 `live_store`，3.x 的备份文件、备份目录和 WebDAV 配置都能读。）

1. **一键备份**：“创建备份”直接写入备份目录（3.x 每次弹出选目录），成功提示带文件名。
2. **目录中的备份**：备份页新增一组，列出备份目录里的 `purelive*` 文件（新到旧，时间、大小、完整/仅关注），点一下恢复，菜单里还有“仅恢复关注列表”“删除”；下拉刷新。3.x 用户把旧备份放进这个目录就能直接恢复。
3. **默认目录**：没设置过备份目录时用默认目录（Android `Download/PureLive`，不能写时用应用自己的目录；Windows `文档\PureLive`），页面上显示路径；设置过的可以“改回默认目录”；桌面上可以“打开备份目录”。
4. **恢复预览**：见“做法”，本地和 WebDAV 恢复都一样；没有变化时说明“文件内容和当前数据相同”；提示先备份。
5. **分开的失败提示**：见问题 4、8、10。
6. **同步到电视**：输入电视同步页显示的地址即可（说明会发送哪些内容、不含账号）；失败时提示检查电视端和局域网。
7. **WebDAV 测试连接、显示密码**：对话框里直接验证服务器；密码可以切换显示。
8. **WebDAV 列表**：文件夹在前、备份文件有单独图标、显示时间和大小；点文件打开操作菜单（3.x 点文件没反应，只能点右边的菜单）；系统返回键回到上一级目录；面包屑始终显示当前目录。
9. **WebDAV 空状态**：没有配置时说明 WebDAV 的用途并给“创建新配置”按钮；空目录提示“点右下角按钮把当前数据备份到这里”。
10. **标题栏**：WebDAV 标题下显示当前服务器名，服务器列表、刷新各有按钮（3.x 都在一个菜单里）。

## 已批准的升级（docs/specs/UPGRADES.md）

`docs/specs/UPGRADES.md` 没有属于本页的条目。

## 缺的共享服务和接口

| 内容 | 现在的做法 | 需要协调者加 |
|---|---|---|
| 系统文件/目录选择器（3.x file_picker） | 应用内浏览框（`showFileBrowser`，`dart:io`），可以输入路径；Android 上只看得到应用能读的目录 | 加 file_picker（或 Android SAF）后替换 `backupPickerProvider` |
| Android 存储权限申请（3.x permission_handler） | 默认目录不需要权限；不能写的目录提示换一个 | 需要读写公共目录时加权限接口 |
| 扫码（3.x mobile_scanner） | 同步电视改为输入地址 | 加依赖后在电视对话框里加“扫码” |
| WebDAV 帮助截图（3.x `assets/webdav/*.png`，7 张） | 只有文字步骤 | 拷贝图片并在 `apps/pure_live/pubspec.yaml` 登记 |
| 日志服务（3.x `LogController`、`LogFileWriter`） | 备份页不再有日志管理 | 日志服务和页面（设置或工具箱） |

## 留给后续

| 内容 | 去向 |
|---|---|
| 上表的依赖和资源 | 协调者 |
| WebDAV Digest 认证 | 有用户需要时在 `web_dav_client.dart` 加 |
| 搜索记录现在由页面在 `BackupService` 的结果上追加；建议以后挪进 `BackupService`（新窗口交接、局域网同步也会带上） | T09b.1 后续 / 远程同步页 |
| Android 真机检查：`Download/PureLive` 在 Android 11+ 不申请权限能否写入、3.x 的备份目录（常在公共目录）能否读取 | 真机测试时 |
| 可选“备份包含账号”（Cookie、WebDAV 密码） | 不做：3.x 本地和 WebDAV 备份都不含账号，加了要先问用户（T09b.1 也记了“备份口令加密不做”） |

## 测试

10 个用例（加速流程，只测主要路径）：

| 测试文件 | 内容 |
|---|---|
| `test/pages/backup/backup_page_test.dart`（7） | 预览：3.x 备份的增删计数、保持不变的部分、非备份文件报错；仅关注文件自动改为恢复关注；搜索记录随完整备份往返、3.x 备份不动搜索记录；文件名、重名、电视文档和地址规则；页面：创建备份写入默认目录并列出；从目录恢复 3.x 文件（预览文字、取消不改、确认后写入）；选到非备份文件时什么都不改 |
| `test/pages/web_dav/web_dav_page_test.dart`（3） | 多状态回答（不同前缀、编码的中文名、跳过目录自身和别处的路径）；页面（内存里的 WebDAV 服务器）：添加服务器时测试连接（密码错 → 正确）、保存后列出文件、上传完整备份、从服务器恢复（预览后写入）；进入子目录、删除确认、面包屑回到根目录 |
