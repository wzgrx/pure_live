# TwitCasting 接入与公开合同核验（2026-09-07）

基线 `d37bdf88`；新增独立 Dart 适配，没有合并上游或引入 Rust/Go 下载器。版本保持 3.1.8+4121，当前 Android `1aa6886f` 与 Windows `2d8e4e0c` 候选均未包含本批新增平台。

## 来源与实测

- [biliup 固定 TwitCasting 源码](https://github.com/biliup/biliup/blob/906e0f6fdb104d65989d12b76c9a6f02205384cb/crates/biliup/src/downloader/live/twitcasting.rs)：10:33:38Z 读取成功，核对公开房间身份、secret-word 提示与 streamserver 请求参数。参考把部分结构缺失视作下播，本实现将其保留为 schema 错误。
- [TwitCasting 首页](https://twitcasting.tv/)：10:33:41Z HTTP200 / 616625 B。页面 `tw-top-tab-item[data-channel]` 含18个顶栏分类；官网 Top.js 使用 `frontendapi.twitcasting.tv/top/category` 的 id/count，默认 count=60，没有已验证的 offset/cursor。官网搜索表单使用 `/search/text/` 和 `tw_search_query`。
- 首条公开直播房间：10:34:45Z 页面 HTTP200 / 122988 B；10:34:47Z streamserver HTTP200 / 1695 B，movie.live=true，movie ID840587446；tc-hls 声明 high/medium/low 三档。媒体列表 HTTP200 / 444 B，含4个2秒 fMP4 分片条目和初始化文件引用；本次仅取得列表，没有下载这些媒体字节。
- 同轮目录实际54条。唯一 `current_viewer_count=null` 的条目是 `is_group=true`，在读取人数前排除；其余公开可用条目人数为整数。这不是以0代替未知人数的依据。
- 明确下播房间的 streamserver 返回 movie ID840137905 / live=false，却附带另一 movie840588276 的 HLS。下播状态优先，忽略全部陈旧地址，避免播放别人的直播。

原始响应与请求记录保留在本地忽略目录 `local-artifacts/twitcasting-20260907/`。已提交夹具只保留必要字段与规范化身份，完整 HTML 中的匿名 CSRF 不进入仓库。

## 源码范围

- 推荐与分类读取公开 top window，最多60条；目录按频道 ID 保持身份，直播 movie ID只用于校验当前媒体，排除锁定、群组、删除和明确离线条目。
- 详情同时校验 twitter:creator 与 data-user-id；HTTP401/403、404、429、5xx、schema、取消和明确 offline 分列，错误消息省略原始 URL/响应内容。
- 生产 Dio 请求复用应用代理与既有连接超时；流式响应上限1 MiB，严格 UTF-8，块间20秒超时。此处不是承诺整个操作绝对20秒期限。
- high/medium/low 是稳定选择标识，标签仅显示 HLS 档名，不把路径中的数字当作分辨率。地址限定 HTTPS TwitCasting 主机及当前 movie 路径；旧详情的数据列表不被恢复流程改写。
- 播放与录制共用公开请求头，严格录制解析和重新取详情恢复均接入；缺失请求档位直接报告不可用，不静默降档。
- 注册表、网页搜索、根频道链接解析、打开官网、观看人数设置、多画面弹幕能力和录制脚本同步；配置迁移第5代只追加新平台，保留旧平台隐藏状态和排序，用户随后关闭新平台也保持关闭。

## 验证进度

首轮8文件定向回归 **81/81通过**，质量记录 `20260907T110732146Z-quality-focused.json`，742.550秒，结束活跃重型进程0。全库 analyze 没有错误/警告，有10处花括号风格提示（487.9秒），已修正，范围复查最终无诊断，见下文。

审查页面调用发现热门远端控制器会在过滤卡片后改变请求的 pageSize；分类远端调用还沿用默认30条，二者都不适配此60条窗口。热门与分类现选择固定窗口控制器，一次过滤后缓存、再按客户端20/80等大小切片；分类显式请求60条，同时保持旧平台默认请求量。新增实际热门路由、移动端连续页/刷新、分类与桌面改变页大小回归，最终通过，见下文。

验收脚本的原画质正则遗漏 HLS high；扩展静态用例先实际退出1，再补齐 high/medium/low 后通过，红绿日志分别为 `quality-label-red.log` / `quality-label-green.log`。这是测试工具识别修订，不是已有原生切档通过证据。

首次补充运行47通过/3失败：一个命令中的测试路径误写为 settings_upgrade_test.dart（实际为 settings_upgrade_migration_test.dart）；两个新增移动端用例在本机默认进入桌面分页，期望累计列表与真实桌面单页不一致。已更正路径并显式区分移动/桌面测试控制器；保留 `final-focused-first.log`，这三项不计作产品故障。

最终7文件定向复查 **53/53通过**，包含实际 TwitCasting 人数设置开关；修订范围 analyze **No issues found**。真实生产适配器 HTTP 探针 **1/1通过**。记录 `20260907T112025103Z-twitcasting-final-contract.json`，374.435秒，结束活跃重型进程0；日志分别为 `final-focused.log`、`final-analyze.log`、`production-contract.log`。81与53有重叠，不相加为独立用例总量。

11:20:20.538957Z，生产默认 Dio 经本机 Clash 7897 取得**55条公开推荐、18个顶栏分类、55条首分类房间、3档 HLS**。首房间媒体列表444 B，包含EXTM3U/EXTINF；严格录制输入与重新获取详情的同档恢复均通过。探针请求整个60条窗口，包含过滤逻辑，不仅验证前10条。结果写入 `production-contract.json`；`mediaSegmentsFetched=false`，未使用原生播放器/FFmpeg解码，也没有生成录像文件。

中英文工具箱帮助已补根频道与 c: 前缀链接。JSON、文档本地链接、画质/平台静态脚本及 git diff --check 通过。没有运行完整全库测试或新增 APK。

## 明确保留的能力与原生缺口

官网搜索入口属于 webOnly；原生全站搜索、完整侧栏分类、品牌资源、远端弹幕、账户/口令房间、HEVC/WebRTC/DVR 均未接入。本实现只接收频道根链接，movie/archive 链接暂不回流，避免把旧录像隐式替换为当前直播。

目录60条窗口不是全站总量。页面内复用一次获取的过滤后快照，刷新才重新取窗口；直接分别调用 API 的不同页仍各自读取当前窗口。Android/Windows 的实际目录/搜索回流、播放/音频/切档/离页、录制封装与完整解码、长录/失效恢复仍待独立验收。HTTP及解析得到地址不等同原生播放或完整录制成功。本批尚未构建、操作设备或发布。

## OPENREC 保留项

先行核对 [bililive-go 固定 OPENREC 实现](https://github.com/bililive-go/bililive-go/blob/ef71711a7c573b013d82fec01ee8d0609ee36aca/src/live/openrec/openrec.go)，读取成功。10:32:18Z公开目录API、10:32:20Z首页经本机代理均返回 HTTP403 / 919 B；10:33:10Z公开目录直连同样403。正文是通用 CloudFront 请求阻断页，证据不足以推断具体地区限制或房间不存在；未沿用参考中将任意非200映射 RoomNotExist 的做法。

原始记录在 `local-artifacts/openrec-20260907/`。未改系统/应用代理、账户或路由。OPENREC 继续作为未实现分组，不因取得403而虚构成功适配。
