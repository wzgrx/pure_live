# F.0a 接回 M12.5 半成品：权限、分享接收、剪贴板口令、播放代理

- 状态：未开始
- 档位：必须；规模：中
- 功能点：F-AND-01、F-AND-02、F-AND-03、F-NET-02（见 [INVENTORY.md](../INVENTORY.md)）
- 涉及代码：`apps/pure_live/lib/app/`（新 `app/intake/`）、`platform/`、`shared/rooms/`、`features/settings/`、`features/toolbox/`、`android/`（两个插件、清单）；`packages/live_media`、`live_record`、`live_store`（只添加）
- 依赖：U.14（权限说明、分享接收的界面）合并后；U.6d（剪贴板识别开关的位置）
- 来源：M12.5 分支 `worktree-agent-a27f9a86b17d9663f`：`2894bdfe0` 播放代理、`341513e13` 口令解码 + 剪贴板识别 + 分享接收（Dart）、`e8ff1bb40` Android 的 `ShareIntakePlugin` 和 `PermissionsPlugin`、`4157aafbc` 通知和电池优化权限。分支基于 `e62c995e4`，目录是旧的 `lib/pages/`；任务说明在 scratchpad `rest/m12_5_intake.md`
- 评审页：小于“中”的部分按授权直接开发；有一个要选的（X1），和改动清单一起发一个评审页
- 记录：[records/F.0a.md](../records/F.0a.md)（开发后）

## 要做的

| 功能点 | v3 | v4 现在 | 要做到 |
|---|---|---|---|
| F-AND-01 | 启动时和回前台 1 秒后读剪贴板，认出口令弹“进入直播间”（`common/global/platform/desktop_manager.dart:621`、`plugins/share_command_handler.dart:28`） | 只能生成口令（`shared/rooms/share_code.dart`） | 认出 3.x 和 v4 的口令和平台链接；同一内容只弹一次；用 U.3d 的 `showRoomPrompt`（`shared/rooms/room_prompt.dart`），按钮只有“取消 / 进入直播间”（同 v3） |
| F-AND-02 | `share_handler` + `SharedMediaIntake`（`main.dart:105`、`common/utils/shared_media_intake.dart:9`） | 清单有 SEND、VIEW 过滤器，没有接收代码 | 分享来的链接和口令进房；m3u/txt 导入网络电视；xml/gz/json 导入节目单；其他说明不支持 |
| F-AND-03 | 打开后台播放、助眠时先说明再申请通知权限和忽略电池优化（`player/core/live_audio_service.dart:207`） | 没有申请 | 同 v3：取消说明时开关保持关；被拒时说明影响并给系统设置入口；说明对话框照 U.14 |
| F-NET-02 | 播放代理是独立的一组设置（`player/core/playback_proxy_policy.dart:6`） | 播放和录制只走应用代理，`proxyPort` 没人读 | 播放（mpv `http-proxy`、中继）和录制（FFmpeg `-http_proxy`、中继）走播放代理；关掉时直连（v3）；设置页说明两种代理的区别 |

## 改动清单（初稿，对比页确认后定）

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 补上 | 搬 `2894bdfe0`：播放代理接进 `MediaOpener`、录制输入 | F-NET-02 |
| c2 | 补上 | 搬 `341513e13`：`decodeRoomShareCode`、`ClipboardRoomWatcher`、`ShareIntake`、工具箱粘贴口令；提示改用 `showRoomPrompt` | F-AND-01、F-AND-02 |
| c3 | 补上 | 搬 `e8ff1bb40`：`ShareIntakePlugin`（复制分享文件到缓存、只读一次启动意图）、`PermissionsPlugin`、清单的 VIEW 类型 | F-AND-02、F-AND-03 |
| c4 | 补上 | 搬 `4157aafbc`：开关打开前的说明和申请、被拒说明、第一次录制时问一次通知权限（v3 没有，分支加的） | F-AND-03 |
| c5 | 保留 | 分支里的测试（`intake_test`、`permissions_test`、`platforms_test` 新增部分）照搬并跑通 | — |

## 需要用户选的

- X1 剪贴板识别要不要开关：A（建议）加设置“识别剪贴板里的直播间”，默认开（同 v3 一直识别），提示框里不加“不再识别”；B 不加开关，同 v3。

## 测试和验证

- 单元测试：分支的用例照搬；口令（3.x、v4、夹在别的文字里）、同一内容只弹一次、分享的文件按扩展名和开头字节分类、权限被拒的分支、代理开关和直连。
- K90：TASKS 第 5 节 5.1 第 10 条、5.4 第 11 条、5.5 第 6 条；`flutter build apk --debug` 通过。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
