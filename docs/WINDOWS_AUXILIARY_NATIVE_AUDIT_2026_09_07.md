# Windows 辅助页面累计候选原生验收（2026-09-07）

## 候选与验证范围

- 干净源码 `fadd5bdb567d7b0ec856838079927a8cc5a8b27b`，Windows x64 **Debug / unsigned**，版本 `3.1.8+4121`，不是 3.2.0 发布包。
- 构建记录 `20260907T024755676Z-build-windowsx64-debug.json`：375.47 秒，Flutter Windows 228.1 秒，结束活跃重型进程 0。保留既有 CMake CMP0175 / MSB8028 警告。
- 本次 `-SkipQuality` 复用 af88a032 完整 **1522/1522 + 42/42** 与其后仅历史数量标签改动的 **43/43 / analyze 无诊断**。没有声称 fadd5bdb 重新执行完整门禁。
- ZIP `local-artifacts/3.1.8-4121/PureLive-3.1.8-4121-windows-x64-debug.zip`，141,280,797 B，SHA-256 `E70BA0E34F59F88D5C3B334935D1C65E67134CF2B8AF3D2DC51AF6D427D2CB46`。旧 f867f799 Windows 包归档到 `local-artifacts/candidate-archive/f867f799-windows/`。
- ZIP 1303 个条目，不包含 AppData。解压到 `local-artifacts/candidates/windows-fadd5bdb/`，独立 `--instance=acceptance_fadd5bdb`，预置空插件偏好文件，避免导入主实例旧配置；本批不使用用户主资料。

## 原生操作结果

通过 Computer Use 控制本地候选窗口，实际截图尺寸 1276×718；每次输入后刷新观察，不用 Widget 测试代替实机结论。

| 子场景 | 实际观察 | 边界 |
| --- | --- | --- |
| 工具箱空跳转 | 第一按钮出现空链接提示，仍在工具箱 | 未打开播放器 |
| 工具箱空直链 | 第二按钮出现空链接提示 | 未请求画质/线路 |
| 无效跳转与草稿 | 单字符 `a` 提交后出现解析错误，`a` 仍在第一框，第二框为空 | 非真实平台短链测试 |
| 折叠/展开 | 第一卡片收起，第二卡片上移；再次展开后 `a` 保留 | 当前页面内草稿，不证明重启持久化 |
| 历史空状态 | 显示 `历史记录 (0/50)` 与空状态 | 隔离实例没有历史，不覆盖真实历史刷新 |
| 数量标签 | 原生弹窗显示“预设数量”“自定义数量” | 中文桌面尺寸；英文窄屏仍引用先前 Widget 证据 |
| 数量取消 | 选择 20 后显示当前值 20，取消回页仍为 `0/50` | 未确认缩减/清空记录 |
| 正常退出 | 关闭按钮 → 退出确认；随后独立 PID 34776 已退出 | 不涉及其他 Pure Live 实例 |

证据目录 `local-artifacts/windows-native-fadd5bdb-20260907/`：候选/进程元数据、stdout/stderr、按场景命名的 accessibility 文本；截图在本任务 Computer Use 返回中。**部分即时 accessibility 抓取滞后于截图**：`toolbox-entry.txt` 仍是上一页、`history-limit-cancelled.txt` 仅有过渡组，不能单独用于证明最终页面；相应视觉结论来自实际截图。文本框值也未完整暴露于 accessibility 树。

输入工具限制：`sky.type_text` 两次未将 `not-a-live-link` 写入已聚焦框；重新观察后，单键 `a` 出现输入法候选，Return 提交成功。因此无效链接场景实际输入为 `a`，不是长字符串。尚未定位文本注入与 Windows 输入法交互原因，不归因为应用丢字缺陷。一次旧 element_index 缓存失败后改用最新截图坐标；页面/菜单动画中的快照不计为布局缺陷。

日志存在 Easy Localization `site_*` 缺键警告及 `Problem getting monitor brightness`；本轮不宣称无日志警告，也未定位这两类日志来源。未测 CPU/内存稳定性、真实平台取流、复制确认、选择器取消或物理 DLNA。

## Android 与剩余工作

Windows 前的第二次 Android 工具箱补证再次在下一次输入前被前台守卫停止：`local-artifacts/toolbox-native-af88a032-20260907/result.json` 记录 completed=false、steps=[]、PID 22322；只到首页/更多，未执行工具箱表单。清理仅停止 Pure Live，常亮恢复；该次 PID 错误摘录文件 0 B，不扩大为全设备无错误结论。等待协调手机使用窗口后继续 Android；没有使用 MT 修改 APK 或配置 lspctl。

当前 Android 仍是 af88a032（旧历史标签）；Windows 已含 fadd5bdb 新标签。更新 W1-01 增量证据但仍 RUN，**62 项账本中 42 项未闭环**不变。下一步集中补实际平台的直链/播放器选择器与取消、录制恢复和资源回落；本次没有代码改动、重新全测、版本提升或发布。
