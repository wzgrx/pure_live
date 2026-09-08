# HLS 源级 token 传递能力审计（2026-09-09）

## 定位：平台接入的运输层能力，不是已注册的平台

基线 `43a424a3ad998ec95742073b9641ab5704d5b11f`。本批依据 [TTing/FLEX 公开合同](TTING_PUBLIC_CONTRACT_AUDIT_2026_09_09.md) 实现显式、单源绑定的 HLS token 请求策略，并接入已有 `FFmpegHlsInputRelay` 的上游请求/重定向边界。

功能实现提交 `b68a0f1074063922a00b39adab03402c3e59492a`；随后仅修正 if 花括号与多余导入两项分析提示。

普通 URI 相对解析不应自动继承主列表 query；原 relay 的这一行为不是普通 HLS 缺陷。本批是用户要求新增参考平台所需的能力扩展，未把缺少 TTing 特定能力归因于上游 Bug，也没有同步上游。已有匿名在线证据为 NCP 子列表无 token 返回 403、按官方播放器请求规则补齐后 200；本批不重复使用那次过期签名请求。

**尚未接通 TTing API/平台注册、应用播放器及录制任务解析到这个可选参数的传递。** 本批完成低层策略及真实 loopback HTTP 合同，不宣称 TTing 已可播放或录制。

## 实现与不变量

- `HlsSourceQueryPolicy.fromSource` 保存单个已选择 URI 的不可变策略，要求唯一、非空、有效编码的 token，限制源 URI 长度为 16,384 字符；错误诊断不回显原签名。
- 只向同协议、同 host/有效端口、同源目录及其子目录的无 token 资源附加原始 token query 对。比较目录段而非字符串前缀；userinfo、编码分隔符、控制字符及含糊的路径不获得参数传递。
- 保留既有子链接 token（含空值/重复值）、其他签名参数、重复参数、编码、fragment。只复制 token，不复制 rootOnly 等整组主列表参数；它不是刷新 token 的机制，也不是资源 URL 白名单。
- 可选 `sourceQueryPolicy` 必须匹配 relay 的精确初始 URI，包括路径、画质与签名；没有输入或策略错配时，在建立网络资源前报错，不静默退回错误源。显式策略可启动桌面 relay，普通未选择策略的调用路径保持原条件。
- 在发起子请求及每个重定向时应用策略，沿用原 master/媒体/KEY/MAP 重写、范围请求、Cookie/Authorization origin 规则、TLS 检查、资源代次回收与停止排空。loopback URL 仍只暴露临时 opaque ID，不嵌入源 token。
- 策略属于单个 relay，close 清除其持有引用，并沿用连接取消及资源清理；没有全局 token 表或修改全局网络客户端。未声称能够擦除托管运行时中的字符串内存。

HTTP 支持用于显式本地夹具，生产 TTing 适配器仍须按已取证 HTTPS 合同核对实际响应与源域名。作用域外 URL 保留本身的参数，不向其附加源 token；这不等同于审查或剥离远端主动写入 URL 的其他凭据。

## 确定性证据

新增两个文件共 40 项，连同原 relay/Cookie 文件共 **67/67** 通过：

- 策略 34 项：精确源/新签名身份、原始编码与重复参数、明确子 token、协议/host/端口/目录边界、路径歧义、无效 UTF-8、单 token 约束、长度上限和脱敏错误。
- 真实 HTTP relay 6 项：无 opt-in 的子列表仍 403（标准 URI 行为对照）；opt-in 的 master→nested media→KEY/MAP→Range 分片通过；录制排空模式结束后复用已发布列表并补 ENDLIST，不新增源请求；同域内重定向补 token、跨目录/端口不补；独立双会话与关闭一个后另一个仍用自己的 token；错配策略报错。
- 相邻 27 项：原 `ffmpeg_hls_input_relay_test.dart` 与 `hls_session_cookies_test.dart`，涵盖原 Cookie 重定向、停止时未完成响应、范围重写、资源代次界限和连接结束。

初次扩展运行 `20260908T232017152Z-hls-source-query-green.json` 为 **65 通过 / 1 失败**，249.743 秒、CPU 峰值 38.45%、Working Set 13,467,283,456 B、结束活跃重型进程 0。唯一失败是夹具在 first.close 后读取 `first.inputUri.port`，底层 HttpServer 已解绑；请求/token 断言已通过。将两个 inputUri 在 close 前保存，生产代码保持不变；首轮日志/测试副本/哈希独立保留，不计产品失败。另增加一项排空组合，再次回归。

`20260908T233134648Z-hls-source-query-green.json`：**67/67**，604.670 秒、CPU 峰值 47.17%、Working Set 12,167,917,568 B、结束活跃重型进程 0。该次 Dart analyze 退出 0，但实际输出仍有两条 info（多行 if 缺花括号、测试冗余 dart:async 导入）；该记录的 passed 字段仅反映退出码，分析提示另行处理。

已修正这两处纯语法/导入提示，核对差异没有改变分支条件、返回值或任何测试断言，保留 67 项测试证据，不机械重跑。追加四文件 `dart analyze --fatal-infos` **No issues found**、终端退出 0，记录 `20260908T233824245Z-hls-source-query-analysis.json`：331.348 秒、CPU 峰值 27.48%、Working Set 11,763,769,344 B、结束活跃重型进程 0。该次只做格式/分析，testExit 为 null，未伪报再次执行测试。

收尾逐项核对的输入 SHA-256：
- 策略：`3F155C78064D57867DE90C92A2460ED473F29A91AE5DA6FC5B7F48B1E60DF4BB`。
- relay：`2056E15E104B933C54CA334B692EF0577963E303372104F7FE2715F45B563BE2`。
- 策略测试：`DA36EC4FF923B208AE1975057801137BA1111254D3B33920681F87189B12DC1C`。
- relay 策略测试：`91B7453ED732DC63B60E641A7BEA72B94D0D8FE26706FA378FE70D0883C865E7`。

所有脚本、原始日志、输入哈希、基线和调用链审查保存在忽略目录 `local-artifacts/hls-source-query-20260909/`。这些夹具没有使用生产签名、账号、解码器或手机。

## 应用接入前的实际断点

1. `LivePlayUrlResolution`、正常/恢复扩展及 `PlayerController` 目前复制 URL/画质确认；新策略尚未作为源元数据沿该链传递。
2. `PlayerManager` 的刷新结果、提交快照与原生事务需要保留源策略，同时保持 session/intent revision、暂停和 latest-wins 规则；不能在站点解析时启动无所有者的后台 relay。
3. `MediaKitAdapter` 的 SourceEventFence 使用实际打开源。后续 loopback 原生 URI 与远端显示/刷新身份需要明确对应，且旧 relay 必须随真正原生源退出释放，而不是仅随路由卸载。
4. `LiveAudioService` 绑定当前 UnifiedPlayer/会话；`AudioStreamLoader` 在 lib 中仅有方法定义、没有实际调用者，主音频接入不应误加到该旧 helper。
5. multiview 的默认解析及 qualityLoader 直接调用 `getPlayUrls`，会跳过统一 resolution 的新元数据，需与换档/线路、每格生命周期一起串联。
6. `StreamResolverService` 到 `ResolvedRecordStream` 再到 `FFmpegService.start` 尚未传入此策略；需要与新签名、重试、停止及 FFmpeg 会话清理一起覆盖。

因此下一步是完整的源元数据及会话接线、TTing 严格 API/状态/身份与平台注册，而非把现有 URL 加入列表便计为新增平台。持有记录仅证明这部分源码已审查，不证明所有原生路径已经完成修改。

## 发布与回滚

无 ADB/MT、设备操作、构建、安装或发布；Android bee143e2、Windows f3de664a 候选均未变，版本仍 3.1.8+4121。本批以及前面三批弹幕 UI 修订均尚未包含在旧 Android 候选。

当前 17 直播站点 + IPTV、10 组参考平台未注册、历史 42 个宏观未闭环项均保持，未增加原生 PASS。全平台稳定 3.2.0 仍按完整目标验收后交付。

本批可独立反向提交回滚；可选参数没有现有应用调用者，回滚不触及数据库、Root/LSP 或用户数据。后续一旦接入调用方，回滚需同时移除其新能力依赖。
