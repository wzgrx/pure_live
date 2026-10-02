# T13c.2 接回 M12.5 半成品：权限、分享接收、剪贴板口令、播放代理

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 档位：必须；规模：中
- 功能点：F-AND-01、F-AND-02、F-AND-03、F-NET-02（见 [inventory/FEATURES.md](../../../inventory/FEATURES.md)）；界面照 [T13a.1](../../T13a/T13a.1/README.md)（已确认）和 T07a.6 的 `showRoomPrompt`
- 涉及代码：`apps/pure_live/lib/app/`（新 `app/intake/`）、`platform/`、`shared/`、`features/settings/`（剪贴板开关、接上权限）、`features/toolbox/`（粘贴口令）、`android/`；`packages/live_store`（只添加）
- 来源：M12.5 分支 `worktree-agent-a27f9a86b17d9663f` 的 `2894bdfe0`、`341513e13`、`e8ff1bb40`、`4157aafbc`（旧目录 `lib/pages/`，按文件搬，不合并）
- 评审页：没有发（任务书要求直接开发）；X1、X2 按建议 A 做
- 记录：[records/F.0a.md](record.md)（开发后）

## v3 的行为（`v3.2.11`）

1. **剪贴板口令**：启动后第一帧、每次回前台 1 秒后读剪贴板（`common/global/platform/desktop_manager.dart:595-625`，所有平台）；只认分享口令（`common/utils/share_command_handler.dart:85-88`、`plugins/share_command_handler.dart:28`），房间号为 `0`/`null` 等不认；同一内容本次运行只问一次、自己生成的口令不问（`share_command_handler.dart:137-164`）；弹“分享”对话框，“取消 / 进入直播间”（`share_command_import_dialog.dart:58-66`）。没有开关。
2. **分享接收**（Android）：`share_handler` 收 SEND、SEND_MULTIPLE、VIEW（`main.dart:105-131`）；依次判断：口令 → 同上对话框；扩展名 m3u/m3u8/txt → 导入播放列表，xml/gz/json → 导入节目单（附件或文字里的路径、地址）；含直播间链接 → 解析（短链接联网）后进房（`shared_live_link_opener.dart:30-63`）；平台下线 →“该平台已下线…”；解析失败 →“无法解析此链接”；都不是 →“不支持的文件格式，仅限 M3U 或 TXT”（`shared_media_intake.dart:71-148`）。
3. **权限**：打开“后台播放”“新直播间自动助眠”时，通知没开先弹说明（取消 / 去开启）再弹系统框，没给就不打开开关；然后电池优化同样先说明，不给也打开（`player/core/live_audio_service.dart:207-227`，`video_settings_page.dart:327-371`）。录制不问通知；录制目录要“所有文件访问权限”时直接跳系统页面。
4. **播放代理**：`enableProxy`、`proxyHost`、`proxyPort` 是独立的一组，只管播放（mpv `http-proxy`、播放中继，`player/core/playback_proxy_policy.dart:9-28`）；关掉时直连，不退回应用代理。录制的中继走**应用代理**（`common/global/initialized.dart:94-101`）。

## v4 现在

- 只能生成口令（`lib/shared/rooms/share_code.dart:18`）；T07a.6 的 `showRoomPrompt`（`shared/rooms/room_prompt.dart:22`）没人调用。
- 清单有 SEND、VIEW 过滤器（`android/.../AndroidManifest.xml:78-117`），没有接收代码，点了只打开应用。
- 没有申请权限的代码；T09a.4 留了接口 `switchGateProvider`（`features/settings/playback_tiles.dart:66`，默认 null，开关直接打开）。
- 播放和录制都走应用代理（`app/bootstrap.dart:107`、`:182` 的 `MediaOpener(proxy: proxy)`）；`proxyPort` 只有设置页读，`enableProxy`/`proxyHost` 只给本地网络权限用（`platform/system_access.dart:64-71`）。

## 差别和根因

| 编号 | 问题 | 根因和位置 |
|---|---|---|
| P1 | 剪贴板里的 3.x 口令没反应 | 没有解码（`share_code.dart` 只有 `encodeRoomShareCode`），也没有检查剪贴板的代码 |
| P2 | 别的应用分享来的链接、文件只打开应用 | T07a.1 只搬了清单的过滤器，接收插件（3.x 打过补丁的 `share_handler`）没换成 v4 的通道 |
| P3 | 开后台播放不申请通知权限，Android 13 起后台播放和录制的通知都看不见 | 3.x 用 `permission_handler`，v4 没有对应插件；`switchGateProvider` 没有实现 |
| P4 | 3.x 用户设的播放代理不生效，播放走了应用代理 | `bootstrap.dart:182` 把应用代理交给了 `MediaOpener`；没有 3.x `PlaybackProxyPolicy` 的对应 |

## 改动

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 补上 | `decodeRoomShareCode`（3.x 和 v4 的口令）、`OwnClipboardTexts`（自己复制、分享的不问）；剪贴板检查：启动后、回前台 1 秒后，同一内容本次运行只问一次；Android 用剪贴板的变化时间判断，没变不读（不触发系统的“已读取剪贴板”提示）；提示用 T07a.6 的 `showRoomPrompt`，只有“取消 / 进入房间” | P1 |
| c2 | 补上 | 新设置 `detectClipboardRooms`（默认开）放在设置“通用”，用现有开关行 | P1，用户已定 |
| c3 | 补上 | Android 接收插件（分享、“打开方式”、只读一次启动意图、文件复制到缓存）；`ShareIntake` 照 v3 的顺序：口令 → 对话框；播放列表 / 节目单 → 导入网络电视；链接 → 进房；提示文字照 T13a.1 的 c10、c11；工具箱也能粘贴口令 | P2 |
| c4 | 补上 | 权限插件（通知状态和申请、电池优化、系统设置页）；实现 `switchGateProvider`：说明 → 系统框；取消不打开、不变红；照 T13a.1 的 c12、c13（通用对话框，永久拒绝时“去设置”，回来再查一次）；电池优化照 v3 不阻止打开 | P3 |
| c5 | 补上 | `PlaybackProxyPolicy`：播放（mpv、播放中继）走播放代理，关掉直连；录制保持应用代理（照 v3，X1） | P4 |
| c6 | 增强 | 照 T13a.1 的 c14：第一次开始录制而通知关着时说明一次；录制目录要所有文件权限时先说明 | T13a.1 |
| c7 | 保留 | 分支里能用的代码和测试搬到新目录（`lib/pages/` → `features/`、`app/intake/`） | — |

T13a.1 的 Android 部分（c1～c15）一起做，逐条见 [records/U.14](../../T13a/T13a.1/record.md)。

## 需要选的（按 A 做）

- X1 录制走哪个代理：**A** 照 v3 走应用代理（录制不受“播放代理”影响，3.x 的设置含义不变）；B 照分支改走播放代理（3.x 用户开着应用代理录海外直播间会变成直连）。
- X2 剪贴板认什么：**A** 照 v3 只认分享口令（T07a.6 的对话框写的就是“分享口令”）；B 照分支连平台链接也认（v3 没有的行为，复制任何直播间链接回到应用都会被问）。

## 测试和 K90 验证

- 单元测试：口令解码（3.x 样本、夹在文字里、坏的）；剪贴板检查（开关、同一内容只问一次、自己的口令不问、变化时间没变不读、进入房间）；分享（口令、链接、短链接失败、平台下线、文件按扩展名和开头字节、不支持的文字和文件、快捷方式和通知的跳转）；权限（已开、说明后同意、取消、拒绝、永久拒绝去设置后回来）；代理（播放代理开关、直连、应用代理不影响播放，录制仍走应用代理）。
- K90：TASKS 第 5 节 5.1 第 10 条、5.4 第 11 条、5.5 第 6 条；原生部分的看法写在记录里。`flutter build apk --debug` 通过。

## 风险和性能

- 剪贴板检查只在启动和回前台各一次，没有常驻定时器；Android 先读变化时间，不读内容。
- 分享的文件复制到缓存后导入、删除；单个最多 256 MB、一次 20 个。
- 不改 3.x 的设置键和含义；新设置只有 `detectClipboardRooms`。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
| 2026-10-02 | 写功能对比；发现清点 F-NET-02“播放和录制走它”与 v3 不符（录制走应用代理），改成 X1 |
| 2026-10-02 | 开发完成（和 T13a.1 的 Android 部分一起），等合并和 K90 验证 |
