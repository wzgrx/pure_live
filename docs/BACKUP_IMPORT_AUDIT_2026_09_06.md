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

## 第一批纯解析：音量

音量标量和房间字典先完整解析再修改 Rx；非对象、错误条目、非有限数值报错，保留旧 JSON 字符串字典与 null 默认行为。版本化和 legacy 备份入口均先执行此解析，避免晚期坏音量修改早期 app。定向导入/隐私测试及 analyze 通过，证据：local-artifacts/build-records/20260906T080917770Z-quality-focused.json（217.151 秒）。进程句柄中断后已失效，但终态记录为 succeeded、active_heavy_processes_after=0，未重复启动。其余分区预解析、空输入辨识和持久化失败处理仍未完成。


## 第二批纯解析：8 个简单分区

主题、字体、退出、IPTV、启动、代理、刷新、Cookie 的 fromJson 复用各自无副作用 parseConfig，先转换完整分区再修改 Rx；备份入口在 app 写入之前统一调用这些解析器。原默认值、代理地址归一化和刷新并发数归一化保持；浮点设置明确接受 JSON 整数并转 double。Cookie 的账户同步仍只在提交阶段执行。

新增回归覆盖全部 8 分区的错误字段，分别走 versioned/legacy 路径并断言 app 完整快照保持；直接主题导入的后置坏字段同样在早期写入前失败。原诊断中的 theme 字段类型错误已由正式回归覆盖修复。

9 项导入/隐私测试及 analyze 通过：`local-artifacts/build-records/20260906T150859508Z-quality-focused.json`（No issues found）。此处不是整份备份的最终原子性验收：app/player/danmaku/window/favorite/history/webdav/page/tags 尚待提取纯解析，空输入识别和写盘失败边界仍待完成。未构建、安装或发布新包。

相邻刷新/主题字体/代理/字体路径 12 项回归通过：`local-artifacts/build-records/20260906T151008880Z-quality-focused.json`；未重复 analyze。

## 第三批纯解析：5 个集合分区

收藏、历史、WebDAV、分页和标签已接入导入入口的统一预检，并在各自直接导入方法中先完整解析再写入。对象列表导入启用 strict 模式：非 List 报错而非静默清空；原通用迁移读取默认行为保持。对象记录与旧 JSON 字符串记录两种格式仍兼容，历史限制及收藏归一化保留。

分页选项采用 eager List<int> 拷贝，避免 lazy cast 在写入标量后抛错。标签先同时解析 tags 和 roomTagsMap，再替换/保存两者；缺省/null 标签字段仍保留原值。版本化 tags 和 legacy custom_tags_data 均在 app 修改前预检。

本批及相邻历史/收藏回归共 20 项通过，analyze 无问题：`local-artifacts/build-records/20260906T151644728Z-quality-focused.json`。夹具使用临时 Hive；未触及手机配置。

剩余纯解析分区：app、player、danmaku、windowSize。空输入识别、完整有效恢复往返、所有分区组合保持性及异步写盘失败仍待验收；目前只证明已覆盖坏输入在写入前失败，不宣称全事务恢复。

## 第四批纯解析：应用、播放器、弹幕、窗口

最后 4 个分区接入统一预检。应用在菜单列表转换成功前保持全部值，刷新率旧配置先归一化；弹幕保留范围限制及 pipDanmaNoEmojiMode 旧别名。播放器将竖屏房间覆盖字典解析独立出来：启动读取仍容错，备份导入遇到坏字典则在任何设置写入前失败，合法枚举过滤保持。窗口导入严格检查嵌套 PiP 对象及非有限/错误坐标，旧 player-owned rememberPipPosition 在所有权归一化后再次校验。

54 项定向回归及一次 analyze 通过：`local-artifacts/build-records/20260906T152303774Z-quality-focused.json`。相邻 PiP/旧设置迁移 10 项通过：`local-artifacts/build-records/20260906T152420764Z-quality-focused.json`。目前 18 个分区均有输入预解析路径。

剩余验收重点：空对象/仅版本/无关 JSON 的识别；v2/v3/legacy 完整导入往返及隐私保留；所有分区的组合快照；异步持久化失败反馈。类型预检并不等同于所有语义值有效或写盘事务完成。未构建、安装、发布。

## 空输入身份识别

导入入口先识别备份内容：空对象、仅版本、空/仅未知字段分区、无关 JSON、空旧标签载荷和非法版本类型均在写入前报错。识别键复用现有 extractConfig 的规范输出键，并补充实际使用的旧弹幕别名及旧标签容器；未维护第二套数百字段清单。显式已知字段为 null 仍代表原默认导入意图；v2、v3、已知字段的未来版本和旧扁平格式保留兼容。

17 项导入/集合/隐私回归和 analyze 通过：`local-artifacts/build-records/20260906T152940531Z-quality-focused.json`。先前诊断的 4 个坏输入路径现均有正式保护断言覆盖（后置错误主题字段及 3 类空/无关输入），通过快照比较确认 app 未变更。

接下来仍需完整控制器注册下的有效备份往返与全快照断言；单字段/身份识别测试不替代完整恢复验收。写盘完成/错误反馈尚待处理。
