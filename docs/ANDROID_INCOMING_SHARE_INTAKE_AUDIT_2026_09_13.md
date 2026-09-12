# Android 外部分享接收与文件导入审计（2026-09-13）

## 结论

本批把 Android `ACTION_SEND` 冷启动口令、运行中口令和播放列表附件接入同一串行处理链，并完成
REDMI K90 Pro Max 原生闭环。产品提交依次为：

- `269caa91656c615e7dbbda41840bb9bbdb44307a`：消费初始分享、监听运行中分享，按口令/播放列表/EPG
  分类，限定 Manifest MIME，并用应用自有 Navigator 等待 Splash 结束后显示导入弹窗；
- `63417d9bec9aa9e2567eb4b3d4308182798e9831`：移除 `AlertDialog` 内参与 intrinsic 计算的
  `LayoutBuilder`，保留窄屏和大字号堆叠；
- `292d3c83311cfe3a40140bf461acaf3342e72e55`：收到 `content://` 附件时，在临时授权有效期内复制到
  应用缓存，再把可读物理路径交给 Dart 导入器，适配 Android scoped storage；
- `9c92fb7e27659f09e1b3de5d5b745b30ff59fe2a`：缓存副本保留安全化后的原附件名，IPTV/EPG 导入结束后
  清理插件拥有的唯一暂存目录，并把原文件名和暂存清理加入原生门禁；
- `a180776c0decc4d3a6d01c7c3ff18fd888022fe4`：根据首轮严格门禁的红证据，把清理根目录从
  `Directory.systemTemp` 修正为 `path_provider` 返回的应用临时目录。

最终 arm64 Debug 在同签名覆盖安装后完成冷启动口令、运行中不同口令、运行中重复口令抑制，以及
M3U 内容 URI 导入。导入后的 SQLite 快照中恰有一个夹具频道及其唯一 Provider，Provider 名称与发送方
原文件名一致；插件拥有的 `cache/share_handler` 暂存文件已清空。随后完整 IPTV 缓存树和 Hive 都按备份
恢复。进程日志没有 FATAL/ANR、Flutter 渲染/Widget 异常或分享/导入错误，应用停止，桌面和
stay-awake 恢复。

该证据补充 A1-05/A2-01 的 Android 外部接收路径；Windows 原生剪贴板导入、两个真实应用之间的发送、
EPG 多附件、Release 和异常 Provider 继续执行，因此两组保持 `RUN`。宏观仍为 **20 PASS / 40 RUN /
2 NR，共 42 组未闭环**。本批 Windows Computer Use 与 Astra Light 使用均为 **0 次**。

## 原始缺口与真实失败证据

1. `MyApp.initSharedMediaListener` 读取 `getInitialSharedMedia()` 后丢弃结果，冷启动分享不会进入业务层；
   文件附件又只检查 `media.content`，忽略 Android 插件写入的 `attachments`。
2. 旧 Manifest 以 `*/*` 宣告接收全部类型，动态分享目标仍含示例包名，占用系统分享目标但不能准确
   表达应用实际支持范围。
3. 修订前精确候选接收有效 `text/plain` 口令后进入应用首页，但导入弹窗不可见。红证据：
   `local-artifacts/diagnostics/android-share-intake-red-20260913T0510/`。
4. 第一份接通口令的候选在 K90 上确实进入弹窗构建，但原生日志复现
   `LayoutBuilder does not support returning intrinsic dimensions`，屏幕只剩错误遮罩；证据：
   `local-artifacts/diagnostics/android-share-intake-investigation-20260913T0550/`。
5. Android 17 上把 `/sdcard/Download/...m3u` 物理路径直接交给应用会得到 `EACCES`。即使是
   `content://`，先解析成外部路径也会丢失发送方临时授权；因此插件改为直接从 ContentResolver 流
   复制，而不是依赖外部物理路径。
6. 保留原文件名和暂存清理的首个候选已正确入库，但严格门禁发现
   `cache/share_handler/<uuid>/<原文件名>` 仍存在。红证据：
   `local-artifacts/diagnostics/android-share-intake-20260913T063431728/summary.json`。根因是
   `Directory.systemTemp` 没有解析到 Android 应用缓存根；改用 `getTemporaryDirectory()` 后同一门禁转绿。

所有失败轮次都在摘要中保持 `failed`，没有记作通过。每轮原生脚本的 `finally` 均停止应用、恢复
IPTV/Hive 并回到桌面。

## 产品修订

- `SharedMediaReceiver` 先订阅运行中 stream，再读取并消费初始值；初始值处理后 reset，重复 start
  复用同一任务，stream/read/reset 的错误分别收口。
- `SharedMediaIntake` 将口令、`.m3u/.m3u8/.txt` 和 `.xml/.gz/.json` 附件串行处理；路径去重，口令优先，
  不支持的输入只发一次本地化反馈。
- 直接分享口令与剪贴板口令共用 `ShareCommandHandler.acceptCommandText` 的验证、排队、消费者成功后
  提交和生命周期重复抑制。
- 应用自有 `GlobalKey<NavigatorState>` 传给 `GetMaterialApp`；冷启动处理最多等待 8 秒，并明确等到
  当前路由不再是 Splash 才呈现弹窗。
- Android 入口只宣告实际支持的文本、M3U、XML、JSON、GZip 和二进制 MIME；动态分享目标使用真实
  `com.mystyle.purelive.MainActivity`。
- Android 插件保留可读的应用内 `file://`；其余 URI 查询显示名，安全化 basename 后复制到
  `cache/share_handler/<uuid>/<原文件名>`。复制失败删除未完成文件及其目录；Dart 导入结束后仅清理
  这个三层结构，不触碰外部输入或结构不明的临时文件。
- 导入弹窗不再嵌套 intrinsic 不兼容的 `LayoutBuilder`；改用 MediaQuery 的可用宽度和字号选择堆叠，
  继续使用可滚动 AlertDialog 与固定最小操作面。

## 确定性验证

| 项目 | 结果 |
| --- | --- |
| 分享接收与 Manifest/插件源码合同 | `test/shared_media_intake_test.dart` 10/10 |
| 插件暂存目录所有权与平台临时路径清理 | `test/shared_media_temp_cleanup_test.dart` 5/5 |
| 导入弹窗 320×480、3.0 倍英文 | `test/share_command_import_dialog_test.dart` 1/1 |
| 首批五文件联合复验 | **109/109 PASS** |
| 最终路径修订直接复验 | **15/15 PASS** |
| 分享处理器最终直接复验 | 26/26 PASS（前一产品批） |
| 相邻七文件 | 129/129 PASS（前一产品批） |
| PowerShell 原生工具静态合同 | PASS；ADB 入口全部显式 `-s`，禁用操作与恢复门禁通过 |
| Built-in Kotlin 审计 | 10 个 Gradle 文件通过 |
| 全库 Flutter analyze | `No issues found` |

`tool/android_share_intake_smoke.ps1` 已加入固定 CI 静态门禁。它要求显式 serial、APK 和期望 SHA，
覆盖安装前备份规范 Hive 与整个 IPTV 缓存树；文件导入后要求插件暂存目录没有残留，拉取关闭状态的
SQLite 快照并用独立 Python sqlite3 查询夹具及原文件名 Provider，最后恢复数据树并逐文件核对
uid/gid/mode/size/SHA。

## 构建与 K90 原生结果

构建命令：
`tool/build_local_release.ps1 -Target AndroidArm64 -Configuration Debug -SkipQuality`。

| 项目 | 结果 |
| --- | --- |
| 精确产品提交 | `a180776c0decc4d3a6d01c7c3ff18fd888022fe4` |
| 版本 / manifest code | `3.1.8+4121` / `6121` |
| APK | `288819570` B |
| SHA-256 | `5B9A2D261124003C2AC7FD4FBFADD2E7C8EEC0506E3F00CEE7EFD005C7199B19` |
| ABI / 原生库 | `arm64-v8a` / 16；最小 ELF LOAD `0x4000` |
| Flutter 资源 | 1262 项 / `206831944` B |
| 构建记录 | `local-artifacts/build-records/20260912T224205532Z-build-androidarm64-debug.json` |

最终原生摘要：
`local-artifacts/diagnostics/android-share-intake-20260913T064232160/summary.json`。

- 设备先核对为 `25102RKBEC / myron / uid=0(root)`，全部设备命令显式绑定
  `192.168.1.2:5555`。
- `install -r -t` 返回 `Success`，`firstInstallTime` 保持 `2026-07-21 18:07:53`，设备
  `base.apk` 与候选 SHA 完全一致；覆盖安装前后 Hive 和 IPTV 树不变。
- 冷启动分享的 `LaunchState` 为 `COLD`；Splash 后显示“分享”、`bilibili`、room ID `27632810`、
  “取消”和“进入房间”。两个按钮分别为 `150×144`、`302×144`，完全位于 1200×2608 屏幕。
- 运行中第二条不同口令显示 room ID `27632811`；弹窗活动期间再发送同一口令，取消后没有二次弹窗，
  证明 warm stream 和串行重复抑制都生效。
- M3U 通过应用 FileProvider 的内容 URI 进入插件；SQLite 快照中频道
  `Share Intake Fixture 26091306423216` 与唯一 Provider ID 对齐，Provider 名称精确等于发送方原文件名
  `purelive-share-intake-26091306423216`，流地址精确匹配夹具；导入完成后的
  `sharedStagingFilesAfterImport` 为空。
- 原生 smoke 的 IPTV 缓存树恢复前后元数据和每文件 SHA 完全一致，数据库回到原 SHA
  `FD2A61D0...095D5`；该轮 Hive 也从 `19B6A903...F6333` 精确恢复。
- 全批收尾又使用首轮操作前备份把规范 Hive 恢复到本轮起始 SHA
  `91D6BAC5FDC7D43C6709D42D3FF4C56E9732649C3551FFA8317AC1DAD7F6128F`；uid/gid/mode 和 SELinux
  context 保持。记录：
  `local-artifacts/diagnostics/android-share-intake-final-state-20260913T0618.json`。
- 结束时 Pure Live 已停止，顶层为 `com.miui.home`，stay-awake 为 0；未重启手机/adbd、未切换网络、
  未改 ADB 端口/授权，也未更新 Root/LSP/模块。

原生工具识别/夹具/证据查询修订截至 `0e5ccd779aabbb394d15abf0b7820358c9667609`；随后
`9c92fb7e` 与 `a180776c` 的产品及门禁修订共同构成上述最终 APK。
