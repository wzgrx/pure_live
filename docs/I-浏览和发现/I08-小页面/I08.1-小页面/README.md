# I08.1 小页面：工具箱、远程接收、关于、版本、启动页

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（页面重构）
- 来源：模块重构计划的页面部分（D-001）；3.x 的 `lib/modules/toolbox/`（611 行）、`remote_receiver/`（1758 行）、`about/`（1164 行）、`version/`（587 行）、`splash/`（172 行）和 `common/utils/version_util.dart`、`release_asset_urls.dart`、`githup_mirror.dart`、`plugins/update.dart`、`plugins/race_http.dart`
- 旧编号：M13.13、T07i.1
- 相关：E04.1（`LinkParser`）；J02.1（`BackupService`，设备同步用 3.x 备份格式）；I01.2（启动页、启动时检查更新接上）；I01.3（应用内下载、mDNS）；O03.1（扫码）；之后的 A15.1、A15.2、A06.3、A06.4、A12.6（界面）、Y02（更新通道）、J05（设备同步）；提交 `d5a0a060a`；记录 [record.md](record.md)

## 目标

在 4.x 里做出 3.x 的五个小页面：工具箱（链接跳转、获取直链）、设备同步（和 3.x 设备互通）、关于、版本页（检查更新、安装包和下载源、更新日志）、启动页；修掉 3.x 的问题：更新文件只在启动时读一次、版本号启动 2 秒内是 `0.0.0`、关掉自动检查仍联网、支持列表写死且过时、配对码可以穷举、发送接收没有超时。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 当时做成 | 现在（文件:行） |
|---|---|---|---|
| 工具箱 | 两张卡片各一个输入框；支持列表是翻译里写死的（还列着已下线的 Kick） | 一个链接框两个按钮；支持列表从平台登记生成 | 同，A15.1 定稿；`linkPlatforms` 挪到 `shared/links/supported_platforms.dart:12` |
| 工具箱取消 | 点光标也取消（`toolbox_controller.dart:24-25`、`:46-54`） | 文字变了才取消 | `features/toolbox/toolbox_actions.dart` |
| 检查更新 | `version_util.dart:77-90` 静态变量，只读一次；关掉自动检查仍联网（`home_page.dart:198-206`） | 版本页每次重新读；关掉不联网 | `features/version/update_prompt.dart:34`（Y02） |
| 版本号 | 启动 2 秒前是 `0.0.0`（`version_util.dart:63-70`） | 编译进程序的常量 | `features/version/app_version.dart:12`（Y01） |
| 下载更新 | 应用内下载对话框（约 950 行） | 交给系统浏览器 | 应用内断点续传（I01.3 `app/downloads.dart`，A06.3 `update_download.dart`），装 APK 前查“安装未知应用”权限 |
| 新版本对话框 | `NewVersionDialog` | 同（“更新”进版本页） | A06.3 重做（`update_prompt.dart:108`）；A15.2 另有一版设计，以哪个为准未定 |
| 历史版本 | `about/version_history.dart` | `about/release_history_view.dart` | 挪到 `features/version/release_history_view.dart`（555 行） |
| 设备同步配对码 | 6 位，答错不限次数（`remote_sync_service.dart:503-511`） | 连续答错 10 次换码 | `features/remote_receiver/remote_sync_service.dart:100`（J05） |
| 发送接收超时 | 没有（`:985-1120`） | 连接 5 秒、整次 2 分钟 | 同（`:81`） |
| 和 3.x 设备互相发现 | mDNS（bonsoir） | 只有 v4 之间的 UDP 广播 | I01.3 加 `mdns_peers.dart`（122 行） |
| 扫码 | mobile_scanner | 没有（缺依赖），手动框认二维码文字 | O03.1 加 `shared/qr_scan.dart` |
| 启动页 | 固定青色渐变、`main.dart:197` 的 `initialRoute` | 主题色、可跳过；`splashInitialLocation` 写好了，等协调者接 | 已接：`app/app.dart:119`；离开前等关注核验 350 毫秒（I01.2） |
| 项目声明 | 说“登录及云同步功能由 Firebase 提供” | 新键 `about_legalese`，去掉这句 | 同 |

## 结果

- 做了什么（详见 [record.md](record.md)“做法”）：`toolbox_actions.dart`、`toolbox_page.dart`、`version/update_feed.dart`（镜像竞速读两个更新文件、按平台覆盖、安装包挑选、17 个下载镜像）、`app_version.dart`、`version_page.dart`、`update_prompt.dart`、`markdown_text.dart`、`about/about_page.dart`、`release_history_view.dart`、`remote_sync_protocol.dart`（和 3.x 一字不差）、`remote_sync_service.dart`、`remote_receiver_page.dart`、`splash_page.dart`。
- 修了 3.x 问题 12 条（record.md“审查发现的 v3 问题及处理”；第 12 条没有调用者的方法不搬）。
- 界面改进 10 条（之后由 A15.1、A15.2、A06.3、A06.4、A12.6 定稿）。
- 翻译键中英文各 19 个；旧键 `toolbox_support_content` 等由 I01.2 删掉。
- 提交 `d5a0a060a`（2026-10-01）。
- 测试：当时 21 个（工具箱 6、版本 8、启动页 3、设备同步 4）。

## 验证

- 自动测试：现在 `apps/pure_live/test/features/toolbox/toolbox_page_test.dart` 10 个、`test/features/splash/splash_page_test.dart` 7 个、`test/features/version/version_page_test.dart` 18 个和 `update_dialogs_test.dart` 9 个、`test/features/remote_receiver/remote_sync_test.dart` 12 个。
- 真机：record.md 写“本次只在 WSL 上跑了测试”。S02.2 冒烟走过启动页和工具箱“进入直播间”；应用内更新、设备同步、扫码列在 [S02.4](../../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md)（未开始）；工具箱“获取直链”没有归属（见[子分类说明](../README.md)“已知问题”）。

## 留下的问题

- record.md“需要协调者接上”的两条：启动页路由（`app/app.dart:119`）、启动时检查更新（`features/home/home_page.dart:71`，电视 `tv/home/tv_home_page.dart:161`）都已接上。
- record.md“留给后续”现在的去向：应用内下载和安装 → I01.3、A06.3、A15.2（完成，真机在 S02.4）；扫码 → O03.1（完成）；和 3.x 设备互相发现 → I01.3（完成，真机在 S02.4 第 3 阶段）；实机检查 → S02.4；旧翻译键 → I01.2 已删。
- 版本页和设备同步现在归 Y02、J05；新版本对话框以哪个设计为准待维护者决定（A15.2 已记）。
