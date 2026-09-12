# 视频几何仲裁与强制横屏返回方向审计（2026-09-12）

## 结论

本轮从几何证据层一路验证到 K90 Pro Max 原生呈现，修订了三个互相关联的问题：

1. 活跃画面截图会接受极端非零画布比例，异常观测可能提前稳定并覆盖可信源提示；
2. 抖音候选共识以最大面积样本为锚点，单个大面积异常值可能否决两个一致的正确候选；
3. 竖屏房间显式进入横屏全屏后，Android 系统返回只退出沉浸状态，没有恢复进入前的竖屏普通房间方向。

几何修订提交为 `01f7bfc69028658a1f06ffb30abdc69767171d0b`，方向恢复与原生层级采集修订提交为 `039f8ff37ef05d668ebfb462e34512755afd392f`。两次提交均已推送 `origin/master` 并核对远端 SHA。

## 修改前证据

### 确定性红灯

- `test/portrait_stream_support_test.dart` 增加“极端截图比例不可稳定、不可擦除可信 hint”；旧实现失败。
- `test/live_stream_geometry_hint_test.dart` 增加“多数紧凑候选应胜过单个最大面积异常候选”；旧实现失败。
- 两文件首次运行结果为 **35 PASS / 2 FAIL**，失败恰好落在上述两条新增合同。
- `test/fullscreen_orientation_restore_test.dart` 首次引用方向恢复事务时编译失败，证明生产代码尚无对应所有权与退出顺序。

### 原生复现

精确 `01f7bfc` 候选已完成竖屏普通页、竖屏沉浸、面板恢复和显式横屏全屏；随后发送一次系统返回，界面退出沉浸，但显示仍保持 `2608×1200`，8 秒内没有回到 `1200×2608`。失败及清理证据：

- `local-artifacts/diagnostics/android-geometry-arbitration-raw-20260912T215127155/summary.json`
- `local-artifacts/diagnostics/android-geometry-arbitration-raw-20260912T215127155/portrait/summary.json`

同轮还记录了 `uiautomator` 在 Flutter 路由或系统栏动画中偶发 `ERROR: could not get idle state.`；旧脚本依赖 sdcard 临时文件且可能在 shell 返回成功时拿不到文件。

## 源码与工具修订

### 几何证据

- `ActiveVideoContentObservation` 将零比例继续解释为“画布信息缺失”，非零比例仅在 `0.30..3.50` 且有限时进入可靠证据。
- 抖音 fallback 候选按比例排序，搜索误差不超过 8% 的最大紧凑簇；只有严格多数簇可形成共识，并在该簇中选择最大面积候选。
- 异常截图因此既不会自行结算，也不会抹去可信源提示；单个大画面异常值也不会否决多数一致样本。

### 强制横屏的退出所有权

- `VideoController` 为每次全屏进入保存一次性方向恢复意图；普通全屏进入会清除上一轮尚未消费的意图。
- 移动端显式 `forceLandscape` 退出时严格执行：退出沉浸 → 请求竖屏 → 等待 350 ms → 释放方向限制回到跟随系统。
- 恢复意图只消费一次，避免连续返回或后续普通房间继承旧状态。

### 原生层级采集

- `tool/android_presentation_smoke.ps1` 改用 `adb -s SERIAL exec-out uiautomator dump --compressed /dev/tty`。
- 只有取得完整 `<?xml ... </hierarchy>` 才视为成功；最多重试四次，并保存每次无 XML 的原始输出。
- 这使短暂的 framework idle 错误与真实产品断言分离，同时保持每条目标 ADB 命令显式指定设备。

## 自动化门禁

- 几何直接回归：**37/37 PASS**。
- 几何、播放器适配层、缓冲/恢复、移动布局与竖屏交互联合：**209/209 PASS**，全库 analyze 无问题；记录 `local-artifacts/build-records/20260912T133703989Z-quality-focused.json`。
- 精确 `039f8ff3` 最终提交复跑方向恢复、系统返回、预测返回、竖屏切换、几何、播放器恢复及 Windows 全屏相邻合同：**197/197 PASS**，全库 analyze 无问题；记录 `local-artifacts/build-records/20260912T141850972Z-quality-focused.json`。
- PowerShell 解析与 `tool/validate_build_policy.ps1` 通过。

## Android 构建与覆盖安装

- 构建提交：`039f8ff37ef05d668ebfb462e34512755afd392f`
- 构建记录：`local-artifacts/build-records/20260912T140510397Z-build-androidarm64-debug.json`
- APK：`local-artifacts/3.1.8-4121/PureLive-3.1.8-4121-android-arm64-v8a-debug.apk`
- 大小：`288821628` B
- SHA-256：`0F28A5F0C61A1794F72E905A1E3C0CFA015FE412B9BB50FCAFFB6D21A7D4CD7F`
- Manifest：`versionName=3.1.8`、`versionCode=6121`、仅 arm64-v8a；16 个原生库均满足最小 `0x4000` LOAD 对齐，内容完整性通过。

设备先核对为 `25102RKBEC / myron / Android 17`，`su -c id` 返回 `uid=0(root)`。随后使用 `adb -s 192.168.1.2:5555 install -r -t` 同签名覆盖：

- `firstInstallTime` 保持 `2026-07-21 18:07:53`；
- `lastUpdateTime` 更新为 `2026-09-12 22:06:07`；
- 拉回设备 `base.apk` 后 SHA-256 与候选逐字节一致；
- 证据：`local-artifacts/diagnostics/android-orientation-restore-install-20260912T220554200/summary.json`。

## K90 Pro Max 原生闭环

最终干净原生轮次绑定同一提交、同一 APK，先执行竖屏房间，再执行普通流，汇总均为 `passed=true`：

- 总证据：`local-artifacts/diagnostics/android-orientation-restore-smoke-clean-20260912T221116878/summary.json`
- 竖屏：普通页 `1200×2608` → 竖屏沉浸 `1200×2608` → 面板恢复 → 横屏全屏 `2608×1200` → 一次系统返回恢复 `1200×2608` 普通房间 → PiP → 原房间恢复；竖屏手势、横屏动作、提示与致命日志断言全部通过。
- 紧接普通流：普通页保持 `1200×2608` 且竖屏专用路径缺席 → 横屏全屏 `2608×1200` → 系统返回恢复普通房间 → PiP → 原房间恢复；证明上一房间的竖屏几何状态没有污染下一普通流。
- 结束状态：Pure Live 进程停止，MIUI 桌面恢复前台，`user_rotation=0`，stay-awake 从临时 `7` 恢复原值 `0`。

## 验收账本

`A3-03` 由 `NR` 更新为 `RUN`。确定性异常几何、延迟/多数仲裁及同一 APK 的竖屏→普通流原生序列已有证据；真实媒体中的内嵌黑边、长时间延迟几何和多次房间/重启组合仍继续执行，因此本轮不提升为 `PASS`。

宏观计数更新为 **20 PASS / 38 RUN / 4 NR**，仍有 42 组验收未闭环。Windows 客户端 Computer Use 留给后续单独一批，Astra Light 本批使用 0 次。
