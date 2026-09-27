# 0027 DLNA 投屏：自写 live_cast 包，投上游原始地址

- 状态：已接受
- 日期：2026-09-28

## 背景

F-CAST-01（product.md §13）要求：搜索局域网设备，把当前房间的播放地址投过去；无设备、搜索失败、地址无效各有提示；入口在 Android 顶栏和菜单。REG-ROOM-016 和 REG-LEASE-017 还要求：只投规范化的网络地址，不导出本机地址；投屏命令单次执行、先设置源再播放；切换接收设备前等上一台完成。

3.x 用 `dlna_dart` 0.1.1（BSD-3，约 950 行，依赖 `xml ^6.5.0`）。读过它的实现，有几处和上面的要求或 v4 的约定冲突：

- 搜索时在 `0.0.0.0:1900` 绑定服务端口（默认不开 `reusePort`）并加入组播组；系统或别的应用占着 1900 时直接失败。发送只用一个绑在 `anyIPv4` 上的套接字，多网卡（Wi-Fi + 有线、热点、VPN）时只走默认路由那一块。
- 每 2 秒发一轮 M-SEARCH（含 `ssdp:all`），直到调用方停止，没有超时，也不能按一次搜索取消；错误用 `print` 输出。
- `SetAVTransportURI` 把地址和标题原样拼进 XML：签名地址里的 `&` 让请求体变成非法 XML；DIDL-Lite 元数据作为子元素嵌入而不是转义成文本，服务类型写死 `AVTransport:1`。很多渲染器因此拒绝。
- 返回值是原始字符串，UPnP 错误码不解析；套接字和 HTTP 不能注入，无法做不联网的测试。

另外，v4 的播放经过本机回环中继（ADR 0018），播放器打开的是 `127.0.0.1` 地址，电视访问不到，必须拿上游地址。

## 决定

1. **新包 `packages/live_cast`**：纯 Dart，只用 `dart:io`、`meta` 和工作区已有的 `xml`（7.1.0），不依赖其它 `live_*` 包（`check_deps.py` 登记为无内部依赖，应用可以依赖它）。UDP 套接字（`SsdpSocket`）和 HTTP（`CastHttp`）都是接口，测试用假实现和 `fake_async`；`IoCastHttp` 基于 `HttpClient`。
2. **搜索**：每个非回环 IPv4 地址绑定一个临时端口的 UDP 套接字（设置 `IP_MULTICAST_IF` 和 TTL 2），对 `urn:schemas-upnp-org:service:AVTransport:1` 和 `urn:schemas-upnp-org:device:MediaRenderer:1` 各发一个 M-SEARCH，1 秒后重发一次；默认收 4 秒（可配），MX 取超时的一半（1–5）。回应是单播，所以不占 1900 端口、不加入组播组、不监听 NOTIFY。回应按 USN 的设备部分（`uuid:…`）去重，读描述后再按 UDN 去重；只保留有 AVTransport 服务的设备。取消订阅立即关闭套接字；描述读取另有 3 秒超时。
3. **设备描述**：元素按本地名匹配（前缀和未声明的前缀都不影响）；取根设备或嵌入设备里第一个带 AVTransport 的设备的 `friendlyName`、UDN、厂商和型号，以及 AVTransport 和可选 RenderingControl 的 `controlURL`。相对地址按 `URLBase`（有效时）或 LOCATION 解析，包括 libupnp 系渲染器常见的 `_urn:schemas-upnp-org:service:AVTransport_control` 这种首段带冒号的相对路径（`Uri.resolve` 会拒绝或把冒号转义，单独处理）。
4. **控制**：AVTransport 实例 0 的 `SetAVTransportURI`、`Play`、`Pause`、`Stop`、`GetTransportInfo`。元数据是最小 DIDL-Lite：标题（最长 80 字）、`object.item.videoItem`、一个 `res`，protocolInfo 为 `http-get:*:<mime>:*`，MIME 按线路格式和路径选：HLS 用 `application/vnd.apple.mpegurl`，`.ts` 用 `video/mp2t`，`.mp4` 用 `video/mp4`，其余 `video/x-flv`。所有参数按 XML 文本转义（元数据因此是两层转义），`SOAPAction` 用描述里声明的服务类型；请求头保持大小写（`SOAPAction`），不复用连接，不走代理。SOAP Fault 里的 UPnP 错误解析成 `UpnpActionFailure`（错误码 + `UpnpError`），其它失败分成超时、网络、HTTP 状态、协议四类，都是密封类 `CastFailure` 的子类。
5. **投送顺序**（`castTo`）：先设置源再播放；设置源遇到“忙”（701、705、715）时发一次 Stop 再设置一次；Play 遇到 701（还在加载）等 0.8 秒再试一次。除此之外不重试。
6. **投什么**：当前线路的**上游原始地址**（`PlaybackState.line`，没有时用 `commit.line`），不是本机中继地址。只接受 http(s)、有主机、没有用户信息、不是回环或未指定地址（`localhost`、`127.x`、`::1`、`0.0.0.0`）的地址，否则面板说明原因、不搜索。线路带请求头时提示“这个平台的直播流可能需要特殊请求头，电视上不一定能播”但允许尝试；线路有租期时提示地址会过期。
7. **状态**：应用级的 `castProvider`（不随直播间销毁，离开直播间不自动停止）。同一时间只有一个命令序列，重复点击共用它；换到另一台设备时先对上一台发 Stop 并等它完成，再投新设备。打开面板时查一次 `GetTransportInfo`，显示“电视正在播放 / 已暂停 / 已停止播放”；不轮询、不订阅事件。
8. **Android 组播锁**：搜索期间持有 `WifiManager.MulticastLock`（`CastMulticast.kt`，方法通道 `purelive/cast` 的 `acquire` / `release`，锁不计数，Dart 端合并重叠的搜索），需要 `CHANGE_WIFI_MULTICAST_STATE` 权限；拿不到锁时照常搜索。其它平台不调用。
9. **规格修订**：REG-ROOM-016 的“切换接收设备前等上一个设备暂停完成”改为“停止完成”。直播流暂停后没有意义，暂停会让上一台电视停在冻结画面、继续占着连接；Stop 让它回到空闲状态。

## 备选方案与放弃理由

- **继续用 `dlna_dart`**：问题见背景，其中地址不转义会让大多数带签名参数的直播地址投送失败，绑定 1900 端口会在部分手机上直接搜索失败；修补需要改它的大部分代码，而投屏只用到 5 个动作。
- **通用 UPnP 库**：要带上 GENA 事件、SCPD 解析、设备端等用不到的部分，并逐个评估维护状态；本包约 1300 行（含注释），只做投屏需要的事，行为都有测试。
- **原生插件（Android 上的 Java UPnP 库）**：每个平台一份实现，Windows 要另找；还要逐个核对许可证。纯 Dart 在 Android 和 Windows 上共用一份代码。
- **在局域网开放中继，让电视经由手机取流**：能带上请求头、续租签名，解决下面“已知限制”的前两条；但中继要绑定到局域网地址，违背 REG-LEASE-010（只绑定回环），宪法要求局域网功能必须配对确认，手机还得一直亮着转发。以后如果要做，另写决策，并且要用户显式开启。
- **绑定 1900 并监听 NOTIFY**：能被动发现开机晚的设备，但 1900 常被系统或别的应用占用；一次性的 M-SEARCH 已经够用，面板有“重新搜索”。
- **投网页地址（直播间链接）**：DLNA 渲染器不能播放网页。

## 影响

- 新包 `live_cast` 进入工作区和门禁；没有新增第三方依赖（`xml` 已在工作区，`fake_async` 只用于测试）。
- 应用：`features/cast/`（`showCastSheet`、`castProvider`、`castSearchProvider`、`castRendererProvider`），菜单项“投屏”和 Android 顶栏按钮由直播间页面接入；`MainActivity.configureFlutterEngine` 注册 `CastMulticast`，清单加 `CHANGE_WIFI_MULTICAST_STATE`。

已知限制：

- 需要 Referer、Cookie 或特定 User-Agent 才能取流的平台，电视通常拿到 403，只能提示后让用户尝试。
- 签名地址有时效（租期），过期后电视停止播放，手机不会自动续投，需要重新投屏。
- 渲染器的格式支持不一：不少电视不支持 HTTP-FLV 或 HEVC，这时换一条线路（平台提供 HLS 时更容易成功）。
- 只搜 IPv4；访客网络或开了 AP 隔离、跨网段时搜不到。Windows 防火墙可能拦截回应，第一次搜索时可能弹出防火墙提示。Android 17 的局域网访问权限如果需要运行时申请，要在搜索前处理（本次没有做）。
- 不跟踪电视端的变化：在电视上退出播放后，应用仍记着这次投屏，直到用户停止，或重新打开面板时查询到“已停止播放”。
- Activity 销毁而进程还在时，Kotlin 端不会主动释放组播锁；Dart 端每次搜索结束都会释放，进程结束时由系统回收。
