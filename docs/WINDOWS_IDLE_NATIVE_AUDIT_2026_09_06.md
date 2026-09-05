# Windows 空闲原生线程与虎牙交互复验

## 基线与证据范围

- 业务源码固定 `8930e176e0617e0016c67461e860fe498de384f7`；本轮只读核对上游 master
  `c6c9bd70aedc503c003110dae10a83ad0bb891d8`，没有合并或操作手机。
- 本机 Flutter 3.47.0 / Dart 3.13.0，Windows **Profile AOT**，不把 Profile 数字当作最终 Release
  性能，也不把它当作公开 v3.1.8 APK。Dart AOT SHA-256：
  `EF55988B9CB1A68562D25E7CCEB823176AA0A087275D0D0C652EC95A61F08429`。
- 四次串行 Profile 构建均使用 `build_resource_guard.ps1`；后两次记录为
  `20260905T154506572Z-build-windows-profile-timer-identity.json` 和
  `20260905T160124645Z-build-windows-profile-timer-cost.json`。
  最后一轮曾等待其他项目 Java 活跃任务，未并行抢占；Flutter 构建阶段 52.5 秒。
- 临时 native 探针仅运行于自己的独立测试实例，测试结束已移除全部 `main.cpp` 探针补丁。
  不修改 Flutter SDK，不把跳过定时消息的实验代码纳入应用，不发布该诊断二进制。
  本轮业务代码未变，沿用此前 1077/1077 + 42/42 门禁，不追加无意义的完整回归。

## 发现一：这组空闲样本不是 Dart 持续绘制

先开启 Profile VM 的 CPU profiler，按目标 PID 校验 VM 身份；记录有限区间的 Dart / Embedder /
GC 时间线，随后恢复原时间线配置。输出不保存 VM 服务令牌、直播签名或用户输入。

| 场景 | 采样 | 结果 |
|---|---|---|
| 空关注页 | 20.002 秒 VM 时间线 | main isolate CPU 样本 0，没有 Frame 事件；管道 isolate 只有少量等待读取样本 |
| 虎牙热门卡片全部加载后、尚未播放 | 25.003 秒 VM 时间线 | main CPU 样本 0，没有 Frame 事件 |
| 同一热门阶段的原生线程 | 25 秒 | `io.flutter.ui` 消耗 8.297 CPU 秒，另一原生线程 1.359 秒 |

这与此前有限入场 tween、加载样式控制器的确定性缺陷是不同层。
没有据此向全部页面添加强制刷新、降低设备刷新率、清理图片缓存或停止正常动画。
Profile 的使用边界依据 [Flutter 性能分析说明](https://docs.flutter.dev/perf/ui-performance)。

## 发现二：64 Hz 消息存在，但不是该 CPU 的主因

仅在实例启动前设置诊断环境变量。消息统计不注册新定时器，60 秒自动停用：

1. 启动收敛后每 5 秒约 319–320 条 `WM_TIMER`；`WM_NULL` 收敛为 0，`WM_PAINT` 为 0。
2. 来源是 `FLUTTERVIEW`、timer ID 1、无 TimerProc；与锁定 SDK
   `flutter_window.cc` 的 `kDirectManipulationTimer` / 14 ms 精确对应。
   启动期另有 MSCTF 输入法定时消息，不以出现过即认定高频来源。
3. 第三份诊断候选做有限 A/B：20–35 秒临时不分发该唯一触控板定时消息，35 秒自动恢复。
   全程空关注页，没有测试触控板操作，也没有将该候选用于发布。

| 5 秒区间结束时间 | 主线程 CPU ms | 触控板消息分发总耗时 μs | 跳过次数 |
|---|---:|---:|---:|
| 15 s | 1031.250 | 2032 | 0 |
| 20 s | 921.875 | 2060 | 0 |
| 25 s | 1046.875 | 0 | 319 |
| 30 s | 937.500 | 0 | 320 |
| 35 s | 1000.000 | 0 | 319 |
| 40 s | 1031.250 | 1936 | 0 |
| 45 s | 1031.250 | 1893 | 0 |

**跳过该回调未使 CPU 下降**；正常分发每 5 秒约 2 ms。故撤销临时探针，保留触控板滚动、
缩放和惯性合同。来源见 [Flutter Windows 窗口源码](https://api.flutter.dev/windows-embedder/flutter__window_8cc_source.html)
及 [DirectManipulation Update](https://api.flutter.dev/windows-embedder/direct__manipulation_8cc_source.html)。

网络搜索到的 [Flutter #182822](https://github.com/flutter/flutter/pull/182822) 修复的是
TaskRunner 时间溢出，当前 SDK 已包含对应保护；本次没有持续 WM_NULL，未套用旧版本的延时补丁。

## 下一条线索：前台状态、原生无障碍查询与观察工具

- 系统 WPR CPU 启动返回 `0xc5585011`，未创建录制会话，`wpr -status` 确认未录制。
  没有修改系统权限或安全设置；改用自己测试进程的有界原生取样。
- 在空闲实例主线程采集 200 个 RIP、9.50 秒，每次挂起后通过 `finally` 立即恢复；最大挂起
  0.186 ms，平均 0.069 ms。该样本是墙钟取样，不是 CPU 调度加权，也不用于测直播帧间隔。
- 样本分布：win32u 173、ntdll 17、Flutter 5、combase 4、UIAutomationCore 1。
  用同一 Flutter DLL/PDB 符号化得到 `AXNodeData::HasStringAttribute`、
  `AXPlatformNodeWin::QueryService`、ATL COM 查询和 CRT locale 初始化路径。
  原生无障碍/COM 调用是后续定位线索，尚不构成具体调用者或唯一根因的证明。
- 后续两个 15 秒空闲窗口 CPU 均已回落，24 核归一均值分别约 0.011% / 0.022%。
  第一个发生在工具 JS 内核重置**之前**，因此不把重置说成修复。
  再激活应用并抓取状态后，10 秒均值约 0.538%；前台/后台、观察工具及用户窗口切换
  尚未隔离，禁止与旧 2.3% 样本直接计算性能提升。
- 旧采样脚本均值包含首个无差分基点 0，短区间存在向下偏差；本表只忠实引用原始记录，
  不重写历史 JSON。该测量缺陷已修复：首点为 null，真实零负载仍为 0，时钟/计数器异常
  也排除，摘要新增有效 CPU 样本数和计算口径。实际采集与统计共用
  `windows_runtime_metrics.ps1`；`test_windows_runtime_metrics.ps1` 覆盖 9 个区间案例，
  并直接执行生产摘要函数验证空基点不稀释平均值，共 10/10 通过。
  此项属于维护分支采样工具缺陷，不是播放内核修复；Windows PowerShell 5.1 与当前
  PowerShell 均通过。生产采样器对独立 shell 夹具的 10 秒集成检查为 6 个资源样本、
  5 个有效 CPU 差分，首项 CSV 留空，记录
  `20260905T162136213Z-cpu-metric-integration-pid77524-summary.json`。
  该夹具验证采集口径，不代表客户端性能。

## 虎牙实际交互复验与未闭合项

- 同一 Profile 业务 AOT 打开虎牙 DANK1NG，AL FLV、界面显示蓝光 30M；源正常进入 playing、
  退出 loading，分时画面及远端弹幕持续更新；双击进入全屏、双击返回普通布局成功。
- Esc 和空格自动化动作未观察到预期结果；音频按钮点击也未获得进入音频模式的可靠证据。
  不把图标 hover、tooltip 或按键工具成功等同于播放器动作完成。
- 后续一次绑定 Pure Live 的窗口捕获混入了前景 Codex 窗口。立即停止该截图上的输入；
  这与前次捕获 Edge 遮挡的情况一致，交互观察存在目标/焦点混杂。
  不据此继续改写通过 Widget 回归的快捷键，也不将该项标为通过。
- 此实例属于本任务独立 Profile 夹具，最后核对路径后终止，未操作正常安装目录或用户数据；
  该退出不计正常 UI 关闭/资源释放验收。临时诊断补丁与脱敏数据保留在
  `local-artifacts/diagnostics/windows-profile-8930-20260905/`。

## 后续验收要求

1. 原生 CPU：固定前台状态与观察者，采集无障碍调用栈/调用者对照；不通过关闭无障碍能力换取低占用。
2. 交互：先确认键盘事件实际进入目标窗口、焦点所属与控件点击完成，再定位 Esc / 音频 / 小窗。
3. 连续观看：保留 WUP 原生 FLV、健康连接只预取、恢复代次和线路身份修复，继续在实际最终候选
   测音视频连续性；本次空闲审计不替代 Android 呈现、长时资源和最终包验收。
4. 3.2.0 仍处验收，不以局部样本宣称全平台无 Bug、无卡顿或已发布。
