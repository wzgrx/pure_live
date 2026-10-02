# T12c.1 投屏（DLNA）

- 日期：2026-10-01
- 目标包：`packages/live_cast`（纯 Dart，只依赖 `meta`、`xml` 和 `dart:io`，不依赖其他 `live_*` 包）
- 参考：
  - v3：`lib/modules/live_play/dialogs/live_dlna_dialog.dart`（524 行）和它的测试 `test/live_dlna_dialog_test.dart`；v3 用的第三方包 `dlna_dart` 0.1.1（`lib/dlna.dart` 725 行、`lib/xmlParser.dart` 231 行）。归档分支 `legacy/` 下的这个文件和 `v3.2.11` 完全相同；
  - 归档 v4 的 `packages/live_cast`（没上线过，只作参考）；
  - pure_live_TV `4686b7df`、media_core：都没有投屏代码，没有可借鉴的修复。

## 做法

v3 的投屏分两层：`dlna_dart` 负责搜设备和发命令，`LiveDlnaPage` 这个对话框的 `State` 里写着全部流程（搜 20 秒、刷新、选设备、切换设备时先暂停上一台、关闭后不再发命令）。重构后都放进 `live_cast`，界面只剩画图：

| 文件 | 内容 |
|---|---|
| `controller.dart` | `DlnaCastController`：v3 对话框 `State` 里的流程原样搬出来，状态用不可变的 `DlnaCastState` 表示，界面监听 `changes` 重画；`normalizeDlnaSource`（v3 原函数） |
| `discovery.dart` | `DlnaDiscoverySession`、`DlnaDiscoveryStarter`（v3 的两个接口）；`SsdpDiscovery` 按 v3 的节奏搜索，交出整份设备列表；`startDlnaDiscovery` 是默认的启动函数 |
| `renderer.dart` | `DlnaCastDevice`（v3 接口，加了停止和读状态）；`DlnaRenderer` 用 SOAP 控制 AVTransport：设置地址、播放、暂停、停止、读状态；`CastMedia`、`didlLite` |
| `ssdp.dart` | M-SEARCH 报文、SSDP 应答和通告的解析、按网卡开的 UDP 套接字和 1900 端口的通告监听 |
| `description.dart` | 设备描述解析、控制地址解析（来自归档 v4，按 v3 调整了名字和地址） |
| `soap.dart`、`http.dart`、`failure.dart` | SOAP 报文和应答、直连局域网的 HTTP、带类型的错误（来自归档 v4） |

M13 换掉 v3 调用的方式：`LiveDlnaPage(datasource: url)` 改成在 `initState` 里建 `DlnaCastController(url, onNotice: …)` 并调 `startSearch()`，`build` 按 `state` 画 v3 的同一套界面（`status` 选面板，`starting` 换刷新按钮为转圈，`searching` 显示列表上方的进度条，`busy` 禁用行和刷新，`selectedDeviceId` 打勾，`castingDeviceId` 行尾转圈，`error` 是列表上方的红字），`dispose` 里调 `close()`。行的副标题照 v3 显示 `device.address`。

| v3 | 重构后 |
|---|---|
| `normalizeDlnaSource` | 同名函数，行为不变 |
| `DlnaCastDevice`（`id`、`name`、`pause`、`setSource`、`play`） | 同名接口，加 `address`（v3 的副标题）、`stop`、`transportInfo` |
| `DlnaDiscoverySession`、`DlnaDiscoveryStarter` | 同名，用法不变 |
| `_startPackageDiscovery`（`DLNAManager`） | `startDlnaDiscovery` |
| `LiveDlnaViewStatus` | `DlnaCastStatus`（同样五种） |
| `_inlineErrorKey`：`dlna_search_interrupted`、`dlna_cast_failed` | `DlnaCastError.searchInterrupted`、`castFailed` |
| `_notify`：`dlna_cast_started`、`dlna_cast_failed` | `onNotice(DlnaCastNotice.castStarted / castFailed)`，文字由界面按 v3 的键给出 |
| `startSearch`、`castToDevice`（测试里调用） | 同名方法 |

## 保留的 v3 行为

- **地址校验**：只投 http/https、有主机名、不带用户名密码的地址；文件、RTMP、`javascript:` 都拒绝，不搜索，显示“地址无效”。
- **搜索节奏**（`dlna_dart` 的 `DLNAManager`）：打开就发一轮，之后每 2 秒一轮，直到停止。第一轮连发 `ssdp:all`、MediaRenderer、AVTransport 三个目标（间隔 30 毫秒，MX 为 1），之后每五轮里第 0 轮发 `ssdp:all`，第 1、3 轮发 MediaRenderer，第 2、4 轮发 AVTransport（MX 为 3）。报文头的顺序也照 v3。同时在 1900 端口听设备的上线通告。
- **一次搜索 20 秒**；搜到的设备整份替换列表，列表里没有的就是不在了；搜索结束后列表保留，仍然可以投。
- **刷新**：开着的搜索还在启动时再点刷新，返回同一个任务；新搜索开始时先清空列表、放掉旧搜索，旧搜索晚到的结果一律丢弃。
- **结束方式**：没搜到设备，搜索失败显示“搜索失败”，正常结束显示“没有找到设备”；已经搜到设备时搜索中断，保留列表并在上方提示“搜索中断”。
- **投屏**：同一时间只投一次，重复点返回同一个任务；先设置地址，等它完成再播放；换一台设备时先暂停上一台（暂停失败不影响新设备）；成功后打勾并提示“已开始投屏”，失败显示红字并提示“投屏失败”，可以再点重试。
- **关闭对话框**：之后到达的搜索会被停掉，正在进行的投屏不再发“播放”；已经在播的电视继续播（v3 关闭时不发停止）。
- **元数据**：标题为空时用地址作标题，类型声明为任意（`http-get:*:*:*`），条目是 `object.item.videoItem`，`id="id" parentID="0" restricted="0"`。
- **名字为空**的设备照样列出，界面显示“未知设备”；副标题是 v3 显示的基础地址（描述里的 `URLBase`，没有就用描述地址的协议、主机和端口）。
- **设备离开**：120 秒没有消息就从列表里去掉。

## 审查发现的 v3 问题

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 路由器、NAS 媒体服务器等不能投的设备也出现在列表里，点了必然失败（报 `StateError`） | `dlna_dart` `xmlParser.dart:201-230`、`dlna.dart:57-66` | 只要描述能解析就列出，不看有没有 AVTransport；`controlURL` 用不带 `orElse` 的 `firstWhere`，后面的 `if (s != null)` 是死代码 | 只列有 AVTransport 和可用控制地址的设备；不是渲染器的设备每次搜索只读一次描述，不再重读 |
| 2 | 每收到一个 SSDP 包就重新下载一次设备描述：一台设备对 `ssdp:all` 会按根设备、UUID、各设备类型、各服务各回一包，每 2 秒一轮，20 秒里同一台设备的描述要下载几十到上百次 | `dlna.dart:568-590`（`onMessage` → `_upnp_msg_parser.onNotify` → `getInfo`，`dlna.dart:538`） | 去重放在下载描述之后（按 `URLBase` 查表），下载本身没有去重 | 按 USN 的设备部分（没有 USN 时按描述地址）记下已读的设备，每次搜索每台设备只读一次；读失败的到下一轮再试 |
| 3 | 设备按基础地址区分：同一主机端口上的两台渲染器只剩一台；一台设备同时连有线和无线会出现两次 | `dlna.dart:574-578`（`deviceList[info.URLBase]`） | 用地址代替设备身份 | 按描述里的 UDN 区分 |
| 4 | 开了 VPN（如 Clash 的 TUN）时搜不到设备 | `dlna.dart:635`（客户端套接字绑在 `0.0.0.0`）、`705`（`socket.send`） | 组播只从默认路由的网卡出去，而开着 VPN 时默认路由是 VPN 网卡 | 每个 IPv4 网卡各开一个套接字，绑在网卡地址上并设置组播出口（来自归档 v4）；列不出网卡时退回 `0.0.0.0` |
| 5 | 1900 端口被别的程序占着时，整个搜索失败，即使设备完全可以通过搜索应答找到 | `dlna.dart:611-633` | 监听 1900 端口是启动的必要步骤，绑定失败就抛出 | 1900 端口的通告监听改为尽力而为，绑不上就只靠搜索应答 |
| 6 | 埋在根设备下面的渲染器（根设备是别的类型）投不了；设备描述缺 `friendlyName` 时整台设备被丢掉 | `xmlParser.dart:66-68`（`tagVal` 取 `.first`，没有就抛出）、`213-216`（只读文档里第一个 `serviceList`） | 按标签名全文找第一个，必需字段缺失就抛出 | 逐个设备找带 AVTransport 的那一个；名字缺失时为空，由界面显示“未知设备” |
| 7 | 控制地址拼错：绝对地址（`http://…`）被拼在基础地址后面；没有 `URLBase` 且描述不在根目录时，相对地址按根目录算 | `dlna.dart:63-64`（`base + '/' + controlURL`） | 用字符串拼接代替 URL 解析 | 按 RFC 3986 解析，冒号开头的路径段（小米、libupnp 的 `_urn:…_control`）手工处理（来自归档 v4） |
| 8 | 连不上的设备（已经离开网络）让投屏卡住很久才报失败 | `dlna.dart:472`、`487`（`getUrl`、`postUrl` 没有时限），`473`、`493` 只限制等应答 | 连接阶段不计时，`HttpClient` 也没设 `connectionTimeout`，要等系统的 TCP 超时 | 一次请求从连接到读完都算在时限里（动作 15 秒，与 v3 等应答的时间相同；描述 10 秒） |
| 9 | 元数据作为子元素直接塞进 `CurrentURIMetaData`，没有转义；`dc:date` 用 Dart 的 `DateTime.toString()`（不是合法日期格式）；演出者写死成拼错的 `unknow` | `dlna.dart:233-277`（`XmlText.setPlayURLXml`） | 拼字符串时没把 DIDL-Lite 当作字符串参数 | DIDL-Lite 转义后作为字符串放进参数（UPnP 规定的形式，主流控制端都这样发）；去掉日期和演出者，其余照 v3 |
| 10 | 设备回的 SOAP 错误（如 714 类型不支持、716 地址打不开）只变成一句异常文字 | `dlna.dart:494-497` | 只看状态码 | 解析 UPnP 错误码，抛出带类型的 `UpnpActionFailure`（来自归档 v4），日志和以后的提示可以按错误码区分 |
| 11 | 设备说 `ssdp:byebye`（离开）后仍留在列表里 | `dlna.dart:526-541`（`onNotify` 只取 `LOCATION`，`byebye` 没有就忽略） | 没处理离开通告 | 收到 `byebye` 就从列表里去掉 |

另外：`dlna_dart` 出错时用 `print` 打到控制台（`dlna.dart:222`、`521`、`550`、`648`、`665`），重构后不打印。

## 有意差异

| 差异 | 原因 |
|---|---|
| 设备的 `id` 是 UDN（`uuid:…`），不再是基础地址 | 问题 3。副标题仍显示基础地址（`address`），界面看起来和 v3 一样 |
| SOAPAction 和报文用描述里声明的服务类型（如 `AVTransport:2`），v3 一律写 `AVTransport:1` | UPnP 规定 SOAPAction 要和设备声明的服务类型一致；只声明 `:1` 的设备（绝大多数）发出的内容和 v3 相同 |
| `Content-Type` 写 `text/xml; charset="utf-8"`（v3 是 `text/xml`）；不复用连接 | UPnP 规定的写法；归档 v4 记录有的嵌入式服务器处理长连接有问题 |
| 设置地址时设备回 701、705、715（忙、被锁、内容占用），先发停止再设置一次；播放时回 701（还在加载），等 0.8 秒再播一次 | 来自归档 v4。只在 v3 会直接报“投屏失败”的情况下多试一次，不改变成功路径 |
| 搜索在第一轮一个包都发不出去时（所有网卡都拒绝）直接显示“搜索失败” | v3 不看发送结果，会空等 20 秒再显示“没有找到设备” |
| 设备描述读失败的，下一轮再试 | v3 每个包都重读（问题 2），失败的设备会在下一个包时重试；现在限制为每轮最多一次 |

## 来自归档 v4 的部分

`failure.dart`、`soap.dart`、`http.dart` 基本原样；`description.dart` 的解析和地址处理（改了名字回退和加了 `address`）；`ssdp.dart` 的按网卡开套接字；`renderer.dart` 的 SOAP 调用、`TransportInfo`、忙时重试；测试的假套接字、假 HTTP 和三份设备描述样本（小米电视、乐播、Kodi）。归档 v4 的搜索是“搜 4 秒、逐个交出设备”的一次性搜索，和 v3 的“每 2 秒一轮、交出整份列表”不同，按 v3 重写了。

## 留给其他模块的部分

| 内容 | 去向 |
|---|---|
| 对话框界面本身（v3 `LiveDlnaPage` 的 `build`、`_DlnaStatusPane`，文字键 `dlan_title`、`dlna_searching`、`dlna_search_hint`、`dlan_device_not_found`、`dlna_search_failed`、`dlna_invalid_source`、`dlna_unknown_device` 等）和 v3 的窄屏三倍字号测试 | M13 直播间 |
| 投屏入口：直播间菜单和控制栏（`live_play_menu_button.dart:100`、`video_controller_panel.dart:1974`）→ `LiveUrlTool.castPlayUrlByRoomId` → `KnownRoomLinkDialog`（选画质、选线路）→ 投屏对话框 | M13 直播间 |
| 会话型输入（niconico、BIGO、FC2 只有“配方”没有地址，REG-LEASE-017）：打开投屏前由页面判断，提示“需要会话”，不进投屏对话框；本包的 `normalizeDlnaSource` 只接受 http(s) 地址，兜底拒绝 | M13 |
| 投给电视的标题：v3 用地址作标题。`CastMedia` 支持传标题和 MIME 类型（`DlnaRenderer.setMedia`），要改成“主播 - 标题”需先问用户 | M13（需用户同意） |
| Android 收组播要持有 `WifiManager.MulticastLock`（只影响 1900 端口的通告监听；v3 没有，靠搜索应答也能找到设备）；Android 17 的局域网权限 | T07a.1 原生部分 |
| 实机验证：WSL 上套接字和组播发送正常（1900 端口监听收到了本机每个网卡发出的 M-SEARCH），但局域网里没有设备应答，没能对真电视测试；在 M13 接入后用手机和 Windows 对照 v3 实测 | M13 |

## 升级条目

`docs/specs/UPGRADES.md` 里没有模块列含 T12c.1 的条目，本模块没有要做的升级。

## 依赖变化

- v3 用 `dlna_dart` 0.1.1（它又用 `xml`）。
- 重构后只依赖 `meta`、`xml` 7.1.0（与 `dlna_dart` 用的是同一个包）和 `dart:io`；测试另用 `fake_async` 1.3.3。不依赖 Flutter 和其他 `live_*` 包（`tools/gate/check_deps.py` 规定为空集）。

## 测试

56 个用例：

| 测试文件 | 用例 | 内容 |
|---|---|---|
| `controller_test.dart` | 13 | 移植 v3 对话框测试 12 个用例中的 11 个（窄屏三倍字号的界面测试留给 M13；地址校验、无效地址不搜索、启动合并和 20 秒超时只停一次、失败后重试恢复、整份替换列表、刷新丢弃旧结果、投屏合并且先设地址后播放、换设备先暂停且容忍失败、投屏失败可重试、关闭时停掉晚到的搜索、关闭后不发播放），另加搜索中断保留列表、状态流 |
| `discovery_test.dart` | 7 | v3 的搜索节奏；每台设备只读一次描述（问题 2）；媒体服务器不列出不重读、失败的下一轮重试；上线通告、`byebye` 和 120 秒无消息；停止后丢弃晚到结果；启动失败的两种情况；列出的设备在搜索停止后仍可控制 |
| `description_test.dart` | 10 | 小米、乐播、Kodi 样本和 `address`；问题 1、6、7；地址解析 |
| `ssdp_test.dart` | 8 | M-SEARCH 格式和轮次；应答、通告、没有 USN 的应答、要忽略的包；本机回环上的真实套接字 |
| `renderer_test.dart` | 5 | 设置地址的报文和服务类型、播放暂停停止读状态、忙时停止后重试、加载中重试播放、带类型的错误 |
| `soap_test.dart` | 9 | 报文、请求头、元数据转义成字符串（问题 9）、标题回退和 MIME、控制字符、应答和错误解析 |
| `http_test.dart` | 4 | 本机回环：请求头大小写和正文、超时、超大正文、连接被拒 |
