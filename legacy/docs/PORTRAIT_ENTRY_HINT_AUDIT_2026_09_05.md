# 竖屏全屏进入提示布局回归

## 来源与复现

分类 `fork-regression`。提示布局来自 `d67d3edd0`，本轮未合并上游。K90 Pro 运行源码 `8cda379d` 的 Debug 包，下滑进入竖屏全屏时，提示文本和底部播放器按钮占据同一区域。截图：`local-artifacts/diagnostics/android-portrait-presentation-20260905T053410185/portrait-fullscreen.png`。

首个错误约束：提示仅预留 bottom=18 dp，而该模式底部控制栏高 104 dp，两者独立定义。文本 Row 又未给文本弹性宽度，窄屏/大字体时可能横向溢出。截图灰暗来自提示正在淡出及重叠，不是主题设置失效；源码本身已明确白字与深色背景，不重复修改主题系统。

## 修复设计

- 控制栏和提示共享 `portraitFullscreenControlsHeight=104`，提示始终预留控制栏高度加 12 dp 间距；不随控制栏动画上下跳动。
- 左右保留 12 dp，文本使用 Flexible 自动换行，保持系统文字缩放、白字/深色底。
- 保留 3 秒短提示、淡出、IgnorePointer 与已修复的恢复手势，不影响底部按钮点击、不添加常驻遮挡。
- 普通横屏、普通竖屏、系统 PiP 的视频比例和播放器生命周期均未更改。

## 验证

修复前新增两项 Widget 回归均失败：提示下边界 771.5 超过允许的 684；窄屏大字体发生 RenderFlex overflow。记录 `local-artifacts/build-records/20260904T214043013Z-quality-focused.json`。提示定位/大字体与既有进入门禁、隐藏计时、手势和播放器切换回归合并执行；新包需再次目视核对提示位置。

回滚仅涉及提示 padding/Flexible 与共享常量，未修改任何持久化字段。

修复后提示交互 + 播放器选择合计 19/19 通过，附带 8/8 PiP 证据解析用例；记录 `local-artifacts/build-records/20260904T214216083Z-quality-focused.json`。本轮未重复执行全仓 Analyze，最终正式冻结门禁仍需执行。
