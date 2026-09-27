# 战旗当前 H5 取流合同与画质矩阵（2026-09-10）

实现 `7569e40d2d27c14b2807259e3730c099f13304e3`，基线 `e4959552ba9cd9e1ea4a926fc7d9a7c2ce6e6900`。继[元数据审计](ZHANQI_METADATA_API_AUDIT_2026_09_10.md)，修订当前播放器配置优先级，并补公共访客取流分支证据。**元数据和矩阵解析通过；尚无有效媒体或原生播放/录制证据，战旗仍未注册。**

## 现行播放器不是参考代码的旧 HLS 路径

从已读取官网的明确脚本 URL 逐层核对 [yp-socket 加载器](https://static.zhanqi.tv/assets/web/v3/static/j/yp/yp-socket.js?v=f00e896d)，它加载 H5 的 zplayer、manifest、vendor 和 [app.js](https://h5player.zhanqi.tv/assets/h5liveplayer/dist/js/app.js?v=a2f9efc0202)。本轮只下载其中所需脚本并静态读取，未执行远端 JS、广告、反馈或聊天逻辑。videoJJToH5.js 实际是附加 LiveOS 集成，不把其 SDK 当作直播取流器。

官方 H5 优先解码非空 `h5Cdns`，否则 `cdns`，该路径不读取 `VideoLevels`。现网样本 ver=3.0、vid 与详情 videoId 一致；五个画质标签只在索引 **2（超清）** 有非零单元，四条逻辑线路都指向 CDN key **202**、相同空后缀。当前静态映射对应 FLV，而非旧 VideoLevels 的 HLS。五个标签不是五个有效画质，四个同 CDN/后缀单元也不是四个不同源身份。

归因：上轮底层 API 只实现冻结参考的 legacy 声明合同，缺少当前官方客户端的配置分支。本批补该取流合同差距，不把媒体 404 归咎于单纯缺少 HLS 请求头，也不将新解析称为已修复站点媒体。

## 生产解析修订

- `ZhanqiApi.parseRoom` 先核对 code/roomId/ownerId/flash 状态，随后优先解析当前 H5 配置；当前配置有效时不再暴露旧 `declaredStream`。当前配置损坏时明确失败，不静默回退到陈旧 HLS。
- 新增 `ZhanqiPlayerLayout`，验证广播与房间前缀、ver/status、画质/线路/后缀矩阵、默认索引及数值类型；Base64 64 KiB 编码上限、严格 UTF8/JSON，每个维度最多 16、标签最多 256 字符，结果深层只读。
- 保留原始列号、禁用列和默认列，不按标签伪造分辨率；缺失短行尾部单元保持禁用。全零矩阵保持无源，默认列失效明确可观察。
- 保留所有非零 CDN id，包括尚未映射的 id，不猜测其域名。源身份分组以同一广播下的 CDN key+后缀归并，同时保留全部原始质量/线路单元；跨质量标签却指向同一身份的情况也不会虚增源数。
- 当前仅实现已观察 v3 配置；旧版本、区域 `trule` 替换与远程 CDN 映射仍为后续合同，遇到这些输入不发布未经核对的矩阵。签名/调度和实际 URL 尚未接入生产播放/录制，此处不是缺失功能已全部完成的声明。

夹具来自本轮实际 h5Cdns，替换广播身份；保留五列、四行、零单元、默认索引和原始标签。31 项新回归覆盖优先级、legacy 共存/损坏、身份不一致、未知 CDN、重复源、类型/容量边界和不可变结构；旧 48 项元数据与共享 transport 回归继续通过。

## 公共访客 HTTP 分支重建与真实失败

依据官方 app.js 的请求和 URL 拼装，使用独立 curl Cookie 文件获取匿名 uid=0 的 room.viewer；没有读取或注入用户账号会话。原始返回/签名/访客值仅存忽略目录，未加入 Git 或本报告。

| 阶段 | 本轮观察 | 判定边界 |
| --- | --- | --- |
| 数字房间网页 | HTTP 504 | 保留失败；此前官网首页和 metadata API 可读，不判全站关闭 |
| room.viewer | HTTP 200、code=0、uid=0 | 仅为本轮匿名访客 |
| POST `/api/public/burglar/chain` | multipart 的实际 stream 文件名、cdnKey=202、platform=128；HTTP 200、code=0、有 key | 正常公开签名返回，不是媒体有效性证明 |
| 声明 FLV 域名+签名 | HTTP 404、242 B HTML、无 FLV 前缀 | 未取得媒体；不记播放 PASS |
| 官方 Ali CDN resolver | 经校验的参数返回 HTTP 200、一个调度域名 | 仅证明调度响应，不替代对该节点的连通性 |
| 调度节点+签名 DIRECT | curl 6，域名解析失败，未取得 HTTP | 不假定节点内容或归为下播 |
| 同节点本地 Clash 7897 | curl 35，连接中止，未取得 HTTP | 只作不同路由诊断；签名年龄约 266 秒，在官方播放器 600 秒复用窗口内 |

媒体请求均有时间、字节预算及 Range 前缀限制，没有持续录制、轮换猜测 CDN 或改系统代理。参数重建不是完整浏览器/聊天会话复现；CDN 调度、终端网络和当前房间媒体可用性仍有未验证分支。

调查失败原样保留：最初把 viewer.clientIp 当文本 IPv4，类型守卫在发请求前中止；随后 PowerShell 数组位运算括号错误导致空 client_ip 请求，resolver 返回空对象。该响应不算有效调度证据。修正后按官方 uint32→IPv4 转换及 protocol=hdl 重新读取，得到数组型节点返回；错误参数与修正后的两份响应分别保存，没有覆盖失败或把辅助脚本问题记为生产缺陷。

原件、加载链与脱敏摘要在 `local-artifacts/zhanqi-player-20260910/player-contract.json`，列出 13 份原件的大小和 SHA。reverse-api-engineer 0.13.0/schema 1 仅 dry-run，未运行其代理/模型，HAR 和生成客户端路径均为 null。

## 生产探针和定向验证

**134/134**：31 项矩阵/API 新回归、48 项既有战旗回归、54 项共享响应生命周期及真实元数据探针 1 项；四个改动 Dart 文件严格分析 **No issues found**。最终源码 SHA 与测试前格式化后的记录逐一核对一致；本轮一次检查完成，无分析失败或测试重跑。

真实生产探针于 **2026-09-09 18:57:26.271706 UTC** 开始，真实 ZhanqiApi/Dio 读两页目录和一个房间均 HTTP 200；5 行/总数 5、第二页空，身份匹配；`hasPlayerLayout=true`、启用索引 `[2]`、4 个单元/1 个源身份组、`hasDeclaredStream=false`。`mediaValidated=false` 始终保留，此探针不包含上面的媒体请求。

资源记录 `20260909T185800225Z-zhanqi-layout-first.json`：50.118 秒，峰值 CPU 9.25%，工作集 9,564,753,920 B，结束活跃重型进程 0。证据目录 `local-artifacts/zhanqi-layout-20260910/` 含脚本、日志、源码 SHA 与真实报告；固定 SDK、串行互斥、无依赖变更/构建。

## 剩余与设备边界

手机只读重新核对 192.168.1.2:5555、25102RKBEC/myron 一致，Pure Live 未运行、前台仍为哔哩哔哩；未唤醒、接管前台、安装、Root/MT/LSP 操作或重启。Android fb106ed6、Windows 2fb471d3 候选不变，当前新增解析尚未进入候选。

战旗继续保留有效媒体/路由、正常会话、完整质量/线路、分享与应用注册及双端验收缺口；本批不再重复同一失败媒体请求。下一阶段推进其他未注册平台及已注册平台的剩余功能/原生验收，待有新输入再续战旗媒体。当前仍 18 个直播站点+IPTV、9 组参考平台未注册、宏观 42 组未闭环，版本 3.1.8+4121。完整 3.2.0 质量与全平台发布目标保持。
