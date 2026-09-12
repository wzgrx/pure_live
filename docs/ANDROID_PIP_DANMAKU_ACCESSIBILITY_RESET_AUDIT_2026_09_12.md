# Android 小窗弹幕无障碍与默认恢复审计（2026-09-12）

## 首个无效状态

上一轮 K90 原生 XML 已证明页面可达和总开关可持久化，同时暴露三个独立问题：

1. 小窗弹幕开启时，四个 `android.widget.Switch` 都是空 `content-desc` 的 NAF 节点；关闭后 Flutter 又把标题与 Switch 合并成整行语义，同一个控件在两种状态下的可访问名称和点击范围不一致。
2. Syncfusion 滑块只暴露数值，例如 `12.0`、`500.0`，辅助功能无法判断它正在调整字号还是字重。
3. “恢复默认”实际会重置总开关、显示规则、颜色、字号、字重、速度、透明度、密度与帧率共 14 个值，原确认文案只列出其中一部分。

确定性红灯分别得到“找不到带 Enable 名称的可点击 toggle 语义”、滑块缺少设置名称，以及中英文确认文案缺少总开关/显示规则/字重。该结论来自语义节点与控制器赋值的直接断言，不以截图目测替代。

## 源码修订

应用修订提交为 `63597cf112e38dd77c8157b7cbb5e67dfb70ba52`：

- 四个开关统一使用 `SwitchListTile`，标题、状态、点击动作合并为一个整行可点击的 toggle 语义节点；开启与关闭状态使用同一结构。
- 字号、字重、速度、透明度、区域、发送间隔和手动 FPS 均使用带设置名称及格式化单位的 `semanticFormatterCallback`。
- `defaultPipDanmakuAutoFps` 成为初始化、配置导入与恢复默认共用的单一默认常量。
- 中英文确认文案明确说明总开关、显示规则以及全部样式类别都会恢复默认。

新增 Widget 回归覆盖移动端固定预览、桌面双栏独立滚动、开关整行点击/语义状态、滑块名称与数值、恢复取消、14 项默认值和双语文案。最终一次聚焦门禁同时运行六个测试文件，共 **43/43**，全库 analyze 无问题；记录为 `local-artifacts/build-records/20260912T111128152Z-quality-focused.json`，仓库审计为 `local-artifacts/repository-audits/20260912T110904193Z-focused.json`（4800 文件、0 error、既有 2 warning）。

## 当前候选构建与覆盖安装

从干净应用源码 `63597cf1` 构建 arm64 Debug：

| 项目 | 结果 |
| --- | --- |
| 包名 / 版本 | `com.mystyle.purelive` / `3.1.8` / Manifest code `6121` |
| APK | `local-artifacts/3.1.8-4121/PureLive-3.1.8-4121-android-arm64-v8a-debug.apk` |
| 大小 / SHA-256 | `288802226` B / `D52040A348B28638A593F9AC905D8368FFA0A2CB9D584C236BF14F7288DF8977` |
| ABI / 原生库 | 仅 `arm64-v8a`；16 个库；ELF LOAD 最小对齐 `0x4000` |
| Flutter 资源 | 1262 项，`206806033` B |
| 构建记录 | `local-artifacts/build-records/20260912T111332123Z-build-androidarm64-debug.json` |

受保护设备轮次始终明确使用 `-s 192.168.1.2:5555`，正文再次确认 `25102RKBEC / myron` 与 `uid=0(root)`。在 Pure Live 停止时执行 `install -r -t` 返回 `Success`；`firstInstallTime` 保持 `2026-07-21 18:07:53`，首次启动前规范 Hive SHA-256 仍为 `701C666A664A784F5E466D5274F5A13C015DEAAF893BFBA51801ED989D8EA60C`，设备 `base.apk` SHA-256 与本地候选一致。

首次安装轮次的业务基线已经看到 4 个具名 Switch 和具名字号滑块，随后测试器把一组中英文别名错误展开成两个必选项，导致测试器在关闭态报告英文别名缺失。失败摘要 `local-artifacts/android-pip-danmaku-native-20260912/settings-accessibility-reset-63597cf1/summary.json` 同时记录安装、APK 哈希和 Hive 恢复均通过；这是测试器分组错误，而非应用语义失败。测试器在 `e2c2652d` 修正为候选组任一命中。

## K90 原生结果

修订后的完整轮次位于 `local-artifacts/android-pip-danmaku-native-20260912/settings-reset-final-63597cf1/summary.json`，所有业务与清理检查均为 true：

| 阶段 | enable | Switch 数 | 具名 Switch | 字号滑块语义 |
| --- | ---: | ---: | ---: | --- |
| 基线 | true | 4 | 4 | `字体大小, 12.0` |
| 立即关闭 | false | 1 | 1 | 控件组收起 |
| 关闭后重启 | false | 1 | 1 | 控件组收起 |
| 恢复后重启 | true | 4 | 4 | `字体大小, 12.0` |
| 自定义关闭 → 取消恢复 | false | 1 | 1 | 状态保持 |
| 确认恢复 | true | 4 | 4 | `字体大小, 12.0` |
| 恢复后重启 | true | 4 | 4 | `字体大小, 12.0` |

开启时四个原生节点依次为“小窗显示弹幕”“纯文字模式（隐藏表情）”“根据小窗尺寸自动缩放”“保留平台弹幕颜色”，字重滑块同时暴露“字体粗细, 稍粗”。恢复确认框包含完整新文案；取消后自定义关闭状态保持，确认后总开关回到默认开启并跨进程保持。

测试结束把规范 Hive 的 SHA-256 从 `701C666A…EA60C` 精确恢复到同一值，`appStopped=true`，系统回到桌面，stay-awake 从临时值 7 恢复原值 0。全程未重启手机/adbd、切换 Wi-Fi、调整 ADB 端口或授权、更新 Root/LSP/模块，也未卸载或清除应用数据。

## 验收状态

A2-04 保持 `RUN`，本批新增证明：移动端固定预览、桌面双栏结构、开关与可见滑块辅助语义、总开关持久化、恢复取消和确认后的重启持久化。剩余项为颜色及后续滑块逐项原生交互、主弹幕模板保存/恢复组合、Windows 当前候选 GUI，以及真实 Android 系统 PiP / Windows 小窗叠加层长时资源。宏观账本仍为 **20 PASS / 34 RUN / 8 NR，共 42 组未闭环**；本批 Astra Light 使用 0 次。
