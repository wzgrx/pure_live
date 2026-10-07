# N02 投屏

DLNA 设备搜索和投屏控制。

把直播间当前的直播地址投到同一局域网里的电视、盒子、投屏接收软件（DLNA / UPnP 的 MediaRenderer）：搜索设备、列出能投的、设置地址并播放、换设备、失败重试。协议和流程在 `packages/live_cast`；入口在直播间的取流弹窗（C03、A07.6）。

## 范围

- 包括：
  - `packages/live_cast/lib/src/`：`ssdp.dart`（M-SEARCH 报文和轮次、应答和通告的解析、按网卡开的 UDP 套接字、1900 端口的通告监听）、`discovery.dart`（`SsdpDiscovery`：v3 的搜索节奏、每台设备只读一次描述、离开和 120 秒无消息）、`description.dart`（设备描述解析、找 AVTransport、控制地址解析）、`renderer.dart`（`DlnaRenderer`：SOAP 设置地址、播放、暂停、停止、读状态，忙时重试；`CastMedia`、`didlLite`）、`soap.dart`、`http.dart`（直连局域网、整次计时）、`failure.dart`（带类型的错误、UPnP 错误码）、`controller.dart`（`DlnaCastController`：v3 对话框里的流程）。
  - 应用里的接法：`apps/pure_live/lib/features/live_play/dialogs/stream_dialogs.dart` 的 `CastDevices`（`:290` 起：建控制器、持组播锁、每次搜索前申请本地网络权限、投给电视的标题）、`castDiscovery`（`:282`，测试替换）。
- 不包括（归哪里）：
  - 投屏列表的样子、取流弹窗（选画质 → 选线路 → 复制或投屏）→ A07.6；直播间菜单和控制栏的入口、会话型的流不能投的判断（`stream_dialogs.dart:111`，`toolbox_session_source`）→ C03。
  - 组播锁的原生部分（`AppChannelsPlugin.kt` 的 `pure_live/multicast_lock`，`:58`）、Android 17 的本地网络权限（`SystemAccess.requestLocalNetwork`）→ O、O04。
  - 投给“纯粹直播电视版”的同步（不是 DLNA）→ J03 的同步到电视。

## 现状：做到哪、怎么工作的

- 用户看得到的（直播间 → 菜单或画面上的“投屏” → 选画质 → 选线路 → 投屏到）：列表上方写“原画 · 线路1 · 投屏到”，右边刷新；搜 20 秒，搜到的设备（名字和地址，名字为空显示“未知设备”）陆续出现；点一个，行尾转圈，成功后打勾并提示“已开始投屏”，失败红字和提示“投屏失败”、可以再点；换一台设备时先暂停上一台；电视上显示“主播 - 标题”（3.x 显示地址）；关掉对话框后已经在播的电视继续播。Android 17 上第一次搜索会申请“本地网络”权限，拒绝时提示“未获得「本地网络」权限，无法搜索投屏设备……”，列表显示“搜索失败”。
- 内部怎么工作：

```text
CastDevices.initState（stream_dialogs.dart:313）
  DlnaCastController(url, title: CastMedia.roomTitle(主播, 标题), startDiscovery: _discover, onNotice: 提示)
  MulticastLock.acquire（很多手机不持锁收不到 SSDP 通告）→ startSearch
_discover（:335）：SystemAccess.requestLocalNetwork() 被拒 → 提示 local_network_denied_cast 并抛错（显示“搜索失败”）→ castDiscovery()
DlnaCastController（controller.dart:123）
  normalizeDlnaSource（:11）：只投 http/https、有主机、不带用户名密码；否则 invalidSource，不搜
  startSearch（:179）：清空列表、放掉旧搜索（晚到的结果丢掉）、20 秒后停（:131）；没搜到 → empty；失败 → failed；已有设备时中断 → 保留列表 + searchInterrupted
  castToDevice（:305）：同时只投一次；换设备先 pause 上一台（失败不管）→ setMedia（地址 + DIDL-Lite 元数据）→ play
  close（:379）：停掉搜索，正在进行的投屏不再发 play；不发 stop
SsdpDiscovery（discovery.dart:58）：每 2 秒一轮（:63），第一轮连发 ssdp:all、MediaRenderer、AVTransport（间隔 30 毫秒，MX 1），
  之后五轮一循环（searchTargetsFor ssdp.dart:28）；每个 IPv4 网卡一个套接字（openSsdpSockets :286，开 VPN 也能搜到）；
  1900 端口的通告监听尽力而为；按 USN 记住读过描述的设备（10 秒超时 :65）；byebye 和 120 秒无消息就去掉（:66）
DlnaRenderer（renderer.dart:174）：SOAPAction 用描述里声明的服务类型；动作 15 秒、播放前忙时等 0.8 秒重试一次（:179-180）；
  设置地址回 701/705/715 时先停止再设一次；UPnP 错误码变成 UpnpActionFailure（failure.dart:75）
```

- 完成度：N02.1（2026-10-01，`a070b0ed4`）做完 `live_cast`，修了 v3 依赖包 `dlna_dart` 的 11 个问题；C01.2 把它接进直播间的取流弹窗（当时叫 `CastDialog`，现在是 `CastDevices`）；`949c2ee1a`（2026-10-02）让电视显示“主播 - 标题”；Y01.1 第 4 节加了搜索前申请本地网络权限。**从没对真电视投过**：N02.1 在 WSL 上验证了套接字和组播发送，但局域网里没有设备应答；清点 F-RT-01“没验证”→ S02.6 第 1 阶段。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_cast/lib/src/controller.dart`（404 行） | `normalizeDlnaSource`（`:11`）、`DlnaCastStatus`（`:25`，五种）、`DlnaCastError`（`:43`）、`DlnaCastNotice`（`:52`）、`DlnaCastState`（`:62`，不可变）、`DlnaCastController`（`:123`：`searchDuration` 20 秒 `:131`、`startSearch` `:179`、`castToDevice` `:305`、`close` `:379`、`changes` 流） |
| `.../discovery.dart`（210 行） | `DlnaDiscoverySession`（`:11`）、`DlnaDiscoveryStarter`（`:23`）、`startDlnaDiscovery`（`:33`）、`SsdpDiscovery`（`:58`：间隔、首轮间隔、描述超时、过期时间 `:63-66`） |
| `.../ssdp.dart`（318 行） | `searchTargetsFor`（`:28`）、`SsdpKind`（`:51`）、`SsdpMessage`（`:64`，应答和通告的解析）、`SsdpSocket`（`:156`）、`IoSsdpSocket`（`:175`，绑网卡地址、设组播出口）、`openSsdpSockets`（`:286`，列不出网卡退回 `0.0.0.0`） |
| `.../description.dart`（219 行） | `CastService`（`:7`）、`CastDevice`（`:31`，UDN 作 id、`address` 作副标题）、`parseDeviceDescription`（`:109`，逐个设备找 AVTransport，名字缺失为空）、`resolveDescriptionUrl`（`:153`，RFC 3986，冒号开头的路径段手工处理） |
| `.../renderer.dart`（270 行） | `CastMedia`（`:11`，`roomTitle` `:41`）、`didlLite`（`:49`）、`TransportState`（`:66`）、`TransportInfo`（`:108`）、`DlnaCastDevice`（`:138`）、`CastMediaTarget`（`:167`）、`DlnaRenderer`（`:174`：`setMedia` `:212`、`play` `:230`、`pause` `:241`、`stop` `:244`、`transportInfo` `:247`） |
| `.../soap.dart`（91 行）、`http.dart`（115 行）、`failure.dart`（231 行） | `soapEnvelope`（`:7`）、`soapHeaders`（`:20`，`text/xml; charset="utf-8"`）、`parseSoapResponse`（`:31`）、`escapeXml`（`:57`）；`CastHttp`、`IoCastHttp`（`:53`，不复用连接、整次计时、限制正文大小）；`CastFailure` 一族、`UpnpError`（`:97`） |
| `apps/pure_live/lib/features/live_play/dialogs/stream_dialogs.dart` | `castDiscovery`（`:282`）、`CastDevices`（`:290`：`initState` `:313`、`_discover` `:335`、`dispose` 放锁 `:343`）；会话型的流不进投屏（`:111`）；标题（`:194`） |
| `apps/pure_live/lib/platform/platform_services.dart` | `MulticastLock`（`:70`） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_cast/test/controller_test.dart`（14） | 移植 3.x 对话框测试的 11 个用例（地址校验、无效地址不搜、20 秒超时只停一次、失败后重试、整份替换、刷新丢弃旧结果、投屏合并、先设地址后播放、换设备先暂停、投屏失败可重试、关闭后不发播放）+ 搜索中断保留列表、状态流 |
| `.../discovery_test.dart`（7） | 搜索节奏、每台设备只读一次描述、媒体服务器不列出、通告和 byebye 和 120 秒、停止后丢弃、启动失败、停止后仍可控制 |
| `.../description_test.dart`（10） | 小米、乐播、Kodi 三份样本和 `address`；不能投的设备、埋在下层的渲染器、控制地址 |
| `.../ssdp_test.dart`（8）、`renderer_test.dart`（5）、`soap_test.dart`（9）、`http_test.dart`（4） | 报文格式和轮次、本机回环套接字；SOAP 报文、忙时重试、错误码；元数据转义；超时和超大正文 |
| `apps/pure_live/test/features/live_play/live_play_more_page_test.dart` | 搜到的设备列出并拿到选的地址（`:181`）；搜索前申请本地网络权限、拒绝时提示（`:208`） |

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/dialogs/live_dlna_dialog.dart`（524 行）和测试 `test/live_dlna_dialog_test.dart`：对话框的 `State` 里写着全部流程（搜 20 秒、刷新、选设备、切换先暂停、关闭后不再发命令）；入口 `live_play_menu_button.dart:100`、`video_controller_panel.dart:1974` → `LiveUrlTool.castPlayUrlByRoomId`（`lib/common/utils/live_url_tool.dart:405`）→ `KnownRoomLinkDialog`（选画质、线路）。
- 依赖包 `dlna_dart` 0.1.1（`lib/dlna.dart` 725 行、`lib/xmlParser.dart` 231 行）：搜索节奏、报文；11 个问题见 N02.1 README。
- 必须保留：地址校验规则、搜索节奏和 20 秒、整份替换列表、刷新丢弃旧结果、先设地址再播放、换设备先暂停、关闭时不发停止、元数据的条目结构（`object.item.videoItem`、`http-get:*:*:*`）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 从没对真电视投过 | — | 不知道 K90 + 家里的电视 / 盒子能不能搜到、能不能播；三份描述样本之外的设备没见过 | [S02.6](../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 第 1 阶段（CHECKLIST 第 1 节第 13 条，没有设备就跳过） |
| Android 17 本地网络权限没在真机看过 | `stream_dialogs.dart:335-341` | 拒绝后的提示、再次搜索时会不会再弹 | [O04.1](../../O-Android系统集成/O04-权限/O04.1-Android17本地网络权限/README.md) |
| 投出去以后应用里没有遥控（暂停、停止、音量），关掉对话框就管不到那台设备 | `controller.dart:379` | 同 3.x；要停只能在电视上操作 | 照 3.x；要遥控先进 V01 提议 |
| 会话型的流（niconico、BIGO、FC2 只有“配方”）不能投 | `stream_dialogs.dart:111` | 这些平台没有投屏 | 照设计（没有可直接播的地址） |
| 投的是取流时的地址，带租期的地址（例如哔哩哔哩、斗鱼）过期后电视会断 | — | 投了很久的电视可能停 | 同 3.x；不做 |
| `UpnpActionFailure` 的错误码没有映射成用户看得懂的提示（都是“投屏失败”） | `failure.dart:75-97`；`stream_dialogs.dart:395-396` | 用户不知道是设备不支持这种格式（714）还是打不开地址（716） | 真机发现常见错误码后再定；没有任务 |

## 相关决定和规范

- D-019（真机只用测试包）、D-017（测试用假套接字和假 HTTP，不访问真实设备）；投给电视的标题改成“主播 - 标题”（`949c2ee1a`，D-034 补记确认）。
- 本地网络权限：O04；组播锁：O。

## 测试和验证

- 自动测试：`cd packages/live_cast && dart test`；`cd apps/pure_live && flutter test test/features/live_play/live_play_more_page_test.dart`。
- 真机：CHECKLIST 第 1 节第 13 条（同一 Wi-Fi 下有电视或盒子时：菜单 → 投屏 → 列表里出现设备 → 投出去电视上能播）；顺带看开着 Clash（VPN）时能不能搜到（N02.1 问题 4）。

## 路线

1. S02.6 第 1 阶段：K90 对真电视投一次；结果写回 N02.1 的“验证”；记下不能投的设备型号和错误码。
2. 视结果开任务：常见错误码的提示、个别设备的兼容。
3. 投屏遥控、投本地录像等新功能先进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [N 多画面和投屏](../README.md)。

- 代码：`packages/live_cast`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| N02.1 | 投屏 | 功能 | 完成 | 2026-10-01 | a070b0ed4 | [设计或说明](N02.1-投屏/README.md)、[记录](N02.1-投屏/record.md) |

<!-- docs:生成结束 -->
