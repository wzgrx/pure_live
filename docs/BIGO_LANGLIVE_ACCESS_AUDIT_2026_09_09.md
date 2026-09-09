# Bigo 补查与浪 Live 公开访问合同（2026-09-09）

继 [Bigo 元数据层](BIGO_METADATA_API_AUDIT_2026_09_09.md)，本轮完成其他房间补查，并读取浪 Live 冻结适配器和当前官方静态资源。没有创建平台占位入口，也没有把访问失败归为下播。

## Bigo：两间额外样本仍要求登录

从上一轮保存的公开目录选另外两条未锁定卡片，经本机 Clash 7897 各调用一次官方状态 API。两次 HTTP 200、code=0、uid 与各自目录 owner 匹配；均 needLogin=true、alive=0、空 HLS、零 CDN 条目。目录是前批快照，不宣称本轮重新取得实时目录；这也不是全站登录条件的普查。

结果支持继续保留 loginRequired / reportedAlive=null，不支持注册可播平台或把房间归为明确离线。原件和哈希位于忽略目录 `local-artifacts/bigo-followup-20260909/`。没有重复请求同一房间以碰运气，也没有取得或注入账号会话。

## 浪 Live：冻结代码与当前接口可达性分开

参考 [bililive-go 浪 Live 适配器](https://github.com/bililive-go/bililive-go/blob/ef71711a7c573b013d82fec01ee8d0609ee36aca/src/live/lang/lang.go)，blob `2f286ec455fce3aa1087ed3bc8d097bd026318ba`。参考取 `/room/{id}` 路径中的 ID，GET `https://api.lang.live/langweb/v1/room/liveinfo?room_id={id}`，读取 `ret_code` 及 `data.live_info`；以 live_status=1 表示直播，返回 liveurl 和 liveurl_hls。其非 200/非零业务状态与缺字段分类较粗，源码存在本身不是现网有效性证据。本轮未合并、修改或运行参考代码。

| 读取 | 本机 Clash 7897 结果 | 边界 |
|---|---|---|
| [官网首页](https://www.lang.live/) | HTTP 403、CloudFront 错误页 | 不据此判定站点停止运营，也不猜测具体地域/账号原因 |
| 上述 liveinfo，room_id=2921848 | HTTP 403、非 JSON | ID 来自[官方历史房间页](https://www.lang.live/room/2921848)的搜索收录；收录时间较旧，不是当前在播证据 |
| [官方 WebView 首页](https://webview.lang.live/) | HTTP 200 | 页面主要为应用壳，不是有效房间/媒体列表 |
| WebView 引用的 21 份公共 JS 与 build manifest | HTTP 200 | 仅下载和静态读取，没有执行 JS 或访问账号/支付/管理接口 |

当前 WebView 配置仍声明 `API_URL=https://api.lang.live/`，另有 CORE_API_HOST 指向 `core-api.lang.live`；这只证明官方配置存在，未据此拼接未观察的接口或切换开发/测试环境。构建清单主要是活动/内嵌页面，不是公开桌面直播路由。

特别注意：公共 bundle 内含 mock 房间和媒体数据，关联测试用户/测试存储；本轮明确排除这些数据，未将其当成当前公开直播、未请求其中媒体地址。参考接口的 403 与页面壳的 200 同时保留，不把后者当成前者已经恢复。

reverse-api-engineer 0.13.0/schema 1 dry-run 成功；没有启动其代理或改模型，run_id/har_path/script_path 为 null。本轮合同来自只读 HTTP 与静态 JS，原件、索引、时间和 SHA-256 在忽略目录 `local-artifacts/langlive-public-20260909/access-contract.json`。

## 下一步与全目标状态

浪 Live 缺当前有效 liveinfo、明确在线/离线/受限响应、身份字段、媒体协议和目录合同，先补这些证据再实现应用接入。Bigo 仍需有效媒体或正常登录会话合同；两者不缩减原平台扩展范围。

本轮不继续盲试访问失败的端点，转而补 TTing 已注册链路的 Windows 原生短录/完整解码证据；该结果另记。当前仍 18 个直播站点 + IPTV、9 组未注册平台、42 个历史宏观大项未闭环。没有 ADB/MT、安装、Root/LSP、重启或清数据操作，也没有上游同步或正式发布。
