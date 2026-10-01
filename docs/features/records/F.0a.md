# F.0a 接回 M12.5 半成品：权限、分享接收、剪贴板口令、播放代理

- 日期：2026-10-02
- 功能对比：[F.0a/README.md](../F.0a/README.md)（X1、X2 按 A）；界面照 [U.14](../../ui/compare/U.14/README.md)（记录 [U.14](../../ui/records/U.14.md)）和 U.3d 的 `showRoomPrompt`
- 半成品：M12.5 分支 `worktree-agent-a27f9a86b17d9663f` 的 4 个提交按文件搬过来，没有合并分支
- 构建：`flutter build apk --debug` 通过（只构建，没有安装）

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 口令解码、自己的口令不问、剪贴板检查、`showRoomPrompt` | ✅ | `decodeRoomShareCode`、`OwnClipboardTexts` 从分支搬（`shared/rooms/share_code.dart`）；`ClipboardRoomWatcher`（`app/intake/clipboard_rooms.dart`）照 v3 只认口令、同一内容本次运行只问一次（分支存进 meta、连链接也认，都改回 v3，见 X2）；Android 先读剪贴板的变化时间，没变不读内容；提示用 U.3d 的对话框，没有“不再识别” |
| c2 | 设置 `detectClipboardRooms`，默认开，在“通用” | ✅ | “通用”最后一组“分享与剪贴板”，用现有开关行；图标 `AppIcons.settingsClipboardRooms`（live_ui 新加） |
| c3 | 分享接收、“打开方式”、工具箱粘贴口令 | ✅（有偏差） | `ShareIntakePlugin.kt` 从分支搬，加了快捷方式和通知的跳转（`ACTION_OPEN`）、长按图标的快捷方式；`ShareIntake`（`app/intake/share_intake.dart`）照 v3 的顺序。**偏差**：分享来的口令照 v3 先弹对话框（分支是直接进房）；分支新加的“`#EXTM3U` 文字导入”“无扩展名按开头字节识别”没搬（v3 没有）；多个文件只显示最后一条结果（同 v3） |
| c4 | 权限插件、`switchGateProvider` | ✅ | `PermissionsPlugin.kt` 从分支搬，加 `notificationState`（`granted`/`askable`/`blocked`，用“问过一次 + 系统的 rationale”判断永久拒绝）；`BackgroundPermissions`（`shared/permission_prompts.dart`）；`switchGateProvider` 默认取它（Android），`SwitchGateResult` 加 `cancelled`（取消说明时不变红，同 v3）。分支“被拒也打开开关”改回 v3：通知被拒开关保持关 |
| c5 | 播放代理 | ✅ | `PlaybackProxyPolicy`（`app/platforms.dart`），`MediaOpener` 用它（直播间、多画面、小窗共用一个）；录制仍走应用代理（X1，v3 `initialized.dart:94`） |
| c6 | 第一次录制的通知说明、所有文件权限先说明 | ✅ | `RecordingPermissionPrompts`：只在前台、只问一次（meta 键 `permission.recordingNotifications`），不等它就开始录；`androidStorageAccess` 多了 `explain`，取消就不跳系统页面 |
| c7 | 分支能用的搬过来 | ✅ | 分支的测试按新接口重写（`test/intake_test.dart`） |

## 根因

- P1：v4 只搬了口令生成（`share_code.dart`），没有解码和检查剪贴板。
- P2：M12 只搬了清单的过滤器，3.x 的 `share_handler`（打过补丁）没有 v4 的替代。
- P3：3.x 用 `permission_handler`，v4 没有插件；U.6c 留的 `switchGateProvider` 没有实现。
- P4：`bootstrap.dart` 把应用代理交给了 `MediaOpener`，没有 3.x `PlaybackProxyPolicy` 的对应。

## v3 文件 → v4 文件

| v3 | v4 |
|---|---|
| `plugins/share_command_handler.dart`（解码）、`common/utils/share_command_handler.dart`（黑名单、只问一次） | `shared/rooms/share_code.dart` |
| `common/global/platform/desktop_manager.dart:595-651`（剪贴板检查） | `app/intake/clipboard_rooms.dart`、`app/intake/system_intake.dart` |
| `main.dart:105-131`、`common/utils/shared_media_intake.dart`、`shared_live_link_opener.dart` | `app/intake/share_intake.dart`、`platform/share_channel.dart`、`android/.../ShareIntakePlugin.kt` |
| `player/core/live_audio_service.dart:207-261` | `shared/permission_prompts.dart`、`platform/system_permissions.dart`、`android/.../PermissionsPlugin.kt` |
| `player/core/playback_proxy_policy.dart` | `app/platforms.dart` 的 `PlaybackProxyPolicy` |

## 新设置和 3.x 数据

- 新设置：`detectClipboardRooms`（`app` 节，默认开）。3.x 的键都没动：`enableProxy`、`proxyHost`、`proxyPort` 现在照 3.x 管播放；`enableAppProxy` 等照旧管应用请求和录制。
- 新 meta 键：`permission.recordingNotifications`（录制的通知说明问过了）。原生 `SharedPreferences` `pure_live_permissions`（通知权限问过一次，用来判断永久拒绝）。

## 测试

新增 32 个（F.0a 和 U.14 合计，U.14 的见它的记录）：

- `test/intake_test.dart` 12 个：口令（往返、夹在文字里、标准 Base64 和整数房间号、不可用的房间号）；剪贴板（只问一次、自己的口令和链接不问、进入房间；开关关了不读、变化时间没变不读、剪贴板空；回前台 1 秒后才读）；分享（快捷方式和通知的页面、房间；口令先问；链接先提示再进房、短链接失败、平台下线；没有链接的文字和不认识的文件分开提示；播放列表导入网络电视）；长按图标的最近两个房间；通道数据的解析。
- `test/shared/permission_prompts_test.dart` 7 个：已允许不问；通知和电池两个说明（通用对话框的布局）；取消、拒绝、电池不阻止；永久拒绝去设置后回来再查；`switchGateProvider` 的映射；录制的通知说明（只在前台、只一次）；所有文件权限先说明、取消不跳。
- `test/platforms_test.dart` +1：直播流走播放代理，关了直连，应用代理不影响播放。
- `test/features/settings/settings_general_test.dart` +1：“分享与剪贴板”开关；`settings_playback_test.dart` +1：取消说明后开关不打开、不变红。
- `test/features/toolbox/toolbox_page_test.dart` +1：工具箱粘贴口令进房。
- `packages/live_store/test/stores_test.dart`：新设置的默认值（加一行断言）。
- 全部 `flutter test`（`apps/pure_live` 634 个）、`live_store`、`live_ui` 的测试通过；`flutter analyze` 没有问题；`check_ui_structure.py` 通过。

## 要在 K90 上看的（TASKS 第 5 节 5.1 第 10 条、5.4 第 11 条、5.5 第 6 条）

1. 打开“后台播放”：先弹“需要通知权限”（通用对话框），去开启 → 系统框；拒绝两次后再打开：弹“通知权限已关闭 / 去设置”，在系统设置打开通知后回来，开关自动打开；接着电池优化的说明和系统框。
2. 从哔哩哔哩 App 分享直播间：提示“正在打开分享的直播间…”后进房；分享一个 3.x 口令：弹“打开分享的直播间”（副标题“收到别的应用分享的口令”）；分享 m3u 文件、用纯粹直播“打开方式”打开 m3u：导入网络电视；分享一段普通文字：提示“分享的内容里没有能打开的直播间链接”。
3. 复制一个 3.x 口令后切回应用：约 1 秒后弹提示，同一口令只弹一次；HyperOS 上不应每次回前台都出现“已读取剪贴板”的系统提示；设置里关掉开关后不再弹。
4. 播放代理指向局域网代理，进海外直播间：媒体请求走代理；关掉后直连；应用代理开、播放代理关时播放直连。
5. 第一次开始录制而通知关着：弹一次说明；录制目录选到公共目录且没有所有文件权限：先说明再跳系统页面。

## 和合并有关的

- **改了 `features/live_play/logic/background_playback.dart`**（任务书没列这个目录）：U.14 的 c2（媒体通知小图标）、c6（按钮中文）、c7（画中画暂停按钮）只能在这里改；只加了 `mediaControls`、`PictureInPicture.bindPlayback/unbindPlayback` 和两处调用，没动别的逻辑。
- 改了 `lib/main.dart`（启动 `SystemIntake`，一行）。
- `features/settings/playback_tiles.dart`：`switchGateProvider` 默认值、`SwitchGateResult.cancelled`；`settings_catalog.dart` 加一组；和 U.6 后续任务改同一文件时注意。
- `platform/recording_platform.dart`：`AndroidRecordKeepAlive` 构造参数多了 `extra`、`onStart`、`onStopAll`（原有参数不变）。
- 翻译中英各加 31 条，没改已有的。
