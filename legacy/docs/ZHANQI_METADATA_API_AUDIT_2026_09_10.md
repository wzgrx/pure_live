# 战旗目录/状态 API 与失效媒体证据（2026-09-10）

实现 `659e4715eb629778187ca614c91b414f2181f303`，基线 `9ff99f949325af5c0bddf99d1d7377d96feb75ac`。本批新增 `ZhanqiApi`、脱敏夹具、确定性回归及生产 HTTP 探针，**仍未注册战旗 LiveSite，媒体播放/录制未通过**。此前九组未注册平台仍在完整目标范围内。

## 参考代码和实际公开请求

只读核对 [bililive-go 冻结适配器](https://github.com/bililive-go/bililive-go/blob/ef71711a7c573b013d82fec01ee8d0609ee36aca/src/live/zhanqi/zhanqi.go)，完整文件 blob 为 `f76eb21e3ba62c5be0f2a23c61941e39e7cf4b42`。参考按 URL 第一段读取 domain API，以字符串状态 4 表示直播，并解码 VideoLevels 中单个 streamUrl；没有取得媒体的有效性证据。本轮未合并或运行参考代码。

2026-09-09 18:30—18:35 UTC（本地 09-10），官网与公开 API 经本机只读 HTTP 请求取得以下结果：

| 输入 | 实际结果 | 对实施的约束 |
| --- | --- | --- |
| [官网首页](https://www.zhanqi.tv/)及[lives 页面](https://www.zhanqi.tv/lives) | HTTP 200；页面含旧赛事/重播栏目 | 页面可达不是当前媒体在播证明 |
| 首页 index_v3.js | 声明首页分组列表与更多直播入口 | 首页混合 topic/lpl 等链接；不取路径首段伪造数字房间码 |
| lives 页与 gameRoomList.js | 原生 `/api/static/v2.1/live/list/{size}/{page}.json`，按 ceil(cnt/size) 分页 | 保留服务端总数；空页也终止，防止旧总数造成循环 |
| [列表第 1 页](https://www.zhanqi.tv/api/static/v2.1/live/list/20/1.json) | HTTP 200、code=0、cnt=5、5 个房间，均 status 字符串 4 | code、房间 id、主播 uid 分开；其中一行 nickname=null |
| [列表第 2 页](https://www.zhanqi.tv/api/static/v2.1/live/list/20/2.json) | HTTP 200、cnt 仍 5、rooms 空 | 确认页号与空页合同，不用返回页长推断服务器已永久停播 |
| [官方房间 8888](https://www.zhanqi.tv/api/static/v2.1/room/domain/8888.json) | HTTP 200、status 字符串 0，但 VideoLevels 仍包含旧 HLS 地址 | 下播/未知快照不发布残留媒体 |
| 首页样本与列表样本的 domain 详情 | 两次 HTTP 200、status=4、flash RoomId 与详情 id 一致 | 仅保留“平台声明直播”，不是本机验证的可播状态 |
| 上述两份 VideoLevels 声明的 HLS | **两次 HTTP 404，正文 stream not found** | 元数据成功和媒体失败分别记账；不声称播放/录制已恢复 |

没有为失败媒体更换猜测 CDN、拼接未观察的质量或循环重试。上述有限样本也不足以证明全站终止运营。原始页面、官方 JS、头部、JSON、失败媒体正文及每份 SHA256 在忽略目录 `local-artifacts/zhanqi-public-20260910/`，索引为 evidence.json。

## 新 API 范围与不变量

- 固定 HTTPS 官方 API、数字 public code 与分页参数校验；复用共享 Dio 路由与独立请求取消令牌。错误分类为 transport/access/missing/rateLimited/service/api/schema/identity/cancelled，不把 HTTP/API 失败伪装成明确下播。
- 目录保留三种身份、原始标题、可空昵称/图片、原始 online 数值及 reportedStatus。online 未获并发口径证据，不作为已验证的当前在线人数。结果不可变，页内重复 code/id 原子失败；不同房间可共享 owner，不误合并身份。
- 详情可核对预期 code/id/uid，再核对 flash RoomId 与数字 Status。状态 0 映射 reportedLive=false，状态 4 映射 true，其他数字字符串保持未知；未知状态只有合成回归，不冒充现网观察。
- 仅状态 4 解码有界 Base64/严格 UTF8/JSON。只保留已观察的官方 alhls-cdn HTTPS 路径族、并核对媒体房间前缀；空 streamUrl 保持无源。declaredStream 明确是声明值，非有效媒体凭证；没有虚构分辨率、质量列表、CDN 线路或续签。
- JSON 响应 1 MiB 上限、总时限、禁止自动重定向、异常文本脱敏。真实 Dio 回归覆盖 HTTP 错误/溢出收尾、共享调用方不被取消、同调用方并行请求隔离、停滞与持续小块响应的总时限。

代码 `lib/core/site/zhanqi/zhanqi_api.dart`，48 项专用测试 `test/zhanqi_api_test.dart`，共用 `test/platform_response_lifecycle_test.dart` 新增战旗案例，夹具 `test/fixtures/zhanqi/`。夹具替换身份/主播/媒体路径，保留实际类型、null 和分页结构；没有把本轮真实房间媒体写成有效测试视频。

## 验证和失败留账

首次四文件测试 **140/140**（含在线元数据 1/1）通过，但严格分析发现八处多行 if 缺大括号，整个检查阶段仍记失败。随后仅补大括号，另补调用前已取消的 API 回归；最终离线 **140/140，在线探针明确跳过 1 项**。在线行为不变，复用首次真实请求证据，未重复访问媒体以取得绿色结果。

在线生产探针 `tool/probes/zhanqi_metadata_probe_test.dart` 在 **18:39:23.954165 UTC** 开始：通过真实 ZhanqiApi/Dio 顺序获取两页列表、从第一页选取房间并核对三种身份；三请求均 200、Referer 正确、禁止重定向。5 行/总数 5、第二页空、详情 reportedLive=true 且有 declaredStream。**mediaValidated=false 始终保留**，该探针不请求媒体，也不将外部 404 判为 API 代码失败。

最终四文件 `analyze --fatal-infos` 为 **No issues found**，提交前逐文件核对最终源码 SHA 与记录一致。首次失败未覆盖，在线证据和最终静态补大括号输入分别保存。

| 阶段 | build-records 文件 | 秒 | 峰值 CPU | 峰值工作集 B | 结束活跃重型进程 |
| --- | --- | ---: | ---: | ---: | ---: |
| 首次测试含在线通过、分析失败 | 20260909T184003224Z-zhanqi-metadata-first.json | 57.470 | 16.86% | 8886685696 | 0 |
| 最终离线测试及严格分析通过 | 20260909T184146016Z-zhanqi-metadata-final.json | 49.934 | 10.87% | 8990789632 | 0 |

证据在 `local-artifacts/zhanqi-metadata-20260910/` 的 first/final 日志、源码/夹具 SHA。串行守卫、固定 SDK、定向测试，无依赖升级或全量构建。

## 一直播前置检查和当前设备

本轮另只读核对冻结的一直播适配器（blob `ba85cfd0167ce71155cc09a8aeb5ebd6be16c179`）：旧实现使用 www.yizhibo.com 的 H5 API 与页面 play_url。此电脑直连解析主机失败，指定本地 Clash 7897 后 TLS 握手失败，均未取得 HTTP 响应。证据在 `local-artifacts/yizhibo-public-20260910/`；**没有据此判定停运，也没有把同名 .net 搜索结果当作官方迁移目标**。两站 reverse-api-engineer 0.13.0/schema 1 仅 dry-run，未启动其代理或模型执行。

手机只读重查明确 serial 192.168.1.2:5555，型号/代号 25102RKBEC/myron 一致，前台为哔哩哔哩，Pure Live 未运行。保持现状，未唤醒、切换前台、安装、Root/MT/模块操作、重启或清数据。

## 后续全目标

战旗下一步是核对当前官方播放器的实际取流调用和有效媒体合同，区分旧 VideoLevels 声明、播放鉴权及当前 CDN；取得证据后再接通分享/目录/收藏/画质/录制/迁移及双端验收。一直播保留访问与官方生命周期待核实项；其他七组平台继续审查。没有将缺失平台从原目标删去，也没有添加看似可播的空入口。

当前仍 **18 个直播平台 + IPTV、9 组参考平台未注册、宏观 42 组未闭环**。Android 候选 fb106ed6 和 Windows 候选 2fb471d3 未重建，新增底层 API 不在这些包内。版本仍 3.1.8+4121；全量质量、全平台 3.2.0 构建签名与发布继续等待完整验收。
