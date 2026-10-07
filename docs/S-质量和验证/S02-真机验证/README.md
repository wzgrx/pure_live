# S02 真机验证

在测试手机 K90 上看 4.x 实际跑起来的样子：界面重构后的冒烟、按功能点的逐项清单、把一批“待真机”任务一次看完、给“登记完成但没有真机结果”的任务补验、真机上发现的问题回收和修复。

## 范围

- 包括：
  - 每次上机的做法（构建、安装测试包、带前台检查的输入、只断测试包的网、截图、日志、结果写在哪）。
  - 本子分类的清单 [CHECKLIST.md](CHECKLIST.md)：按功能点（`F-ROOM-01` 这类，见 [inventory/FEATURES.md](../../inventory/FEATURES.md)）分六节：看直播、弹幕、录制、关注搜索分区历史账号、数据和其他、系统界面；每条写“由谁验证”。
  - 任务：S02.1（真机问题修复）、S02.2（冒烟）、S02.3（主流程）、S02.4（数据、海外平台和其他）、S02.5（构建号 5001 的 18 个待真机任务）、S02.6（S02.3 漏掉的 8 个功能点，加上 2026-10-07 核对出的国内补验）。
- 不包括（归哪里）：
  - 某个任务自己的 `verify.md` 由那个任务写（模板 [templates/verify.md](../../templates/verify.md)）；S02.5 只把它们排成一次走完的顺序，结果仍写回各任务。
  - 其他组的单项验证任务：[O02.1](../../O-Android系统集成/O02-画中画/O02.1-画中画复验/README.md) 画中画复验、[K02.1](../../K-账号和登录/K02-登录状态/K02.1-Cookie和密码加密存储验证/README.md) 加密存储、[O04.1](../../O-Android系统集成/O04-权限/O04.1-Android17本地网络权限/README.md) 本地网络权限、[O06.1](../../O-Android系统集成/O06-返回手势、平板和折叠屏/O06.1-预测返回在ColorOS14/README.md) ColorOS 预测返回、[R01.2](../../R-性能和流畅度/R01-基准和测量/R01.2-在K90上跑基准/README.md) 基准数字、[H01.4](../../H-录制/H01-录制核心/H01.4-录制余项/README.md) 录制的 4 项、[J06.1](../../J-设置和数据/J06-3.x数据迁移/J06.1-3.x数据迁移的真机验证/README.md) 迁移数据——各自在组里登记，可以和 S02.4、S02.5、S02.6 同一次上机。
  - 所有界面按设计逐个核对（含平板、宽屏）归 [S03](../S03-统一验证/README.md)；覆盖安装 3.x 归 [S04](../S04-覆盖安装验证/README.md)；Windows 的真机核对归 [X01.1](../../X-多端客户端/X01-Windows/X01.1-键盘鼠标操作核对/README.md)。

## 现状：做到哪、怎么工作的

- **一次上机怎么做**（S02.2、S02.3 的实际做法，S02.5 任务书补了断网的做法）：
  1. 构建：WSL 里 `source ~/tools/purelive-env.sh`，`cd apps/pure_live`，`flutter build apk --profile --target-platform android-arm64`（S02.2、S02.3 用的是 `288fec0ec` 的 arm64 profile 包；只看界面时 `--debug` 也行，看手感、动画节奏用 profile）。debug 和 profile 构建的包名是 `com.mystyle.purelive.v4dev`、应用名“纯粹直播 v4dev”（`apps/pure_live/android/app/build.gradle.kts:80-89`），和用户的 3.x 并存。
  2. 安装：`adb connect 192.168.1.2:5555`（端口会变，连不上先问维护者），`adb -s 192.168.1.2:5555 install -r build/app/outputs/flutter-apk/app-profile.apk`。
  3. 上机前：`adb -s 192.168.1.2:5555 logcat -d | grep "adbd service requested"` 看有没有别的自动化程序在操作手机；`export PL_APP=com.mystyle.purelive.v4dev; source ~/tools/pl-adb.sh`（脚本第 7 行默认的 `.next` 是旧包名）；用 `adb shell am start -n com.mystyle.purelive.v4dev/com.mystyle.purelive.MainActivity` 把测试包调到前台。
  4. 操作：只用 `tap`、`key`、`text`、`swipe`、`tapl`（每次先 `need_pl` 检查前台是测试包），不用裸的 `adb shell input`；返回键之后不连着点，先重新检查前台。
  5. 断网：**只断测试包的网**，不关 Wi-Fi（adb 走 Wi-Fi，关了连不回来）。K90 是 root 的：`UID=$(adb shell dumpsys package com.mystyle.purelive.v4dev | grep -m1 -o 'userId=[0-9]*' | cut -d= -f2)`，断 `adb shell su -c "iptables -I OUTPUT -m owner --uid-owner $UID -j REJECT; ip6tables -I OUTPUT -m owner --uid-owner $UID -j REJECT"`，恢复把 `-I` 换成 `-D`，做完 `adb shell su -c "iptables -S OUTPUT"` 确认没有残留。维护者手里拿着手机时也可以开关飞行模式。
  6. 截图：`shot <名字>` 存到会话的临时目录，缩到宽 540 再看；要进仓库的放任务文件夹的 `verify/`（宽不超过 1080、单张不超过 300 KB）。
  7. 日志：`adb logcat -d --pid=$(adb shell pidof com.mystyle.purelive.v4dev)`；应用自己的日志在“设置 → 数据 → 日志管理”（`apps/pure_live/lib/features/backup/log_page.dart`），打开“启用本地日志”后写文件，可导出（Cookie、令牌在写入前由 `apps/pure_live/lib/app/app_log.dart:127` 的 `redactSecrets` 去掉）。
  8. 结果：写进对应任务的 `verify.md`（步骤、期望、结果、截图）；清单式的验证写进 S02.x 的 `record.md` 或 `verify.md`；[CHECKLIST.md](CHECKLIST.md) 每条的“结果”一列写“通过（日期，任务）”或“有问题（现象，去向）”。
  9. 收尾：临时改过的系统设置全部恢复（动画 `animator_duration_scale`、`wm size`、`wm density`、系统刷新率、画中画和本地网络权限、灭屏时间、防火墙规则）。
- **CHECKLIST 怎么用**：
  - 清单按功能点分节，一条对应一个或几个功能点，写“步骤”“预期”和“由谁验证”；功能变化时（例如 A07.13 改了切换直播间）才更新预期。
  - 做一个 S02.x 任务时，任务书写明要走哪几节哪几条（就是“由谁验证”一列写着它的那些）；走完把结果填进“结果”一列，带上日期和任务编号，同一条再验证时覆盖成最新结果。
  - 某条有问题：在结果里写现象和去向（已有任务或新登记的任务），截图和日志放进去向任务的文件夹。
  - 单个任务的 `verify.md` 是“这个改动”的步骤；CHECKLIST 是“这个功能”的回归步骤。改动类任务（如 S02.5 的 18 个）看 `verify.md`，整体回归（S02.4、S02.6、S03.1、发布前冒烟）看 CHECKLIST。
- **完成度**（对照 CHECKLIST，2026-10-07）：
  - 看过并通过的：1.5 横屏全屏和返回、1.10 后台播放和媒体通知（开的分支）、3.1 录制和合成（S02.2）；1.11 进画中画、1.14 直播间菜单（只看了菜单）、4.2 搜索、4.4 分区、4.11 里的分享链接进房（S02.3）。
  - 看过但没走完的：3.3 划掉应用后继续录（HyperOS 最近任务里上滑没删掉卡片，现归 H01.4）；1.11 从画中画回来后控制条（S02.1 防御性修了，复验归 O02.1）。
  - 没看的：其余全部。按“由谁验证”一列数（一条分给两个任务时两边都算）：S02.6 53 条（第 1 节 17、第 2 节 9、第 3 节 2、第 4 节 16、第 6 节 9），S02.4 13 条，S02.5 顺带 7 条，H01.4 6 条，S03.1 回归 5 条，S04.1 2 条，O02.1、O04.1、K02.1、A06.5 各 1 条。
  - 构建号 5001 新改的 18 个任务都没在真机上看（S02.5）；其中 16 个有 `verify.md`，R01.1、R02.2 的步骤写在 S02.5 任务书的阶段 3。

## 代码地图

本子分类不写代码；上机时用到的：

| 文件 | 职责 |
|---|---|
| `apps/pure_live/android/app/build.gradle.kts:42-50` | 正式包 `com.mystyle.purelive`、`minSdk 26`、`targetSdk 37`、版本号取 `pubspec.yaml`（现在 `4.0.0+5001`） |
| `apps/pure_live/android/app/build.gradle.kts:63-89` | release 开 R8 和资源压缩（`isMinifyEnabled`、`isShrinkResources`）；debug、profile 加 `.v4dev` 后缀、不压缩 |
| `apps/pure_live/integration_test/perf_test.dart`、`perf_driver.dart`、`perf/` | 手机上跑的 profile 基准（R01.1）；`flutter drive --profile` 会覆盖装 `.v4dev` |
| `apps/pure_live/lib/app/app_log.dart` | 应用日志：等级、内存里 2000 条（`AppLog` `:144`）、“启用本地日志”时写文件，`redactSecrets`（`:127`）去掉 Cookie 和令牌 |
| `apps/pure_live/lib/features/backup/log_page.dart` | 日志管理页（设置 → 数据）：按等级看、复制、导出（`_share` `:83`）、打开目录（`:95`）、清除（`:109`） |
| `apps/pure_live/lib/features/live_play/logic/room_layout.dart:59-67` | 直播间布局怎么选：高 <480 且横着、宽 ≥600 是横屏手机，宽 ≥840 才是宽屏分栏（K90 看不到分栏的原因） |
| `~/tools/pl-adb.sh`（仓库外） | 带前台检查的 adb 辅助：`need_pl`、`tap`、`key`、`text`、`swipe`、`shot`、`ui`、`tapl` |
| [CHECKLIST.md](CHECKLIST.md) | 按功能点的真机清单（本子分类的资料） |
| [inventory/FEATURES.md](../../inventory/FEATURES.md) | 功能点编号、3.x 位置、4.x 位置、“没验证”的标记和由哪个任务验证 |

测试：本子分类没有自动测试；各任务的真机步骤来自它的 `record.md` 的“要在 K90 上看的”和 README 的“实现和验证”。

## 3.x 基线

- 3.x 没有真机清单和逐项验证的流程，真机问题靠用户反馈（GitHub issue）；它的 CI（`v3.2.11:.github/workflows/feature-build.yml`）只构建和跑单元测试。
- 真机上的预期以 3.x 的行为为准，具体到每个功能点的 3.x 位置见 [inventory/FEATURES.md](../../inventory/FEATURES.md)（例如 F-ROOM-07 全屏 `lib/modules/live_play/widgets/video_player/video_controller_panel.dart`）；确认过的改动以各任务 README 的“确认的改动”为准（例如暂停后单击只显示控制层，D-012，3.x 会继续播放）。
- 必须保留的操作习惯（[specs/UI.md](../../specs/UI.md) 附录 A）是真机上要特别看的：返回逐级退出、双击全屏、左右半屏调亮度和音量、锁定锁住所有手势。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| **一批任务登记“完成”但没有真机结果**（2026-10-07 各组 v2 文档核对）：A07.2、A07.3、A07.7、A07.8；A08.1～A08.4；A09 的观看记录、标签管理、平台显示、关注分区、网页搜索；A10.1、A10.2；A11.1～A11.5 大部分；A12.1～A12.6；A13.1、A13.2；A14.1 的原生部分；A15.1、A15.2；A16.1（Windows）；A17.1（电视）；D01 的 30 个平台弹幕（D01.18、D01.19 受阻）；E06.1 的 9 条；H01.3 的 2 条；I01～I08 的 10 个任务；C02.1、C03.1、O05.1 | 各任务 README 的“实现和验证”或“验证” | 不符合 [PROCESS.md](../../PROCESS.md) 第 3.2 节“完成必须有真机结果” | 不把它们改回“待真机”（维护者定），而是按区域分批补验，结果写回各任务：**国内的直播间、浏览、账号、弹幕、录制界面、系统界面**并入 [S02.6](S02.6-K90补验/README.md)（阶段 1～3 扩充，新增阶段 4 弹幕、阶段 5 录制和系统界面）；**海外平台和数据类**（备份、WebDAV、设备同步、应用内更新、关于和版本、字体、日志、云账号说明）并入 [S02.4](S02.4-K90验证数据和其他/README.md)；录制核心（H01.3 的清晰度标签和合并进度）在 H01.4；设置各页（A11）、宽屏首页（A06.2）、宽屏分栏（A07.5）在 [S03.1](../S03-统一验证/S03.1-统一验证/README.md)；Windows（A16.1）在 X01.1；电视（A17.1）等电视客户端开工。对应条目已补进 CHECKLIST，“由谁验证”一列写明 |
| 没有归属的真机步骤（I、A 组核对时发现）：移动网络提示、关注的定时和回前台刷新、标签管理、观看记录的刷新和保留数量、工具箱“获取直链”、日志导出、其他平台弹幕抽查 | I02～I08、I01.3、D01 的 README | 这些行为只有组件测试 | 已补进 CHECKLIST：1.20 移动网络提示、4.12 关注定时、4.13 标签管理、4.15 观看记录、4.16 工具箱、5.10 日志、2.9 国内弹幕、2.10 海外弹幕；归属见“由谁验证” |
| K90 横屏 869×400 dp，高度不到 480，看不到宽屏分栏 | `features/live_play/logic/room_layout.dart:59-67` | 平板分栏、宽屏面板的条目在 K90 上默认看不到 | 临时 `adb shell wm size 1600x2560`（或 `wm density 240`）模拟，测完 `wm size reset`、`wm density reset`；模拟不了的留给 S03.1 的平板 |
| 测试包是 debug、profile 构建，不开 R8 和资源压缩 | `build.gradle.kts:63-89` | release 才有的问题（例如 4.0.0 发布前被压缩器删掉的媒体通知图标，见 [Y01.1](../../Y-发布和运营/Y01-版本签名和发布/Y01.1-4.0.0发布前修复/record.md)）在测试包上看不到 | 发布包另做冒烟；S04.1 用的就是 release 包 |
| “等重试用完造录制失败”在 H01.5 修好前走不通：断网先触发的 EOF 不计重试次数，任务一直快速重连 | `packages/live_record/lib/src/policy.dart` 的 `shouldEnterPollingAfterRetryLimit`（[H01.5](../../H-录制/H01-录制核心/H01.5-主播下播后不再无限快速重试/README.md)） | S02.5 的 4B-01、[A08.5 的 verify.md](../../A-界面设计/A08-弹幕界面/A08.5-设置里的弹幕页/verify.md) 第 4 步照原写法等不到“录制已停止” | S02.5 任务书 4B 已改成先关“自动断线重连”再断网（照 [H05.1 的 verify.md](../../H-录制/H05-录制通知/H05.1-录制通知按状态写标题/verify.md) 第 7 步）；A08.5 的 verify.md 第 4 步要 A 组同样改（写进报告） |
| HyperOS 最近任务里上滑没能划掉卡片 | S02.3 记录 | “划掉后继续录”没验证（CHECKLIST 3.3） | 归 H01.4：先长按卡片看有没有“清除”，或用 `adb shell am kill` 对照 |
| 手机上有别的自动化应用会抢前台 | S02.3 记录 | 输入落到别的应用 | 每次输入前 `need_pl`；抢前台时 `am start` 调回来，严重时请用户暂停那个应用 |
| `~/tools/pl-adb.sh` 第 7 行默认包名还是旧的 `.next` | 仓库外 | 不改环境变量时 `need_pl` 永远失败 | 用前 `export PL_APP=com.mystyle.purelive.v4dev`；改脚本默认值由维护者做 |
| 录制清晰度标签写请求的“原画”、实际是 720p（S02.2 发现） | `packages/live_record` | — | 已修：`a5870d018`，测试 `packages/live_record/test/applied_quality_test.dart`；真机复看在 H01.4 |

## 相关决定和规范

- D-019：K90 随时可用，可以把测试包切到前台；只点测试包；不碰 3.x 和正式包。
- D-008：4.0.0 覆盖发布为构建号 5001；这一批改动的真机验证就是 S02.5。
- D-029：功能点改“完成”要有 K90 结果或关键部分不靠原生和系统服务；C01.3、D06.1、Q04.1 的真机验证并入 S02.4、S02.6。
- D-012、D-020～D-023：S02.5 清单里“和 3.x 不同、不算 bug”的几条依据。
- [PROCESS.md](../../PROCESS.md) 第 3.2 节（“完成”必须有真机结果）、第 10 节（真机验证的设备、测试包、截图）。
- [specs/ENGINEERING.md](../../specs/ENGINEERING.md) 第 6 节（测试包和正式包）。

## 测试和验证

- 本子分类的“测试”就是真机步骤：CHECKLIST 的六节，加上 S02.5 任务书里按布局编的清单。
- 每次上机写明构建的提交号和包类型（debug、profile），截图放 `verify/`。
- 发现问题先找根因（读代码、抓日志），再归到已有任务或登记新任务；不在 S02 里直接改代码（S02.1 那样集中修的除外，要单独登记）。

## 路线

1. **S02.5**（第一档）：构建号 5001 的 18 个待真机任务，分四个阶段上机；看完一个阶段就把对应任务改“完成”或开返工任务。
2. **S02.6**（第一档）：先做登记的三个阶段（直播间、多画面和网络电视、账号搜索和浏览），每个阶段顺带扩充进来的国内补验条目；再做阶段 4（弹幕，含其他国内平台抽查）、阶段 5（录制界面和系统界面）（2026-10-07 已登记，规模“大”）。可以和 S02.5 用同一个构建、同一天上机。
3. **S02.4**（第二档）：CHECKLIST 第 5 节和第 2 节第 10 条（海外弹幕），六个阶段；可以和 O04.1、K02.1 同一次上机。
4. 之后每次发布前：用发布包按 CHECKLIST 第 1～4 节的第 1 条走一遍冒烟（PROCESS 第 11 节第 5 步）。
5. 新的验证需求在这里登记 S02.n 任务；属于某个功能的验证登记在那个功能的组。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [S 质量和验证](../README.md)。

- 代码：—
- 进度：`█████████░░░░░░░░░░░` 43%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| S02.1 | 真机问题修复 | 验证 | 完成 | 2026-10-01 | f4cb41c68 | [设计或说明](S02.1-真机问题修复/README.md)、[记录](S02.1-真机问题修复/record.md) |
| S02.2 | K90 冒烟：界面重构后把主流程走一遍 | 验证 | 完成 | 2026-10-02 | c8e72f34d | [设计或说明](S02.2-K90冒烟/README.md)、[记录](S02.2-K90冒烟/record.md) |
| S02.3 | K90 验证：看直播、录制、关注搜索分区历史账号 | 验证 | 完成 | 2026-10-02 | 1f6270984 | [设计或说明](S02.3-K90验证主流程/README.md)、[记录](S02.3-K90验证主流程/record.md) |
| S02.4 | K90 验证：备份恢复、WebDAV、设备同步、扫码、应用内更新、字体、播放代理、Twitch 和 Kick | 验证 | 未开始 | — | — | [设计或说明](S02.4-K90验证数据和其他/README.md)、[任务书](S02.4-K90验证数据和其他/brief.md) |
| S02.5 | 4.0.0（构建号 5001）这一批改动的真机验证 | 验证 | 未开始 | — | — | [设计或说明](S02.5-4.0.0构建号5001/README.md)、[任务书](S02.5-4.0.0构建号5001/brief.md) |
| S02.6 | K90 补验：S02.3 漏掉的 8 项（常亮、预测返回、剪贴板口令、网页搜索、投屏、多画面、哔哩哔哩网页登录、登录后画质） | 验证 | 未开始 | — | — | [设计或说明](S02.6-K90补验/README.md)、[任务书](S02.6-K90补验/brief.md) |

## 还没完成的

- **S02.4 K90 验证：备份恢复、WebDAV、设备同步、扫码、应用内更新、字体、播放代理、Twitch 和 Kick**（未开始，第二档，规模 中）
  - 阶段：备份恢复和扫码权限 → WebDAV → 设备同步和扫码配对 → 应用内更新、关于、字体、日志导出 → 播放代理和本地网络权限 → 海外平台：Twitch、Kick 和海外弹幕抽查
  - 说明：并入原 Q04.1 的验证：F-NET-02 播放代理（CHECKLIST 5 第 6 条）、F-NET-04 Twitch 令牌（第 7 条）（V03.3）
- **S02.5 4.0.0（构建号 5001）这一批改动的真机验证**（未开始，第一档，规模 中）
  - 阶段：直播间（暂停、菜单、切换直播间、弹窗） → 弹幕和录制 → 列表手感和刷新率 → 设置和通知
- **S02.6 K90 补验：S02.3 漏掉的 8 项（常亮、预测返回、剪贴板口令、网页搜索、投屏、多画面、哔哩哔哩网页登录、登录后画质）**（未开始，第一档，规模 大）
  - 阶段：直播间：常亮、预测返回、断网重连、投屏 → 多画面和网络电视 → 账号和搜索：网页登录、登录后画质、网页搜索、剪贴板口令和文件分享 → 弹幕 → 录制界面和系统界面
  - 来源：V03.3 功能清点：S02.3 记录“没测的”和“没验证”的功能点

## 资料

- [CHECKLIST.md](CHECKLIST.md)

<!-- docs:生成结束 -->
