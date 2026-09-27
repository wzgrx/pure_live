# 0031 第三批平台迁移的共用决定

- 状态：已接受（第三批前半、后半）
- 日期：2026-09-28

## 背景

第三批按 ADR 0003 用第一批的结构迁移。旧应用不能再构建（ADR 0016），一些平台的协议又超出了第一批共用代码能表达的范围。下面是迁移中做的、会影响之后平台的决定。

## 决定

1. **没有 `expected.json`。** 旧应用不能运行，第三批的回放测试直接对照样本内容和规格，每个规格 §11 写明这一点。
2. **样本脱敏加 `textPatterns`**（tools/live_cli/lib/src/fixture/scrub.dart）：正则的第一个捕获组被替换，用于藏在路径或复合值里的签名（Akamai `hmac=`、变体路径里的会话令牌、HTML 里的 CSRF 令牌、HLS 会话数据）。替换的是捕获组在匹配里**最后一次**出现的位置；写规则时上下文放在组前，组后最多一个分隔符。
3. **弹幕文本帧**：`TextFrame`（live_danmaku transport）让 `DanmakuSocket.send` 发 WebSocket 文本帧。Socket.IO、SHOWROOM 这类协议不认二进制帧；字节仍是 UTF-8，测试替身和录制不受影响。
4. **可以没有客户端心跳**：`SocketConnector.heartbeat()` 返回 null 时不发心跳，只靠静默看门狗（max(3 × 周期, 90 s)）。用于服务端自己保活的协议（Picarto、TwitCasting、17LIVE 的 Ably）。
5. **弹幕录制可以精简消息**：帧里除聊天、礼物、人数以外的消息只留类型；辅助接口的响应（令牌接口）只留连接器读取的字段。压缩负载（猫耳 Brotli、17LIVE gzip + base64）解压、脱敏、再压缩，保证测试仍走真实解码。
6. **HLS 主列表解析共用** `HlsPlaylist`（live_core），变体的编码从 `CODECS` 得出（`avc`、`hevc`、`av1`）。主列表只能读一次（PandaTV 的 Amazon IVS）或按主机分配边缘节点（Picarto）时，由适配器读主列表、给出变体地址。
7. **FLV codec id 12（旧式 HEVC）暂不交给播放器**：live_media 还不能把 codec 12 改写成 enhanced FLV。
   - 映客的 Zego 线路（codec 12）不提供，只给网宿 H.264 线路；
   - 17LIVE 默认选 H.264 转码档（总是 AVC），其它档位照常列出但不标编码；
   - 中转实现改写之后，再放开这些线路和默认画质。
8. **新依赖**：`brotli` 0.6.0（MIT，纯 Dart），猫耳聊天的 Brotli 负载需要；live_cli 作为开发依赖用它校验。gzip、zlib 用 `dart:io`。
9. **下线判断**：第三批前半九个平台都不满足 ADR 0003 的下线条件；映客接近条件 3（网页只有展示位能看），改用 App 接口 `now_publish` 后保留。
10. **第三批后半**（liveme、steambroadcast、sixroom、kugoulive、jdlive、baidulive、looklive、weibo、niconico、xiaohongshu、youtube、tiktok、fc2live、bigo）：
    - 四个下线候选按 ADR 0003 的标准重新评估，结论写在各自规格的 §0：YouTube、FC2 保留；TikTok 保留为“仅链接”（和小红书一样，没有目录和搜索）；Bigo **有条件保留**。
    - **Bigo 暂不接入应用**：它的 HLS 分片要解扰，适配器已提供解扰函数（spec/sites/bigo.md §6.3），但 live_media 的 HLS 中继还不能在转发时调用它。接入前播放成功率接近 0，符合标准 1，所以应用不注册它，关注和历史里只显示名字。中继做完后再注册，并在 14 天探针复核后定去留。
    - **能力不全的平台**：适配器只实现自己有的能力。应用按能力筛选：发现页和平台状态只列有目录的平台（`browsablePlatformsProvider`），关键词搜索只查有原生搜索的平台（`searchablePlatformsProvider`），其余靠网页搜索（F-SRC-02）或链接。七个平台没有原生搜索：jdlive、baidulive、looklive、weibo、steambroadcast、fc2live 及仅链接的两个。
    - **控制连接**：FC2 和 niconico 播放时要保持一条控制连接（租约，spec/sites/fc2live.md §6.3、niconico.md §6.4），适配器随 `sitesProvider` 释放时关闭。
    - **niconico 分片 Cookie**：分片和密钥需要按路径区分的 Cookie，`StreamLine.headers` 只能带一组；适配器提供 `cookieFile(line)`（Netscape 格式），播放器（mpv `cookies-file`）和中继接入前，只有播放列表带 Cookie，需要真机和真实网络验证。

## 影响

- 合并时要合并的共用文件：live_core 导出、探针注册表、弹幕工厂和导出、`transport.dart`（`TextFrame`）、`socket_connector.dart`（可空心跳）、`scrub.dart`（`textPatterns`）、脱敏规则注册表、帧脱敏分发、录制器。
- live_media 待办：~~codec 12 → enhanced FLV 改写~~（不需要：各平台的 libmpv 都是 FFmpeg ≥ 8，能直接识别，见 docs/rewrite/DIAGNOSIS.md；第 7 条的限制可以放开，另行处理）；Bigo 的 HLS 解扰中继（第 10 条）；niconico 的按路径 Cookie；TwitCasting 的 HLS 分片需要把播放列表响应下发的 `lvhls_ssid_<id>` Cookie 带到分片请求（`StreamLine.headers` 表达不了响应 Cookie，FFmpeg 会自动传，中转和录制也要传）。
