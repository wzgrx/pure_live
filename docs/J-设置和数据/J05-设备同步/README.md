# J05 设备同步

局域网设备同步。

同一个局域网里两台装着纯粹直播的设备（4.x 和 4.x、4.x 和 3.x）互相发现、凭配对码把一台的设置和关注发给另一台，或者从另一台拿过来。协议和 3.x 一字不改，所以新旧版本能互通。设备同步页长什么样归 A12.6；这里管协议、服务、发现和安全。

## 范围

- 包括：
  - `apps/pure_live/lib/features/remote_receiver/remote_sync_protocol.dart`：端口、接口路径、配对码、二维码内容、发现包、设置包、地址解析。
  - `remote_sync_service.dart`：本机的 HTTP 服务（收别人的请求）、客户端（发送、取回、应用）、UDP 广播发现、配对码的轮换、带不带账号。
  - `mdns_peers.dart`：mDNS（bonsoir，服务类型 `_purelive-sync._tcp`，用 3.x 的 TXT 记录）发现，和 3.x 设备互相看见。
  - 设备 id：设置 `remote_sync_device_id`（`SettingScope.internal`，3.x 生成的照旧用）。
- 不包括（归哪里）：
  - 设备同步页、对方请求的确认框、配对码输入、接收前预览、扫码后选方向的样子 → [A12.6](../../A-界面设计/A12-账号和数据界面/A12.6-设备同步/README.md)（`remote_receiver_page.dart`，772 行）；扫码组件 `shared/qr_scan.dart` → O03.1。
  - 传的内容（备份格式）和恢复 → J03（`BackupService.exportAll` / `restoreAll`）；接收前预览用的是 J03 的 `previewRestore`。
  - Android 17 的“本地网络”权限、Wi-Fi 组播锁的原生部分 → O04（`platform/system_access.dart`）、O（`pure_live/multicast_lock`）。
  - 同步到电视（扫电视上的码，`/api/setSettings`）不是这个协议 → J03（`features/backup/tv_sync.dart`）。

## 现状：做到哪、怎么工作的

- 用户看得到的（备份与恢复 → 设备同步）：打开页面就开始服务和搜索；本机一栏显示地址 `ip:端口`、6 位配对码和二维码；发现的设备列在下面（4.x 设备经 UDP 广播和 mDNS，3.x 设备经 mDNS）；点一个设备选“发送到这台”或“从这台接收”，输入对方屏幕上的配对码；发送时对方弹“允许 / 拒绝”；接收时先取回对方的设置、显示“会改什么”的预览，确认后才应用；可以手动输入地址；手机上可以扫对方的二维码。“包含账号”开关默认关（同 3.x）。离开页面就停止服务。
- 内部怎么工作：

```text
RemoteSyncService.start()（remote_sync_service.dart:175）
  → SystemAccess.requestLocalNetwork()（Android 17；拒绝时提示 local_network_permission_denied 并返回，:180-183）
  → _pickLocalIp（:243：去掉 127、169.254；192.168 > 10 > 172.16/12 > 其他）
  → HttpServer.bind(anyIPv4, 39888 起找 100 个端口)（:186-198）→ 新配对码（:205）
  → _startDiscovery（:464）：UDP 39889 广播，每 5 秒宣告一次，2 分钟没听到的设备去掉；_startMdns（:489）：持组播锁、bonsoir 广播 + 发现
服务端 handleRequest（:285）：
  GET /api/remote-sync/status → 设备信息（不要配对码）
  GET|POST /api/remote-sync/settings → 先比配对码（常数时间，protocol :43），错 10 次换码（:317-325）
     → POST 先读正文、格式不对直接 400（不打扰用户）→ confirm(action, 对方地址) 问用户 → 允许才
        GET：BackupService.exportAll(includeSensitiveData: includeAccounts)；POST：BackupService.restoreAll
  不加 CORS 头（网页不能读设置）
客户端：send（:379，POST 设置包）、fetch（:395，GET 设置，只取不应用，页面先预览）、apply（:407）；
  _busy（:427）同时只做一件、2 分钟超时；_request（:441）用 dart:io HttpClient 直连（不走应用代理），连接 5 秒超时
```

- 线上格式（`remote_sync_protocol.dart`，和 3.x `lib/modules/remote_receiver/remote_sync_protocol.dart` 相同）：HTTP 端口 39888、UDP 39889、配对码头 `x-purelive-pairing`、6 位数字、二维码 `purelive://<ip>:<端口>/sync?code=<码>`、发现包 `type: pure_live_discovery`、设置包 `{type: pure_live_sync, version: 1, settings: <备份>}`。
- 完成度：I08.1 做了服务和页面，I01.3 接上 mDNS（和 3.x 互相发现），A12.6（`965d41956`）按设计重做页面并把“接收”拆成 `fetch` + 预览 + `apply`。功能点 F-BAK-05（设备同步）、F-BAK-06（扫码）“没验证”：**两台真设备之间从没同步过**，归 S02.4 第 3 条。
- 和 3.x 比：协议、端口、配对码、带不带账号的规则不变；多了接收前预览、错 10 次换码、POST 正文先校验、不加 CORS 头；3.x 的 `receiveFromAddress`（`remote_sync_service.dart:1041`）只请求 `/status` 就算成功，4.x 的“接收”是真的取回并应用。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/features/remote_receiver/remote_sync_protocol.dart`（111 行） | 常量（`:9-31`）、`newPairingCode`（`:34`，`Random.secure`）、`pairingCodesMatch`（`:43`，常数时间）、`createQrUri`（`:55`）、`discoveryPacket`（`:59`）、`settingsPacket`（`:77`）、`parseHttpAddress`（`:85`，只认 IPv4 和主机名，默认端口 39888）、`parseQr`（`:99`） |
| `apps/pure_live/lib/features/remote_receiver/remote_sync_service.dart`（590 行） | `RemoteSyncDevice`（`:17`）、`RemoteSyncConfirm`（`:61`）、`RemoteSyncService`（`:76`）：`maxWrongCodes = 10`（`:100`）、`includeAccounts`（`:122`）、`devices`（`:131`）、`qrData`（`:140`）、`deviceId`（`:145`，存 `remote_sync_device_id`）、`deviceName`（`:161`）、`start`（`:175`）、`stop`（`:216`）、`_pickLocalIp`（`:243`）、`handleRequest`（`:285`）、`_settings`（`:315`）、`send`（`:379`）、`receive`（`:387`）、`fetch`（`:395`）、`apply`（`:407`）、`_busy`（`:427`）、`_request`（`:441`）、`_startDiscovery`（`:464`）、`_startMdns`（`:489`）、`_announce`（`:537`）、`_heard`（`:567`） |
| `apps/pure_live/lib/features/remote_receiver/mdns_peers.dart`（122 行） | `MdnsPeer`、`MdnsPeers` 接口（`:12`，测试替换）、`BonsoirPeers`（`:29`，`_purelive-sync._tcp`，TXT 里带 id、name、platform、version、ip、port） |
| `apps/pure_live/lib/features/remote_receiver/remote_receiver_page.dart`（772 行） | 界面（A12.6）；逻辑相关：页面创建和销毁服务、`confirm` 回调接对方请求的确认框、接收时 `fetch` → `previewRestore` → `apply` |
| `apps/pure_live/lib/platform/system_access.dart` | `SystemAccess.requestLocalNetwork`（O04） |
| `apps/pure_live/lib/platform/platform_services.dart` | `MulticastLock`（`:70`，Android 收组播） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/remote_receiver/remote_sync_test.dart`（12） | 读 3.x 的二维码和地址（`:40`）；两台服务经真实 HTTP 用配对码和同意收发设置（`:52`）；错码被拒、错 10 次换码、没同意被拒（`:71`）；页面：本机地址和码、三组和开关、拿不到地址时的说明、发送（对方名字和六格码）、接收（码 → 预览 → 应用）、对方请求的确认框、手机扫码后选方向、宽屏两栏、横屏 |

## 3.x 基线

- `git show v3.2.11:lib/modules/remote_receiver/`：`remote_sync_service.dart`（1138 行）、`remote_sync_protocol.dart`（96 行）、`remote_sync_page.dart`（447 行）、`remote_sync_device.dart`、`local_address.dart`。
- `start`（`remote_sync_service.dart:145-172`）：先 `LocalNetworkAccess.ensure()`（`:154`，被拒就返回，提示和代理那句共用），拿不到本机地址时**不启动服务**（`:158-160`）；`confirmRequest`（`:39`）问用户；mDNS 服务类型 `_purelive-sync._tcp`（`:45`）；`syncToAddress`（`:985`）、`getRemoteSettings`（`:1079`）、`receiveFromAddress`（`:1041`，只查 `/status`）。
- 必须保留：线上格式和端口（3.x 设备要能互通）；配对码必填；对方必须在自己设备上同意；默认不带账号；设备 id 的设置键 `remote_sync_device_id`。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 被拒“本地网络”权限时，提示的是讲局域网代理的那句（“未获得「本地网络」权限，局域网代理（如电脑上的 Clash）无法连接……”） | `remote_sync_service.dart:180-182` 用 `local_network_permission_denied` | 用户在设备同步里看到讲代理的话，以为设置错了；3.x 一样（`remote_sync_service.dart:154` 调同一个 `ensure()`）。O 组发现 | 等 [O04.1](../../O-Android系统集成/O04-权限/O04.1-Android17本地网络权限/README.md) 真机确认后，加一句设备同步专用的提示（新翻译键，例如 `local_network_denied_sync`，投屏已有 `local_network_denied_cast`）；小改动，没有任务 |
| 两台真设备之间（4.x↔4.x、4.x↔3.x）从没同步过；扫码没在真机看 | 整个子分类 | mDNS、广播、组播锁、配对码在真网络里的表现不知道 | [S02.4](../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md) 第 3 条（CHECKLIST 第 5 节第 3 条）；另一台设备可以是电脑上的 Windows 版或模拟器，不能用用户手机上的 3.x |
| 拿不到本机地址时仍启动服务（3.x 不启动），页面只能说“没连网络或没给权限”，分不清是哪种 | `:184-204`；`remote_receiver_page.dart:438` | 用户要自己判断（A12 已知问题也记了） | 服务给出原因时再改文字；随上一条一起做 |
| 本机地址只在 `start` 时取一次，中途换 Wi-Fi 不更新 | `:184` | 换网络后二维码和地址是旧的，要离开页面再进 | 不做（3.x 一样） |
| 服务端收到的导入（对方“发送”过来）只有“允许 / 拒绝”，没有预览 | `:342-365` | 允许后直接按备份规则恢复（文件里没有的部分保持不变） | 照 3.x；要预览先进 V01 提议 |
| 只传 `BackupService` 的部分：搜索记录、网络电视列表、多画面上次的画面不随设备同步 | `:352`、`:380`、`:408` | 和本地完整备份不一样多 | 不做（3.x 设备读不了这些）；“发送前勾选同步哪些内容”见 [V01.6](../../V-需求和反馈/V01-新功能提议/V01.6-设备同步选择同步内容/README.md) |
| 明文 HTTP：设置（勾了“包含账号”时还有 Cookie）在局域网里明文传 | `_request` `:441` | 同一网络里能抓包的人能看到 | 照 3.x；默认不带账号，页面开关处有说明 |

## 相关决定和规范

- D-018（`remote_sync_device_id` 键不变）、D-019（真机不用用户的 3.x 当对端）、D-004（只做 Android，但服务在 Windows 上也能跑，测试可用电脑当对端）。
- O04（本地网络权限）、A12.6 S1（接收前预览，按建议 A）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/remote_receiver/`。
- 真机：S02.4 第 3 条：K90 上的测试包和另一台设备（电脑上的 Windows 版、模拟器上的 4.x 或 3.2.11）互相发现、扫码、发送、接收；Android 17 下先拒绝一次“本地网络”权限，看提示（O04.1）。

## 路线

1. O04.1 + S02.4 第 3 条：真机走通，确认提示文字问题。
2. 根据结果开小任务：设备同步专用的权限提示、拿不到地址时分清原因。
3. V01.6（第三档提议）：发送、接收前勾选同步哪些内容（参考上游 pure_live `9483ccf03`），用户确认后在本组登记实现任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [J 设置和数据](../README.md)。

- 代码：`features/remote_receiver/`
- 进度：还没有任务


还没有任务。

<!-- docs:生成结束 -->
