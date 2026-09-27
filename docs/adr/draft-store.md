# NNNN live_store 的实现选择：库结构、密钥接口、设置读取和备份细节

- 状态：提议
- 日期：2026-09-27

## 背景

ADR 0004 定了存储方向（drift 主库、系统密钥库、设置注册表、v4 备份）。实现 `packages/live_store` 时还有几处 0004 和 store.md 没有写死、又会长期影响应用和数据格式的选择。

## 决定

1. **主库。** 文件 `<数据根>/DB/pure_live.db`，drift 2.35 + sqlite3 3.x（原生构建钩子自带 SQLite，不用已停止维护的 `sqlite3_flutter_libs`）。后台 isolate 打开，WAL 模式，`foreign_keys` 开启。第 1 版结构只有预览版要用的表：rooms、follows、follow_areas、tags、room_tags、history、block_rules、room_prefs、settings、meta；record_tasks、record_files、webdav_profiles 等录制和 WebDAV 做到时再按版本迁移加入。每个版本的结构由 `drift_dev make-migrations` 存到 `drift_schemas/`，测试用 `SchemaVerifier` 校验；生成代码提交进仓库，不生成 manager API。
2. **密钥接口是“加密 / 解密”，不是“取密钥”。** `SecretCipher.seal/open`：Android Keystore 和 Windows DPAPI 都不导出密钥，应用按平台实现这个接口。包内提供 `AesGcmSecretCipher`（调用方给 32 字节密钥，AES-256-GCM，附加认证数据绑定引用名，防止密文被挪到别的引用名下）。密文存在独立文件 `<数据根>/DB/secrets.json`（先写 `.part` 再改名），主库只有引用名。打开时全部解密进内存，读取是同步的，正好满足 `live_net` 的 `CookieVault`（同步 `cookieFor` + 变化流）；适配几行代码放在应用里，因为 `live_store` 只能依赖 `live_core`。解不开的密文按未登录处理，但保留在文件里，直到该引用名被重新写入（避免一次密钥故障清掉全部登录）。加密用 pointycastle（纯 Dart）。
3. **设置在打开时一次读进内存。** `SettingsStore.get` 同步返回，`set` 先落库再更新内存和变化流。库里只存用户改过的值，备份也只导出改过的值；默认值变化时新默认自动生效。`set` 经过定义的解码和夹紧，类型推断成 `Object` 时整数也能写进小数设置。
4. **纯黑是独立开关。** `theme.mode` 只有 system / light / dark，`theme.pureBlack` 单独一项，依据 spec/design/principles.md §2（放弃“纯黑作为第四种模式”）。
5. **v4 设置分区整体替换，3.x 只写出现的键。** v4 备份的 settings 分区替换本机 `synced` 作用域（同一平台家族时再加 `device`）的全部设置，文件里没有的键回到默认；3.x 备份没有这种完整性保证（分区结构按版本变过），只写文件里出现的键。
6. **备份细节。**
   - 本版不存储的分区（recordTasks、webdavProfiles、iptv）导出时不写；恢复时读到就写进报告并跳过。因为“文件里没有的分区保持本机不变”，以后的版本恢复 4.0 的备份不会清掉这些数据。
   - roomTags 的形状为 `{platform, roomId, tagIds}`；follows、history 的项为房间快照加 `followedAt` / `order` / `lastWatchedAt`。
   - 3.x 导入时，重新分配的标签 id 由原 id 推出（`<原 id>~<n>`，原 id 为空时用 `tag~<n>`），不用随机数，保证同一文件导入两次结果相同。3.x 关注没有关注时间，用导入时间。
   - PBKDF2（60 万次）在单独的 isolate 里计算，桌面 JIT 约 1.4 秒。
7. **分享口令放在 live_store。** MessagePack 只用到字符串、整数、空值和布尔，自己实现这一小部分（约 100 行，测试按字节核对 3.x 的布局），不为它再引入一个依赖。

## 备选方案与放弃理由

- 密钥接口返回原始密钥：Keystore 的不可导出密钥做不到，DPAPI 也没有密钥可取。
- 密文放在主库的表里：违反 0004 §3“主库只存引用名”，也会让主库备份或诊断导出带出密文。
- 每次读取设置都查库：界面构建要等异步结果，重现 REG-STORE-001 那类“首帧设置未就绪”的问题。
- 备份导出全部设置（含默认值）：新版本调整默认值时，旧备份会把旧默认值当成用户选择写回来。
- 一次建全 store.md §3 的所有表：录制和 WebDAV 的字段还会随实现调整，提前定死反而要多一次迁移。

## 影响

- 应用启动时 `await LiveStore.open(数据根)` 后再构建界面，并提供 Android Keystore / Windows DPAPI 的 `SecretCipher` 实现。
- 以后改表结构都要加迁移步骤并运行 `make-migrations`，迁移测试随之生成。
- 3.x Hive 自动迁移（读取 `.hive` 文件、来源发现、指纹账本）仍待实现，见 `packages/live_store/README.md`。
