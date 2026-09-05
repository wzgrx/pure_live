# GPT-6 Astra 指令与工作流审计

## 范围和依据

基线为 `3377ce300dfe254049e45b5eb0252bf0c17aeda1`，审查 AGENTS、两个仓库技能、CLAUDE 兼容入口、构建/维护/上游策略、Codex workspace 配置、10 份 GitHub workflow 及相关校验器。此前尚未提交的播放器和测试文件保留，不纳入本次规则改动。

2026-09-06 实际读取的官方资料：

- [GPT-6 Astra 指南](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-6-astra)：目标明确、按授权持续完成任务、减少冲突指令、按风险选择测试、按实际条件决定委派。
- [AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)：项目指令入口与作用域。
- [Skills](https://learn.chatgpt.com/docs/build-skills)：技能元数据发现与按需加载。

以下取舍是针对本仓库的实现，并非官方承诺的性能数值。保留当前模型及推理配置，没有新增 API 参数、全局配置或强制最大推理设置。

## 发现与处置

| 发现 | 影响 | 修改 |
| --- | --- | --- |
| AGENTS、技能和 CLAUDE 重复展开维护/构建细节 | 上下文重复，规则变更易漂移 | AGENTS 保留核心边界；技能按任务路由；资源/签名规则仍以 BUILD_POLICY 为准 |
| 所有 Bug 都容易扩展到无关上游查询、所有检查 | 小任务停顿、重复验证 | 明确局部证据先行、按风险定向验证、通过后只有新证据才扩大检查；上游实际合并仍保留完整审查 |
| 缺少明确的新请求接管和完成条件 | 工作到一半只汇报计划，或切换请求后继续旧构建 | 明确保留未提交工作、按当前请求执行、记录剩余任务；重大缺失才提问 |
| workspace setup 自动 `flutter pub get` | 绕开固定 SDK 与重型互斥，打开项目即解析依赖 | setup 留空，按需通过现有入口解析 |
| stage-ios 标签由三份 workflow 同时接收 | 重复 iOS 构建；两个 builder 共用组且其中一个取消旧运行 | 仅 feature-build 接收三种 stage 标签；另外两份保留手动兼容入口，构建组关闭抢占取消 |
| feature-build 只依赖前一个可跳过平台 | Android 失败、Windows 未选择时，Linux 仍可能继续 | 累积直接依赖并逐项检查所选平台成功 |
| legacy builder 发布只检查 quality | 平台失败/空选择仍可能进入 Release | 两个 builder 都检查至少一个平台被选择，以及所有所选平台成功；补发布/索引超时 |
| Linux quality job 预下载 Windows Firebase SDK，Windows job 反而没有该步骤 | 无关开销和平台错位 | 移至对应 Windows job，并补 legacy Windows 同一步骤 |
| 手动 release index 没锁定 checkout master，也未限定变化文件 | 分支误用、无关文件导致空提交或并发冲突 | 固定 master、仅检查 releases.json、加超时和并发组 |
| publish-signed-android 仅验证“有签名”，未比对固定证书 | 非预期证书的 APK 也可通过旧检查 | 固定证书比对；核对来源 workflow 成功、提交 SHA 和已有 tag 指向；加发布互斥组 |
| 静态 gate 主要靠文本标记 | 标记存在不代表依赖图或触发器正确 | 新增结构校验器检查 YAML 重复键、触发器唯一性、依赖环/缺失、失败门禁、超时、Action 固定 SHA 和技能链接 |

保留 Android/Windows 优先、用户已有的 Bug 修复批次 Android 默认交付、固定签名、16 KB APK 内容核验、数据迁移、手动暂停/退出、来源代次、缓存上限与资源互斥。没有为“释放性能”删除这些约束。分支合并和设备操作继续以当前任务范围为准。

## 入口体积

按 UTF-8 字节统计，不当作 token 或速度测试：

| 文件 | 之前 | 之后 |
| --- | ---: | ---: |
| AGENTS.md | 8,787 | 4,926 |
| pure-live-build/SKILL.md | 4,487 | 1,862 |
| pure-live-maintenance/SKILL.md | 2,342 | 1,862 |
| CLAUDE.md | 1,006 | 264 |
| 合计 | 16,622 | 8,914 |

入口减少约 **46.4%**；新增按需工作流说明，不在每个任务默认展开。没有运行同任务模型 A/B 基准，因此不声称实际响应速度或正确率提高了某个百分比。

## 验证

- `python tool/validate_agent_workflow.py`：5 个指令/路由文件、10 个 workflow，0 错误；两个负向对照能检出重复 iOS 触发和缺失失败门禁。
- `tool/validate_build_policy.ps1`：通过。保留原有构建/签名约束，更新累计依赖的期望值。
- 两个技能均通过系统 skill-creator 的 `quick_validate.py`。
- 全部 workflow 的 30 个 PowerShell 块完成 AST 解析；129 个 Bash 块通过 `bash -n`；10 个内嵌 Python 块通过 AST 解析。GitHub 表达式先替换为中性占位，仅验证语法，不执行脚本。初次原样 PowerShell 解析和本地默认编码导致的 Bash 输入失败是检查工具问题，修正后重新检查通过，不计为产品故障。
- `git diff --check` 通过；workspace TOML、技能 frontmatter 和本地引用链接通过。

证据位于 `local-artifacts/agent-audit/`。本次没有启动 Flutter analyze/test/build、Gradle、ADB 或远程 workflow，也没有增加版本号或发布 APK。静态语法和依赖图检查不代表远程 runner/Secrets/下载/签名执行已验收。

## 保留的边界与后续

- 既有维护/构建脚本仍拥有执行细节。为避免改变安装包，未将四千余行历史打包/签名工作流一并重写；本轮去掉重复触发并修复调度/发布检查。未来合并实现需做产物等价核验。
- 各发布路线仍由调用方逐阶段等待完成，不把 GitHub concurrency 当持久 FIFO 队列。不同发布入口针对同一版本也应顺序调用。
- 当前已经保存的播放器修复仍待其独立验收/交付。规则审计完成不等于虎牙观看体验或 3.2.0 整体验收完成。
- 文件在本地修改，尚未推送或触发远程执行。
