# HLS 后台刷新失败的停止覆盖证据（2026-09-10）

起点 `2bf912ed` / 生产源码 `db0ad486`。承接 [起点桥接](HLS_SELECTED_START_AUDIT_2026_09_09.md) 和 [初始读取审计](HLS_PREFETCH_PREPARATION_AUDIT_2026_09_09.md)。本轮检查停止边界时先发现一个影响验收可信度的漏报，音视频共同停止时间仍为独立未完成项。

## 根因与范围

- 首个错误状态：`HlsPrefetchScheduler._refresh` 在活动期遇到清单获取、解析或保留合同失败，只把 feed 标记为 failed 并停止该 feed 的后续刷新，没有设置已有的 coverageIncomplete 闩锁。
- 诊断回调与业务覆盖事件是不同通道。先前真实录制的后续 `sequence-gap` 出现在停止前，但 native 尚未请求失败清单就停止，终态因此仍是 inputCoverageIncomplete=false。文件完整解码也不证明全时间段连续覆盖。
- 来源分类 `fork-regression`：调度层来自维护分支 `fc0fa50e`，诊断回调追加于 `718cad56`；本轮 `git blame` 复核该失败分支。已有冻结上游不含这些维护分支组件，未同步上游。
- 设计要求：活动期终止刷新立即进入已有覆盖损失通道，每个 scheduler 最多通知一次；诊断观察者异常不阻断业务标记。停止/冻结/关闭引发的取消不标新缺口；已经发布的缓存仍可正常排空，完整 body、缺失时间覆盖与包损坏保持区分。
- 不引入重试、额外网络请求、强制 native 中止、删除原始录制或媒体裁切。继续使用现有会话代次/手动停止/租约围栏及任务层覆盖持久化逻辑。此标记本身不修复源站缺片。

## 验证设计

新增 scheduler 两路活动失败的一次通知/观察者隔离、三类停止取消、生产 relay 的 HTTP/解析/sequence-gap 三类真实回环 HTTP 场景。关键断言先于第二次 native 清单 GET 与停止：已经发出覆盖事件，随后冻结清单和缓存 body 仍可读取，回收归零。

原生验证计划直接使用 FFmpegManager、显式生产预取和固定 CMAF，比较健康停止、停止前后台序号缺口和 HTTP 失败。检查及时 inputCoverage 事件、最终闩锁、排空以及独立文件可读性；不得把预期不完整样本计为健康录制 PASS。

## 结果

源码提交 `270a71f49c5694233776e8612858cb70d982d8fd`，证据如下。默认预取保持关闭，未操作手机、更新模块、重录线上直播或构建发布；完整 3.2.0 门禁和 42 组未闭环计数保持。

## 红测及扩展回归发现

- `20260909T160747895Z-hls-refresh-coverage-red.json`：8 项中 3 PASS / 5 FAIL。两路活动终止的标记仍 false，三个 relay 场景的业务事件仍 0；三个停止取消场景通过。耗时 204.120 秒（含其他工作区重型任务排队），CPU 峰值 73.92%，内存 10,548,551,680 B，终态活跃重型进程 0。
- `20260909T161032296Z-hls-refresh-coverage-native-red.json`：两项统计通过，含三场原生实验的断言失败。证据 `controls/refresh-1788970212332206`；健康、序号缺口、HTTP 失败都输出 180 V / 282 A 包。失败分别在 3035 / 3032 ms 进入后台诊断，3037 ms 请求停止；两个终态仍 coverage=false / warningCount=0，本地响应错误数为 0，直接复现“未等到下一次 native GET 就停止”的漏报。耗时 103.338 秒，CPU 32.45%，内存 11,471,421,440 B，终态活跃重型进程 0。
- 首轮修复扩展检查 `20260909T161229207Z-hls-refresh-coverage-fixed.json` 为 51 PASS / 2 加载失败：旧的 `_EventManager.start` 测试替身遗漏之前加入的 `hlsPrefetch` 可选参数，导致编译失败并连带报告编译器退出。未执行严格分析，未算整体通过。检查相邻 recorder 测试后，`_Native.start` 租约替身也有同一遗漏；两处补齐相同默认 false 参数，不改变模拟事件行为，并把租约测试加入重跑范围。

覆盖标记在传输终止场景表示连续采集保证失效，不单凭它推断缺失了多少片或已经保存的文件含坏包；序号缺口有独立合同证据。健康样本与失败样本可以具有相同缓存字节，这正是终态不应只依赖退出码、已保存包数或解码结果的原因。

## 最终验证与回滚

- 修复后的七文件定向回归 **80/80 PASS**。`20260909T161515303Z-hls-refresh-coverage-fixed-compatible.json` 的严格分析发现新测试两处多余字符串插值花括号，故该整阶段为 failed；随后只调整这两处等价测试字符串，不改生产逻辑或通过的控制器/租约测试。
- 最终 `20260909T161739271Z-hls-refresh-coverage-native-fixed.json`：**11/11 PASS**（新文件 8 项 + 两项统计 + 一项含三场原生控制）；其他四个 opt-in 探针未运行。六个修改 Dart 文件严格分析 PASS。耗时 121.512 秒，CPU 峰值 12.44%，内存 10,342,125,568 B，结束活跃重型进程 0。执行源码哈希保存在 `native-fixed-source-hashes.json`，提交前逐项复核。
- 修复原生证据：`local-artifacts/hls-refresh-coverage-20260910/controls/refresh-1788970584530023`。

| 场景 | inputCoverage 事件时刻 | 停止请求时刻 | 终态覆盖标记 | 事件数 | 本地 HTTP 失败数 |
| --- | --- | --- | --- | --- | --- |
| 健康 | 无 | 3006 ms | false | 0 | 0 |
| 后台 sequence-gap | 3036 ms | 3037 ms | true | 1 | 0 |
| 后台 HTTP 503 | 3032 ms | 3034 ms | true | 1 | 0 |

三场仍为 native code=0、drained=true、forcedCancel=false、tailDiscarded=false、integrityError=false，缓存关闭 entries/bytes=0。两个预期失败源被正确标记覆盖保证失效，测试 PASS 指的是这项行为成立，不是这些输入通过健康录制验收。原生日志仍保留停止 I/O 与 ESRCH 文本，未声明零告警。

- 红/绿共六份保留 TS：各 180 视频包 / 282 音频包；全文件严格解码 exit=0、stderr=0，十二项音视频 payload SHA-256 比较均与红测健康样本相同。`retained-decode/summary.json` 与 `input-hashes.json` 保留逐包和输入证据，未重录或替换旧样本。
- 解码阶段 `20260909T161835876Z-hls-refresh-coverage-retained-decode.json`：14.464 秒，CPU 峰值 0.31%，内存 9,079,226,368 B，结束活跃重型进程 0。
- 业务影响通过既有 `recorder_output_lifecycle_test` 验证覆盖标记的会话围栏、持久化和终态处理；租约、用户停止、未完成 body 排空与包损坏证据测试保持。两处测试替身兼容修订没有开启预取。
- 回滚本批可撤回 `270a71f4`；默认应用预取仍关闭，当前 Android/Windows 候选未包含此改动。本轮没有包构建、版本递增、手机操作或发布。

## 下一步

继续处理真实直播后续 sequence-gap 的刷新时序及独立音视频的共同停止边界。两者均未因本次“正确报告失败”而变成已修复；起点前缀修复、覆盖诊断和真正连续录制是三层证据。全平台、其余平台适配、UI/操作验收及最终文档与 3.2.0 发布仍遵循完整清单。
