# S02.6 K90 补验：任务书

## 背景

- 来源：V03.3（2026-10-03 功能清点核对）。S02.3（K90 验证主流程）登记为“完成”，但它的记录“没测的”写明多画面、网络电视、投屏、剪贴板口令、断网重连、账号登录没测；C03.1（预测返回）合并在 K90 用的构建 `288fec0ec` 之后；O05.1（屏幕常亮）在构建里但没看。功能清点因此有 8 个功能点是“没验证”、归给本任务：F-ROOM-13、F-AND-08、F-RT-01、F-MV-06、F-SRC-04、F-ACC-03、F-ACC-07、F-AND-01。
- 现象：没有已知的坏处；风险是这些路径靠原生、系统服务或联网，单元测试覆盖不到（例：常亮靠 `wakelock_plus`，返回靠 `OnBackInvokedCallback`，剪贴板靠原生读变化时间）。
- 为什么现在做：第一档。这几项都在 4.0.0 里发出去了，真机上没看过。决定 D-019（K90 随时可用，只点测试包，不碰 3.x 和正式包）。
- 已经做过的：S02.2（K90 冒烟）、S02.3（画中画、后台播放、菜单、返回、录制 5 分钟、分享链接、搜索、分区）。

## 目标和验收

1. 下面“真机验证”表的每一步都有结果（通过 / 不通过 + 现象），写进本文件夹的 `verify.md`，截图在 `verify/`（宽不超过 1080，每张不超过 300 KB）。
2. 通过的功能点在 `docs/inventory/FEATURES.md` 改成“完成”，备注写“2026-xx-xx K90（S02.6）”，统计表同步。
3. 不通过的每条写现象、复现步骤、`adb logcat` 里相关的几行和根因线索（文件:行），在对应组开任务（编号、标题写进 `verify.md` 的“结论”）。
4. 投屏那一步的本地网络权限结果同时写进 O04.1；扫码登录后重启仍登录的结果同时写进 K02.1。

## 现状（读代码得出，写文件:行）

- 常亮：`packages/live_player/lib/src/screen_wake.dart:9`（`ScreenWake`，全应用一个计数）；`packages/live_player/lib/src/video_view.dart:79`（`keepScreenOn` 且播放或缓冲时请求）；直播间 `apps/pure_live/lib/features/live_play/player/player_view.dart:503-516` 读 `Settings.enableScreenKeepOn`；应用内小窗 `features/live_play/mini/floating_window.dart:187`。多画面 `features/multiview/widgets/cell_view.dart:92` 用默认值（一直常亮，同 3.x）。
- 返回：`features/live_play/logic/predictive_back.dart:15` 的 `RoomBackChannel`；`live_play_page.dart:262` 打开时 `hold`，`:646` 的 `_nativeBack`：有对话框或弹层先关，再面板、详情、全屏、桌面小窗，最后退出直播间；直播间是第一页时 `SystemNavigator.pop`。原生 `android/app/src/main/kotlin/com/mystyle/purelive/MainActivity.kt:92`（通道名）、`:112-130`（注册状态）。
- 投屏：`features/live_play/dialogs/stream_dialogs.dart:146`（`StreamUse.cast`）、`:336`（搜索前 `SystemAccess.requestLocalNetwork()`，被拒提示 `local_network_denied_cast`）；`packages/live_cast` 的 `DlnaCastController`。
- 多画面：`features/multiview/logic/multiview_controller.dart:155-162`（手机 `maxCells` 是 4）；`multiview_page.dart:402`、`:413`（沉浸 `immersiveSticky`，退出 `edgeToEdge`）。
- 网页搜索：`shared/in_app_web.dart:45` 的 `InAppWebPage`。
- 网页登录：`features/account/bilibili_web_login.dart:46`。
- 登录后取流：`app/platforms.dart:52` 的 `StoreCookieVault`。
- 剪贴板：`app/intake/clipboard_rooms.dart:34`（`ClipboardRoomWatcher`，`:93-101` 先比变化时间再读内容、解码）；`shared/rooms/share_code.dart:181` 的 `OwnClipboardTexts` 只记本次运行自己写的文字，所以**杀掉应用重开后**剪贴板里的自己的口令也会被问。
- 文件分享：`app/intake/share_intake.dart:52`；`ShareIntakePlugin.kt:84`。

## 3.x 基线

- 常亮：`git show v3.2.11:lib/modules/live_play/controllers/live_play_controller.dart` 的 `:177-179`、`:252-260`（暂停也亮；v4 只在播放或缓冲时亮，O05.1 确认的差别）。
- 返回：`lib/modules/live_play/services/android_predictive_back_service.dart:7`（一组全局回调，旧页面 dispose 会清掉新页面的；v4 谁打开谁关）。
- 剪贴板：`lib/common/global/platform/desktop_manager.dart:595-651`（启动、回前台 1 秒后读）；同一内容本次运行只问一次。
- 投屏：`lib/modules/live_play/dialogs/live_dlna_dialog.dart:6`。
- 多画面：`lib/modules/multiview/multiview_controller.dart:49`（手机最多 4 格）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 10 节真机验证、第 14 节规则）。
2. `docs/S-质量和验证/S02-真机验证/CHECKLIST.md` 第 1、2、4 节。
3. 本文件夹的 `README.md`；`docs/S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md`（上一轮的结果和“没测的”）；`docs/C-直播间/C03-直播间工具/C03.1-直播间小项/record.md`、`docs/O-Android系统集成/O05-方向、刷新率、常亮/O05.1-屏幕常亮跟随设置/record.md`、`docs/O-Android系统集成/O03-分享接收和快捷方式/O03.2-接回半成品/record.md` 的“要在 K90 上看的”。

## 范围

- 可以改：本文件夹（`verify.md`、`verify/`）；`docs/inventory/FEATURES.md` 里这 8 个功能点的状态和统计表；O04.1、K02.1 的 `verify.md`（只记本次顺带看到的结果）。
- 不能改：代码、测试、构建文件；版本号、`assets/version.json`、`assets/releases.json`；签名配置；用户的 3.x 安装（`com.mystyle.purelive`）和它的数据。发现问题只记录和开任务，不在本任务里修。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 直播间：常亮、返回、断网重连、投屏（表第 1～4 步） | `verify.md` | 4 步都有结果和截图 |
| 2 | 多画面和网络电视（第 5～6 步） | `verify.md` | 2 步都有结果 |
| 3 | 账号和搜索：网页登录、登录后画质、网页搜索、剪贴板口令和文件分享、快手标题（第 7～11 步）；FEATURES 改状态 | `verify.md`、`FEATURES.md` | 全部步骤有结果；清点和统计改好 |

## 测试

- 不写自动测试。准备：
  - 构建：`flutter build apk --profile --target-platform android-arm64`（`apps/pure_live`），包名 `com.mystyle.purelive.v4dev`；在 `verify.md` 记下提交号。
  - 装机：`adb connect 192.168.1.2:5555`；`adb install -r <apk>`；每次点按前 `adb shell dumpsys activity activities | grep -m1 mResumedActivity` 确认前台是测试包（K90 上有个自动操作小红书的应用会抢前台，用 `adb shell am start -n com.mystyle.purelive.v4dev/com.mystyle.purelive.MainActivity` 调回来）。
  - 截图：`adb exec-out screencap -p > verify/NN.png`，缩到宽 540 再看、提交前转成 jpg。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 设置 → 视频 → “屏幕常亮”开；进一个直播间不碰手机 3 分钟（系统灭屏时间设 30 秒）。再关掉设置，同样等。最后开着设置、暂停播放等 1 分钟 | 开：一直亮；关：约 30 秒后灭屏；暂停后约 30 秒灭屏 |
| 2. 直播间里：打开清晰度面板后手势返回；进横屏全屏后手势返回；什么都不开时手势返回；再用三键导航（设置里切换）的返回键各做一遍 | 依次：只关面板；只退全屏；退出直播间回到上一页；返回键同样；没有闪退、没有一次退两级 |
| 3. 播放中关 Wi-Fi 10 秒再打开（哔哩哔哩直播间，弹幕开着） | 画面显示正在重连，恢复后自动继续；弹幕有状态行，恢复后重连 |
| 4. 同一 Wi-Fi 有电视或盒子时：菜单 → 投屏 | 第一次弹系统“本地网络”权限，允许后列表出现设备；投出去电视上能播，显示“主播名 - 标题”；拒绝时提示“未获得「本地网络」权限……”（结果也记给 O04.1）。没有设备就写“跳过：没有 DLNA 设备” |
| 5. 首页 → 多画面 → 2×2，放 4 个国内直播；点格子；进沉浸、全屏再退出；按返回 | 4 路同时播放不卡；点格子声音跟过去；沉浸隐藏系统栏、退出后恢复；返回安全退出、没有残留声音 |
| 6. 网络电视导入一个 m3u，播放一个频道；打开节目单，点一个可回看的节目，再“返回直播” | 能播；节目单滚到正在播的；回看能播；返回直播正常 |
| 7. 账号 → 哔哩哔哩 → 网页登录，用短信登录；退出后再看浏览器 Cookie 是否清掉（再进网页登录页应是未登录） | 登录完成回到账号页显示用户名；退出后网页登录页是未登录状态 |
| 8. 登录哔哩哔哩后进一个游客只拿到“超清”的直播间（游客时清晰度菜单只有“超清”或提示平台实际返回超清的） | 能选“原画”并播放，不再提示画质受限。顺带：扫码登录一次、杀掉应用重开仍是登录状态（记给 K02.1） |
| 9. 搜索 → 网页搜索 → 哔哩哔哩，进到一个直播间的网页 | 询问是否进入，进入后正常播放 |
| 10. 在直播间分享一次（得到口令）→ 在分享面板选“复制”→ 杀掉测试包 → 重新打开；再切到别的应用、切回来；再到设置 → 通用 → 关掉“识别剪贴板中的分享口令”后复制另一个口令切回来。另用文件管理器把一个 m3u 文件“打开方式”选纯粹直播 | 重开后约 1 秒弹“进入直播间”，点进入能播；同一口令切回来不再问；关掉设置后不问；HyperOS 不应每次回前台都提示“已读取剪贴板”。m3u 导入网络电视并提示结果 |
| 11. 从推荐或分区的快手卡片进房；停留超过 1 分钟；关注后回到关注页 | 标题是卡片上的直播标题（不是主播简介），1 分钟后的定时刷新不改标题，关注页里也不被简介替换（E06.1 A-3） |

## 风险和注意

- 只点测试包：每次输入前确认前台；不要打开、不要截图 3.x 的 `com.mystyle.purelive`。
- 第 10 步的口令是测试包自己生成的；不能用 3.x 生成（D-019）。
- 第 4 步要求同一 Wi-Fi 有 DLNA 设备；第 8 步要维护者自己的哔哩哔哩账号，Cookie 不进仓库、截图里打码。
- 断网时不要关移动数据开关以外的系统设置；做完恢复 Wi-Fi。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/S02.6` 或本机工作区；提交信息以 `[S02.6]` 开头（英文）；不推 master。
- 提交前：`python3 tools/docs/docs.py`、`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：把已做的步骤写进 `verify.md` 并提交，在末尾写“停在哪”（做到第几步、哪一步不通过、下一步），登记表改 `done`、`next`、`branch`。

## 报告（中文，简洁）

每一步通过没有；不通过的现象、根因线索、开的任务编号；FEATURES 改了哪几项、统计前后；O04.1、K02.1 记了什么；需要维护者决定的。
