# Windows PowerShell 5.1 工具链兼容性审计

## 发现

在用用户常用的 `powershell.exe` 入口复跑录制存储定向门禁时，质量流程在进入 Flutter 测试前连续暴露两个工具链缺口：

1. 多份含中文 UI 语义的 `.ps1` 使用无 BOM UTF-8。Windows PowerShell 5.1 会按活动 ANSI 代码页解释脚本，中文既可能变成不同标签，也可能变成引号等语法字符；录制导航测试和代理测试因此先后在解析阶段终止。
2. `android_proxy_session.ps1` 使用 `ConvertFrom-Json -AsHashtable`；该参数属于 PowerShell 6+，Windows PowerShell 5.1 在读取代理清理 journal 时会直接报参数绑定错误。

有效失败证据保存在：

- `local-artifacts/build-records/20260913T013615392Z-quality-focused.json`：代理测试脚本被 ANSI 解码后出现结构性解析错误。
- `local-artifacts/build-records/20260913T013804139Z-quality-focused.json`：Unicode 解析修复后继续到 journal 读取，稳定暴露 `AsHashtable` 兼容性缺口。

## 修订

提交 `fd015458` 完成以下收敛：

- 为全部 **25 个含非 ASCII 文本的受跟踪 PowerShell 文件**保留 UTF-8 BOM；其余 39 个纯 ASCII 脚本继续使用普通 UTF-8。
- 将英文标签序号夹具改为 ASCII-only XML，避免测试逻辑依赖中文替换字面量。
- 代理 session journal 先用两代 PowerShell 都支持的 `ConvertFrom-Json` 解码，再从顶层属性显式构造有序字典；既有 schema、设备身份、端口和布尔类型检查不变。
- `validate_build_policy.ps1` 现在枚举全部受跟踪 `.ps1`，只要文件含非 ASCII 字节却缺少 UTF-8 BOM 就立即失败，防止后续新增中文脚本重新破坏 Windows PowerShell 5.1。

该改动不放宽 ADB 前台、设备身份、串口、反向端口或清理 journal 门禁。

## 验证

- `test_android_recording_guard.ps1` 分别由 Windows PowerShell 5.1 与当前 PowerShell 完整通过；每轮均记录真实 ADB 命令 **0**。
- `test_android_proxy_session.ps1` 分别由两代 PowerShell 完成 **38 个代理事务场景**，每轮真实 ADB 命令 **0**。
- `validate_build_policy.ps1` 在两代 PowerShell 均通过；受跟踪脚本统计为 **64 个 `.ps1`、25 个含非 ASCII、缺 BOM 0 个**。
- 最终 Windows PowerShell 5.1 端到端执行 `local_ci.ps1 -Scope Focused -TestPath test/recorder_storage_policy_test.dart -SkipPubGet` 成功，内置策略/导航/代理/原生入口审计全部通过，Flutter 存储策略 **15/15 PASS**；证据为 `local-artifacts/build-records/20260913T014333405Z-quality-focused.json`。

本批只修改工具脚本编码、PowerShell 5.1 journal 解码兼容层与确定性夹具，没有执行应用源码 analyze、构建 APK/Windows 包、连接手机或发布版本；Computer Use 与 Astra Light 使用均为 **0 次**。
