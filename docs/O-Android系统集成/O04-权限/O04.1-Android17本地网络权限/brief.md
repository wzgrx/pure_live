# O04.1 Android 17 本地网络权限在 K90 上验证：任务书

## 背景

- 来源：功能清点 [inventory/FEATURES.md](../../../inventory/FEATURES.md) 第 2 节 F-AND-04“没验证”；V03.3（2026-10-03）核对时更正“K90 不是 Android 17”的说法（K90 是 Android 17，HyperOS），本任务改成在 K90 上直接验证，档位升到第二档；投屏和局域网直播源的申请是 4.0.0 发布前 Y01.1 第 4 节加的。
- 现象（为什么要验证）：Android 17 起，`targetSdk = 37` 的应用不拿 `ACCESS_LOCAL_NETWORK` 就连不上局域网地址。用户用电脑上的 Clash 做代理、和另一台设备同步、投屏到电视、看家里 IPTV 服务器的直播，都会受影响；没有权限时请求直接失败，看起来像“代理坏了”“搜不到电视”。
- 为什么现在做：第二档、小；代码在 4.0.0 就发出去了，一直没在 Android 17 真机上看过。
- 已经做过的：I01.3（通道 `pure_live/system_access`、`LocalNetworkGuard`）、Y01.1 第 4 节（投屏、局域网直播源也先申请，请求码改成 20261003 避免和其他插件冲突）。

## 目标和验收

1. 确认 K90 是 API 37，测试包声明了 `android.permission.ACCESS_LOCAL_NETWORK`。
2. **局域网代理**：开着指向局域网的代理时，启动或改完代理设置约 1 秒后弹系统权限框；拒绝时提示“未获得「本地网络」权限，局域网代理（如电脑上的 Clash）无法连接。请在系统设置 → 应用 → 纯粹直播 → 权限中允许。”，这次运行不再弹；允许后经代理的请求能用。
3. **设备同步**：打开设备同步页时弹框；拒绝时有提示、服务不启动、页面不卡住；允许后能显示本机地址、能被另一台设备发现。
4. **投屏**：菜单 → 投屏，搜索前弹框；拒绝时提示“未获得「本地网络」权限，无法搜索投屏设备。……”，列表显示搜索失败；允许后（有电视或盒子时）能搜到设备。
5. **局域网直播源**：网络电视里播放一个局域网地址的频道时，打开前弹框；拒绝时提示“……局域网里的直播源（如家里的 IPTV 服务器）无法连接。……”，画面区显示打不开的状态；允许后能播。普通的公网频道不弹框。
6. “不再询问”（拒绝两次）后，四处都只给提示、不卡住、不闪退。
7. 结果和截图写进本文件夹的 `verify.md`；全部通过时登记表改“完成”。
8. 报告里写清：清点 F-AND-04 和 CHECKLIST 第 5 节第 8 条应改成什么；设备同步的提示文字要不要改（建议）。

## 现状（读代码得出，写文件:行）

- 原生：`apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/SystemAccessPlugin.kt`：`LOCAL_NETWORK = "android.permission.ACCESS_LOCAL_NETWORK"`、`LOCAL_NETWORK_SDK = 37`、请求码 `20261003`（:37-42）；`localNetworkGranted`（:106-110，API < 37 直接 true）；`requestLocalNetwork`（:118-130：已允许直接 true；没有 Activity 或已有请求挂着时回答 false；否则 `requestPermissions`）；结果（:132-142）；Activity 分离时按当前状态回答挂着的请求（:70-75）。清单 `apps/pure_live/android/app/src/main/AndroidManifest.xml:21`。
- Dart：`apps/pure_live/lib/platform/system_access.dart`：`SystemAccess`（:12，非 Android 一律 true）；`isLocalNetworkUrl`（:47）；`ensureLocalNetworkFor`（:56-61：有局域网地址才申请，拒绝时 `local_network_denied_stream`）；`LocalNetworkGuard`（:67：跟四个代理设置，`settle` 1 秒，`ensure` :106 已允许就不问、`_asked` 一次运行只问一次、拒绝时 `local_network_permission_denied`）。
- 使用方：`apps/pure_live/lib/app/startup.dart:76`（Android 上启动 `LocalNetworkGuard`）；`features/remote_receiver/remote_sync_service.dart:180-182`（`start` 前申请，拒绝提示 `local_network_permission_denied` 并返回）；`features/live_play/dialogs/stream_dialogs.dart:335-341`（`_discover`，拒绝提示 `local_network_denied_cast` 并抛错，面板显示“DLNA 设备搜索失败”）；`features/live_play/logic/room_controller.dart:489`（取流前）、`:691`（回看前）；`features/multiview/logic/multiview_controller.dart:590`。
- 局域网地址怎么判断：`packages/live_net/lib/src/proxy.dart:121` 的 `isLocalNetworkProxyHost`（私有网段、`.local` 等；回环地址不算）。
- 读代码发现的一处不一致：设备同步被拒时用的是讲代理的提示（`remote_sync_service.dart:181`），3.x 同样（`git show v3.2.11:lib/modules/remote_receiver/remote_sync_service.dart:154` 调同一个 `LocalNetworkAccess.ensure()`）。

## 3.x 基线

- `git show v3.2.11:lib/common/services/local_network_access.dart`（42 行）：permission_handler 的 `Permission.accessLocalNetwork`；`ensureForProxies`（:17）一次运行只问一次；`ensure`（:26）拒绝时 `local_network_permission_denied`。
- `lib/common/services/settings/proxy_settings_controller.dart:41-51`：四个代理设置防抖后申请，启动 2 秒后查一次。
- 3.x 的投屏、网络电视不申请；它们在 Android 17 上拿不到权限时直接失败。4.x 加上申请是 Y01.1 确认过的改动。
- 文字：`local_network_permission_denied` 照 3.x（`assets/translations/zh.json:1964`）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 10 节真机验证、第 14 节规则）。
2. `docs/S-质量和验证/S02-真机验证/README.md`（上机做法）、`CHECKLIST.md` 第 5 节第 8 条。
3. 本文件夹的 `README.md`；`docs/O-Android系统集成/O04-权限/README.md`；Y01.1 记录的第 4 节（`docs/Y-发布和运营/Y01-版本签名和发布/` 下 Y01.1 的 `record.md`）。

## 范围

- 可以改：本文件夹（`verify.md`、`verify/` 截图）；登记表本任务的状态。
- 不能改：任何代码；清点和 S 组文档（要改的写进报告）；用户的正式包和 3.x 数据；用户电脑上的代理配置（只临时打开“允许局域网连接”，测完恢复）；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1～c3：按下面的真机步骤做四个使用方和“不再询问” | `verify.md`、`verify/*.jpg` | 12 步都有结果 |
| 2 | c4、c5：登记表、报告里的清点和清单更新建议、问题去向 | `docs/tasks.toml`（本任务状态） | `python3 tools/docs/docs.py --check` 通过 |

规模小，两个阶段可以一次做完。

## 测试

- 不改代码，不加测试。上机前跑一遍相关自动测试确认构建的提交是好的：`cd apps/pure_live && flutter test test/services_test.dart test/features/live_play/live_play_more_test.dart test/features/live_play/live_play_more_page_test.dart test/features/remote_receiver/remote_sync_test.dart`。

## 真机验证（维护者在 K90 上做）

准备：
- 合并后的 master 构建测试包装到 K90；每次点按前确认前台是测试包。
- 一台同一 Wi-Fi 下的电脑：开 Clash（或任何 HTTP 代理）并打开“允许局域网连接”，记下电脑的局域网地址 `192.168.1.x` 和端口；用 `ffmpeg -re -f lavfi -i testsrc=size=1280x720:rate=30 -f lavfi -i sine -c:v libx264 -c:a aac -f hls -hls_time 2 -hls_list_size 5 -hls_flags delete_segments live.m3u8` 生成一路 HLS，在同一目录 `python3 -m http.server 8000` 提供；写一个 `lan.m3u`，频道地址 `http://192.168.1.x:8000/live.m3u8`（先用手机浏览器打开这个地址确认能访问；WSL 里起服务时要确认手机能连到）。
- 撤销权限：`adb shell pm revoke com.mystyle.purelive.v4dev android.permission.ACCESS_LOCAL_NETWORK`；清掉“不再询问”：`adb shell pm clear-permission-flags com.mystyle.purelive.v4dev android.permission.ACCESS_LOCAL_NETWORK user-set user-fixed`。每个使用方开始前都撤销一次。

| 步骤 | 期望 |
|---|---|
| 1. `adb shell getprop ro.build.version.sdk`；`adb shell dumpsys package com.mystyle.purelive.v4dev \| grep -i -A1 LOCAL_NETWORK` | 37；声明了 `ACCESS_LOCAL_NETWORK`，当前未授予 |
| 2. 设置 → 网络 → 打开应用代理，地址填电脑的局域网地址和端口；等 2 秒 | 弹系统的本地网络权限框 |
| 3. 拒绝 | 提示“未获得「本地网络」权限，局域网代理（如电脑上的 Clash）无法连接。……”；改一下端口再改回，这次运行不再弹框 |
| 4. 杀掉应用重开（代理仍开着） | 启动约 1 秒后再次弹框；允许后进一个海外直播间，Clash 的连接列表里有应用的请求 |
| 5. 撤销权限；首页“我的”→ 设备同步 | 进页面时弹框 |
| 6. 拒绝 | 有提示（记下文字：现在是讲代理的那句）、页面没有本机地址、不卡住；退出再进会再弹框 |
| 7. 允许 | 显示本机地址；（有另一台装了纯粹直播的设备时）能互相发现 |
| 8. 撤销权限；进直播间 → 菜单 → 投屏 | 搜索前弹框；拒绝时提示“未获得「本地网络」权限，无法搜索投屏设备。……”，面板显示搜索失败；点刷新再弹一次框 |
| 9. 允许后刷新 | 开始搜索；有电视或盒子时出现在列表里 |
| 10. 撤销权限；网络电视导入 `lan.m3u`，播放那个频道 | 打开前弹框；拒绝时提示“……局域网里的直播源（如家里的 IPTV 服务器）无法连接。……”，画面区是打不开的状态；允许后重试能播 |
| 11. 播放一个公网的网络电视频道或普通直播间 | 不弹框 |
| 12. 撤销权限后连续拒绝两次（到“不再询问”），再分别触发投屏和局域网频道 | 不再弹系统框，只有提示；不卡住、不闪退 |

测完：关掉应用代理、恢复 Clash 的“允许局域网连接”原来的状态、`adb shell pm grant com.mystyle.purelive.v4dev android.permission.ACCESS_LOCAL_NETWORK`（或在系统设置里允许）、删掉导入的测试频道。

## 风险和注意

- HyperOS 可能把本地网络权限放在“附近的设备”一类里，系统框的文字和设置里的位置以真机为准，照实记录；提示文字里写的“系统设置 → 应用 → 纯粹直播 → 权限”如果和实际位置不符，写进报告。
- 拒绝后系统可能对某些连接仍然放行（例如组播发现），步骤 6、8 要看功能是不是真的失败，不只看提示。
- 不碰正式包 `com.mystyle.purelive`（D-019）；所有 `pm revoke`/`grant` 只对 `com.mystyle.purelive.v4dev`。
- 和 S02.4（设备同步、播放代理）、S02.6（投屏）有重叠：同一次上机时，本任务看权限，那边看功能本身，结果各写各的 `verify.md`。

## 环境和提交

- 构建：`source ~/tools/purelive-env.sh`；根目录 `bash tools/ffmpeg_kit/fetch.sh`、`flutter pub get`；`cd apps/pure_live && flutter build apk --profile`，`adb -s 192.168.1.2:5555 install -r build/app/outputs/flutter-apk/app-profile.apk`。
- 提交只有文档（`verify.md`、截图、登记表），提交信息以 `[O04.1]` 开头（英文）；运行 `python3 tools/docs/docs.py` 和 `--check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：已经做完的步骤写进 `verify.md` 并提交，末尾写“停在第几步”；登记表写 `next`。

## 报告（中文，简洁）

12 步各自的结果；系统框的样子和设置里的位置；拒绝后功能是不是真的失败；“不再询问”之后的表现；建议的后续（设备同步专用提示、要不要加“去设置”按钮）；清点 F-AND-04、CHECKLIST 第 5 节第 8 条应改成什么；测完已恢复的设置。
