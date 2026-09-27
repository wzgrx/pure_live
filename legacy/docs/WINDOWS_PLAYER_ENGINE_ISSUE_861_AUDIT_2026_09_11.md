# Windows 播放器内核配置审计（Issue #861，2026-09-11）

## 结论

- 上游 Issue [#861](https://github.com/liuchuancong/pure_live/issues/861) 报告 3.1.1 Windows 设置仍显示或可选择 IJK，并描述 IJK 以独立窗口播放、主窗口控制与弹幕失效。Issue 未附运行日志、设置备份或可复现视频。
- 在本分支基线 `d0437fb86d883a23fee68705702bda9291a7172b` 中，Windows 启动路径和 `GlobalPlayerService` 已固定为集成式 media_kit/MPV，设置页也只列出 MPV。因此，报告中的独立 IJK 运行形态不是当前源码支持的桌面路径，不据此虚构第二套桌面内核。
- 当前源码存在可确定复现的配置/呈现缺口：旧版本或备份中的 `videoPlayerKey=ijk` 会保留在 Hive、导入结果和设置页活动标签中，而实际 Windows 播放仍使用 MPV。这会让用户看到的内核状态与运行时不一致。
- 本批统一了平台能力策略：Windows、Linux、macOS 仅接受 MPV；Android/iOS 继续保留现有多内核选择，iOS 新配置仍以 IJK 为默认。旧桌面值、未知值和备份导入均在进入运行时前归一化。

## 修改前证据

先添加配置和真实设置页 Widget 回归，再运行修改前基线：

- 记录：`local-artifacts/build-records/20260910T224259511Z-quality-focused.json`
- 结果：7 项通过、2 项失败；两个失败均为 `Expected: mpv / Actual: ijk`。
- 失败覆盖：旧桌面 IJK 的导入/解析，以及真实 Windows 设置页初始化。
- 同轮仓库审计为 0 error、2 个既有 warning；失败来自生产行为，不是测试编译或环境问题。

## 实现

1. `player_settings_controller.dart`
   - 新增平台可用内核集合与统一归一化函数。
   - 控制器初始化时迁移持久化旧值。
   - 配置提取和解析时归一化，防止旧备份重新写回桌面 IJK。
2. `main.dart`、`player_manager.dart`
   - 启动选择和管理器回退共用相同的平台规则；桌面显式 MPV 路径保持不变。
3. `player_kernel_settings_page.dart`
   - 活动标签按平台归一化。
   - 单内核桌面显示“集成式 MPV”说明并禁用点击，不再呈现一个无效的可切换入口。
   - 移动端弹窗按真实 key 构建，继续提供 MPV/IJK/Exo。
4. 中英文资源
   - 增加桌面固定 MPV 的说明，避免“可切换”文案误导。
5. 分析期间发现的探针兼容修订
   - 全库分析暴露 `huya_recorder_continuity_probe_test.dart` 未跟进 `FFmpegManager.start` 的 `flvDiagnostics` 参数；补齐参数转发和 `FlvRelayDiagnostics` 导入。该真实网络长录探针仍为显式 opt-in，本批没有执行。

## 验证

最终记录：`local-artifacts/build-records/20260911T005230117Z-issue861-player-engine-final6.json`

- 修改 Dart 文件格式：7 文件，0 个待格式化。
- 定向单元/Widget 回归：144/144 通过。
- 严格分析：全部 7 个修改 Dart 文件 `dart analyze --fatal-infos`，0 issue。
- 新真实页面测试验证：旧 IJK 值迁移并持久化为 MPV；页面显示 `MPV Player` 与固定内核说明；不显示 `IJK Player`；内核行没有点击处理。
- 配置测试验证：桌面导入/解析归一化，移动端保留受支持内核，未知值回退至平台默认。

全库分析的失败链也保留：

- `20260910T231348387Z-quality-focused.json`：发现探针方法签名未跟进。
- `20260910T235228655Z-quality-focused.json`：签名修订后仅剩 `FlvRelayDiagnostics` 缺少导入。
- 补齐导入后，由最终严格分析覆盖全部本批修改 Dart 文件。没有把两次门禁失败改写成通过记录。

## 边界与后续

- 本批是 Windows 源码、配置迁移和 Widget 验证，不是物理 Windows 声卡、视频输出、独立窗口或弹幕叠加的原生验收。
- 未操作 Android 手机，未构建 APK/Windows 候选，未发布 3.2.0。
- Issue #861 所述旧版独立 IJK 窗口行为仍需报告者提供日志或在旧构建上复现；当前源码的确定性状态错配已修订。
- Issue #860 的频繁弹幕断线缺少日志，作为独立网络/生命周期审计继续处理。
- 全平台 3.2.0 的完整双端功能、异常恢复、性能和发布门禁仍按总清单推进；宏观 42 组未闭环计数保持不变。
