# Windows 音量控件替换与操作归属（2026-09-10）

## 范围与基线

在 `92c8952acf3c38ae337ebb605b00a54d196065d3` 上继续 [音量初始化审计](VOLUME_LIFECYCLE_AUDIT_2026_09_10.md)。实际调用点 `video_controller_panel.dart` 仅在 `Platform.isWindows` 显示 `OverlayVolumeControl`；本批是 Windows 控件与 Flutter Widget 合同，不是 Android 物理按键修复或真机验收。

原控件只在 initState 订阅一次 controller Rx，未处理 didUpdateWidget；异步初值只有 mounted 检查；同时监听移动/桌面两套默认音量。来源分层：旧初值/两平台默认音量链可追溯到上游 `8dd7bf630` / `b2f19b262`（upstream-existing）；控制器 Rx 订阅由维护提交 `842fe3a36` 添加但缺少替换归属（fork-regression）。本轮只查本地历史，没有合并上游，也没有认定最新上游或 Issue #858 的处理状态。

## 确定性复现

新 `volume_control_lifecycle_test.dart` 挂载实际控件，以窄的 VideoController/设置接口替身控制初值、Rx 事件和写入；测试不复制控件实现。首次基线 1 PASS / 5 FAIL，记录 `20260910T104239489Z-volume-widget-baseline.json`。其中一项迟到回包断言在重绘前读取图标，形成误通过；补齐 pumpAndSettle 并断言旧读确已发起后，在未修改业务源码时得到 **0 PASS / 6 FAIL**，记录 `20260910T104638653Z-volume-widget-baseline-settled.json`。

六项均保留原断言，不以删测通过：

1. 相同 Widget 位置替换控制器后，仍显示旧初值且不监听新 Rx。
2. 旧控制器事件继续改变已属于新房间的图标。
3. 用户已静音后，初值回包将显示重新改成有声。
4. 旧控制器迟到初值将新房间的显示改回旧状态。
5. 初始查询等待期间的新音量事件，被更旧查询值覆盖。
6. Windows 播放期间修改移动端默认音量，实际误调用当前控制器 setter `[0.9]`，期望不写入。

## 修订

- 控制器替换时取消旧 Rx 订阅，创建新归属代次，使用新控制器当前值初始化图标/静音恢复值，并重新查询及订阅。
- 初值查询绑定控制器、代次及值修订号；用户静音/拖动、平台默认设置或新 Rx 事件均优先于更早的查询。等值事件也退休旧查询。
- 只监听当前平台的默认音量与全局静音；保留当前平台设置生效、静音与恢复行为，并对有限值做 0–1 限幅、忽略非法观察值。
- 新初值会同步刷新已打开的百分比面板。控制器替换/卸载时移除并 dispose OverlayEntry；悬停释放只交给旧所有者，旧浮层事件不操作新控制器。
- 业务修改仅在 `volume_control.dart`；不改解码器、录制、全局音频路由、设置 schema、资源或模块。回滚可独立恢复该文件及新增测试。

## 验证

四文件 **89/89 PASS**：新增 12 个 Widget 用例，加上真实 VideoController 音量/source commit、键盘退出/音量空值以及音频模式/PiP 生命周期的已有回归。除六项复现，新增相邻检查覆盖新房间静音恢复、当前平台默认/全局静音、卸载后的迟到读及设置事件、打开面板时替换/悬停释放、打开面板的迟到初值刷新、非法事件及超界默认值。两个修改 Dart 文件严格 `dart analyze --fatal-infos` **No issues found**。

记录 `local-artifacts/build-records/20260910T105044687Z-volume-widget-repair.json`：109.034 秒，峰值 CPU 17.69%、工作集 15,023,890,432 B，结束活跃重型进程 0。记录 sourceCommit 为修改前的 92c8952a，sourceFiles 的 SHA-256 绑定实际测试输入；提交前复核两个文件哈希一致。原始日志在忽略目录 `local-artifacts/volume-widget-20260910/`。

这不是整个应用的新全量门禁、Windows 原生候选或实际声卡/音量输出证据。鼠标进入/离开、百分比和图标由 Widget 引擎验证，未启动用户桌面播放器、操作手机或构建新包。拖动轨迹、极端文本缩放和无障碍操作仍需其各自测试；不从图标检查推导所有 UI 项完成。

## 后续验收

[48154d15 Android 候选](ANDROID_CUMULATIVE_CANDIDATE_2026_09_10.md)继续保留，但不含本批及前一批音量修订；其旧全量/产物证据不冒充当前源码结果。需要将已完成源码批次纳入后续累计候选，再验证 Windows 普通/全屏/小窗下的实际显示、声音、输入及资源释放。代码已验证的源同步与包发布分开，暂不发布 3.2.0。

继续完整目标：剩余参考平台扩展、双端功能/布局/操作矩阵、长时与多路录制、资源趋势、全平台发布和文档整理。当前仍为 20 直播站点 + IPTV，7 组参考平台未注册；历史 62 组中 42 组未闭环不因 89 项测试改变。没有新 ADB/MT/LSP 操作或上游同步。
