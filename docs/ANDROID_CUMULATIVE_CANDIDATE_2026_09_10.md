# 累计 Android 候选与完整门禁（2026-09-10）

## 状态与身份

累计候选业务源码为干净 `48154d15f2d6d79b057f4ed27a3f49a7bc9b8495`，已普通 push 并核对 origin/master。此后的本篇及验收索引提交仅补证据，不改变该 APK 源码身份。此前完整门禁的失败、独立复现和夹具修订详见 [累计质量记录](CUMULATIVE_QUALITY_AND_SOURCE_SYNC_2026_09_10.md)，保留原始失败，不将 273 项定向结果冒充本次全量结果。

**已完成：完整自动化门禁、Android arm64 Debug 构建、包完整性/签名核验及独立归档。尚未完成：当前手机安装/数据复核、Android/Windows 全功能原生验收及全平台稳定 3.2.0 发布。** 本轮没有手机操作、上游合并、Root/LSP/模块更新、tag 或 Release。

## 完整门禁

记录 `local-artifacts/build-records/20260910T100007699Z-quality-full.json`，09:50:52 UTC 开始，551.709 秒：

- 构建/路径/录制/代理/设备守卫离线夹具及设备 UI map 通过；这些离线夹具不是 ADB 操作或真机验收。
- 锁定依赖解析成功，没有依赖升级；仓库审计 4632 个已跟踪文件、2561 个文本：0 错误、2 个既有警告（公共 localhost TLS 测试密钥白名单和 empty-catch 清单）。
- 全库 `flutter analyze` **No issues found，181.2 秒**。
- 完整 Flutter 测试 **4072/4072 PASS，3 分 09 秒**，不是只重跑先前失败文件。
- 公开接口探针 **42/42 PASS**，具体项从完整日志独立提取到候选目录 `full-quality-summary.json`。范围为 Bilibili、斗鱼、虎牙、快手、CC、抖音、Twitch、SOOP、YY 的指定分类/推荐/搜索/房间/播放/弹幕身份检查；不涵盖所有已注册平台的全部接口，更不证明持续解码、录制或 GUI 稳定。
- HTTP/HTTPS 代理为本地 Clash `127.0.0.1:7897`；NO_PROXY 保留 localhost 及 bilibili/bilivideo/huya/163/douyin/douyu/yy 域，Twitch/SOOP 随进程代理。结果具有本次时效与路由范围，不外推为任意地区可用。
- 峰值 CPU 25.64%、重型进程工作集 14,581,583,872 B；结束活跃重型进程 0。

## Android 构建

成功门禁后执行 `tool/build_local_release.ps1 -Target AndroidArm64 -Configuration Debug -SkipQuality`，显式复用以上完整门禁，不重复依赖升级或清缓存。记录 `local-artifacts/build-records/20260910T100835463Z-build-androidarm64-debug.json`：10:03:20 UTC 开始，312.243 秒，Gradle assembleDebug 285.6 秒，workers 16。

增量目录原已存在，Gradle daemon/build cache/configuration cache/VFS 保持开启；本次日志没有观测到 FROM-CACHE/UP-TO-DATE 命中，configuration_cache_reused=false，不将“开启缓存”写成“已复用缓存”。峰值 CPU 66.01%、工作集 14,506,414,080 B，结束重型进程 0。Firebase 插件 KGP 迁移提示是构建警告，本次编译成功；后续 SDK/依赖迁移仍需独立验证。

| 项目 | 核验值 |
| --- | --- |
| 包名 | `com.mystyle.purelive` |
| 版本 | `3.1.8+4121`（非 3.2.0） |
| APK Manifest versionCode | `6121` = 基础 4121 + arm64 ABI 偏移 2000 |
| ABI / 类型 | 仅 `arm64-v8a` / Debug |
| 原生库 | 16 个；ELF LOAD 最小对齐 `0x4000`，APK 16 KB zipalign 核验通过 |
| 文件字节 | `288640934` |
| SHA-256 | `B33B83C8C96D44426711F229CDD79308C89E4D3D14B86A815E157DECDE782416` |
| 签名证书 SHA-256 | `1e832295a696cf8210bca063e458bad0be12dfa64939d3362ff11b8f237ff7b9` |

完整归档目录为本机忽略路径 `local-artifacts/candidates/android-48154d15/`，其中 APK 为 `PureLive-3.1.8-4121-android-arm64-v8a-debug.apk`。构建输出目录列出的旧 Windows ZIP/EXE 不是本轮生成物；本轮只构建上述 Android APK。

## 独立归档核验

记录 `local-artifacts/build-records/20260910T101321134Z-niconico-cumulative-apk-archive.json`：89.930 秒（含其他任务资源排队），完成后活跃重型进程 0。

- 再次执行 APK 内容核验并将哈希与成功构建记录匹配，确认干净源码、目标/变体和完整质量记录一致。
- apksigner 实际 **Verifies / v2=true / 单签名者**，证书与先前已归档 Debug APK 一致；这不是重新读取当前手机签名，安装前仍要复核现装包。
- ZIP 全条目 CRC 通过；归档内 zh/en 翻译与 version.json 字节逐一匹配源码。
- Debug kernel 中确认 `NiconicoSite`、`LiveCancellableSearch`、`LiveQualityDiscoveryScope`、`NiconicoPlaybackInput` 标记。它们只证明相关代码进入包，不证明实际播放/取消已在设备成立。
- APK 没有 `/test/fixtures/` 或 `localhost-key.pem` 条目；必需 Flutter/媒体/SQLite 资源与库由包门禁检查。
- 原 `152cf151` 候选继续保留，哈希仍为 `43BE5AEAF5AE0CA2A2C60DCE78EBDCA7F633501567453764096BCEC2436D26F5`。没有覆盖此回滚参考。

实际归档证据为候选目录 `archive-verification.json`、`asset-verification.json`、`signature.log`、`BUILD_METADATA.json`、`build-record.json` 和 `quality-record.json`；没有把包或含环境细节的原始日志上传到 Git。

## 原生缺口与下一步

1. `native-handoff-plan.json` 的 **78 个场景全部 not-run**，只是 candidate_verified/full_quality_gate_passed 变为 true；installed/native_verified/whole_release_gate_passed 仍为 false。此前未取得的前台窗口继续保持待确认，本轮未重复询问或切前台。
2. 后续若进入 Android 窗口，先重新核对 `-s` 指定设备的 25102RKBEC/myron、当前前台/录制状态、包签名与版本，建立一致的数据备份再覆盖安装；保留数据，禁止卸载清空或以重启救场。历史 ADB 在线与旧备份不代替当前前置检查。
3. 继续代码优先：针对 [#858 审查](ISSUE_AUDIT_2026_09_10.md) 的音量初始化迟到/房间归属/初始监听覆盖偏好线索先设计确定性复现，再决定业务修订；本轮只读链路并保留线索，未认定该 Issue 根因。
4. Windows 原生累计候选仍需更新；20 个直播站点 + IPTV 不等于全部参考平台接入，7 组参考平台未注册。历史 62 组的 42 组未闭环与本候选 78 个场景是不同统计口径，不相加、不换算总进度百分比。
5. Android/Windows 全界面、操作、实际长录、多路和资源趋势，以及所有目标平台的正式构建/签名/更新日志/发布验收仍属用户完整目标。此次本地 Debug 产物不触发 3.2.0 发布，不缩小完成条件。
