# Q04 网络状态和权限

应用怎么知道“现在有没有网、是不是移动数据”，以及访问局域网（电脑上的代理、家里的 IPTV 服务器、投屏设备）之前要的 Android 17 本地网络权限。

## 范围

- 包括：
  - `apps/pure_live/lib/app/network.dart`：`NetworkKind`（没有网、只有移动数据、其他）、`networkKindOf`、`readNetworkKind`（connectivity_plus；电脑上一律“其他”、插件出错也当“其他”）、`networkProbeProvider`、`networkChangesProvider`（网络变化）、`Offline` 异常、`MobileDataNotice`（列表加载前的断网预检和移动数据提示）。
  - `apps/pure_live/lib/platform/system_access.dart`：`SystemAccess`（通道 `pure_live/system_access`：能否安装应用、打开安装设置、本地网络是否允许、申请本地网络）、`isLocalNetworkUrl`、`ensureLocalNetworkFor`（打开局域网直播源前申请）、`LocalNetworkGuard`（代理指向局域网时申请，启动时和代理设置停 1 秒后检查）；Kotlin `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/SystemAccessPlugin.kt`、清单 `AndroidManifest.xml:21` 的 `ACCESS_LOCAL_NETWORK`。
  - 移动数据下的默认清晰度用哪个设置（`preferResolutionCellular`，由直播间按 `NetworkKind` 选，`room_controller.dart:407-411`）。
- 不包括（归哪里）：
  - 离线、加载失败、移动数据提示条的样子 → A02.1（通用状态组件）、`shared/rooms/room_grid.dart` 的提示条（A09）；错误文字 `room_texts.dart` 的 `describeLoadError`（A 组）。
  - 本地网络权限的真机验证和提示文字 → [O04.1](../../O-Android系统集成/O04-权限/O04.1-Android17本地网络权限/README.md)（O 组管 Android 权限的整体）；安装未知应用的权限 → Y02（更新安装）。
  - 投屏搜索时的权限（`local_network_denied_cast`）→ N02；设备同步 → J05。
  - 代理地址是不是局域网的判断函数 `isLocalNetworkProxyHost` → [Q02](../Q02-代理和镜像/README.md)（`packages/live_net/lib/src/proxy.dart:121`）。

## 现状：做到哪、怎么工作的

- 用户看得到的：
  - 热门页刷新时没有网络：列表区域显示“没有网络连接”的离线状态，连上网后自动重新加载（A02.1 的“离线”）；用移动数据加载时列表顶上一条“您当前正在使用移动蜂窝流量”的提示，可以“不再显示”（本次运行内）。
  - 进直播间时用移动数据就按“移动网络首选清晰度”选默认档。
  - 应用代理或播放代理填的是局域网地址时，Android 17 上启动后（或改完代理设置 1 秒后）弹系统的“本地网络”权限请求；拒绝了提示“未获得「本地网络」权限，局域网代理（如电脑上的 Clash）无法连接……”，本次运行不再问。播放局域网地址的直播源（家里的 IPTV 服务器）前也先申请，拒绝时提示局域网直播源无法连接。
- 内部怎么工作：
  - `readNetworkKind`（`network.dart:40-47`）：只在 Android、iOS 上问 connectivity_plus；`networkKindOf`（`:26-35`）：有 Wi-Fi 或以太网时即使同时有移动数据也算“其他”（3.x 只要列表里有移动数据就算，4.x 改了，`:22-25` 的注释）。
  - `MobileDataNotice.precheck`（`:82-86`）：没有网抛 `Offline`，是移动数据就把 `onMobileData` 置真；由 `RoomFeed` 的 `precheck`（`shared/rooms/room_feed.dart:427`）在刷新前调用——**只有热门页传了它**（`features/popular/popular_catalog.dart:57`）。
  - `room_grid.dart:270` 听 `networkChangesProvider`，从没有网变成有网时重新加载。
  - `SystemAccess._ask`（`system_access.dart:18-29`）：非 Android 一律允许；通道出错按各方法的默认值（本地网络默认允许）。`LocalNetworkGuard`（`:67-125`）监听四个代理设置，`settle` 1 秒后 `ensure`：需要且没授权、本次运行没问过才申请（`:107-115`）；`AppStartup` 在 Android 上启动它（`app/startup.dart:76`）。`ensureLocalNetworkFor`（`:56-61`）在直播间（`room_controller.dart:489`、`:691`）、多画面（`multiview_controller.dart:590`）打开局域网地址前调用。
  - Kotlin：`SystemAccessPlugin.kt`：`localNetworkGranted`（`:106`，API 37 以前一律真）、申请请求码 `20261003`（`:42`，4.0.0 发布前改的，Y01.1 第 4 节）。
- 完成度（和 3.x 对照）：
  - 一致：电脑不做预检；插件出错放行；移动数据提示“不再显示”只在本次运行；局域网代理的权限申请时机（3.x `LocalNetworkAccess.ensureForProxies`）。
  - 确认过的改动：Wi-Fi 和移动数据同时在时不算移动数据；离线后连上网自动重新加载（A02.1）；投屏和局域网直播源也先申请权限（4.0.0 发布前修复）。
  - 还缺：断网预检和移动数据提示只在热门页（见“已知问题”）；本地网络权限没有真机结果（O04.1）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/app/network.dart`（87 行） | `NetworkKind`（`:8`）、`NetworkProbe`（`:20`）、`networkKindOf`（`:26`）、`readNetworkKind`（`:40`）、`networkProbeProvider`（`:50`）、`networkChangesProvider`（`:55`）、`Offline`（`:62`）、`MobileDataNotice`（`:73`，`precheck` `:82`） |
| `apps/pure_live/lib/platform/system_access.dart`（125） | `SystemAccess`（`:12`：`canInstallPackages` `:32`、`openInstallSettings` `:35`、`localNetworkGranted` `:38`、`requestLocalNetwork` `:41`）、`isLocalNetworkUrl`（`:47`）、`ensureLocalNetworkFor`（`:56`）、`LocalNetworkGuard`（`:67`，`needed` `:88`、`ensure` `:107`） |
| `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/SystemAccessPlugin.kt`（143） | 通道实现：`LOCAL_NETWORK`（`:37`）、请求码（`:42`）、`localNetworkGranted`（`:106`）、申请（`:119` 起） |
| `apps/pure_live/lib/shared/rooms/room_feed.dart` | `precheck` 参数（`:260`、`:280`）和刷新前调用（`:427`） |
| `apps/pure_live/lib/shared/rooms/room_grid.dart` | 移动数据提示条（`:227-242`）、网络恢复后重新加载（`:270`） |
| `apps/pure_live/lib/features/popular/popular_catalog.dart:57` | 唯一传了 `precheck` 的地方 |
| `apps/pure_live/lib/app/startup.dart:76` | Android 上启动 `LocalNetworkGuard` |
| `apps/pure_live/lib/features/live_play/logic/room_controller.dart` | `_preferredQuality`（`:407-411`，移动数据用 `preferResolutionCellular`）；`ensureLocalNetworkFor`（`:489`、`:691`） |

测试：`apps/pure_live/test/plugins_test.dart`（`:68` 网络类型的判定；`:77` 列表刷新的断网预检和移动数据提示）；`apps/pure_live/test/services_test.dart`（`:336` 局域网代理只问一次本地网络权限；`:366` 局域网直播源先申请、拒绝时提示）。网络恢复后重新加载没有单独的用例。

## 3.x 基线

- `git show v3.2.11:lib/common/base/base_controller.dart`：`checkNetworkBeforeRequest`（`:29-46`）：电脑不预检；没有网时页面错误“当前无网络连接，请检查网络设置”；列表里有移动数据就显示提示条（`:40`），`neverShowCellularBanner` 是静态的（本次运行）。调用它的是所有分页列表：`common/base/live_directory_controller.dart:167`（分区目录）、`server_fixed_page_controller.dart:111`、`server_all_page_controller.dart:90`、`server_remote_page_controller.dart:88`、`:184`（热门、分区房间、搜索等）。
- `lib/common/services/local_network_access.dart:10`：Android 17 本地网络权限，代理指向局域网时申请（F-AND-04）。
- `lib/modules/live_play/controllers/player_controller.dart:594`、`:613`：WLAN 和移动数据各一个默认清晰度（F-ROOM-02）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 断网预检和移动数据提示只在热门页：`RoomFeed` 的 `precheck` 只有 `popular_catalog.dart:57` 传了；分区房间（`features/area_rooms/area_rooms_page.dart:72`）、电视分区房间（`tv/pages/tv_area_rooms_page.dart:54`）没传，分区目录、搜索也没有。3.x 的所有分页列表都预检 | `apps/pure_live/lib/features/area_rooms/area_rooms_page.dart:72-80` 等 | 断网时这些页面要等请求失败（最多 20 秒超时）才显示错误，而且是“加载失败”不是“没有网络连接”；移动数据下不提示。F-NET-03 登记“完成”只核对了热门 | 需要维护者决定：建议开小任务（Q04，第三档）给分区房间、分区目录、搜索补 `precheck`；或确认是有意的改动并写进 A02.1 |
| 本地网络权限没有真机结果（K90 就是 Android 17） | [O04.1](../../O-Android系统集成/O04-权限/O04.1-Android17本地网络权限/README.md)、CHECKLIST 第 5 节第 8 条 | — | O04.1 |
| 拒绝本地网络权限后本次运行不再问，要用户自己去系统设置 | `system_access.dart:110-113` | 照 3.x | 不做 |
| Q04.1 不做（功能清点余项，D-029） | [Q04.1](Q04.1-网络余项/README.md) | — | 缺的播放代理已由 O03.2 做完；F-NET-02、F-NET-04 的验证在 S02.4 |
| 代码注释里的旧编号（M12.x、F.0a） | `network.dart`、`system_access.dart` | 找文档先查 MAPPING | Z 组统一替换 |

## 相关决定和规范

- D-029：Q04.1 不做，要补的点由 O03.2 做完，验证并入 S02.4。
- D-019：本地网络权限在 K90（Android 17）上看。
- [specs/UI.md](../../../specs/UI.md) 附录（离线状态的行为在 A02.1 的设计里）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/plugins_test.dart test/services_test.dart`。缺的：分区和搜索的预检（功能没做）；网络恢复后自动重新加载（`room_grid.dart:270`）没有用例。
- 真机：[CHECKLIST](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 1 条（WLAN 和移动数据下进直播间，移动数据用“移动数据清晰度”）；第 5 节第 6 条（播放代理指向局域网代理）、第 8 条（本地网络权限：投屏、设备同步、局域网直播源）——S02.4、O04.1。

## 路线

1. O04.1 在 K90 上看本地网络权限的三种场景。
2. 请维护者决定分区、搜索的断网预检要不要补（建议补，第三档）。
3. 没有别的排着的任务。新想法（例如网络变化时自动降清晰度）写进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [Q 网络和代理](../README.md)。

- 代码：`app/network.dart`、`platform/system_access.dart`
- 进度：还没有任务


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| Q04.1 | 网络余项：功能清点里网络部分的 1 项缺失、1 项没验证 | 功能 | 不做 | — | — | [设计或说明](Q04.1-网络余项/README.md) |

<!-- docs:生成结束 -->
