# Android 外部分享接收与文件导入审计（2026-09-13）

## 结论

本批把 Android `ACTION_SEND` 冷启动口令、运行中口令、播放列表附件，以及
`ACTION_SEND_MULTIPLE` 的播放列表+EPG 接入同一串行处理链，并完成 REDMI K90 Pro Max 原生闭环。
产品提交依次为：

- `269caa91656c615e7dbbda41840bb9bbdb44307a`：消费初始分享、监听运行中分享，按口令/播放列表/EPG
  分类，限定 Manifest MIME，并用应用自有 Navigator 等待 Splash 结束后显示导入弹窗；
- `63417d9bec9aa9e2567eb4b3d4308182798e9831`：移除 `AlertDialog` 内参与 intrinsic 计算的
  `LayoutBuilder`，保留窄屏和大字号堆叠；
- `292d3c83311cfe3a40140bf461acaf3342e72e55`：收到 `content://` 附件时，在临时授权有效期内复制到
  应用缓存，再把可读物理路径交给 Dart 导入器，适配 Android scoped storage；
- `9c92fb7e27659f09e1b3de5d5b745b30ff59fe2a`：缓存副本保留安全化后的原附件名，IPTV/EPG 导入结束后
  清理插件拥有的唯一暂存目录，并把原文件名和暂存清理加入原生门禁；
- `a180776c0decc4d3a6d01c7c3ff18fd888022fe4`：根据首轮严格门禁的红证据，把清理根目录从
  `Directory.systemTemp` 修正为 `path_provider` 返回的应用临时目录；
- `8f43f21be4f726c81ad2f87ad49e64b379cf0f9c`：分享入口在 `finally` 中释放每个插件附件，覆盖
  口令优先、不支持的扩展、前一个导入异常和后续附件尚未执行等路径；释放单项失败只记录错误并继续
  处理其余附件；
- `98f5472aab1d5820b3fb11da73043054263677ba`：每个 URI 独立收口 Provider/路径异常，失败项不再
  中断 `ACTION_SEND_MULTIPLE` 后续附件；显示名先清洗控制字符，再按 UTF-8 字节而非 UTF-16 长度
  限制到 180 字节，扩展名单独限制为 24 字节，截断不拆分 Unicode code point。

最终 arm64 Debug 在同签名覆盖安装后完成冷启动口令、运行中不同口令、运行中重复口令抑制，以及
M3U 内容 URI 导入。另用“最后处理的 warm 口令 + M3U 附件”验证口令优先路径：没有重开弹窗、没有
导入夹具频道、插件暂存树为空；随后单独分享同一附件才入库。最终 SQLite 快照中恰有一个夹具频道及其
唯一 Provider，Provider 名称与发送方原文件名一致；插件拥有的 `cache/share_handler` 暂存树已删除。
Debug 专用 shell 探针再发送真实 `ArrayList<Uri>`：M3U Provider/频道与 XMLTV 来源/频道/节目各精确一条，
两个来源都保留原附件名，暂存树仍为空；探针只在 Debug Manifest 注册并要求系统 `DUMP` 权限。
追加的非导出 Debug ContentProvider 又在同一个 `ACTION_SEND_MULTIPLE` 中依次注入类型异常、查询异常和
超长中文/emoji/控制字符显示名：异常项没有抑制后续两份 M3U，查询异常项按 URI 文件名入库，超长名
清洗后 basename 为 175 个 UTF-8 字节、末尾 emoji 完整，两份频道各精确一条，暂存树为空。随后完整
IPTV 缓存树和 Hive 都按备份恢复。除探针预期的 Provider 异常日志外，没有 FATAL/ANR、Flutter
渲染/Widget 异常或导入失败，应用停止，桌面和 stay-awake 恢复。

同源码的 R8/资源收缩 Release 测试包随后也完成保留数据覆盖：冷/热/重复口令、混合附件释放、单 M3U、
探针排除、APK 哈希与精确恢复全部通过。独立系统包 DocumentsUI 又在真实 UI 中选择 M3U+XMLTV，经过
系统分享面板把 `ACTION_SEND_MULTIPLE` 交给 Pure Live；两份 ExternalStorageProvider 内容 URI 都明确
授权给目标包，播放列表与 EPG 数据各精确入库一次，17/17 检查通过。该证据补充 A1-05/A2-01 的
Android 外部接收路径并关闭“真实外部应用发送方”缺口；Windows 原生剪贴板导入和最终正式签名候选继续
执行，因此两组保持 `RUN`。宏观仍为 **20 PASS / 40 RUN / 2 NR，共 42 组未闭环**。本批 Windows
Computer Use 与 Astra Light 使用均为 **0 次**。

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
7. 混合分享门禁首轮在 cold→warm 后错误复用了较早的 cold 口令，它不属于“最后一条重复口令”，因此
   产品按设计再次显示弹窗。失败证据：
   `local-artifacts/diagnostics/android-share-intake-20260913T070033478/summary.json`。工具提交
   `2ad872e2` 改用刚处理的 warm 口令后，才精确验证重复口令优先路径的附件释放。
8. Provider 边界门禁首轮已经执行类型异常、复制失败和查询异常，但日志断言等待了未触发的外层兜底
   文案；Android `ContentResolver` 会记录并吞掉 Provider 的 `getType` 异常，随后实际落入复制失败路径。
   失败摘要 `local-artifacts/diagnostics/android-share-intake-20260913T074432554/summary.json` 保留该差异，
   `ed126884` 按真实三段日志修正证据门禁。
9. 第二轮已经把异常后的两份有效附件写入数据库，Windows 控制台却以 GBK 输出含 emoji 的
   `ensure_ascii=False` JSON，取证脚本得到 `UnicodeEncodeError`。失败摘要
   `local-artifacts/diagnostics/android-share-intake-20260913T074806139/summary.json` 和数据库快照都保留；
   离线转义查询确认两行存在，`d563a0bf` 将该段证据固定为 ASCII 转义 JSON 后完整重跑转绿。

所有失败轮次都在摘要中保持 `failed`，没有记作通过。每轮原生脚本的 `finally` 均停止应用、恢复
IPTV/Hive 并回到桌面。

## 产品修订

- `SharedMediaReceiver` 先订阅运行中 stream，再读取并消费初始值；初始值处理后 reset，重复 start
  复用同一任务，stream/read/reset 的错误分别收口。
- `SharedMediaIntake` 将口令、`.m3u/.m3u8/.txt` 和 `.xml/.gz/.json` 附件串行处理；路径去重，口令优先，
  不支持的输入只发一次本地化反馈；所有插件附件最终都进入逐项释放，即使口令优先、扩展不支持或
  前一个导入异常也不会跳过尚未执行的缓存副本。
- 直接分享口令与剪贴板口令共用 `ShareCommandHandler.acceptCommandText` 的验证、排队、消费者成功后
  提交和生命周期重复抑制。
- 应用自有 `GlobalKey<NavigatorState>` 传给 `GetMaterialApp`；冷启动处理最多等待 8 秒，并明确等到
  当前路由不再是 Splash 才呈现弹窗。
- Android 入口只宣告实际支持的文本、M3U、XML、JSON、GZip 和二进制 MIME；动态分享目标使用真实
  `com.mystyle.purelive.MainActivity`。
- Android 插件保留可读的应用内 `file://`；其余 URI 查询显示名，安全化 basename 后复制到
  `cache/share_handler/<uuid>/<原文件名>`。复制失败删除未完成文件及其目录；Dart 导入结束后仅清理
  这个三层结构，不触碰外部输入或结构不明的临时文件。每个 URI 单独收口异常并递归清理自己的 UUID
  目录；文件名以 180 个 UTF-8 字节为上限、扩展名以 24 字节为上限，控制字符替换为 `_`，逐 code
  point 截断以保留完整 emoji/代理对。
- Debug 构建增加受 `android.permission.DUMP` 保护的 `ShareIntentProbeReceiver`；它只接受应用
  `cache/share_probe` 下 1～8 个规范文件，构造真实 `ACTION_SEND_MULTIPLE`/`ArrayList<Uri>` 后显式
  发送给 MainActivity。非导出的 `ShareIntentProbeProvider` 只服务同应用 Debug 探针，可注入类型/查询
  异常和超长显示名，文件访问仍以规范路径限制在同一探针缓存根。主 Manifest 没有这两个组件；Release
  产物是否排除它们仍由后续 Release Manifest 门禁复验。
- 导入弹窗不再嵌套 intrinsic 不兼容的 `LayoutBuilder`；改用 MediaQuery 的可用宽度和字号选择堆叠，
  继续使用可滚动 AlertDialog 与固定最小操作面。

## 确定性验证

| 项目 | 结果 |
| --- | --- |
| 分享接收、附件释放、Debug Provider 与 Manifest/插件源码合同 | `test/shared_media_intake_test.dart` 11/11 |
| 插件暂存目录所有权与平台临时路径清理 | `test/shared_media_temp_cleanup_test.dart` 5/5 |
| 导入弹窗 320×480、3.0 倍英文 | `test/share_command_import_dialog_test.dart` 1/1 |
| 分享入口与两个导入管理器联合复验 | **110/110 PASS** |
| 最终路径修订直接复验 | **15/15 PASS** |
| 分享处理器最终直接复验 | 26/26 PASS（前一产品批） |
| 相邻七文件 | 129/129 PASS（前一产品批） |
| PowerShell 原生工具静态合同 | PASS；ADB 入口全部显式 `-s`，禁用操作与恢复门禁通过 |
| DocumentsUI 外部发送工具静态合同 | PASS；独立 UID、语义选取、URI 授权、SQLite 与精确清理门禁通过 |
| Built-in Kotlin 审计 | 10 个 Gradle 文件通过 |
| 全库 Flutter analyze | `No issues found` |

边界修订 `98f5472a` 后直接重跑 11/11 与 Built-in Kotlin 审计；随后 `c6817e74` 加入 Debug Provider
和门禁，再次通过同一 11/11、PowerShell 静态合同与 Kotlin 审计。上表 110/110、15/15 和全库 analyze
来自此前产品批的已记录输入；本次没有把它们写成新提交的重复执行结果，新增产品行为以精确构建和下方
K90 数据库/日志证据闭环。

`tool/android_share_intake_smoke.ps1` 已加入固定 CI 静态门禁。它要求显式 serial、APK 和期望 SHA，
并要求显式选择 Debug/Release，避免用错误的探针预期验收另一种构建；
覆盖安装前备份规范 Hive 与整个 IPTV 缓存树；混合口令/附件要求不重开弹窗、不写入夹具频道且整个
插件暂存树消失。文件单独导入后再次要求暂存树消失；随后 Debug shell 探针发送 M3U+XMLTV 的真实
Parcelable URI 列表，并从关闭状态 SQLite 查询两类来源、频道和节目。Provider 边界阶段再发送
“类型异常 + 查询异常 + 超长显示名”三 URI 列表，以日志证明异常路径实际到达，并用关闭状态 SQLite
证明两个后续附件各入库一次、回退名准确、控制字符已清洗且长名加扩展不超过 180 UTF-8 字节。最后
恢复数据树并逐文件核对 uid/gid/mode/size/SHA，同时删除受路径守卫保护的探针输入目录。
Release 模式复用全部公共步骤，但不调用 Debug 探针，并从安装后的 package dump 确认
`ShareIntentProbeReceiver`、`ShareIntentProbeProvider`、`RecorderLifecycleProbeReceiver` 均不存在。

`tool/android_documentsui_share_smoke.ps1` 把真实外部发送方单独固化：只接受显式 Release、serial、APK
路径和 SHA；先核对设备身份及 DocumentsUI/Pure Live 的独立包名、UID，再精确备份 Hive 与完整 IPTV
树。工具在唯一 Download 目录写入并核对两份夹具，通过 DocumentsUI 语义节点长按/点按达到“已选择
2 项”，点击其真实分享动作，在系统 chooser 中按应用标签选择 Pure Live。目标启动后同时要求 chooser
来源、`ACTION_SEND_MULTIPLE`、两份 `com.android.externalstorage.documents` URI 对目标包的 read grant、
暂存清空和关闭状态 SQLite 数据成立；finally 仅删除两个精确文件，再以受保护前缀执行非递归 `rmdir`，
随后逐文件恢复并核对用户数据。

## 构建与 K90 原生结果

构建命令：
`tool/build_local_release.ps1 -Target AndroidArm64 -Configuration Debug -SkipQuality`。

| 项目 | 结果 |
| --- | --- |
| 精确构建提交 | `c6817e749aefc55d69fcb726cfaf446ec0746170`（产品修订 `98f5472a`，Debug Provider/探针 `c6817e74`） |
| 版本 / manifest code | `3.1.8+4121` / `6121` |
| APK | `288823157` B |
| SHA-256 | `55F94C97419C5A61ADC5D66FDBFEE4C1622071763A5CDB1040BDA718CB41F2B3` |
| ABI / 原生库 | `arm64-v8a` / 16；最小 ELF LOAD `0x4000` |
| Flutter 资源 | 1262 项 / `206833496` B |
| 构建记录 | `local-artifacts/build-records/20260912T234345813Z-build-androidarm64-debug.json` |

同源码当前文档提交 `52e25b82d35a7b363b545e59a1a648250c34c428` 另生成 R8/资源收缩 Release
测试包；本机没有 `android/key.properties`，因此构建器明确使用 Android Debug 证书并在文件名标注
`debug-signed`，它不是最终正式签名发布件。

| Release 测试包项目 | 结果 |
| --- | --- |
| APK | `127835744` B，`PureLive-3.1.8-4121-debug-signed-android-arm64-v8a-release.apk` |
| SHA-256 | `4BF855719631665EBE88B368CB64E2359AB72788D600D9E477E5416FD81E6B82` |
| ABI / 原生库 | `arm64-v8a` / 16；最小 ELF LOAD `0x4000` |
| Flutter 资源 | 1259 项 / `15543712` B |
| 证书 | Android Debug；SHA-256 `1E832295A696CF8210BCA063E458BAD0BE12DFA64939D3362FF11B8F237FF7B9`，与已装 Debug 候选一致 |
| APK Manifest | MainActivity、SEND、SEND_MULTIPLE 存在；三个项目 Debug 探针组件计数 0 |
| 构建记录 | `local-artifacts/build-records/20260913T000101263Z-build-androidarm64-release.json` |

最终原生摘要：
`local-artifacts/diagnostics/android-share-intake-20260913T075039675/summary.json`。

- 设备先核对为 `25102RKBEC / myron / uid=0(root)`，全部设备命令显式绑定
  `192.168.1.2:5555`。
- `install -r -t` 返回 `Success`，`firstInstallTime` 保持 `2026-07-21 18:07:53`，设备
  `base.apk` 与候选 SHA 完全一致；覆盖安装前后 Hive 和 IPTV 树不变。
- 冷启动分享的 `LaunchState` 为 `COLD`；Splash 后显示“分享”、`bilibili`、room ID `27632810`、
  “取消”和“进入房间”。两个按钮分别为 `150×144`、`302×144`，完全位于 1200×2608 屏幕。
- 运行中第二条不同口令显示 room ID `27632811`；弹窗活动期间再发送同一口令，取消后没有二次弹窗，
  证明 warm stream 和串行重复抑制都生效。
- 随后把刚处理的 warm 口令与 M3U 内容 URI 放进同一 Intent：弹窗没有重开，
  `sharedStagingEntriesAfterCommand=[]`，关闭状态 SQLite 中夹具频道计数为 0，证明口令优先分支释放附件
  而没有误导入；摘要门禁 `commandPriorityAttachmentReleased=true`。
- M3U 通过应用 FileProvider 的内容 URI 进入插件；SQLite 快照中频道
  `Share Intake Fixture 26091307503968` 与唯一 Provider ID 对齐，Provider 名称精确等于发送方原文件名
  `purelive-share-intake-26091307503968`，流地址精确匹配夹具；导入完成后的
  `sharedStagingFilesAfterImport` 和 `sharedStagingEntriesAfterImport` 均为空。
- `ShareIntentProbeReceiver` 返回 `result=-1, data="ok:send_multiple:2"`；多附件 SQLite 快照中
  `Share Multiple Playlist 26091307503968`、`Share Multiple EPG 26091307503968` 和
  `Share Multiple Programme 26091307503968` 各一条，Provider/EPG 来源名称分别等于两份原附件
  basename，`multiplePlaylistAndEpgAttachmentsImported=true`，暂存树为空。
- `ShareIntentProbeReceiver` 的 Provider 边界动作返回 `result=-1, data="ok:provider_edges:3"`。日志同时
  命中注入的类型异常、复制失败和查询异常；后续频道 `Share Provider Fallback 26091307503968` 与
  `Share Provider Long Name 26091307503968` 各一条。前者 Provider 名精确回退到 URI basename；后者
  从包含中文、emoji、控制字符且超过文件系统单分量预算的显示名得到
  `共享_附件_长😀…长😀`，UTF-8 为 175 字节，控制字符和替换字符都不存在，末尾 emoji 完整；加
  `.m3u` 后为 179 字节。`providerFailureDidNotSuppressLaterAttachments`、
  `queryFailureUsedUriFilename` 和 `longUnicodeDisplayNameSanitizedAndBounded` 全为 true。
- 原生 smoke 的 IPTV 缓存树恢复前后元数据和每文件 SHA 完全一致，数据库回到原 SHA
  `FD2A61D0...095D5`；规范 Hive 精确恢复到本轮起始 SHA
  `91D6BAC5FDC7D43C6709D42D3FF4C56E9732649C3551FFA8317AC1DAD7F6128F`，uid/gid/mode 和 SELinux
  context 保持。
- 结束时 Pure Live 已停止，顶层为 `com.miui.home`，stay-awake 为 0；未重启手机/adbd、未切换网络、
  未改 ADB 端口/授权，也未更新 Root/LSP/模块。

Release 模式原生摘要：
`local-artifacts/diagnostics/android-share-intake-20260913T080423059/summary.json`。

- 同证书 `install -r -t` 返回 `Success`，首次安装时间仍为 `2026-07-21 18:07:53`，设备 `base.apk`
  与 Release 测试包 SHA 精确一致；覆盖安装没有改变 Hive 或 IPTV 树。
- R8/资源收缩包完成冷启动口令、运行中口令、重复抑制、重复口令+附件释放和单 M3U 导入；夹具 Provider/
  频道各一条，暂存文件与目录都为空，进程日志无 FATAL/ANR 或导入失败。
- 安装后的 package dump 不含三个项目 Debug 探针，`releaseDebugProbesExcluded=true`；该轮不借用 Debug
  Provider 声称 Release 多附件边界结果，多附件/异常矩阵仍以上述精确 Debug 包为证据。
- 13 项 Release 模式检查全为 true；IPTV 树逐文件恢复，Hive 回到 `91D6BAC5…6128F`，应用停止，
  顶层 `com.miui.home`，stay-awake 恢复为 0。

真实 DocumentsUI 外部发送摘要：
`local-artifacts/diagnostics/android-documentsui-share-20260913T083103384/summary.json`。

- 最终工具提交为 `0876d27ec59382e822f29412c59d4e3dbcf3abe5`，继续绑定上述精确 Release
  测试包与 SHA；覆盖安装返回 `Success`，`firstInstallTime` 保持 `2026-07-21 18:07:53`，设备
  `base.apk` 哈希精确匹配，三个 Debug 探针仍不存在。
- 发送方 `com.google.android.documentsui` / UID 10096 与目标 `com.mystyle.purelive` / UID 10946
  独立。UI 层级先显示唯一外部目录和两份文件，再依次出现“已选择 1 项”“已选择 2 项”；分享动作
  `com.google.android.documentsui:id/action_menu_share` 可点击。
- `com.android.intentresolver/.ChooserActivity` 的 activity 记录明确
  `launchedFromPackage=com.google.android.documentsui`，系统面板内“纯粹直播”目标可点击；随后目标
  前台保持存活。
- `dumpsys activity permissions` 分别记录两份
  `content://com.android.externalstorage.documents/document/...` URI 的
  `sourcePkg=com.android.externalstorage targetPkg=com.mystyle.purelive` read grant；系统日志明确记录
  `android.intent.action.SEND_MULTIPLE`。MIUI chooser 的预览进程曾记录自己的元数据预览权限警告，
  但目标授权、读取和入库均成立，该观察不属于 Pure Live 导入失败。
- 关闭应用后 SQLite 中 Provider `documentsui-playlist-26091308310340`、频道
  `DocumentsUI Playlist 26091308310340`、EPG 来源 `documentsui-epg-26091308310340`、EPG 频道与节目
  各精确一条，来源名保留外部文件 basename；插件暂存树为空，目标进程没有 FATAL/ANR 或导入失败。
- 17 项检查全为 true；外部两个夹具文件和唯一目录精确删除，IPTV 树元数据/逐文件 SHA 与 Hive
  `91D6BAC5…6128F` 均恢复，应用停止、顶层 `com.miui.home`、stay-awake 回到 0。测试未停止或更新 MT，
  未改 ADB/网络/Root/LSP 状态。

原生工具在 `2cc1b56d` 加入混合分享门禁，`2ad872e2` 修正最后一条重复口令夹具；`d2f7400c` 增加
Debug-only 多附件发送器，`944338e4` 增加 M3U+EPG 数据库和暂存清理门禁；`c6817e74` 增加异常
Provider/长名注入，`ed126884` 按 Android 实际异常传播修正日志门禁，`d563a0bf` 固定 emoji JSON
取证编码，`7f1df73e` 增加显式 Release 模式和安装后探针排除检查。`91498e22` 新增 DocumentsUI
真实外部发送工具，`0876d27e` 把两份 URI grant 分别绑定到目标包。最终 Debug 原生轮次使用
`d563a0bf` 工具绑定 `c6817e74` 精确 APK；公共 Release 轮次使用 `7f1df73e`，外部发送轮次使用
`0876d27e`，二者均绑定 `52e25b82` 构建的精确测试包。
