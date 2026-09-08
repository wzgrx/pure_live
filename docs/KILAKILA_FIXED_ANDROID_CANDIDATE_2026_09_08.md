# 克拉克拉修复后 Android 候选审计（2026-09-08）

## 结论与源码

干净源码 `ae5232b2840b78acc32dfe09da4372abd116abe8` 完成一次新的完整门禁、Android arm64 Debug 构建、内容/签名核验与独立归档；包含 [萌星目录修复](KILAKILA_RISING_STAR_AUDIT_2026_09_08.md) `8d5883f10272c9fcfba387c72cc37ef8e69cdbb5`。不是沿用旧候选的 2081 项结论。

候选状态 **pending-native-acceptance**，未安装、未发布。旧 `8ea62ac6` 的 `hold-known-kilakila-directory-bug` 继续作为历史记录保留；新包替代它成为本轮原生验收输入。版本仍 3.1.8+4121，未提前发布 3.2.0。

## 完整门禁

- 命令：`tool/build_local_release.ps1 -Target AndroidArm64 -Configuration Debug -FullRegression`。
- Flutter 3.47.0 / Dart 3.13，锁定依赖解析；一次完整 analyze 无诊断，371.7 秒。
- **2087/2087** 单元/Widget 测试通过，测试并发 12；其中包含新增的 6 个萌星目录合同测试。
- **42/42** 既有公开接口探针通过。克拉克拉实时萌星与取流证据另见上一批审计；本项不是 42 个平台或原生播放器验证。
- 仓库静态扫描 4295 已跟踪文件、2224 文本，0 errors / 2 warnings：已审查的公开 TLS 测试密钥和 empty-catch 清单仍保留。扫描不等于全仓语义审查。
- 质量记录 `20260908T025845757Z-quality-full.json`，1397.184 秒（含排队）；监控峰值 CPU 78.05%、15,706,517,504 B，结束活跃重型进程 0。

## 构建与归档

| 项 | 实测 |
| --- | --- |
| APK | `PureLive-3.1.8-4121-android-arm64-v8a-debug.apk` |
| 包名 | `com.mystyle.purelive` |
| 基础 build / Manifest code | 4121 / 6121 |
| ABI / ELF | arm64-v8a / 16 个库，LOAD 对齐至少 0x4000，APK 16 KB 对齐通过 |
| Flutter assets | 1262 |
| 字节数 | 288,134,508 |
| SHA-256 | `4B286F70C1EF7F6611C82AD1AE30D1F7746A1E13A8AB93282CF92A8A84870984` |
| 证书 SHA-256 | `1e832295a696cf8210bca063e458bad0be12dfa64939d3362ff11b8f237ff7b9` |

- 构建记录 `20260908T031128042Z-build-androidarm64-debug.json`：2127.643 秒，含完整门禁及资源排队；Gradle assembleDebug 465.6 秒。不是纯编译耗时，也不是后续工期保证。
- Gradle 16 workers，daemon/build/configuration cache 和增量目录保留。日志观察到 FROM-CACHE / UP-TO-DATE 均为 0，configuration cache 未复用；不把启用等同命中。
- 构建监控峰值 CPU 80.56%、15,282,565,120 B；结束检测到 3 个活跃重型进程，未停止其他任务。后续归档独立排队，最终记录活跃进程 0。
- FFmpeg 原生包校验通过；firebase_auth/firebase_core 的 KGP 未来兼容警告保留，没有顺带升级依赖或模块。
- 归档记录 `20260908T031417475Z-android-candidate-archive-ae5232b2.json`：108.317 秒，退出 0。重新验证新旧 APK 签名，同证书；这是与已归档 Debug 候选比较，未读取手机当前证书。
- APK 内逐值核对中文 `萌星推荐`、英文 `Rising stars` 及对应目录能力说明，并核验原有 CC、映客、外部打开等资源键。TLS 测试私钥未打包。
- 归档后 SHA 再核对一致；保留旧候选，没有覆盖旧归档。

本机固定产物：`P:\pure_live\local-artifacts\candidates\android-ae5232b2\PureLive-3.1.8-4121-android-arm64-v8a-debug.apk`。

## 验收边界与下一步

本轮没有 ADB、MT、Root、LSP、安装、前台输入或发布操作。无手机重启、卸载、清数据、模块更新或其他会话进程中断。覆盖安装保留数据仍是后续设备阶段要求，但先核对当前包、证书、版本及设备身份，按共享租约执行。

`native-handoff-plan.json` 已指向本包和修复后的萌星目录，15 组累计场景全部 not-run；包括 CC 目录、映客、YY、克拉克拉 FLV/HLS、收藏分享、续接和生命周期。原生 PASS 没有增量。Windows 最新 Debug 仍 `f3de664a`，本次只构建 Android。

历史账本 42 个大项待闭环、12 组参考平台未注册，二者不是 Bug 数或可以相加的总剩余量。当前源码仍为 15 个直播站点 + IPTV。下一步以固定候选完成原生验收；全目标和 3.2.0 发布继续，不用构建通过替代实机、长录与性能证据。

证据目录：`local-artifacts/kilakila-fixed-candidate-20260908/`，含 request、pipeline、归档脚本/日志、签名日志、9 个既有修复输入核对、待验收计划、终态 checkpoint 与 `validation-source.json`。完整质量/构建/归档记录和候选目录交叉引用。
