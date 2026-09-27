# 0033 HLS 中继：线路带配方，回环中继改写播放列表

- 状态：已接受
- 日期：2026-09-28

## 背景

- 有些 HLS 线路，播放器自己打不开：
  - **Bigo** 的分片被加扰（spec/sites/bigo.md §6.3）：每个分片前两个 TS 包的前 16 字节按列表里的种子异或。ffmpeg 直接打开线上列表，11 次只成功 1 次；经本地中继解扰后 2/2 成功。ADR 0031 第 10 条因此让 Bigo 等这个中继。
  - **niconico** 的 Cookie 按路径区分（spec/sites/niconico.md §6.3）：主列表、分片、密钥各要自己那一组，合成一个请求头会 403。`StreamLine.headers` 只能带一组。
  - **TwitCasting** 的分片要带媒体列表响应下发的会话 Cookie。FFmpeg 的 HLS 读取器会自己带，播放不受影响；自己拉分片的录制要带。
- 播放规格 SRC-2 第 3 项早就留了“需要改写的 HLS → HLS 中继”，SRC-4 要求播放和录制共用一套回环服务，但一直没有实现：live_media 只有 FLV 拼接和直连。

## 决定

1. **线路带配方**（live_core `stream.dart`）：`StreamLine.hlsRelay` 是可空的 `HlsRelayRecipe`，适配器按需填写：
   - `cookies`：返回按域名和路径生效的 `ScopedCookie` 列表的函数，**每个请求都重新读取**，座位换发的新授权立刻生效。每个请求只带匹配的那些（RFC 6265 的域名和路径匹配规则）。不填时保留线路自己的 `cookie` 请求头。
   - `restore`：给一个媒体列表的文本，返回还原它的分片的函数；列表没有加扰时返回 null。
   - `ScopedCookie` 取代 niconico 自己的 Cookie 类型，放进 live_core 的公共模型。
2. **管线选择**（SRC-2 依次判断）：租期会断连的 FLV → 拼接；**带配方的 HLS → HLS 中继**；其它 → 直连。HLS 中继输入的 `renewsLease` 为假：会话照常在 `refreshAt` 预取，niconico 的座位靠这个保持打开（niconico.md §6.4）。
3. **HLS 中继**（live_media `hls_relay.dart`，挂在 `LoopbackRelay.openHls` 上）：
   - 每个输入一个随机、不可猜的路径前缀，入口是 `/<前缀>/index.m3u8`，输入关闭即失效。
   - 每取一次播放列表就改写一次：主列表的变体、`EXT-X-MEDIA`、`EXT-X-I-FRAME-STREAM-INF`、`EXT-X-RENDITION-REPORT` 指向本地的列表；媒体列表的分片、`EXT-X-PART`、`EXT-X-PRELOAD-HINT`、`EXT-X-MAP`、`EXT-X-KEY` 指向本地的名字。相对地址按重定向后的最终地址解析；非 http(s) 的地址（`skd://`、`data:`）原样保留。同一个上游地址始终对应同一个本地名字。
   - **只转发线路自己的列表里出现过的地址**，不是开放代理。
   - 上游请求带线路的请求头，加上配方给的、路径匹配的 Cookie；TLS 校验保持打开；按平台走代理策略的路线；连接和读取都有 15 秒空闲超时。
   - 还原只用于完整分片，并且用列出它的那一份媒体列表的还原函数；分片的一部分（`EXT-X-PART`）、初始化段和密钥原样转发。需要还原的分片整块读进内存（上限 64 MB），其余分片流式转发。
   - 内存有上限：记住最近 2048 个分片、初始化段和密钥，播放列表最大 4 MB。
   - 上游返回 4xx/5xx 时原样返回状态码，网络错误返回 502，由播放器按自己的规则重试。
4. **Bigo 接入应用**：它的线路带 `restore: BigoProtection.restorer`。ADR 0031 第 10 条的条件满足，登记到平台列表；去留仍按 ADR 0003 在 14 天探针复核后确定。
5. **niconico**：线路带 `cookies`，读的是座位当前的授权。主列表那一组仍放在 `cookie` 请求头里，给探针用。

## 备选方案与放弃理由

- **mpv 的 `cookies-file`**（niconico.md §6.3 的方案 1）：只解决 Cookie，解决不了 Bigo 的加扰；要给每条线路写临时文件、给引擎加平台相关的选项；录制还得另做一遍。
- **让适配器自己起本地服务**：适配器是纯 Dart 的平台层，不应该管网络服务和生命周期；播放和录制会各起一套，违反 SRC-4。
- **把还原做成 FFmpeg 的自定义协议**：media_kit 没有这个扩展点。

## 影响

- 播放规格 SRC-2 第 3 项实现；SRC-10（HLS 查询策略）没有平台需要，不做，配方以后可以按需加字段。
- 录制也应该走同一个中继（SRC-4）：HLS 录制合并时，带配方的线路改为录制 `openHls` 给出的本地地址，Bigo、niconico 的录制因此不用另写。
- 实网验证（2026-09-28）：`live_cli probe` 对带配方的线路会经中继取第一个分片（或 fMP4 初始化段）。Bigo 两个房间的分片解扰后是 MPEG-TS；niconico 两个房间的主列表、变体列表、初始化段都是 200。带画面的播放待真机验证（LL-HLS 的分片部分 FFmpeg 不用，按完整分片播放）。
