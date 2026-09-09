# TTingLive / FLEX TV 当前公开合同取证（2026-09-09）

后续源码进展见 [HLS 源级参数策略审计](HLS_SOURCE_QUERY_POLICY_AUDIT_2026_09_09.md)、[多画面接线](MULTIVIEW_SOURCE_INPUT_AUDIT_2026_09_09.md) 和 [TTing API 数据层](TTING_API_AUDIT_2026_09_09.md)。主播放器/录制/多画面已接入源策略，API 数据层新增 ncp/ncp_llh 合同并通过最终 46 项回归；LiveSite/注册及原生验收仍待继续，下文保留当次公开取证边界。

## 结论与边界

已取得一次从官方主目录、频道身份、当前广播到 NCP HLS 子列表和 64 KiB 媒体前缀的匿名 Clash 路线证据。旧 api.ttinglive.com 对同一频道返回匹配的频道、主播及广播 ID。**尚无生产适配器、平台注册、原生播放或完整录制验收**；17 个直播站点 + IPTV、10 组未注册参考平台的口径保持。

取证在业务源码保持 `b7eaa144098932fa77644e1109e1efeb4fb427fb`、弹幕动作测试排队/运行期间进行。没有修改代理设置、使用账号 Cookie、调用写入接口、操作手机、合并上游或发布。全部请求显式经 `http://127.0.0.1:7897`，不是把 DIRECT 与代理结果拼为完整链路。

## 官方输入与请求合同

[TTingLive 首页](https://www.ttinglive.com/)此前一次实际重定向到 FLEX TV 首页；这只证明该次首页行为，不给出全平台更名日期或所有旧分享链接的兼容保证。当前从保存的官方 HTML 所列 `assets.flextv.co.kr/202609040718` 资源开始，仅下载并阅读关联 JS，没有执行这些脚本。

- app bundle 的模块 91311 给出 `https://api.flextv.co.kr`；14991/28625 组合为官方请求附加 `x-site-code: flex`。
- 首页及模块 88403 指向 `GET /api/channels/live-list-main?includeAdult=false&liveOption=total`。本次返回 5 条、count=5；它是当前主目录快照，不伪造全站分页/总量能力。
- 使用其中明确在线、非成人、未加锁、最低等级为 0 的频道 746608，调用 `GET /api/channels/746608/profile` 和 `GET /api/channels/746608/stream?option=all`。请求带官网 Referer/Origin 与上面的站点头，不携带 Cookie 或用户认证。
- [公开频道入口](https://www.flextv.co.kr/channels/746608/live)也用于追踪实际播放器的懒加载模块；资源发现路径和响应全文保留在忽略目录。

三层身份一致：directory.channelId、profile.id、stream 顶层 id、stream.stream.channelId 均为 **746608**；profile/stream 的 owner.id 均为 **1008656**；当前广播 stream.id 为 **375906**。旧域名同一 stream 路径不带站点头也返回相同三个 ID 和 4 个源；这只是一个兼容样本，不外推所有历史频道。

注意：stream 端点的顶层 title 是频道标题，当前直播标题应读嵌套 stream.title/status.title，后者与目录 title 匹配。endedAt/disconnectedAt 均空，finalized=0；status.barrier、stream 的成人、锁定及等级字段也已核对。数字 owner ID 与频道 ID 不混用，不能只依赖 URL 最后一段或 HTTP 200 判定身份和直播状态。

## HLS 画质与 token 传递

sources 实际返回 ncp 的 1080、720、480、0 四个条目。0 对应包含 1920×1080 / 1280×720 / 854×480 的三变体 master；1080 条目也仍是单变体 master，不是直接媒体列表。主列表声明 AVC/AAC、30 fps，这只是列表声明，未用解码器确认。

按标准相对 URI 解析后的无查询子列表首次返回 **403**，保留原始失败，没有把它归为频道下播。随后沿真实播放器调用链追踪：模块 61188 选择 NCP；模块 32282 将 API URL 中的 token 拆为播放器 option；NCP SDK 模块 17493 在 xhrSetup/fetchSetup 中向后续请求附加该 token。因此不是凭猜测修改鉴权或更换身份。

仅对当前观察到的同一 HTTPS 主机和同一源目录应用上述规则后，子列表返回 **200**：4 个 EXTINF、TARGETDURATION=2、MEDIA-SEQUENCE=27096、无 ENDLIST。对该列表中一个分片发起 `Range: bytes=0-65535` 得 **206 / 65536 B**，前 10 个 188 字节位置符合 MPEG-TS 同步字节。SHA-256：`7a8c697d72548a8d1b8a8131475b5555cd4a4fdb917fe55737c663809210ab11`。没有解码或声画检查，不把这个前缀当完整录制。

移植时应将 token 限定在精确源请求作用域，嵌套 master/媒体/分片均需保留；不机械复制 SDK 的全局配置修改或向任意跨域 URL 传播 token。签名过期需刷新生产解析，禁止把本次临时 URL 固化到程序或文档。

## 本次 HTTP 证据

| 保存名 | HTTP | 响应字节 | 秒 |
| --- | ---: | ---: | ---: |
| live-main | 200 | 9701 | 2.097187 |
| online-profile | 200 | 2435 | 1.564664 |
| online-stream | 200 | 5744 | 1.695421 |
| legacy-online | 200 | 5744 | 2.354225 |
| hls-0 | 200 | 414 | 5.025006 |
| hls-1080 | 200 | 146 | 1.925749 |
| hls-media | 403 | 144 | 1.964327 |
| hls-media-token | 200 | 541 | 2.205151 |
| segment-prefix | 206 | 65536 | 2.302225 |

以上请求均未发生重定向；各响应服务器日期、传输信息、SHA-256 及身份断言保存在 `local-artifacts/tting-public-20260909/online-contract.json`。该文件引用 HTML、JS、目录/profile/stream、旧域名响应、初次 403、成功 HLS 和媒体前缀；原始签名 URL/响应只保存在忽略目录，不进入 Git。

参考输入仍冻结在 biliup `906e0f6fdb104d65989d12b76c9a6f02205384cb` 的 [ttinglive.rs](https://github.com/biliup/biliup/blob/906e0f6fdb104d65989d12b76c9a6f02205384cb/crates/biliup/src/downloader/live/ttinglive.rs)。参考只取一个源、混合多种 400 错误为下播的做法不直接移植。本次 CLI 沿用已验证的 reverse-api-engineer 0.13.0/schema1 预检结论：其 agent 暴露其他模型；没有启动外部 agent、HAR 捕获或执行生成客户端。实际方法是手工只读资源追踪和有界 curl，不宣称运行了该 CLI 的完整捕获流程。

## 接入前剩余工作

1. 严格域名/路由与频道、主播、广播身份校验；区分旧分享、新域名和真正当前频道。
2. 在线、下播、访问限制、锁定、过期、结构错误与取消/总时限的确定性回归，不把所有 400/无 sources 合并为下播。
3. 主目录快照、搜索/分类能力及显示语义；当前只观察 ncp，其他源族单独验证。
4. 嵌套 HLS 与分片的有界 token 传递及刷新，连接、录制、停止和输出完整性。
5. 设置迁移、双语品牌文案、收藏/分享、播放器/FFmpeg 接入，再进入累计构建与 Android/Windows 原生验收。

本轮没有变更既有候选或提升历史 42 个未闭环大项。弹幕红测的首项夹具超时独立保存，不与本页公开链路成功混写。
