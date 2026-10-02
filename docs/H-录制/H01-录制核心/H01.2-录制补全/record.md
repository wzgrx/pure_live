# H01.2 录制补全

- 日期：2026-10-01
- 范围：H01.1（`docs/H-录制/H01-录制核心/H01.1-录制内核/record.md`）“审查发现的 v3 问题”第 4 条（HLS 预取没搬）和“留给后续”、H02.1（`docs/H-录制/H02-录制中心/H02.1-录制中心与录制设置/record.md`）“留给后续”、`~/ref/notes/m13_notes.md` 的 “From H02.1 recording”。
- 改动：`packages/live_record`（`chat.dart` 新、`input.dart`）、`packages/live_media`（`relay/hls_window.dart` 新，`hls_relay.dart`、`loopback_relay.dart` 只加可选参数）、`packages/live_store`（录制设置 19 项、`LegacyMigration.adoptLegacyValues`、`MetaStore.forgetLegacyValues`，都是添加）、`apps/pure_live`（`lib/app/recording.dart`、`lib/app/bootstrap.dart` 一处、`lib/platform/recording_platform.dart`、`lib/platform/plugins.dart`、`pages/recorder/`、`pages/record_settings/`、翻译、`android/` 的 `RecorderForegroundService.kt`）、根 `pubspec.yaml` 的 `ffmpeg_kit_extended_config`、`.gitignore`、`tools/ffmpeg_kit/`（新）、`tools/gate/gate.sh` 一步。
- 没动：`apps/pure_live/lib/features/live_play/`；直播间“录制”按钮用的接口（`recordingProvider`、`available`、`taskFor`、`addTask`、`startTask`、`recorder.stopTask/removeTask/changes/notices`）不变。

## 1. 录制弹幕

| | 做法 |
|---|---|
| v3 | `recording_danmaku_service.dart`（241 行）+ `RecorderController._connectRecordingDanmaku`：观察任务快照，录制中/准备中/重连中的任务保持一个弹幕连接；每次尝试（一个 MP4）写一个同名 `<前缀>.xml`（B 站弹幕 XML，`<d p="时间,1,25,颜色,unix,0,用户哈希,0">`），只写聊天，按 `messageId` 去重 |
| v4 | live_record 的 `RecordChatRecorder`（同样只看 `Recorder.changes` 的快照，不参与选流、FFmpeg、合并，弹幕出错不影响视频）+ `RecordChatWriter`；live_record 不能依赖 live_danmaku（依赖方向），所以连接器是接口 `RecordChatConnector`，应用在 `recording.dart` 的 `recordChatConnector` 里用 live_danmaku 实现：`DanmakuRegistry.connectionFor` 连接、`DanmakuMessageFilter` 过滤（重复和积压闸门 + 用户的屏蔽词、屏蔽用户），连接放弃（`DanmakuClosed`）时通知录制端 30 秒后重连 |
| 分段 | 一次尝试一个文件，和这次尝试的 MP4 同目录同前缀（每次重连是新的尝试、新的目录和 MP4，弹幕也换新文件）；重连间隙没有视频，弹幕不写 |
| 设置 | 录制设置页“同时录制弹幕”开关改为可用，说明用 3.x 的 `record_danmaku_desc`；删掉“正在重做”的提示键 |

和 v3 的差异（改进）：
- **时间基准**：v3 以尝试创建时间为 0 点（在取流、开中继之前，弹幕整体晚几秒）；现在以这次尝试进入“录制中”（FFmpeg 收到第一批数据）为 0 点，更贴近视频开头。
- **文件始终完整**：v3 结束时才写 `</i>`，进程被杀留下不完整的 XML；现在每 2 秒把新条目写在结尾标签前并重写 `</i>`，任何时候都是完整文档。
- **过滤**：v3 录制弹幕不看屏蔽词；现在用屏蔽词、屏蔽用户和重复闸门（和直播间一致）；“折叠重复”“相似度过滤”只影响显示，录制不用，文件保留原话。
- 格式只做 v3 的 XML（v3 没有 ASS/JSON）。

## 2. HLS 预取和保留窗口

**判断**：现在 FFmpeg 经中继按需取分段，一次只取一个分段，取完才重新加载列表。上游每次请求慢（海外平台走代理，每个请求多几百毫秒）或直播窗口短（低延迟 HLS、2 秒分段、只列 3 段）时，分段在 FFmpeg 来取之前就离开列表，FFmpeg 报 “skipping N segments ahead, expired from playlists”（标“有缺口”），CDN 随后删除分段。并行预取能把串行的请求延迟变成并行下载，保留窗口让已离开上游列表的分段继续可取——这正是漏段的两个来源，所以补做。

**做法**：live_media 新加 `HlsMediaWindow`（`relay/hls_window.dart`，一个类约 400 行，替代 v3 的 `hls_prefetch_plan/pool/scheduler`、`hls_retained_window/manifest`、`hls_low_latency`、`hls_date_range`、`hls_media_spool`、`hls_relay_prefetch` 约 2900 行）。`HlsRoute` 和 `LoopbackRelay.start` 各加一个可选参数 `prefetch`/`hlsPrefetch`（不传时行为不变，播放器不用）；录制的 `RecordInputOpener` 自己启动的中继默认打开（`hlsPrefetch: HlsPrefetchOptions()`）。

| 部分 | 做法 |
|---|---|
| 何时开始 | FFmpeg 取过这个媒体列表的分段**并且再次加载**这个列表后才开始（FFmpeg 探测时会读主列表每个变体的头几段，但只会重新加载它录的那些；没被录的变体不会被预取）。之后每半个目标时长（1～6 秒）自己轮询一次列表，不等 FFmpeg |
| 并行预取 | 新出现的分段（序号 ≥ FFmpeg 下一个要的）立即下载，每个列表最多 4 个并行；整段收完才交给 FFmpeg；单段超过 32 MiB 不缓存 |
| 保留窗口 | 给 FFmpeg 的列表从“它下一个要的分段的前一段”开始（`#EXT-X-MEDIA-SEQUENCE` 随之改写），已经离开上游列表但还在窗口里的分段照样列出、照样从内存给出；窗口最多 48 段 |
| 低延迟 | `#EXT-X-PART`、`PART-INF`、`PRELOAD-HINT`、`RENDITION-REPORT`、`SERVER-CONTROL` 去掉（FFmpeg 只读整段，v3 同样只录整段）；`#EXT-X-SKIP` 增量列表不处理（原样转发） |
| 日期范围等 | `#EXT-X-DATERANGE`、`#EXT-X-PROGRAM-DATE-TIME`、`#EXT-X-DISCONTINUITY`、`#EXT-X-BYTERANGE`、`#EXT-X-GAP` 跟着自己的分段走；`#EXT-X-KEY`、`#EXT-X-MAP` 在窗口开头和变化处重写（URI 改为绝对地址再由中继改写成本地）；`#EXT-X-DISCONTINUITY-SEQUENCE` 按窗口第一段重算 |
| 预算 | 每个列表持有的未交付分段最多 96 MiB（内存）；超过就不再预取新段，FFmpeg 照旧自己经中继去取（退回到现在的行为）；交付后的旧段立刻释放 |
| 失败 | 预取失败（403/404/超时）的分段由 FFmpeg 自己去取，得到上游真实状态；序号倒退（换流）时窗口清空重来；FFmpeg 12 次轮询（约 6 个目标时长）既不加载列表也不取段，停止预取并释放内存 |
| 续签、Cookie、令牌、Bigo | 预取请求走中继同一个上游、同样的请求头、配方 Cookie、上游下发的会话 Cookie 和令牌传递；Bigo 解扰在交给 FFmpeg 时做；续签后列表地址变了，轮询跟着新地址 |

**取舍**：
- 只放内存，不像 v3 那样大分段落盘：直播分段一般 1～6 MB，有预算上限；超过就退回按需取，不会更差。
- 不选画质、不跟随主列表（同 v3：只服务 FFmpeg 实际在读的列表）。
- 漏段仍由 FFmpeg 日志判定（“有缺口”），窗口本身不另报。
- 没做 v3 的诊断面板（`hls_relay_diagnostics.dart`），只留 `HlsRoute.windows`（已知分段数、持有字节数）供以后调试。

## 3. 录制设置进 `live_store`

- **设置**：`Settings` 新增 19 项（分区 `recorder`，Dart 名 `recordXxx`，`Settings.recorder` 列出全部），默认值和范围照 3.x `RecorderConfig`。**键名沿用 3.x 的 Hive 键**（`segmentTime`、`maxTaskCount`、`default_quality`、`recorder_rw_timeout`……），理由：和 J02.1 其他 150 多项一致，J02.1 的 3.x 导入、备份恢复、“恢复默认”自动认这些键，不需要另写映射；`legacyKeys` 也就用不上。
- **备份**：v4 备份多一个 `recorder` 分区（3.x 读到会忽略），恢复按分区读入。`recordSavePath`（录制目录）是这台设备的路径，和 `backupDirectory` 一样标为 `internal`，不进备份（Windows 的目录恢复到手机上没有意义）。
- **迁移（只做一次）**：
  1. H02.1 期间用户在 v4 改过的值在 `meta['recorder.settings']`：`RecordSettingsStore.load()` 第一次运行时按 3.x 的宽松规则读出（数字字符串、0/1 布尔都认）、规整后写进设置，然后删掉这个 meta 键；
  2. J02.1 之前导入时放进 `legacy_values` 的 3.x 值：`LegacyMigration.adoptLegacyValues(store)` 把“键已成为正式设置”的值写进设置（库里已有的值优先，同 J02.1 的合并规则），写完从 `legacy_values` 删掉这些键，所以只做一次；
  3. 以后再发现新的 3.x 来源，J02.1 的导入直接把这些键当设置导入（来源账本照旧，一个来源只导一次）。
  顺序保证“用户在 v4 改过的 > 3.x 的”。
- **页面**：`RecordSettingsStore` 改为读 `store.settings`（同步）、`changes` 来自设置变更（恢复备份、恢复默认也会通知录制器 `settingsChanged()`）；录制设置页的写入改成类型化的 `Settings.recordXxx`。

## 4. 录制目录的选择和打开

- **选择**：O03.1 已经把 `recordDirectoryPickerProvider` 换成 `file_picker` 的 `getDirectoryPath`（目录框里“选择文件夹”），本次核对，没有再改。
- **打开（Android）**：选 `android_intent_plus`（6.1.0，pub.dev 最新；v3 也用它）。理由：系统文件管理（DocumentsUI）只认 `content://com.android.externalstorage.documents/document/primary:<相对路径>` 加类型 `vnd.android.document/directory` 的 VIEW 意图，这需要直接发意图；`open_filex` 发的是它自己 FileProvider 的地址、类型按文件扩展名猜，文件管理器不能把它当文件夹浏览。打开前先 `canResolveActivity`，打不开就复制路径并提示（同 3.x 的修正）。
- **应用专属目录**：默认目录在 `Android/data/<包名>/` 下，Android 11 起系统文件管理不让进；这种情况不发意图，直接复制路径，提示里说明原因和“在录制设置里换到公共目录（如 Download）”（新键 `recorder_folder_private_copied`，中英文）。
- **Windows**：照旧用资源管理器打开（`url_launcher` 的 `file:` 目录地址，H02.1），打不开时提示。

## 5. ffmpeg_kit 原生包的本地缓存

- 原因：插件构建钩子对远程地址**每次构建都重新下载**（`_downloadFile` 不看缓存）：Android 约 40 MB、`flutter test` 时 Linux 约 17 MB，离线就失败。本地路径只在大小不同时复制，不联网。
- 做法：根 `pubspec.yaml` 的 `ffmpeg_kit_extended_config` 改为相对路径 `.ffmpeg_kit/<文件名>`（相对根 pubspec，`.ffmpeg_kit/` 已加进 `.gitignore`）；`tools/ffmpeg_kit/bundles.txt` 列出三个包的文件名、SHA-256（取自 GitHub 发布 `native-ffmpeg-9.0.2-b1` 的 digest）和地址；
  - WSL/Linux：`tools/ffmpeg_kit/fetch.sh [android|linux|windows]`，缓存在 `$PURE_LIVE_FFMPEG_KIT_CACHE` 或 `${XDG_CACHE_HOME:-~/.cache}/pure_live/ffmpeg_kit/`，缺少或校验不符才下载（走 `HTTPS_PROXY`），然后在 `.ffmpeg_kit/` 建符号链接；
  - Windows：`pwsh tools\ffmpeg_kit\fetch.ps1 [windows]`，缓存在 `%LOCALAPPDATA%\pure_live\ffmpeg_kit\`，复制到 `.ffmpeg_kit\`（符号链接在 Windows 要开发者模式）；
  - 门禁 `gate.sh` 在测 `apps/pure_live` 前自动跑 `fetch.sh linux`；CI（缓存为空）每次照常下载。
- **怎么配置**：克隆或新建工作树后先跑一次 `tools/ffmpeg_kit/fetch.sh`（之后离线也能构建和测试）；换原生包时同时改 `bundles.txt` 和根 pubspec 的文件名。没跑脚本时钩子报 “Local override not found: .ffmpeg_kit/…”。二进制不进 Git。
- 实测：本机缓存后 `flutter test test/pages/recorder` 在不设代理时通过，钩子日志 “Using local override path”。

## 6. 划掉应用后继续录制

- **现状核对**：C01.2 已把 `MainActivity` 改成 audio_service 的 `AudioServiceActivity`，Flutter 引擎缓存在 `FlutterEngineCache`，Activity 被划掉时引擎不销毁（`provideFlutterEngine` 来自宿主，`shouldDestroyEngineWithHost` 为假）；录制器在这个引擎的 Dart 里，`RecorderPlugin` 只在引擎销毁（`onDetachedFromEngine`）时停服务；录制前台服务 `stopWithTask="false"`、持有唤醒锁和 Wi-Fi 锁，进程留着。所以划掉后录制继续，回到应用（新 Activity 接回同一个引擎）录制中心看到的就是当前状态。
- **补上的缺口**：audio_service 的媒体服务结束时（后台播放停止），如果没有 Activity，`AudioServicePlugin.disposeFlutterEngine()` 会销毁缓存引擎，录制随之中断（分段留在磁盘，下次启动恢复时合并）。现在录制前台服务运行期间用标志 0 绑定 audio_service 的媒体服务（不会因此启动它），它在录制结束前不会被销毁；录制结束解绑后才按 audio_service 原来的逻辑处理。
- 通知点击改为和桌面图标一样的启动意图（`getLaunchIntentForPackage`，`NEW_TASK | RESET_TASK_IF_NEEDED`）：有任务就回到任务，没有就新开 Activity 接回缓存引擎。
- 仍然做不到的：部分国产系统（MIUI/HyperOS 等）划掉即杀进程、或限制后台，前台服务也挡不住，需要用户在系统里允许自启动/后台运行；这类情况下次启动时恢复（合并被杀时的分段，开了“开机自启”就重新检测）。

## 没验证的部分

- **真机（本次不装手机）**：录制弹幕的实际连接和文件（各平台）、HLS 预取对漏段的实际效果（建议用海外平台走代理录 30 分钟对比“有缺口”）、Android 打开文件夹（DocumentsUI 各厂商实现）、划掉应用后继续录制（含后台播放同时进行、停止播放后录制不断）、通知点回应用。
- **Windows**：`fetch.ps1` 没在主机上跑过；录制、合并、打开文件夹仍待 H02.1 记录里的 Windows 检查。

## 测试

加速流程，只测主要路径：
- live_store（31，+1）：`backup_test` 新增：3.x 停放值只采纳一次、库里已有值优先、采纳后离开 `legacy_values`、备份带 `recorder` 分区但不带目录、恢复到另一个库。
- live_record（30，+3）：`chat_test`：XML 每次写入后都完整（转义、非法字符、早于开头的时间夹到 0）；一个连接跨两次尝试、每次尝试一个文件、重连间隙不写、非聊天不写、停止后断开；关闭时不连、放弃后重连。
- live_media（40，+2）：`hls_window_test`：慢读者在 CDN 已删除分段后仍从中继拿到它们（预取、保留窗口、低延迟部分去掉、日期范围保留、媒体序号从下一个要的前一段开始）；不开预取时行为不变。
- 应用全部 `flutter test` 206 个通过（离线用本地 FFmpeg 包）；其中 `test/pages/recorder`（8，+1）：录制设置迁移（v4 meta 优先于 3.x 停放值、一次、进备份）替换原来的 meta 读写用例；Android 文件夹地址（公共目录可开，应用专属目录和 `Android/data` 不开）。

## 构建

- WSL：`flutter analyze` 无问题；`flutter build apk --debug` 成功（含 `android_intent_plus` 和前台服务改动；钩子日志 “Using local override path: .ffmpeg_kit/bundle-base-shared-lgpl-release.aar”，没有下载；APK 含三个 ABI 的 `libffmpegkit.so`）。新工作树第一次构建时 media_kit 分支的钩子下载自己的预编译包失败过一次（`archive.zip.partial` File closed，与本次改动无关），重跑通过。没有往手机安装。
- `android_intent_plus` 6.1.0 是 Java 插件，在 AGP 9 下直接通过，不需要覆盖。

## 合并时注意（冲突点）

- **合并后先跑一次 `tools/ffmpeg_kit/fetch.sh`**（主检出和每个工作树各一次）：根 pubspec 的原生包改成了本地路径，没跑时构建和应用测试报 “Local override not found”。门禁会自动跑。
- `RecordSettingsStore` 的接口变了：构造参数是 `LiveStore`（原来是 `MetaStore`），`set(Settings.recordXxx, 值)` 是类型化的，去掉了 `storageKey`、`keys`、`flush`、`close`；直播间（`live_play/`）没有用它。
- `packages/live_store/lib/src/settings/settings.dart`：在 `enableStartUp` 和 `backupDirectory` 之间加了一段，`all` 里加了 `...recorder`；别的分支加设置时可能在这里相邻冲突。
- `packages/live_media/lib/src/relay/hls_relay.dart`、`loopback_relay.dart`：只加了可选参数和几行接线。
- `apps/pure_live/lib/app/recording.dart`、`lib/app/bootstrap.dart`（`platformAppRecording` 多传 `danmaku`）、`lib/platform/recording_platform.dart`、`lib/platform/plugins.dart`（`installPluginHooks` 多一行）。
- 翻译：删 `record_settings_danmaku_pending`，加 `recorder_folder_private_copied`（中英文，按键名排序）。
- `apps/pure_live/pubspec.yaml`、根 `pubspec.lock`（`android_intent_plus` 6.1.0）、根 `pubspec.yaml`（`ffmpeg_kit_extended_config`）、`.gitignore`、`tools/gate/gate.sh`、`AGENTS.md`（目录一行）。
- `android/.../RecorderForegroundService.kt`（绑定 audio_service 的媒体服务、通知意图）；`MainActivity.kt` 和清单没动。
