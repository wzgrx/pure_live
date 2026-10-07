# J03.1 备份与 WebDAV

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（模块重构：备份页和 WebDAV 页）
- 来源：模块重构计划 M13.10（3.x 的 `lib/modules/backup/`、`lib/modules/web_dav/` 按 4.x 的结构重写）；用户 2026-10-01 授权界面、操作、视觉反馈可以改进，数据仍在 `live_store`、3.x 的备份文件和 WebDAV 配置都能读
- 旧编号：M13.10、T09c.1
- 相关：依赖 J02.1（`BackupService`、`LegacySnapshot`、`WebDavStore`）、Q01.1（`LiveHttp`）；之后的 J04.1（Digest 认证）、A12.4、A12.5（按确认的设计重做页面）、O03.1（系统文件选择器、扫码）、E06.1（备份带上网络电视列表和多画面）；记录 [record.md](record.md)

## 目标

备份页和 WebDAV 页在 4.x 里能用，且比 3.x 安全：恢复前让用户看清会改什么、确认后才写；失败分开说明原因；WebDAV 走应用的网络通道（应用代理生效）；3.x 的备份文件、备份目录和 WebDAV 配置照旧能用，4.x 的备份 3.x 也能读回。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在 | 要做到 |
|---|---|---|---|
| 创建备份 | 每次弹出选目录（`plugins/backup_recovery_service.dart:13`），文件名只到秒，同一秒两次后一次覆盖（`:28`） | 直接写进备份目录，重名加 `_2`（`shared/backup/backup_files.dart:18`） | 完成 |
| 恢复 | 本地恢复不确认（`backup_recovery_service.dart:79-92`），WebDAV 只问“确定覆盖吗”（`web_dav_page.dart:194-204`） | 先预览每部分“现在 → 恢复后”，确认才写（`shared/backup/backup_data.dart:248`、`backup_preview_dialog.dart:140`） | 完成 |
| 失败提示 | 一律“恢复备份失败”（`backup_recovery_service.dart:88-91`） | 不是备份文件、读不了、另一个恢复正在进行、仅关注文件分开说 | 完成 |
| 同步电视 | 扫码，整份数据放 URL 查询参数（`:122-125`） | 放请求体（`features/backup/tv_sync.dart:49`）；当时改成输入地址，O03.1 之后手机上照 3.x 扫码 | 完成；真电视没试 |
| 搜索记录 | 不在备份里 | 完整备份带 `search` 分区（3.x 忽略） | 完成 |
| WebDAV 网络 | webdav_client 自带的 Dio，应用代理无效（`webdav_service.dart:17`） | 自己的客户端走 `LiveHttp`（`features/web_dav/web_dav_client.dart`） | 完成 |
| WebDAV 认证 | webdav_client 按 `WWW-Authenticate` 选 Basic 或 Digest | 当时只做了 Basic | J04.1 补上 Digest |
| WebDAV 列表 | 服务器返回的顺序、`DateTime.toString()` 原样、没有大小（`web_dav_page.dart:502`） | 文件夹在前、文件按修改时间新到旧、本地时间和大小 | 完成 |
| WebDAV 填错 | 要等列表加载失败才知道，错误是英文的 DioException 原文（`web_dav_controller.dart:222`、`:355`） | 对话框里“测试连接”，错误按类型翻译 | 完成 |
| 存储权限 | 为存一个备份申请“所有文件访问”（`file_utils.dart:69-86`） | 默认目录不需要权限，写不了时提示换目录 | 完成；真机没看 |

## 结果

- 提交：`1b730f77e`（2026-10-01 合并）。
- 做了什么（详见 [record.md](record.md)）：
  - c1 备份页：本地备份（完整、仅关注）、从文件恢复、备份目录（默认目录、改回默认、桌面上打开目录）、目录里的备份列表、WebDAV / 设备同步 / 同步到电视入口。
  - c2 恢复预览：`LegacySnapshot.fromBackup` 读出文件（和 `BackupService` 同一套解析），逐项和当前数据比较（设置、关注、关注分区、历史、分组、屏蔽词、屏蔽用户、WebDAV 服务器、搜索记录、账号条数），文件里没有的部分列成“保持不变”；仅关注文件自动改为只恢复关注。
  - c3 搜索记录进完整备份（I05.1 留下的问题，理由：同属使用记录、体积小、不含账号）。
  - c4 WebDAV 页：服务器列表、目录浏览和面包屑、上传完整 / 仅关注、恢复、删除、帮助（3.x 的坚果云教程文字）、测试连接、显示密码；客户端 `WebDavClient`（PROPFIND、GET、PUT、DELETE，多状态回答的解析不依赖命名空间前缀）。
  - c5 修了 11 个 3.x 问题（record“v3 问题及处理”）。
- 偏差：Digest 认证、系统文件选择器、扫码、WebDAV 帮助截图、日志管理当时没做——Digest 由 J04.1（`c168fdb99`）、选择器和扫码由 O03.1、日志页和帮助页的 7 张截图（`apps/pure_live/assets/webdav/`，`web_dav_help.dart:165` 起）由 I01.3（`4f55a8da2`）做完。之后 A12.4、A12.5（`965d41956`）按确认的设计重做了两个页面，逻辑没变；E06.1（`f8acb92b6`）让完整备份带上网络电视列表和多画面上次的画面。
- 测试：当时 10 个（`backup_page_test.dart` 7、`web_dav_page_test.dart` 3）；现在 `test/features/backup/backup_page_test.dart` 18 个、`test/features/web_dav/web_dav_page_test.dart` 10 个、`test/shared/backup_extras_test.dart` 4 个。

## 验证

- 自动测试：`cd apps/pure_live && flutter test test/features/backup/ test/features/web_dav/ test/shared/backup_extras_test.dart`。
- 真机：**没有 K90 结果**。要看的：`Download/PureLive` 免权限写入、恢复一个 3.x 导出的备份（CHECKLIST 第 5 节第 1 条）、坚果云测试连接 / 上传 / 恢复（第 2 条），都在 [S02.4](../../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md)；登记表按当时“构建通过 + 单元测试”记成“完成”。

## 留下的问题

- 真机：见上，S02.4 做完后把结果补进本节。
- 同步到电视没对真的电视版试过 → 有电视盒子时顺带（J03 子分类页“已知问题”）。
- “备份包含账号”（Cookie、WebDAV 密码）→ 不做：3.x 本地和 WebDAV 备份都不含账号，加了要先问用户。
