# TTing/FLEX 生产适配器与 HLS 子列表链路（2026-09-09）

应用源码 `452fadaa4ebb0feb0a9d4b0d007678cfe9771dd9`，运行基线 `b38059adb5304fdeae7236a6660960657d4f844a`，接续 [201 项应用回归](TTING_APPLICATION_INTEGRATION_AUDIT_2026_09_09.md)。探针提交 `34833223f399992945461dc78d6d7148945a9c2a`。本轮新增 opt-in 探针 `tool/probes/tting_application_probe_test.dart`；生产适配器、录制器和 relay 源码未修改。

## 真实网络范围

2026-09-09 **06:08:21 UTC** 开始，约 67 秒完成当前合同检查。仅为本次进程配置 `PROXY 127.0.0.1:7897`，Clash 监听预检通过；没有直连回退、修改系统/App 代理、账号注入或操作手机。

- 实例来自 `Sites.of('ttinglive')`；使用生产 `TtingApi` 默认传输，向进程内共享 Dio 提供实际 IOHttpClientAdapter，而非注入保存的 JSON 响应。
- 生产目录返回 **7 个**公开房间、hasMore=false。选择频道 **52406**，当前广播 **375931**；样本为 **ncp_llh**，API 返回 1080 / 720 / 480 / Auto 四档。
- 8 次 API HTTP 响应均为 200，逐次验证 `x-site-code: flex`、Origin 和 Referer。覆盖目录、首次 profile/stream、录制重新解析、recovery 重新解析和 profile 元数据刷新。
- 每档均由真实 `FFmpegHlsInputRelay.startForArguments` 绑定当次解析 URL 与精确 HlsSourceQueryPolicy。探针只通过它的私有 loopback 地址读取播放列表；子列表的实际 HTTPS 请求和 token 传递由生产 relay 完成，不在探针中手工追加 token。
- 本次每档遍历 6 份主/子播放列表，其中 5 份为滚动媒体列表，四档合计 **24 份 HTTP 200**。遍历也包含媒体列表的 rendition 引用，因此同一档观察到其他档位列表不代表主动切换了画质。

| API 档位 | 播放列表 / 滚动列表 | 独立音轨声明 | PART / MAP 标签 | 本档本地引用数 | 关闭后资源清空 |
|---|---|---|---|---|---|
| 1080 | 6 / 5 | 是 | 是 / 是 | 76 | 是 |
| 720 | 6 / 5 | 是 | 是 / 是 | 74 | 是 |
| 480 | 6 / 5 | 是 | 是 / 是 | 74 | 是 |
| Auto | 6 / 5 | 是 | 是 / 是 | 77 | 是 |

每个列表须以 EXTM3U 开始、滚动列表没有 ENDLIST，所有识别到的 URI 均指向本档的私有 loopback 服务；返回列表不暴露 token。只递归请求 m3u8，不请求密钥、初始化段、PART、PRELOAD 或完整媒体分片。观察到 LL-HLS 标签不是低延迟播放性能证据。

随后真实 StreamResolverService 重新解析所选频道，画质、源策略、到期元数据和共享播放器/FFmpeg headers 一致；recovery 返回当前档位和匹配新结果的策略。服务器可以复用尚有效的签名，本探针不要求文本 token 必须变化，也不声称已跨过真实到期时间。两个品牌的官方频道分享解析为同一频道；profile 刷新保持频道/owner 身份且不保留播放 data。

## 门禁与可复现性

- 生产探针 **1/1 通过**，不是普通回归中的 skip。记录 `20260909T061211344Z-tting-production-green.json`：testExit=0，整条记录因分析退出 2 而标记 failed；310.550 秒、峰值 CPU 72.83%、WS 7,769,464,832 B，结束活跃重型进程 0。
- 初次分析提示两项：tool/probes 不在分析器的 test/ 目录约定中，调用既有 visibleForTesting 资源计数 getter 需精确说明；写报告的多行 if 需大括号。仅补注释/单行 ignore 与大括号，没有改变探针行为或放宽断言，不重复请求已经通过的实时样本。
- 最终 `20260909T061649823Z-tting-production-analysis.json`：单文件 `analyze --fatal-infos` **No issues found**，analyzeExit=0，testExit=null（没有重跑网络）；168.627 秒，峰值 CPU 36.33%、WS 6,625,988,608 B，结束活跃重型进程 0。提交前核对最终探针 SHA-256 与 analysis-source.json 一致。
- 证据目录 `local-artifacts/tting-production-20260909/`：production-report.json 为脱敏指标，check.log 保存执行过程；online-passed-source.json 绑定实际网络通过版本，analysis-source.json 绑定最终静态修订。没有将媒体地址、签名或个人账户写入 Git。

探针默认关闭；复现时在独立 PowerShell 进程设置 `PURELIVE_TTING_APP_PROBE=1`、`PURELIVE_TTING_ROUTE=PROXY 127.0.0.1:7897` 与可选报告路径 `PURELIVE_TTING_OUTPUT`，通过仓库资源守卫运行固定 SDK 的 `flutter test --no-pub --no-test-assets tool/probes/tting_application_probe_test.dart`。每次从当前目录选样，不固化本次频道或签名；样本已下播、目录为空或上游访问失败会作为本次失败，不自动换站点、换路由或跳过。

## 完成与未完成分界

本批证明的是当前 ncp_llh 样本的**注册适配器→生产 API→逐档选源→生产 relay→真实子列表**，并补了录制输入解析/续签/分享/刷新；不是任意频道、所有源族或未来稳定性保证。

仍待音视频媒体分片读取、原生解码/首帧/音轨确认、用户切流、暂停退出、多画面、完整短录封装与严格全文件解码，以及 Android/Windows 持续运行。普通 ncp 的当前整链也不从本次 ncp_llh 结果推定。

README 与平台能力文档同步区分当前源码、正式版与不同 SHA 候选，修正遗留的 16 平台/1d318bba/“同一冻结源码”描述。当前仍 **18 个直播站点 + IPTV、9 组未注册参考平台、42 项宏观未闭环**；Android 候选 bee143e2、Windows f3de664a 未更新，无本轮构建、安装、Root/LSP/MT 操作或发布。全目标继续，不提升原生验收 PASS。
