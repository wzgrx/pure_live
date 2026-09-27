# 搜索与共用页累计 Android 候选（2026-09-10）

## 结果

干净提交 `f5aab636bb581921ff1a5b76bbdc5b89999dea93` 的 Android arm64 Debug 已构建并独立归档，包含[搜索页修订](SEARCH_PAGE_LAYOUT_AUDIT_2026_09_10.md)与[共用页修订](BASE_PAGE_LAYOUT_AUDIT_2026_09_10.md)。尚未安装、执行本批真机验收或发布；版本保持 **3.1.8+4121**，不是 3.2.0 稳定版。Windows 仍为 2fb471d3，尚未包含两批 UI 修订及小红书接入。

构建前核对两批已通过的文件哈希：搜索三文件与共用页四文件均匹配最终验证记录。复用搜索 103/103、共用页联合 172/172 及对应严格分析，二者含重叠用例，不相加为独立覆盖总数；这不是完整发布门禁。

## 产物

| 项目 | 实际结果 |
| --- | --- |
| 包名 | com.mystyle.purelive |
| versionName / 基础 build / Manifest code | 3.1.8 / 4121 / 6121 |
| ABI / ELF | arm64-v8a；16 库，LOAD 最小 0x4000 |
| APK 对齐 | 16 KB 检查通过 |
| Flutter 资源 | 1,262 项，205,964,244 B |
| APK 大小 | 288,491,573 B |
| SHA-256 | `75216CA9C499794A15B7C314DAF43339B521A3E459BD08954929EFDF6FA31365` |
| 证书 SHA-256 | `1e832295a696cf8210bca063e458bad0be12dfa64939d3362ff11b8f237ff7b9` |
| 签名 | APK v2，单一 Android Debug 签名者 |

独立归档位于 `local-artifacts/candidates/android-f5aab636/`，含 APK、BUILD_METADATA、build-record、signature.log、archive-verification 与 native-handoff-plan。复制后 SHA 再次一致；前候选 d4adcb77 原件哈希保持。完整中英文翻译与版本 JSON 和源码比较一致，未打包测试 TLS 私钥或其夹具目录。没有将本地候选签名表述为正式发行签名。

## 手机与数据边界

本轮只读核对先确认 `25102RKBEC / myron`，操作显式指定 `-s 192.168.1.2:5555`。21:15 UTC 观察到前台为 `com.bilibili.app.in`，Pure Live 无 PID；没有接管前台或进行安装。

21:16 UTC 设备旧 APK SHA `D965095AC696FC98D000E89542835F98C8A0C30DA0DF54EF4089D19571762E8D` 与已验签备份相同，故新候选与当前旧 APK 的签名兼容有字节哈希链证据。主 IPTV DB 与设置 Hive 两文件哈希也与此前备份一致。

**本轮未重新取得完整状态快照。两个数据文件一致不代表所有应用数据未变化。** [上一轮备份](XIAOHONGSHU_ANDROID_CANDIDATE_2026_09_10.md)的 227 文件、9 数据库和本机 schema 6→7 演练仅作为历史证据。安装前再次核对当前状态，取得一致且经校验的状态备份。保留数据同签名覆盖安装；不卸载、不清数据。数据库回退需对应旧快照，单独回退 APK 不等于回退数据库。

保持用户要求：不重启手机/adbd，不切换 Wi-Fi、调试端口或授权，不更新 Root/LSP/模块，不执行全局 ADB 重置。LSP/MT 本轮未用于修改；构建来自项目源码，不需要 APK 二次补丁。

## 验收计划修正

新清单仅继承旧清单实际的 51 项场景及有效约束，再增加 6 项：搜索布局状态、搜索能力动作、分页筛选排序、共用页提示、状态页实际刷新、页面尺寸与生命周期。**57 项 ID 唯一，全部 not-run**；序列化后复核计数与当前 APK 哈希。

复查发现旧 d4adcb77 清单虽有 51 项数组，但 `scenario_count` 残留 38，且 `apk_sha256`、`archive_verification` 仍指向更旧候选，另有正确但重复的 SHA/路径字段。旧审计所称“以真实数组计数重建”未落实所有顶层字段。此次按白名单重新生成 schema_version=2 清单，只保留一套当前源码、APK、SHA 和核验路径，避免继续复制陈旧字段；历史归档保留原样用于追溯。

Windows 窄分页栏的实际鼠标、字号与键盘验收另列待验，不计入 Android 场景。57 场景与宏观矩阵重叠，既不是 57 个缺陷，也不与 42 大组相加。

## 资源与剩余

- 构建记录 `20260909T211641846Z-build-androidarm64-debug.json`：134.5 秒，峰值 CPU 64.09%，工作集 11,141,505,024 B，结束活跃重型进程 0。
- 归档记录 `20260909T212011277Z-android-archive-f5aab636.json`：8.926 秒，峰值 CPU 3.3%，工作集 9,745,227,776 B，结束活跃重型进程 0。
- 两阶段串行使用资源守卫、保留缓存。配置启用不等于实际命中；本次未观察到配置缓存复用或 FROM-CACHE/UP-TO-DATE。Firebase 插件 Kotlin 兼容性提示不是本次构建失败，也未触发依赖更新。
- 只读设备证据根：`local-artifacts/shared-ui-android-candidate-20260910/`；包含型号、前台和哈希对账。

宏观仍为 **20 PASS / 32 RUN / 10 NR，42 组未闭环**；19 个直播站点 + IPTV，8 组参考平台尚未注册。下一步是在明确的 Pure Live 设备窗口内，依共享设备包装器与 NoRotation 进行备份、覆盖安装和原生验收；其余代码审查、Windows 及平台能力验证继续按独立证据推进。当前证据不足以给出整个 3.2.0 的可靠完成日期。
