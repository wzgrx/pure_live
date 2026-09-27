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

## 完整控制器往返验收

新增 backup_roundtrip_test.dart，使用真实 SettingsService 和实际启动阶段独立注册的 IptvSettingsController，所有控制器的生产导入/导出方法保持原样。临时 Hive 内通过 4 项完整链路测试：

- v2/v3：完整导入 → 修改后台播放、音量、标签 → 文件恢复 → 全部分区快照相等；省略 Cookie/WebDAV 时保留已有本地值；Hive flush 后核对后台播放与房间音量持久值。
- legacy：完整扁平备份（旧标签容器）重复恢复，含敏感字段的完整导出快照相等；逐个当前导出字段验证备份身份识别，防止新字段被身份门禁误拒绝。
- 后置坏 roomTagsMap：恢复返回 false，含敏感字段的全部已注册分区快照保持。

通过记录：`local-artifacts/build-records/20260906T154624725Z-quality-focused.json`。此前测试夹具的 Get.reset 返回值误用、格式检查及遗漏 IPTV 启动注册分别属于测试/工具问题；补齐真实注册和实时异步环境后通过，没有据此修改产品注册逻辑。测试结束显式 deleteAll(force:true) 释放观察者和定时器，再 reset、关闭临时 Hive。未触及设备用户配置。

这补齐有效恢复的组合证据；故障注入下的异步写盘完成与错误反馈仍待处理，不把 flush 后读值等同于断电原子性。

## 异步写盘完成与错误反馈（2026-09-07）

文件恢复改为 Future<bool>；新增 restoreAllSettings，并让文件、WebDAV、Firebase 三个产品恢复入口全部等待它完成后再报告成功。内部批次收集 HivePrefUtil 写入，等待 GetX 异步通知排空，再等待 putAll 和 flush；输入异常在提交前抛出，存储错误由调用方捕获。恢复期间拒绝另一个恢复请求，结束/失败后释放状态。

GetX stream 并非同步投递，首次实现的同步收集窗口遗漏后续通知；故障测试暴露此点后改为跨一个事件轮次收集。Hive Rx 同时记录当前值的持久化回调：重试相同备份时，即使 Rx 值已等于输入，也重新加入写盘批次，而不额外制造 UI 通知。正常非恢复写入路径保持原样。

故障夹具先排空启动迁移，再关闭临时 Hive：恢复返回 false，未发生未处理的恢复写入异常；重新打开后，重试完全相同文件成功，持久值正确。该测试明确断言失败后内存可能已经改变，未宣称回滚/断电事务。并发恢复拒绝、后续恢复可再次执行均覆盖。

最终 23 项导入/往返/故障/并发/隐私测试通过：`local-artifacts/build-records/20260906T160141633Z-quality-focused.json`。相同应用源码的 analyze 无问题见 `20260906T155709561Z-quality-focused.json` 的对应运行输出；该次整体为失败（尚未排空启动迁移的故障夹具），后续仅修正测试排空并增加并发断言，未把失败记录当成整体通过。

剩余发布层验收：本批未构建/安装，产品文件选择器及云端成功/失败提示未做端到端点击验收。异步网络账号刷新和系统进程终止不在该批次事务保证内。

## 共享持久化变更后的完整质量检查（2026-09-07）

首次完整运行 `20260906T160759361Z-quality-full.json`：1212 通过、1 失败，失败项为转封装 native-stop 所有权测试；不是备份测试失败。随后独立运行该文件 8 项通过（`20260906T160933767Z-quality-focused.json`），没有稳定复现产品缺陷。

代码审查发现测试以固定 20/30 ms 代替异步文件清理完成。仅修改测试：原生执行结束后等待 isProcessing 实际释放（2 秒上限），再核对目录保护、源文件、临时输出和 stopCalls；原来的 300 ms 失败返回期限及原生仍运行时保留所有权的断言保持。产品转封装代码未修改。

完整重跑通过：**1213/1213 测试、42/42 公开接口探针、analyze 无问题**，记录 `local-artifacts/build-records/20260906T161752615Z-quality-full.json`，426.032 秒，结束活跃重型进程 0。完整日志保留于 `local-artifacts/full-quality-finalization-wait-20260907.log`。此记录源码基准为 0f6f695f，包含本次测试等待修正；其后提交仅固化测试和文档。

下一步：以此完整质量证据构建本地候选包，按网络 ADB 状态选择原生验证；仍不把自动测试通过等同于全平台功能/长时稳定验收，正式 3.2.0 保持未发布。

## 候选构建与 Windows 原生备份验证（2026-09-07）

源码 `9c20ad11`（构建时 tracked clean），保留候选标签 3.1.8+4121：

- Android arm64 Debug 构建成功，`20260906T162313904Z-build-androidarm64-debug.json`，APK 286,960,675 B，16 个原生库的 16 KB ELF 对齐检查通过。网络 ADB 本轮无设备，未安装新 APK。
- Windows x64 Debug 成功，`20260906T163704450Z-build-windowsx64-debug.json`，ZIP 141,243,403 B。首次构建缺少生成的 Flutter wrapper/engine 文件；SDK 原件完整，保留并重命名单个 `flutter_assemble.tlog` 跟踪目录后增量重试成功，没有清空全量缓存。失败记录 `20260906T163011936Z-build-windowsx64-debug.json` 保留。
- Windows EXE SHA-256：`BC49A263FF1947B48165484663C3D67918502C0AC64ACF61EE4FEAB40C73FE7B`；ZIP SHA-256：`5B155F4A36839D3CDEF40B848B82CCCCD352A74F288A897E413A8B599C43B226`。

使用原生窗口实际点击设置 → 备份与恢复，走产品文件/目录选择器，而非直接调用控制器：

1. 导入 UTF-8 `.txt` 文件 `{}`，界面显示“恢复备份失败”。前后 Hive 文件 SHA-256 完全相同，`post-invalid-result.json` 为 `unchanged: true`。
2. 设置本地测试目录 → 创建备份，显示“创建备份成功”；导出的 v3 JSON 5,463 B，默认不含敏感分区，`sensitiveDataIncluded: false`。
3. 选择刚导出的文件恢复，显示“恢复备份成功”；再次导出，两个文件逐字节一致，SHA-256 均为 `DC18C53DC84CAEF9431F8179A53D550CEFCDDB35908884902AE648442A5A0000`，`roundtrip-result.json` 为 `identical: true`。
4. 再次打开恢复选择器后取消，没有成功/失败提示；Hive 哈希保持，`cancel-result.json` 为 `unchanged: true`。

证据和备份保留在 `local-artifacts/backup-native-20260907/`，没有提交备份内容。启动前候选输出目录没有 AppData；启动后的 Hive 已留存初始副本。测试仅设置了候选自身备份目录，没有登录、云端上传或修改其他安装目录。正常确认退出后，将这次生成的整个 AppData 保留到上述证据目录的 `candidate-AppData`，没有丢弃用户数据。原生工具首次启动报未发现窗口；刷新后出现使用真实路径标识的唯一窗口，选定后继续验证，没有重复启动应用。

本次有效恢复是同配置往返，未在原生 UI 注入磁盘失败；Android 新包、WebDAV/Firebase 恢复及其他历史 NR/RUN 仍待验证。另发现首次“创建备份”先要求设置目录，设置后创建时又弹出目录选择器；属于重复前置操作，下一小批从页面入口修正并补 Widget 回归，不把该候选的点击结果用于尚未构建的新源码。

## 首次导出操作简化

移除备份页面对空目录的提前拦截，复用原有导出服务的一次目录选择和首次成功后记忆逻辑。空目录时传 `initialDirectory: null`，由系统选择器决定初始位置，不再把 Unix 根路径 `/` 强加给 Windows。既有目录仍作为选择器初始提示；取消不创建文件、不改变目录，导出失败不记住目录。未改变恢复预解析、写盘批次、敏感字段默认值或移动端权限请求逻辑。

新增 `backup_page_test.dart` 使用实际 BackupPage → BackupRecoveryService → FilePickerPlatform 链路，只有目录选择器和写文件结果使用测试替身；验证首次取消、首次成功并记忆目录、首次导出失败、已有目录取消四种情况。真实文件内容/持久化沿用往返测试及上节原生验证。

测试夹具的真实资源加载先改为预读翻译数据，再由内存 AssetLoader 在 Widget 假时钟中提供。修正夹具后，旧页面的首项回归明确观察到选择器调用为零（期望一次），与原生重复前置操作一致。其后测试中的 GetRoot 清理顺序、局部函数前向引用、Toast 两秒定时器均属于夹具问题；清理改在测试体内推进 Toast 时钟并卸载根页面，不将这些失败归因于产品。包含 Toast 清理等待的运行曾在失败后的异步 teardown 挂起，已中断本次自有测试进程，确认无遗留对应 Dart/Flutter 测试进程；没有中断其他项目任务。

最终 **22/22** 页面、导入和往返测试通过：`20260906T171212019Z-quality-focused.json`；页面四种目录行为均已转绿。该 UI 简化尚未构建新的原生候选，上节 EXE/APK 仍对应 `9c20ad11`，不得据旧候选宣称此增量已完成原生验收。

最终独立 analyze 通过：`20260906T171623822Z-quality-focused.json`，No issues found（158.8 秒），结束活跃重型进程 0。测试通过记录和 analyze 记录均以 `9d02305b` 为提交基准，包含上述两处产品修改及新增页面测试，后续提交固化相同源码。完整 1213/42 门禁仍是前一批基准，并非本增量的完整重跑。

## 首次导出新入口的完整门禁及 Windows 原生验收

`cb0082e1` 干净提交（包含首次导出简化及 WebDAV 空目录/协议日志修复）完成新一轮完整门禁：**1223/1223 测试、42/42 公开接口探针、analyze 无问题**。记录 `20260906T173500498Z-quality-full.json`，329.895 秒。Windows x64 Debug 随后构建成功，`20260906T173808861Z-build-windowsx64-debug.json`；同一命令总计 518.432 秒，实际 Flutter 构建 110.3 秒，结束活跃重型进程 0。版本保持 3.1.8+4121，旧安装器没有作为本轮新产物。

新 ZIP SHA-256：`EA06A954A23642ECDD2C6BF17C10534FD57B664269FDF44ECCB6AE45B3C5AA9E`；运行目录 Dart `kernel_blob.bin` SHA-256：`81EC576F5F6D432AB40267587BE90326C06776C50B1C8330C5696952BEB35849`。Debug runner EXE 本身与上一包哈希相同，因此不单用 EXE 哈希判断 Dart 应用源码；同时核对构建元数据、kernel 与实际行为。旧 `9c20ad11` ZIP 和元数据已保留至 `local-artifacts/candidates/windows-9c20ad11-debug/`，旧 ZIP 哈希复核一致。

原生操作使用没有 AppData 的候选目录开始：

1. 备份目录显示尚未设置，直接点击“创建备份”即出现系统目录选择器，不再要求预先设置目录。
2. 取消选择后备份目录仍为空，Hive 哈希前后完全相同；没有创建新备份。
3. 再次创建，只需选择一次目录即显示成功，页面自动记住目录。实际生成 v3 备份 5,463 B，`sensitiveDataIncluded: false`，SHA-256 与上一批同默认配置备份一致。
4. 正常退出并重新启动，再进入备份页面，所选目录仍保留，证明本次原生路径经过持久化而不只是内存更新。

证据 `local-artifacts/backup-first-run-native-20260907/`（候选哈希、取消/导出/重启结果）。本次生成的 AppData 在正常退出后完整保留于该目录的 `candidate-AppData`。本轮导出文件保留在 `local-artifacts/backup-native-20260907/purelive_2026-09-07T01_40_49.txt`；没有触及用户云端数据或其他安装目录。

这关闭 Windows 首次导出入口的待验收项；Android 新入口及其他工作组继续。原生顺带复现的 WebDAV 无配置刷新错误单独见 WebDAV 目录审计，不以完整门禁通过宣称所有界面正常。
