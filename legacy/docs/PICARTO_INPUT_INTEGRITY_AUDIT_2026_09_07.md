# Picarto 录像尾部损坏与源文件保留（2026-09-07）

## 实际证据与结论边界

接续[首轮 Android 原生审计](PICARTO_ANDROID_NATIVE_AUDIT_2026_09_07.md)，本批基线 `e689763b`，优先分析本机已有文件、日志和源码，没有再操作手机或请求外部直播源。

- 原 MP4 SHA-256 `DC532468BBD5BD6FCEBB7778F624C35BD5BC8A5B40F62DD404A6BFFB7BE2CA24` 保持不变。
- 单线程 `showinfo` 全视频解码输出 661 个帧记录；错误出现于末尾、约第 659 帧 / PTS 22.015333 秒附近，含 `error while decoding MB 59 40, bytestream -25`、`corrupt decoded frame`。解码存在帧重排，不把日志邻接当作精确损坏字节偏移。
- 手机 16:37:40.842 日志已报告 `packet corrupt (stream = 1, dts = 3092510880), dropping it` 和 HLS demux I/O error；采集返回 0。16:37:40.998 的 stream-copy 封装同样返回 0，随后原 TS 被删除。
- 这些证据支持“尾部损坏 + 采集阶段曾报告损坏包”，**尚未区分源站损坏、接收截断、停止取消与输出边界**。原 TS/同一上游分段缺失；不据此宣称已经修复 Picarto 尾部损坏。
- 普通全解码返回 0 却有错误日志，严格 `-err_detect explode` 返回 -1094995529。任何完成判定继续检查实际错误信息，而不只检查退出码。

证据位于 `local-artifacts/picarto-integrity-20260907/`：`findings.json`、`native-terminal-sanitized.log`、`tail-frame-error.log`；完整帧日志仍在原录制证据目录。没有提交直播文件、用户 Hive 或原始设备日志。

## 已确认的应用缺陷

本地实现缺口（fork regression），不是上游合并：

1. FFmpegRecordSession 已锁存完整性告警，但终止判断只在参数包含 `-xerror` 时采用它。实时采集不使用该参数；手动停止返回 complete。
2. 采集的明确数据包损坏没有传到录制 attempt，持久化只保存目录/前缀。
3. VideoProcessorService 只验证后续封装的状态和非空文件；stream-copy 不做完整解码，封装返回 0 后就提交 MP4 并删除源 TS。采集已知损坏的证据因此丢失。

本批不通过延长停止等待、禁用 TLS 或反复重试猜测原始损坏原因，也不引入每次长录像都全量解码的隐性资源成本。

## 修订

- 为实时会话单独锁存明确 packet/PES/解码损坏，并在终止事件中传递 `inputIntegrityError`。普通停止时的 demux I/O 提示、时间戳修正、弃用警告不触发该字段；诊断尾部被裁剪后仍保留本会话结果，新会话不继承。
- pending attempt JSON schema 8 保存该字段；schema 7 及无字段旧记录按“未观察到损坏”处理，**不是已验证无损坏**。同目录/前缀重复记录按逻辑或保留告警，重新排队、恢复、用户开始新录制均不擦除旧 attempt 的证据。
- 控制器按当前 session/任务所有权接收字段，在异步终止采样后仍复核来源；旧 session 的迟到损坏事件不污染新 session。
- 封装服务在创建原生会话、部分 MP4 或删除文件之前，核对该精确 attempt 的持久化告警。已知损坏的源段保留，不自动封装或删除；其他目录/前缀的正常 attempt 仍走原有封装流程。
- 失败状态区分 `ffmpeg.inputintegrity` 与普通 merge 错误；手动再次停止、进程恢复也保留该结果。原始文件保留遵循既有缓存/用户删除策略，本批不承诺永久免受用户清理或缓存配额影响。
- 补齐中英文错误说明，以及实机房间头部缺失的 `site_picarto=Picarto`。对所有已注册平台建立中英文站点标签合同，避免下一平台接入再次显示原始翻译键。默认头像未在此批修订。

schema 8 的损坏字段只有新实现理解；旧候选并不具备此保护。未来回滚前应先保留相应任务数据与源段备份，旧包不作为损坏 attempt 的自动恢复验证。

## 验证

- 回归红测已实际运行：旧模型恢复/去重后 `inputIntegrityError` 为 null，期望 true；`red.log` 保留输出。
- 原翻译文件的 `site_picarto` 在中英文均缺失，记录 `translation-before.json`；与上一轮原生原始键显示相互印证。
- 首次定向门禁 125 通过/1 失败：新测试误用 camelCase 阶段名，实际既有持久化规则会转为小写；修正期望为 `ffmpeg.inputintegrity`。应用源码 analyze **无诊断，335.0 秒**，记录 `20260907T091445522Z-quality-focused.json`，全流程 579.457 秒。
- 第二次在格式检查阶段发现编辑工具增加了文件末尾空行，**未执行测试**；记录 `20260907T091645481Z-quality-focused.json`。移除空行后复验。
- 最终同一应用源码的 **126/126 定向测试通过**，记录 `20260907T091917135Z-quality-focused.json`。包括新数据损坏锁存/持久化/源保留/单次停止与再次停止、旧会话隔离、正常 attempt 对照、中英文全部站点标签及相邻 HLS/租约/用户意图/封装生命周期。新增原生探针晚于该次 analyze，由下述原生编译/运行验证；不外推为全量应用回归。
- 静态设备工具合同、73 个录制守卫场景、25 个代理事务场景及资源/构建策略检查通过；实际设备命令 0。部分普通单元测试未加载 EasyLocalization 运行上下文而输出警告，bundled JSON 标签合同单独通过。
- 重新核对旧健康 HLS 原生对照：三个停止点均 inputDrained=true / forcedCancel=false / 全解码错误为空，但都有普通 demux I/O 提示、均无 packet 损坏标记；结果存于 `historical-healthy-controls.json`。这是旧样本对照，不是本批新原生运行。

## 本批实际原生对照（本机 Windows FFmpeg，非 Android 实机）

在共享重型任务锁内串行运行两个 opt-in 探针，未打开桌面 GUI、手机或外部直播源。真实 FFmpegKit 0.6.2 / builder 0.11.1，通过生产命令生成器、FFmpegService 事件和 VideoProcessorService，不使用假原生执行器。探针文件与媒体在本机，原始手机 MP4 没有变化。

### 输入损坏传播与源保留

新增 `tool/probes/recorder_input_integrity_probe_test.dart`，用同一本机有效 TS 及其截去最后 97 B 的副本进行对照。1 个集成测试包含 2 个真实原生场景，**通过**；证据 `input-integrity-1788772978087068/summary.json`：

| 输入 | 原生采集退出码 | 事件/持久化损坏标记 | 封装结果 | 采集 TS | 严格完整解码 |
| --- | --- | --- | --- | --- | --- |
| 完整本机 TS | 0 | false / false | 1 个 MP4 | 正常删除 | 退出 0、错误日志为空 |
| 截断副本 | **0** | **true / true** | 阻止自动封装，0 个 MP4 | **保留** | 未对不存在的 MP4 执行，不记 PASS |

两次原生采集均退出，错误场景没有重新调用原生封装或删除源段。这个可重复对照证明“零退出码也可能带有输入损坏，结果需跨封装持久化”；它不证明原手机录像就是相同的截断原因。

### 健康 HLS 停止对照

复用未改动的 `recorder_hls_stop_probe_test.dart` 和 6 秒 target duration 的本机滚动列表。1 个测试包含 **3 个实际停止点**，均通过。证据 `hls-stop-1788773069218273/summary.json`：

- 媒体启动后 150 / 700 / 1200 ms 请求停止，实际停止耗时 5316 / 4776 / 4358 ms。
- 三次均 inputDrained=true、forcedCancel=false、nativeRunning=false；输出各 1,355,104 B，TS 对齐通过。
- 三次完整音视频解码均退出 0、错误日志为空；普通停止 demux I/O 提示仍被记录，不等同明确 packet 损坏。

执行记录 `native-hls-control-run.json`：09:21:12–09:24:49 UTC（含排队/编译），exitCode=0；两次 Flutter 调用串行。manifest SHA-256 `19D9819F71845723365619963D6FC44C553FBDDDA01FD538BCB55A37C6FAEC45`。质量记录基线为 `e689763b` 加本批工作树增量，不冒充干净提交的整库门禁。

## 下一步与未完成项

本批只补齐已知损坏的证据传递、源段保留和界面错误说明，**不是录像质量 PASS**。当前手机仍为 `2006c044`，未安装本批源码；原生版本尚不具备新增字段。

下一阶段需要保留原 TS，并让终止证据明确包含 manualStop / inputDrained / forcedCancel / inputIntegrityError，再以有边界的 HLS 分段与停止对照区分输入损坏和取消截断。新嵌套代理恢复仍待最小实机复验；长录、后台、续接、其他平台和全平台正式门禁保持原范围，3.2.0 未发布。
