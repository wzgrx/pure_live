# J05.1 同步前勾选内容：设备同步发送、接收前选同步哪几类（接 V01.6）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：新功能提议 [V01.6](../../../V-需求和反馈/V01-新功能提议/V01.6-设备同步选择同步内容/README.md)（D-036 同意做）；上游 pure_live `9483ccf03`
- 相关：决定 D-036、D-003（设计选择 S1～S13 写在 V01.6 README 文末）、D-018（不加新设置）；界面 [A12.6](../../../A-界面设计/A12-账号和数据界面/A12.6-设备同步/README.md)；备份格式 [J03](../../J03-备份恢复/README.md)；真机 [S02.4](../../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md) 第 3 阶段；任务书 [brief.md](brief.md)；记录 [record.md](record.md)；真机步骤 [verify.md](verify.md)

## 目标

以前设备同步只能整份同步：对方同意后，设置、关注、历史、分组、屏蔽词、屏蔽用户（开了“同步账号 Cookie”时还有 WebDAV 和登录）全部按发过来的替换。做完以后：

- **发送**前会列出要发的几类，每类带数量，默认全勾；可以只发其中几类，没勾的在对方那里保持不变。
- **接收**（主动从对方拿，或者对方发过来）前会列出会改什么，每类一个勾选框，默认全勾；只应用勾选的，没勾的保持不变。
- 配对码不变；默认全勾，和以前的行为一样；不加新设置，也不记住上次勾了什么。
- 3.x、上游和旧 4.x 设备收到缺内容的包会把缺的部分重置成默认，所以发给它们时勾选框锁住、整份发（和以前一样），并写明原因。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11:lib/`） | 4.x 改之前（`apps/pure_live/lib/`） | 现在 |
|---|---|---|---|
| 发送 | `remote_sync_service.dart` `syncToAddress`（`:985`）整份发 | `remote_sync_service.dart` `send` 整份发；页面先问“确定要将当前设备的全部配置发送到…吗”（`remote_receiver_page.dart` `_send`） | 先问对方 `/status` 是否声明 `syncParts`（`takesParts`）；勾选对话框（`_SyncPartsDialog`）替代原来的确认框；只发勾选的部分，包里带 `sections` |
| 接收（主动） | `getRemoteSettings` 后整份导入 | 配对码 → `fetch` → 预览（`previewRestore`）→ `apply` 整份 | 预览里每类一个勾选框，`apply(settings, parts:)` 只恢复勾选的 |
| 对方发来 | 只问“允许 / 拒绝” | 同 3.x（`confirm('import', …)`） | 对话框列出会改什么，每类一个勾选框，“拒绝 / 允许”，点外面不关（`chooseImport`） |
| 收到缺分区的包 | 缺的分区重置成默认（`common/services/settings/backup_controller.dart` `_importV2` `:239-285`） | 有才替换（`LegacySnapshot.fromBackup`），缺的保持不变 | 不变；另外按包里的 `sections` 只读列出的分区 |
| 线上格式 | `{type, version: 1, settings}` | 同 3.x | 全勾时一字不差；勾掉了东西时加可选的 `sections`；`/status` 多一个 `syncParts` |

## 结果

- c1 协议（`remote_sync_protocol.dart`）：`partsKey = 'syncParts'`（`/status` 回答里声明能收部分内容）、`settingsPacket(sections:)`（可选，和上游同名同义：留下的顶层分区名）、`sectionsOf`（读包里的 `sections`，不是字符串列表就当没有）、`takesParts`。
- c2 拆包（新文件 `apps/pure_live/lib/shared/backup/sync_parts.dart`）：`SyncPart`（9 类，翻译键复用备份预览的 `backup_part_*`，新加“设置”“账号 Cookie”）、`syncPartsIn`（备份里有哪几类）、`pickSyncParts`（只留勾选的：整个分区的 `tags`、`webdav`、`cookie` 按分区，`favorite`、`history` 按键拆，其余分区归“设置”；空分区去掉；`sensitiveDataIncluded` 跟着改）、`syncPartsLeaveOut` / `onlySyncParts`（全勾时原样返回）、`syncSectionsOf`、`withinSyncSections`（接收方按 `sections` 过滤）、`syncPartCounts`（用 `LegacySnapshot` 数，和恢复时读到的一致）。
- c3 服务（`remote_sync_service.dart`）：`/status` 回答带 `syncParts`；`outgoing()`；`takesParts(ip, port)`（GET `/status`，不要配对码，5 秒超时，连不上当旧设备）；`send(…, parts:)`（勾掉了东西时才拆包、带 `sections`，否则和以前一样）；`apply(…, parts:)`；服务端收到的包先按 `sections` 过滤、先解析（坏包 400，不打扰用户），再用 `chooseImport` 问用户勾哪些（没设时照旧用 `confirm`），只恢复勾选的。
- c4 界面（`remote_receiver_page.dart`）：`_SyncPartsDialog`（每行一个勾选框和文字，整行可点，至少 48 高；两类以上时最上面是三态的“全选”；什么都没勾时主按钮变灰；`locked` 时全勾且不能改；全勾时把没有单独一行的部分也带上，等于整份）；`_send`（问 `takesParts` → 勾选框和数量 → 配对码 → 发送）；`_receive`、`_chooseIncoming` 共用 `_previewDialog`（来源、会怎么变、每类一个勾选框；“账号”一行：对方有登录信息时写“写入 N 项账号信息”，开了同步账号但对方没登录时写“接收后本机的平台登录会被清空”，没带账号时是不能勾的一行“本机账号不变”）。
- c5 翻译：新加 7 个键，改了 1 个键的文字（见 record.md）。
- 不改：配对码、错码换码、`includeAccounts` 默认关、GET 时整份给、`receive()`（整份，测试和旧调用用）、备份恢复和 WebDAV 页。

## 验证

- 自动测试：`apps/pure_live/test/shared/sync_parts_test.dart`（5 个）、`apps/pure_live/test/features/remote_receiver/remote_sync_test.dart`（新增 11 个、改了 4 个，共 24 个），见 record.md。
- 真机：[verify.md](verify.md)（待真机，S02.4 第 3 阶段的两台设备）。

## 留下的问题

- 备份恢复、WebDAV 的“只恢复勾选的”（上游 `a7783b525`）：没做，要做时在 V01 另提（V01.6 S11）。
- 设置再细分（播放、弹幕、外观）：没做（V01.6 S2）。
- 搜索记录、网络电视列表、多画面不随设备同步：照旧（V01.6 S12，J05 已知问题）。
- 上游 `9483ccf03` 接收端的过滤没生效、发部分包给 3.x 会清空对方数据：上游自己的问题，下次对照上游（W01）时记一笔。
