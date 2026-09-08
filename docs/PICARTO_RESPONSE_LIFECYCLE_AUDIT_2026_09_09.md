# Picarto 请求收尾与总时限审计（2026-09-09）

## 来源、复现与影响面

输入为 `3934903cde85603b1d89bafa8e9a8ac23e08f01e`，3.1.8+4121，固定 Dio 5.11.1。
Picarto API 从维护分支引入提交 `f027bbf142c61688a92a9595e2b1aef3472486d9` 至输入 HEAD
无后续差异。冻结上游 `c6c9bd70aedc503c003110dae10a83ad0bb891d8` 与 merge base
`527fea1b40885e3621d53c9646b523dd8522290c` 均无对应目录；来源归类 **fork-regression**，
不是声称远端平台改变或手机发生故障。修复前生产文件 SHA-256：
`3A89DC5C4BE84EEADB4876725790C0165A4BCE12E917EF0FCC17FAB2819946C0`。

`PicartoSite` 的目录、详情/刷新、HLS 主列表、严格录制和恢复都经过该 API read。
通过真实 Dio 请求/响应转换和受控上游 StreamController 复现，未直接模拟最终异常代替运输链路：

| 用例 | 修复前实际结果 | 期望 |
| --- | --- | --- |
| HTTP 403 响应结束 | 上游取消计数 0 | 关闭该请求上游，保留 caller |
| 1 MiB+1 字节超限 | 上游取消计数 0 | schema，关闭该请求上游 |
| 两次成功请求 | 复用同一个 caller 作为运输令牌 | 每次独立令牌并收尾，不保留已结束请求的取消关联 |
| 持续每秒小块数据 | 外层 24 秒观察期限产生 TimeoutException | 生产读取在 20 秒总预算结束并分类 transport |
| 注入响应的多字节文本 | 超过 1 MiB UTF-8 仍返回 | 与生产传输的字节上限一致 |
| 直接 object(String) | 超过 1 MiB UTF-8 仍解析 | 字节上限一致 |
| caller 取消与 typed schema 同时发生 | 对外为 schema | 取消优先，不让旧请求成为错误提示 |

网络传输原本已经有 1 MiB 字节上限；后两项预算修订针对注入请求与直接字符串解析，
不夸大为生产运输允许无限大响应。HTTP 响应错误、字节超限和总时限是实际运输路径问题。
当前 Dio 的 `response_stream_handler.dart` 中输出 controller 没有 onCancel 转发，
停止它的订阅不等同于停止原上游；其 cancelToken 路径会关闭原响应/订阅及接收计时器。

## 设计与不变量

复用已验证的 `withRequestCancellation`，不修改共享 Dio 或五个相邻平台：
每个 Picarto 请求有独立运输令牌，成功/错误/超限/超时退出时关闭该令牌，
caller 的取消转发订阅结束后释放；一条失败请求不取消 caller 或并行请求。

新增有界 readBody：StreamIterator、剩余总时限、1 MiB 累积字节预算、严格 UTF-8、finally 取消。
总预算涵盖 body 消费，不宣称改为整个连接/首包总期限；连接仍沿用现有应用网络策略。
read 的异常分类先检查 caller 取消，再保留 typed 分类；注入和 object 的上限按 UTF-8 字节统一。

保持目录参数、频道身份、画质列表、媒体 URL、请求头、代理、Cookie、数据库和配置不变。
没有修改普通页/全屏/PiP/音频/Windows 布局、用户暂停意图或录制状态机。
变化仅影响这些入口共同的 HTTP 读取与释放，原生性能与 UI 场景另计。

## 验证与工具失误记录

第一条本地临时 runner 在只有一个改动文件时把 PowerShell scalar splat 展开为字符，
格式化命令报告不存在的 t/e/s/t 路径。发现后只中止本任务命令（session 90949，退出 1）；
未运行测试，不将其算为业务红测。随后核对 Git 只有预期测试文件变更，生产文件哈希不变，
未发现残留 dart format 进程。保留 `aborted-format.json`；新 runner 固定文件数组并验证 PathType Leaf。
此失误未修改仓库常设构建脚本，也未停止其他会话。

有效修复前运行 **38 通过 / 7 失败**，记录
`local-artifacts/build-records/20260908T175334860Z-picarto-lifecycle-red-v2.json`。
其中连续小块反例真实等待生产预算，外层 24 秒是断言界限，不是增加业务重试或延迟。
修复后加 UTF-8 分块/边界、停滞 body 取消、运输流错误收尾，九文件 **267/267** 通过。
测试覆盖 Picarto 应用与配置，以及 Inke/Kilakila/Missevan/TwitCasting/Huajiao/Openrec 相邻合同；
原有五平台共同生命周期用例保持通过。超大反例断言只保留失败类别，避免后续 CI 打印整段合成文本。

最终两个改动 Dart 文件 analyze **No issues found**；记录
`local-artifacts/build-records/20260908T180708622Z-picarto-lifecycle-green.json`：
459.432 秒，峰值 CPU 40.8%、工作集 12,477,468,672 B，结束活跃重型进程 0。
测试、格式化、分析都经资源守卫串行执行；排队时保留其他工作区活跃 Java/rg，不终止其他任务。
资源值是守卫观察范围，不是 App 性能。`git diff --check` 通过。

## 交付与余项

遵循当前目标“全面验收后再发布全平台 3.2.0”，本修订不提前发布补丁版本。
本批未操作手机、安装/卸载、清数据、重启手机/adbd、修改代理或 Root/LSP 模块。
已安装 Android、候选 Android 1d318bba 与 Windows f3de664a 均不因源码修订自动更新。
下一步将 OPENREC 接入与本修订纳入一次累计 Android 候选门禁/构建，再按对应输入验收。

仍为 17 个直播站点 + IPTV、10 组未注册，宏观矩阵 20 PASS/32 RUN/10 NR，42 大项待闭环。
本次确定性修复没有新增原生 PASS，OPENREC 的当前样本/Clash 403 缺口也未被本批处理。
回滚可独立撤回本实现，不涉及数据库降级；但会重新引入上述请求收尾缺陷，旧 APK 不是修复证据。
