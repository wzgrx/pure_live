# HLS 上游响应体空闲超时（2026-09-09）

实现 `0664b540b5db472279b62fb17c7b32e69f9a1a95`，修订前 `939aa90e`。承接[缺片状态审计](HLS_INPUT_COVERAGE_AUDIT_2026_09_09.md)，本批补齐延长本地等待之前必需的上游空闲检测；**尚未改变本地 native 读取预算，也未修复持续吞吐不足导致的内容缺口**。

## 首个错误状态和范围

录制 relay 将媒体完整收齐才发布，清单也先完整读取。然而 _publishCompleteBody 与 _readManifest 中的 iterator.moveNext 没有空闲超时；上游先送部分数据再停住，就一直占有连接、暂存槽和可能已创建的 spool。native 的 rw_timeout 作用于另一个 loopback 连接，没有替 relay 关闭其上游读取。单纯调大本地超时会进一步放大这一缺口。

[FFmpeg 官方协议文档](https://ffmpeg.org/ffmpeg-protocols.html#Protocols)定义 rw_timeout 为网络读写等待上限，单位微秒。本修订在录制 relay 的每次上游 body 读取使用首个输入的正数 rw_timeout，缺省 15 秒；忽略输出侧同名参数。每次接收重新计时，磁盘写入背压不计作网络空闲；持续交付总时长大于空闲预算仍可完成。参数无效时保留缺省，正数上限与生产命令构造的 2147483647 微秒一致。

超时沿已有 504 路径返回零 body，并在 finally 取消真实迭代器、释放 spool/暂存名额；不关闭整台 relay 的共享 client，不伪报用户停止或尾片舍弃。停止已发出时保留 _HlsFetchStopped 的处理。仅 drainOnStop 的录制路径启用，非录制播放 relay、请求头/TLS/重定向超时、原生命令、用户设置、完整分片保护均未调整。

来源归为 **fork-regression**：冻结上游 c6c9bd70aedc503c003110dae10a83ad0bb891d8 与 merge base 527fea1b40885e3621d53c9646b523dd8522290c 均没有该 relay 文件；完整媒体暂存由维护提交 6415d42e71aa76d5ab3304f737bebf593cb6a792 引入，本地 body 等待未承担对应网络超时责任。本批只读核对并局部修订，没有合并上游。

## 红绿证据

新增 test/ffmpeg_hls_body_idle_test.dart，直接经过生产 relay 和 loopback TCP 服务，不以模拟 Future 替代真实连接关闭。

- 输入 idle 500 ms；上游给出比实际 body 多 1 字节的 Content-Length，先发完整前缀再保持连接。媒体前缀 3 MiB 触发一次真实落盘，另一个用例停住清单 body。
- 修订前两项均在观察上限 3 秒超时失败；连续交付用例通过。失败是新回归要求未实现，而非将旧等待视作成功。
- 修订后两项返回 504/零字节，TCP 读端确认连接已断开，stagingBodyCount=0，临时目录为空；没有 finishRequested/inputTailDiscarded。随后同一 relay 再请求健康清单与媒体成功。
- 连续 8 块、每块间隔 120 ms 的用例总交付超过 700 ms，完整输出原始字符串 01234567；没有误用输出侧 1 微秒设置，也没有把总传输时间误当空闲。

最终 **44/44 定向（7 文件）、两文件 fatal-infos 分析通过**。相邻覆盖完整/截断/超限/落盘失败、八响应名额、停止与 TLS 取消、源参数和诊断。没有改变这些断言来容纳修订。

## 原生控制及额外风险

复用已校验哈希的原 60 秒媒体夹具，未修改滚动探针；**2/2（统计回归 + 四场景原生控制）通过既有断言**。本批原件在 `local-artifacts/hls-body-idle-20260909/controls/rolling-1788944790111390/`。

| 场景 | started / 字节 | 缺片事件数 | 停止 ms | forcedCancel / inputDrained |
|---|---|---:|---:|---|
| healthy-10 | true / 1884324 | 0 | 681 | false / true |
| continuous-body-10 | false / 0 | 1 | 7026 | true / false |
| continuous-body-15 | true / 451952 | 1 | 2531 | false / true |
| delayed-headers-15 | true / 451952 | 1 | 2482 | false / true |

四场景 inputIntegrityError=false，诊断省略数为零。实际产物与前篇相同：正常 video480/audio750 包，两个 15 秒慢场景 video120/audio188 包、约 4 秒内容。持续传输没有被新 idle 检测截断；10 秒 native 提前超时和 15 秒仍缺内容的问题依然存在。

**额外发现：零输出场景本次触发既有强制取消兜底，前篇为正常排空。** 其 relay 媒体在 36006 ms 返回 410，后续缓存清单在 36008 ms 交付，初始化请求在 36020 ms 返回 410；native 到 41027 ms 才结束。没有未回收的 relay handler/暂存，也没有录像文件，但停止时延/排空差异仍是待复验风险。探针原断言没有要求该失败输入场景 forcedCancel=false，故 2/2 不等于此差异已解决；单次观测也未证明由本次改动引起。保留下一次预算协调的重点对照，不篡改终态证据。

## 资源、交付与下一步

- `20260909T090311823Z-hls-body-idle-red.json`：1 通过/2 失败，183.303 秒（含排队），峰值 CPU 8.58%、WS 7937105920 B，结束活跃重型数 0。
- `20260909T090840594Z-hls-body-idle-final.json`：44 定向和原生 2 项通过、分析退出 0；295.173 秒，峰值 CPU 32.91%、WS 8411709440 B，结束活跃重型数 0。
- 所有重型工作串行使用 build_resource_guard；排队/运行中未编辑源码或测试。使用原进程句柄等待，没有终止其他 Gradle 工作。check.ps1、red/final 源码哈希与直接 Tee 输出、native.log、各场景 JSON/TS 与 artifact-index.json 留在本地证据目录。

下一步需要有界的完整事务预算和上游进展证据，再解耦 loopback 完整发布等待与上游空闲时间，并复验零输出停止路径。当前只解决真正空闲的 body；持续涓流的绝对时间上限、完整片段下载总时限、native 提前超时及低吞吐下的内容完整性仍待处理。已存在的 128 MiB/响应、8 并发名额不是时间上限，不混为完成证据。

仍为 18 直播站点 + IPTV、9 组未注册、42 宏观大项未闭环；版本 3.1.8+4121，候选不变。没有设备、MT、Root/LSP、安装、数据清理、重启、构建候选或发布操作。回滚可对实现提交作反向补丁，但会重新暴露已证明的响应体挂起问题。

后续进展见[总预算与本地等待协调](HLS_BUDGET_COORDINATION_AUDIT_2026_09_09.md)：本篇所列待办中的累计预算和 native 等待已补实现与控制验证；真实内容缺口继续保留，历史停止差异不删除。
