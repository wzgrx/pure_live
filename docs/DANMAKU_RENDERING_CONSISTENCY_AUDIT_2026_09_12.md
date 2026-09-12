# 主画面与小窗弹幕呈现一致性审计（2026-09-12）

## 结论

A4-03 已由未执行进入运行中。源码审计确认主画面和小窗分别使用适合自身视口的字号、速度、密度与区域参数，
并共同使用显示模式驱动的自适应 FPS；本轮修复了两项直接可见的描边偏差：实际小窗把主画面可调描边宽度固定成
1.0，设置预览则始终绘制一份固定黑色阴影而不显示真实描边。现在预览与实际 `CompactDanmakuOverlay` 共用
`CompactDanmakuTypography`，字体、字重、描边开关和 0～4 描边宽度遵循同一策略。

精确提交 `90d5d73b49251847c79895caff05a2e3184a568a` 已通过五文件 **37/37** 回归和全库静态分析；同提交
Android arm64 Debug 通过内容、ABI 与 16 KB ELF 对齐检查，并在 K90 Pro Max 上同签名覆盖安装、完成小窗设置
即时状态与双向重启持久化回归。真实系统 PiP 的逐帧视觉对照、120 Hz 帧时间线、长时高密度热稳定性及 Windows
应用小窗仍继续执行，所以 A4-03 维持 `RUN` 状态。

## 首个错误状态

基线 `c3f1b0ef86c14b4ed16d0184e4bc43dc1d483bd0` 存在两份互相矛盾的描边实现：

1. 主画面 `BarrageConfig` 使用 `danmakuFontBorder`，合法范围为 0～4；实际小窗读取相同的描边开关，却把
   `strokeWidth` 固定为 1.0。因此用户把主画面描边调到 3.0 时，小窗仍以 1.0 绘制。
2. 小窗设置预览没有绘制 `PaintingStyle.stroke`，而是无条件附加 `blurRadius=2` 的黑色阴影。关闭描边后预览
   仍保留黑边效果；打开描边并调整宽度时，预览也不反映实际结果。
3. 新增的 Widget 用例在基线上直接失败：`_PipDanmakuPreviewPainter` 不存在 `showStroke`、`strokeWidth` 与
   `strokePainters`，说明预览没有描述实际小窗的描边状态，而不是截图阈值或测试等待时间问题。

## 源码路径核对

| 维度 | 主画面 | 小窗/设置预览 | 当前结论 |
|---|---|---|---|
| 速度 | `danmakuSpeed`，20～400 px/s | `pipDanmakuSpeed`，20～400 px/s；自动缩放时字号和距离同比例缩放 | 两个视口可独立配置，预览与实际小窗共用 `CompactDanmakuMetrics.baseSpeed` |
| FPS | 手动 30～240 或显示模式自适应 | 手动 15～240 或同一显示模式自适应 | 省电/均衡/最高策略统一；引擎用 VSync `Ticker` 与微秒累加器按目标频率步进 |
| 密度 | 最多 48 条、50 ms 准入 | 1～20 条可见、50 ms～2 s 准入、队列 36 | 小窗按有限轨道独立限流，设置预览使用相同可见数和发射间隔 |
| 字体 | 字号 10～30、字重、字体族 | 字号 8～24、字重独立；字体族继承全局弹幕字体 | 字体族及字重现在进入共享紧凑排版策略，预览和实际小窗同步重建 |
| 描边 | 全局开关与 0～4 宽度 | 继承同一开关与宽度 | 实际小窗不再固定 1.0；预览先画同宽黑色描边，再画文字填充 |
| 区域 | 全局区域；竖屏源可按上四分之一/减量模式进一步收敛 | 小窗区域 10%～100% | 两者都只把比例应用一次；竖屏主画面的额外限制属于明确的呈现策略 |
| 轨道 | 主画面按字号计算 24～64 px | 小窗与预览共用 18～44 px 轨高、表情尺寸和防重叠间距 | 分配高度与绘制高度使用同一紧凑指标 |

描边透明度复用 `flame_barrage` 的单调平方根策略：低透明度文字仍保留可读轮廓，透明度为 0 时轮廓也为 0。
文字和描边使用相同字号、字重、字体族及 1.15 行高，描边先绘制、填充后绘制，设置变更在 `Obx` 依赖收集
阶段读取并即时重建。

## 可重复验证

### 源码回归

- 红灯：单独运行 `preview follows the outline used by the compact renderer`，基线因 Painter 没有描边状态字段失败。
- 绿灯：`compact_danmaku_metrics_test.dart` 与 `pip_danmaku_preview_test.dart` 合计 **15/15 PASS**。
- 最终 focused CI：以下五文件合计 **37/37 PASS**，`flutter analyze` 为 `No issues found`：
  - `test/compact_danmaku_metrics_test.dart`
  - `test/pip_danmaku_preview_test.dart`
  - `test/danmaku_settings_controller_test.dart`
  - `test/danmaku_refresh_rate_policy_test.dart`
  - `test/danmaku_settings_surface_test.dart`
- 精确提交质量记录：`local-artifacts/build-records/20260912T123607829Z-quality-focused.json`。
- 仓库审计：`local-artifacts/repository-audits/20260912T123446335Z-focused.json`，4803 个跟踪文件、1 个本批待提交审计文档、0 错误。

### Android 候选与设置回归

- 构建记录：`local-artifacts/build-records/20260912T122922123Z-build-androidarm64-debug.json`。
- 候选：`PureLive-3.1.8-4121-android-arm64-v8a-debug.apk`，288813391 B，SHA-256
  `04700D3B4EC33583CB21D9360B058E86DD3928C09C9E53336F23E07A2753F90A`。
- 来源提交精确为 `90d5d73b49251847c79895caff05a2e3184a568a`；Manifest `versionCode=6121`，唯一 ABI
  `arm64-v8a`，16 个原生库的最小 LOAD 对齐不低于 `0x4000`。
- 设备 `25102RKBEC / myron / Android 17` 上使用 `adb install -r -t` 覆盖安装；设备 `base.apk` 哈希与候选
  相同，`firstInstallTime` 前后均为 `2026-07-21 18:07:53`。
- 小窗设置完成原状态→反状态→进程重启→原状态→进程重启，以及恢复默认取消/确认/重启；结果为 PASS：
  `local-artifacts/diagnostics/android-pip-danmaku-settings-20260912T203010138/summary.json`。
- 测试前后规范 Hive SHA-256 均为
  `701C666A664A784F5E466D5274F5A13C015DEAAF893BFBA51801ED989D8EA60C`；应用已停止，前台回到
  `com.miui.home/.launcher.Launcher`，`stay_on_while_plugged_in=0`。

## 剩余验收

1. 在真实系统 PiP 中逐项对比描边开/关、0/1.5/4 宽度、字体族、字号、字重、速度、区域和密度，并保留同帧
   截图或屏幕录制证据。
2. 在最高刷新率模式下用 SurfaceFlinger/Perfetto 记录主画面与 PiP 的帧时间线；30/60/120 FPS 各覆盖稀疏与
   高密度消息，不以 `uiautomator` 或 Android View `gfxinfo` 代替 Flutter Surface 帧证据。
3. Android 连续 PiP 往返和 Windows 应用小窗各执行长时压力与资源回落；Windows GUI 若实际需要
   Computer Use，可按仓库规则使用单个 Astra Light 任务。本批 Astra Light 使用次数为 0。
