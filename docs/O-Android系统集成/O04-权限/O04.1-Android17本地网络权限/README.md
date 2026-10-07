# O04.1 Android 17 本地网络权限在 K90 上验证：局域网代理、设备同步、投屏、局域网直播源

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：验证
- 来源：功能清点 F-AND-04（Android 17 本地网络权限）是“没验证”；登记时写的是“要另找 Android 17 设备”，V03.3（2026-10-03）核对时改正：K90 就是 Android 17（[S02.2 记录](../../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md)），题目改成现在的样子、档位从第三档升到第二档；投屏和局域网直播源的申请是 4.0.0 发布前 Y01.1 第 4 节加的，也一起验证
- 旧编号：T13d.1
- 相关：原生和 Dart 的实现见 [O04 子分类说明](../README.md)；I01.3（`pure_live/system_access` 通道和 `LocalNetworkGuard`）、Y01.1 第 4 节（投屏、局域网直播源也申请，请求码改成 20261003）；N02（投屏）、J05（设备同步）、L01（网络电视）、Q02（代理）；CHECKLIST 第 5 节第 8 条；决定 D-019；任务书 [brief.md](brief.md)

## 目标

在 K90（Android 17，API 37，`targetSdk = 37`）上确认：应用连局域网地址的四个地方都会在第一次需要时弹出系统的“本地网络”权限请求；允许后能用；拒绝后分别给出对的提示，不卡住、不闪退、不反复弹框；Android 17 以下（没有这个权限）什么都不问。做完后清点 F-AND-04 能改“完成”。

只验证、不改代码；发现的问题开到对应组。

## 3.x 和现状

| 使用方 | 3.x（`v3.2.11`） | 现在（`apps/pure_live/lib/` 下） | 拒绝时的提示（`assets/translations/zh.json`） |
|---|---|---|---|
| 局域网代理（应用代理 `enableAppProxy`/`appProxyHost`，播放代理 `enableProxy`/`proxyHost`） | `lib/common/services/local_network_access.dart:17` `ensureForProxies`，`proxy_settings_controller.dart:41-51` 改设置后防抖、启动 2 秒后申请；一次运行只问一次 | `platform/system_access.dart:67` `LocalNetworkGuard`，`app/startup.dart:76` 启动；代理设置稳定 1 秒后申请；`needed` 只看已开的代理是否指向局域网（`isLocalNetworkProxyHost`，`packages/live_net/lib/src/proxy.dart:121`）；一次运行只问一次 | `local_network_permission_denied`（:1003）“未获得「本地网络」权限，局域网代理（如电脑上的 Clash）无法连接。……” |
| 设备同步 | `lib/modules/remote_receiver/remote_sync_service.dart:154` 开始前 `ensure()` | `features/remote_receiver/remote_sync_service.dart:180`：`start` 前 `requestLocalNetwork`，拒绝就不开服务 | 同上一行（讲代理的那句，3.x 一样） |
| 投屏搜索 | 不申请 | `features/live_play/dialogs/stream_dialogs.dart:336`：每次搜索（第一次和刷新）前申请，拒绝时搜索失败 | `local_network_denied_cast`（:1001）“……无法搜索投屏设备……” |
| 局域网直播源（家里的 IPTV 服务器） | 不申请 | `platform/system_access.dart:56` `ensureLocalNetworkFor`：地址是局域网才申请；直播间取流 `features/live_play/logic/room_controller.dart:489`、网络电视回看 `:691`、多画面 `features/multiview/logic/multiview_controller.dart:590` | `local_network_denied_stream`（:1002）“……局域网里的直播源（如家里的 IPTV 服务器）无法连接……” |
| 原生 | permission_handler `Permission.accessLocalNetwork` | `android/.../SystemAccessPlugin.kt`：`localNetworkGranted`（:106，API < 37 为 true）、`requestLocalNetwork`（:118，同时只一个请求）、请求码 20261003 | — |

自动测试已经覆盖了“什么时候申请”和“拒绝时的提示”（`test/services_test.dart:336`、`:366`；`test/features/live_play/live_play_more_test.dart:214`；`live_play_more_page_test.dart:233`），没覆盖的是系统真正的权限框、拒绝和“不再询问”后系统的行为、拒绝后连接是不是真的失败（还是系统放行了）。

## 方案

- c1 确认设备：`adb shell getprop ro.build.version.sdk` 是 37；`adb shell dumpsys package com.mystyle.purelive.v4dev | grep -i LOCAL_NETWORK` 看声明和当前状态。
- c2 四个使用方各走一遍：撤销权限 → 触发 → 系统框 → 先拒绝（看提示、看功能是否失败得干净）→ 再触发（看会不会再弹、弹几次）→ 允许（看功能是否正常）。
- c3 “不再询问”之后：系统不再弹框时，各处是否只给提示、不卡住。
- c4 结果写 `verify.md`；通过就把登记表改“完成”，并把清点 F-AND-04、CHECKLIST 第 5 节第 8 条要改的结果写进报告（本任务不改清点和 S 组）。
- c5 发现的问题开到对应组：提示文字（设备同步用了讲代理的那句）→ 建议 O04 开小任务加 `local_network_denied_sync`；投屏、设备同步本身的问题 → N02、J05；代理 → Q02。

## 验证

- 自动测试：已有（见上），本任务不加测试。
- 真机：还没做；步骤在 [brief.md](brief.md)。

## 留下的问题

- 还没开工。已知要确认的：设备同步被拒时提示的是讲局域网代理的话（3.x 同样），真机看过后决定是否加专用提示；被永久拒绝后没有“去设置”按钮，只有文字。
