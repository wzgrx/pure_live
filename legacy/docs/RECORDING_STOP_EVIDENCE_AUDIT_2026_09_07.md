# 录制停止终止证据（2026-09-07）

接续[输入完整性保护](PICARTO_INPUT_INTEGRITY_AUDIT_2026_09_07.md)，基线 `9a588f4b`。本批补诊断，不改变停止算法、超时预算或损坏判定，不将原手机尾部损坏标记为修复。

## 源码

- FFmpegRecordSession 在首次停止请求启动单调计时，终止时冻结不可变快照。自然终止的 stopRequested=false、stopElapsedMs=null，不虚构用户停止。
- 快照同时进入事件、应用日志、developer 日志及 Debug 输出：manualStop、leaseRefresh、stopRequested、stopElapsedMs、inputDrainKind、inputDrainBudgetMs、inputFinishRequested、forcedCancel、inputDrained、inputIntegrityError。
- inputDrained 只表示请求结束输入后原生完成且没有强制取消，**不等于全部媒体有效**。输入完整性与停止原因独立；快照不含 URL/Cookie/Token。原始日志继续使用既有脱敏逻辑。
- HLS 预算读取实际 relay，FLV 显示现有 3000 ms。启动阶段异常、尚未进入原生完成回调的路径不在这份终止快照覆盖范围内。

## 定向门禁

记录 `20260907T094154149Z-quality-focused.json`，基线加本批工作树增量：

- 9 个文件 **85/85 测试通过**；新增 5 项终止快照测试，覆盖自然完成、无 relay 强制取消、HLS 损坏与正常收尾独立、FLV 租约刷新、不可变/凭据隔离。
- analyze 无诊断，201.2 秒；全流程 345.059 秒，结束活跃重型进程 0。
- 既有录制守卫、25 个代理事务场景和静态构建策略通过。普通单元测试部分缺少本地化运行上下文的警告仍保留，不影响 bundled JSON 标签合同。

## 实际原生对照：本机 Windows FFmpeg，无设备命令

证据目录 `local-artifacts/recording-stop-evidence-20260907/`。共享重型锁内串行运行两个 opt-in 探针，09:42:07–09:44:29 UTC，exitCode=0；没有桌面 GUI、手机或外部直播请求。FFmpegKit 0.6.2 / builder 0.11.1，使用生产服务和真实原生库。

1. `input-integrity-1788774182999863/summary.json`：完整与截断 97 B 输入两场景通过。均自然 EOF、无停止请求，采集退出码均为 0。完整输入实际合并并严格全解码无错误；损坏输入的事件/持久化标记为 true，保留 TS、阻止合并，不对不存在的 MP4 记解码 PASS。
2. `hls-stop-1788774248659107/summary.json`：6 秒 target duration，媒体开始后 150/700/1200 ms 停止。实际终止快照 stopElapsedMs 分别 5401/4776/4285，外层 stopMs 为 5415/4780/4287；预算均 14000 ms。manualStop/stopRequested/inputFinishRequested/inputDrained=true，forcedCancel/inputIntegrityError=false，kind=hls。各输出 1,355,104 B，TS 对齐、严格完整音视频解码退出 0 且错误日志为空，原生会话已结束。普通 demux I/O 提示仍存在，不误判为明确 packet 损坏。

夹具 manifest SHA-256：`19D9819F71845723365619963D6FC44C553FBDDDA01FD538BCB55A37C6FAEC45`。独立原生断言核验实际事件，不只检查日志字符串。

## 交付与后续

下一步从干净提交构建 Android arm64 Debug 候选，将本批诊断和 schema 8 源保留一起带到手机；覆盖安装前备份并核对主 Hive。旧候选 2006c044/af88a032 归档 SHA 已重新验证一致。当前阶段未升版、推送或发布；全平台 3.2.0 验收继续。

下次原生短录需保留损坏源 TS，分别读取停止快照、packet 告警、源段与独立解码结果；嵌套代理设置恢复另行核验。此次本机对照不替代 Android 验收，也不证明原手机损坏的具体原因。
