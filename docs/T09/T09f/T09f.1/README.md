# T09f.1 3.x 数据迁移的真机验证

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 档位：必须；规模：中
- 功能点：F-APP-01、F-APP-02（见 [inventory/FEATURES.md](../../../inventory/FEATURES.md)）
- 涉及代码：一般不改代码；发现问题时改 `packages/live_store` 的迁移、`apps/pure_live/lib/app/iptv_legacy.dart`
- 依赖：用户选验证方式（X1）
- 来源：T09b.1、T11a.2 的“没验证”；FEATURE_PLAN 第 7 节
- 评审页：只需要用户选 X1，不用评审页
- 记录：[records/F.4a.md](../../../TASKS.md)（开发后）

## 要做的

| 功能点 | v3 | v4 现在 | 要做到 |
|---|---|---|---|
| F-APP-01 | `common/global/initialized.dart:69`：升级时导入旧数据 | `LegacyMigration` 直读 3.x 的 Hive 文件（T09b.1），单元测试用造的文件 | 3.x 的设置、关注、历史、分组、屏蔽、Cookie、WebDAV、录制任务都在 |
| F-APP-02 | `core/iptv/local/database.dart:42` | `iptv_legacy.dart` 只读复制 3.x 的库（T11a.2） | 网络电视列表、频道、节目单都在 |

## 需要用户选的

- X1 怎么验证（测试包 `.v4dev` 读不到 3.x 的私有目录，规则又不许动 3.x）：A（建议）在 K90 的 3.x 里导出一个备份文件，测试包里恢复，验证备份格式和恢复；Hive 直读靠单元测试，覆盖安装留到发布（T16a）时在备用机上做。B 用户自己用 adb 把 3.x 的 `app_settings.hive` 和 `pure_live_tv.db` 复制给测试包（需要 root）。C 全部留到 T16a。

## 测试和验证

- K90：TASKS 第 5 节 5.5 第 1、9 条。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
