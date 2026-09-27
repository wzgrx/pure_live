# Android 小窗弹幕设置原生审计（2026-09-12）

## 范围与输入

- 手机始终通过 `-s 192.168.1.2:5555` 操作；每轮先确认 `25102RKBEC / myron`，并读取 `su -c id` 为 root。设备运行 Android 17。
- 应用仍是精确源码 `3e41e848e2dc913baa36a9ac207bc54a0efd77b8` 的 arm64 Debug，包名 `com.mystyle.purelive`、版本 `3.1.8`、Manifest code `6121`。本批修改测试工具与验收文档，不重建或重新安装 APK。
- 没有重启手机/adbd、切换 Wi-Fi、修改 ADB 端口或授权、更新 Root/LSP/模块，也没有清除应用数据。每轮临时 stay-awake 均由 7 恢复原值 0，结尾回到桌面并停止 Pure Live。

## 首个错误状态与工具修订

当前 K90 设置首页已经调整过卡片高度，旧缓存仍把“小窗弹幕”记为 `(600,2175)`、边界 `[53,2030][1147,2320]`。实际 UIAutomator 边界为 `[48,1874][1152,2138]`、中心 `(600,2006)`；旧点落在卡片下方空隙，原 `open_pip_danmaku_settings` 又只发送点击、不核对目标页面，因此会在设置首页原地结束并报告成功。

修订分两层：

1. `open_pip_danmaku_settings` 的菜单、设置、小窗弹幕三次点击全部改为中英文实时语义解析，不再依赖这条路由上的缓存点；K90 缓存点仍按实测值纠正，供单点快速操作使用。
2. 序列新增 `assertSemantic` 动作，最终必须看到目标页专属的“样式预览 / Style Preview”。缺少目标语义时保留截图/XML并使整轮失败，不再把一次点击当作页面到达。

新增 `tool/test_android_ui_map.ps1`。旧图在首条“必须使用实时入口语义”断言稳定失败；修订后 pwsh 与 Windows PowerShell 5.1 均为 4/4，通过全部四个横竖屏 profile 的结构校验。实际设备路由依次记录：

```text
tap semantic '菜单' (84,228)
tap semantic '设置' (204,384)
tap semantic '小窗弹幕' (600,2006)
assert semantic '样式预览' at (147,498)
```

首次设备复跑还暴露 `assertSemantic` 步骤未声明 `waitMs` 时 StrictMode 读取缺失属性；执行器现将省略值规范为 0。最终路由摘要 `local-artifacts/android-pip-danmaku-native-20260912/navigation-fixed/summary.json` 为通过，页面同时含“样式预览”“小窗显示弹幕”和“恢复小窗弹幕默认值”。工具修订已在 `3627a936` 推送 GitHub。

## 开关、预览与重启持久化

新增 `tool/android_pip_danmaku_settings_smoke.ps1`，在一个受保护设备轮次中执行：

1. 备份当前规范 Hive 文件；
2. 打开设置页并记录基线 XML/截图；
3. 切到相反开关状态，核对预览的禁用遮罩与设置卡片展开/收起；
4. 强制结束 Pure Live 后重新打开同页，确认相反状态已持久化；
5. 切回原值，再次重启页面确认原值持久化；
6. 停止应用，逐字节恢复测试前 Hive 文件并核对 SHA-256。

最终证据 `local-artifacts/android-pip-danmaku-native-20260912/settings-smoke-final3/summary.json`：

| 阶段 | enable | Switch 数 | 禁用遮罩 |
| --- | ---: | ---: | --- |
| 基线 | true | 4 | 不显示 |
| 立即关闭 | false | 1 | 显示 |
| 关闭后重启 | false | 1 | 显示 |
| 立即恢复 | true | 4 | 不显示 |
| 恢复后重启 | true | 4 | 不显示 |

规范文件为 `/data/user/0/com.mystyle.purelive/app_flutter/PURE_LIVE/HIVE_DB/app_settings.hive`，测试前大小 `443377` B，恢复前后 SHA-256 均为 `701C666A664A784F5E466D5274F5A13C015DEAAF893BFBA51801ED989D8EA60C`；最终 `appStopped=true`，设备轮次退出 0。

第一版夹具错误备份了 29 B 的旧兼容文件 `app_flutter/pure_live/app_settings.hive`，第一次恢复点击又落在 Flutter 合并后的整行语义中心，导致活动开关暂时停在关闭。失败摘要和截图保留；随后先将原始开启状态恢复并重启确认，再把夹具改到规范 Hive 路径、从尾部 Switch 区域点击。最终连续两轮都从开启基线开始且逐字节恢复同一规范文件，没有用删除数据或重装来掩盖夹具问题。

## 验收映射与剩余项

A2-04 从 `NR` 进入 `RUN`：Android 基础候选已经证明移动端固定预览可达、总开关即时改变预览/控制组、关闭与恢复均跨进程保留，且用户设置文件精确复原。后续 `63597cf1` 候选进一步修复并验证开关/滑块辅助语义和恢复默认取消/确认，详见[无障碍与默认恢复审计](ANDROID_PIP_DANMAKU_ACCESSIBILITY_RESET_AUDIT_2026_09_12.md)。完整通过仍需：

- Windows 当前候选的双栏预览与鼠标交互；该 GUI 批次至多使用一个 Astra Light 任务，本批 Astra 使用 0 次；
- 颜色及后续滑块的逐项原生交互与实时预览；
- 主弹幕模板状态和备份恢复组合；
- 真实 Android 系统 PiP / Windows 小窗叠加层与长时资源趋势。

宏观账本由 **20 PASS / 33 RUN / 9 NR** 更新为 **20 PASS / 34 RUN / 8 NR**；未闭环总数仍是 42，本批不是 3.2.0 发布或 A2-04 全项通过。
