# TTing 当前 LL-HLS 预取准入诊断（2026-09-09）

源码 `5f71f3c4ac31c771e7eeb1c4862b20f5b25d288d`，起点 `d185d251`。接续[标准 CMAF BYTERANGE 原生验收](HLS_BYTERANGE_NATIVE_AUDIT_2026_09_09.md)，先确认真实平台是否满足现有预取合同，再决定下一次录制实验。

## 本批改动与证据层

扩展已有 TTing production Dio/relay 清单探针，增加独立的有界元数据摘要。只保存标签名、分片数量、版本、数值尺寸、码率及准入布尔值；源 URL、URI 属性内容、token 和原始清单不落盘。三个确定性用例覆盖数值/顺序、私密属性不输出、LL-HLS 标签解释与支持/畸形输入区分。

真实清单由生产 relay 重写后交给实际 HlsPrefetchPlan、HlsMediaSnapshot、HlsRetainedWindow 与 renderer 作元数据资格判断。它验证解析/保留合同，不代替原始来源权限/传输校验，也没有启动下载池或 native。保留原有目录、清晰度、查询策略、续签、分享与刷新断言。

## 当前真实结果

2026-09-09 13:52 UTC 经本机 Clash 7897；监听进程已确认，未改代理设置。目录 11 个公开房间，所选 channel=1013062、broadcast=375947、sourceFamily=ncp_llh，四档对应四个不同来源 URL。

| API 档位 | master 声明的宽 × 高 | 根 master 明确计划 |
| --- | --- | --- |
| 1080 | 1080 × 1920 | 通过，2 路 |
| 720 | 720 × 1280 | 通过，2 路 |
| 480 | 480 × 854 | 通过，2 路 |
| 自动 0 | 上述三个视频变体 | 暂未准入，0 路 |

每档遍历六份清单，共 24 份：根 master 加五份媒体清单。遍历会沿 rendition-report 引用继续观察，所以五份媒体清单不等于录制计划选中了五路；明确质量的根计划仍是唯一视频 + 音频。

20 份媒体清单均成功解析出完整 EXTINF 分片（3 或 4 片、target duration=2、version=10），但**保留资格全部为 false**，共同的六类未处理标签为：

- `#EXT-X-DATERANGE`
- `#EXT-X-PART`
- `#EXT-X-PART-INF`
- `#EXT-X-PRELOAD-HINT`
- `#EXT-X-RENDITION-REPORT`
- `#EXT-X-SERVER-CONTROL`

每份还含 6–9 个部分分片。本轮元数据证据解释了现有完整快照路径为何整体保留旧 relay；前几轮本地普通 CMAF 原生成功，并不表示真实 TTing 已经使用预取。本轮没有盲目再做 100 秒媒体采集，也没有把“诊断探针通过”记成“真实录制通过”。

## 新发现的验收注意项

本次为竖屏源，720 档声明 720 × 1280。旧 `tting_recording_probe_test.dart` 仍硬编码输出 height=720，后续应按明确来源尺寸/方向核对，避免把正确竖屏流误判为错误质量。该探针源码当前还固定 rwTimeout=10、nativeReadTimeout=60,000,000；正式复验应明确与应用默认 15 秒合同对齐，并记录实际参数，而非依赖先前摘要。以上是下一次录制门禁准备，不是未经解码就宣称实播尺寸已验证。

下一步按 LL-HLS 规范补齐标签与完整分片保留语义，覆盖 DATERANGE 生命周期、PART/预加载状态、report 引用与服务端控制信息；再验证真实录制是否进入预取及连续音视频。自动档的明确选路资格另行处理，质量标签、部分分片与用户停止意图都保留为独立不变量。

## 验证、资源与剩余范围

- **3/3 确定性测试、1/1 真实清单探针、三文件 fatal-infos 分析通过**；无失败重试或门禁降级。
- API 记录八次 200，四个 relay 均验证关闭后的资源注册数为 0；未下载媒体/MAP/KEY/PART，未调用 native。
- 探针隔离的本地化环境打印两次 `tting_auto` 缺键警告，未据此判断应用资源缺失；完整资产/UI 验收仍独立。
- 资源记录 `local-artifacts/build-records/20260909T135331095Z-tting-admission-qualification-first.json`：250.614 秒（含排队），峰值 CPU 9.12%、工作集 5,791,236,096 B，结束活跃重型进程 0。执行句柄已收到终态，三份源码哈希已核对再提交。
- 证据目录 `local-artifacts/tting-admission-20260909/`，核心文件 `qualification-first-online-report.json`，只含脱敏结构与数值。

没有修改生产行为、默认预取、手机、构建、版本、上游或发布。宏观仍 **20 PASS / 32 RUN / 10 NOT RUN，42 项未闭环**；完整 UI/所有平台/录制与稳定 3.2.0 发布目标保持。
