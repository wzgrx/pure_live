# 0004 存储与旧数据迁移

- 状态：已接受
- 日期：2026-09-27

## 背景

旧版把所有数据放在一个 Hive box `app_settings` 里：约 230 个无类型设置键、关注和历史的整串 JSON、明文 Cookie 和 WebDAV 密码；IPTV 另有 drift 数据库（schemaVersion 9，13 张表，Xtream 账号密码明文）。房间身份有 4 种格式，部分设置存的是显示文案。完整清单见 [diagnosis/05-app-shell-data.md](../rewrite/diagnosis/05-app-shell-data.md)。

## 决定

1. **主数据库**：drift（最新稳定版），表包括 rooms（平台 + 区分大小写的房间号，唯一）、follows、follow_areas、tags / room_tags、history、block_rules、room_prefs、record_tasks / record_files、webdav_profiles、settings、meta。
2. **IPTV 数据库**：原库原样沿用，继续按版本号升级，不重建。
3. **密钥**：Cookie、WebDAV 密码、Xtream 密码存入系统密钥库（Android Keystore、Windows DPAPI），数据库里只存引用。
4. **设置注册表**：每个设置定义为 `SettingKey<T>(id, 默认值, 编解码, 旧键, 作用域)`；备份范围、重置、导入都从注册表派生。
5. **旧数据导入**：`hive_ce` 只作迁移用依赖，在后台 isolate 打开旧文件的副本读取；源文件永不修改；导入版本和指纹记在 meta 表；失败可重试；迁移前备份到 `MIGRATION_BACKUP/app-v4-<时间戳>`（避开旧版已用的 `settings-v4`）。
6. **规范化**：显示文案转为枚举（语言转 locale 代码并与 SharedPreferences 的 `locale` 对齐）；播放器 `ijk` / `exo` 转为 `mpv`；房间级键统一为 RoomRef；标签以映射表为准，忽略 `LiveRoom.tagIds`。
7. **备份 v4**：`{format, version: 4, sections, secrets?}`，兼容旧版的无版本号、v2、v3 和“仅关注”格式；先整体校验，再一次事务写入；密钥只在用户设置口令时加密导出。
8. **预览包和签名切换的保底**：预览包使用 `.next` 包名，读不到旧沙盒，只能从文件、WebDAV 或局域网导入；换签名后需要重装的 Android 8 用户也会丢失沙盒。因此 3.3.x 增加“导出 v4 备份”，并提示只在 Firestore 上有配置的用户导出。

## 备选方案与放弃理由

- 继续用 Hive：无类型、整串重写、没有事务，是现有问题的根源。
- 首次启动时直接改写旧文件：失败后无法回退，违反“用户数据一律不删不改”的原则。

## 影响

- 第 3 阶段需要在 `live_store` 里先完成导入器和迁移测试，用真实的旧版数据副本（含 2.0 以前的 `List<String>` 格式）做样本。
- 应用启动时只在需要迁移时显示迁移页。
