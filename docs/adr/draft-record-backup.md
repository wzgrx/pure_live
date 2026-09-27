# NNNN 录制任务进备份：数据库外的分区经应用提供的接口读写

- 状态：提议
- 日期：2026-09-28

## 背景

v4 备份格式（store.md §7.1）从一开始就留了 `recordTasks` 分区，产品清单 F-BAK-01 要求“范围补上录制设置和任务”。ADR 0017 第 1 条决定 4.0 先不存这个分区：导出不写，恢复读到就记 `unsupported` 并跳过。录制设置（`record.*`）早已是 `device` 作用域的设置，随完整备份走；缺的是任务列表。

任务不在 `live_store` 的数据库里：应用用 `live_record` 的 `JsonFileRecordTaskStore` 写 `<数据根>/DB/record_tasks.json`（ADR 0021 第 7 条），任务的状态由正在运行的 `RecordManager` 持有，直接改文件会被管理器下一次写入覆盖。`live_store` 按依赖方向只能依赖 `live_core`（`tools/gate/check_deps.py`），不能引用 `live_record`。

## 决定

1. **分区内容只有“录哪个房间、怎么录”**：房间（platform + roomId）、展示快照、任务画质（`QualityPreference` 的名字）、autoReconnect、monitor（导出时任务在排队到收尾之间、等待开播，或因轮询关闭、应用退出而停止）、createdAt、order。会话信息、文件路径、游标、失败和错误文本不进备份：只对本机的文件有意义，录制文件本身也不进备份。
2. **`live_store` 定义接口，应用实现**：`RecordTaskBackup`（`exportTasks` / `restoreTasks`）和值类型 `BackupRecordTask` 在 `live_store`；`BackupService(recordTasks: …)` 可选。应用的 `RecordTaskBackupAdapter` 在备份真正运行时才取 `recordManagerProvider`，把任务和 `RecordTask` 互转。没有提供接口时（测试、将来的其它宿主）行为和 ADR 0017 相同：不导出，恢复记 `unsupported`。
3. **恢复先校验、后写入，写在事务外**：分区和其它分区一起在计划阶段校验（坏房间、重复项丢弃，未知画质按默认画质，分区不是列表则整份文件报错、什么都不写）；数据库事务提交后，与密钥一样在事务外交给录制器。录制器写失败记 `writeFailed`，不回滚已提交的数据库部分。
4. **“整体替换”不打断录制**：`RecordManager.importTasks` 删除文件里没有的空闲任务（文件保留），写入文件里的任务（以“已停止”写入，同一房间保留本机的会话信息），正在排队、解析、录制、重连、收尾的任务不动；`monitor` 的任务在开播监控打开时进入等待开播。
5. **跨平台家族也恢复**：任务不是设备设置，手机上的监控列表恢复到电脑上同样有用。

## 备选方案与放弃理由

- **把任务搬进 `live_store` 的 `record_tasks` 表再备份**：store.md §3 早有这张表的设计，但管理器目前用 JSON 文件，迁移存储是另一件事，而且即便入库，恢复时也必须经过正在运行的管理器，否则会被它覆盖。
- **恢复时停止正在录制的任务再整体替换**：严格符合“整体替换”，但恢复一个备份不应该悄悄中断正在进行的录制；被跳过的任务在报告里体现为写入数少于读取数。
- **备份会话信息和文件列表**：换设备后路径无效，同设备恢复时本机任务本来就有这些信息（第 4 条保留）。
- **`live_store` 直接读写 `record_tasks.json`**：绕过管理器，和运行中的状态冲突，也让 `live_store` 知道录制器的文件格式。

## 影响

- ADR 0017 第 1 条里 `recordTasks` 的“本版不存储”由本记录取代；`webdavProfiles` 仍按 0017、0022 跳过。
- store.md §7.1、§7.2 已补上分区格式和恢复规则；`live_record` 新增 `RecordManager.importTasks`。
- 测试：`packages/live_store/test/backup_v4_test.dart`（导出格式、往返、校验、仅关注、没有录制器、录制器失败）、`packages/live_record/test/manager_test.dart`（importTasks）、`apps/pure_live/test/record_backup_test.dart`（两个管理器之间的完整往返）。
