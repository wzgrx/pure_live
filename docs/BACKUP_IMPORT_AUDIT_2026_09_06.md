# 备份恢复导入审计（2026-09-06）

## 分区结构预检

本地夹具复现：v3 备份先给 app 设置有效修改，再给 theme 字符串而非对象；恢复返回 false，但后台播放值已从 true 改为 false。红测 `20260906T073058997Z-quality-focused.json` 的完整设置快照比较失败，说明失败结果并不代表数据未变更。

在版本化导入调用任何控制器之前，预检所有已知分区为字符串键的对象或原先允许的 null。后置的 cookie/webdav/tags/page/refresh 同样预检；未知扩展字段仍忽略，null/缺省仍沿用原行为。

导入校验和隐私两个文件共 4 项测试、一次 analyze 通过：`local-artifacts/build-records/20260906T073746397Z-quality-focused.json`。全部使用临时 Hive 目录，未导入真实用户配置，未构建或安装新包。

## 继续审查的边界

这不是完整事务恢复。合法对象中的错误字段类型、嵌套记录解析、空对象/非备份 JSON、legacy 导入及持久化失败仍需验证，避免异常发生前已经修改其他设置。后续应先检查各控制器的解析与写入边界，再选用预解析或可验证的回滚机制；不得仅凭结构检查宣称导入具备原子性。

## 字段与空输入复现（08:01 UTC）

对提交 `1d434a2d` 追加临时 Hive 夹具，运行
`tool/local_ci.ps1 -Scope Focused -TestPath local-artifacts/backup-import-field-probe_test.dart -SkipPubGet`。
记录：`local-artifacts/build-records/20260906T080155905Z-quality-focused.json`，退出码 1；原 3 项结构检查通过，新增 4 项数据保持断言失败。

- `app.enableBackgroundPlay=false` 后跟 `theme.enableDynamicTheme="not a bool"`：明确捕获真实 `TypeError`（在后续未注册控制器查找之前），app 完整快照已被修改。
- `{}`、`{"unrelated":"document"}`、`{"backupVersion":3}`：均在后续控制器查找之前把 app 后台播放由 true 重置为 false。这里仅证明输入辨识前发生写入，不使用测试环境缺少控制器造成的异常来推断完整应用的返回结果。
- 夹具存于本地诊断目录，未放入默认绿色回归，也未当作修复成功。未使用手机数据。

### 根因与实施方向

18 类导入仍是边读边写。`hive_rx.dart` 的 Rx 观察者立即安排异步 Hive 写入；cookie 导入还触发账号服务和用户信息加载，theme 间距触发字体主题刷新。因此简单 catch 后重新导入快照既不是事务，也会再次触发外部副作用，不采用这一方案。

下一批实现应统一为“识别备份 → 纯解析全部已提供内容 → 提交”，而非继续逐分区追加特例：

1. 明确版本化/legacy 输入识别，拒绝空对象、仅版本号和无关 JSON；保留实际历史备份迁移兼容。
2. 将各控制器的类型转换/默认值/范围归一化提取为无持久化、无 Get 依赖的解析步骤，备份入口完成所有解析后才写 Rx。当前字段值显式 null 与缺省的兼容语义需用导出→导入和旧版本夹具锁定。
3. 集合解析一起前置：字符串编码房间/分区、嵌套 PiP、音量字典、标签及 roomTagsMap。现有 `BackupMigrationUtil.parseObjectList` 遇到非 List 直接返回空，音量解析异常也清空；不能将这种静默清空当成成功恢复。
4. 对写盘失败单独设计异步完成/错误反馈。预解析只能保证坏输入在写入前失败，不能宣称覆盖磁盘失败的原子性。

验收：上述 4 项红测转绿；无效晚期字段/嵌套记录均保持完整快照；v2/v3/legacy 有效恢复及隐私字段缺省保留通过；再做一次定向 analyze。此发现尚未修复，属于 3.2.0 发布前待完成项。
