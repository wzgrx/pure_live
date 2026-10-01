# U.11c 设备同步

- 日期：2026-10-02
- 设计：[docs/ui/compare/U.11c/README.md](../compare/U.11c/README.md)（第 1 版，用户已确认；S1、S2 按建议 A：接收先预览再写入、宽屏两列）
- 一并处理的跨任务待同步：U.17b → U.11c（macOS 正式版权限文件）**没做**，见下
- 改动的目录：`apps/pure_live/lib/features/remote_receiver/`、`shared/qr_scan.dart`（U.11a 的扫码页）、`packages/live_ui`（只做添加）、翻译文件、门禁基线、文档；预览用 `shared/backup/`
- 没有改原生部分，没有构建 APK

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 顶栏两个按钮、三块的顺序和内容、对方请求不能点外面关、扫码后选方向、提示文字 | ✅ | 顶栏扫码（只在有相机的设备，照 v3 桌面没有）、开始 / 停止（`play_circle_line` / `stop_circle_line`）；我的设备 → 发现的设备 → 手动输入；“选择同步操作”对话框：接收配置（文字按钮）、发送配置（实心） |
| c2 | 接收先预览再写入（S1） | ✅ | 配对码 → 拉取对方配置（服务拆成 `fetch` 和 `apply`，协议不变）→“接收配置”对话框：“来自 PureLive Windows”、地址 · 版本、“接收后会这样变化：”（设置几项不同、关注、屏蔽词等，同备份页的预览）、账号一行（对方没开“同步账号 Cookie”时写“本机账号不变”）、“接收会替换上面列出的内容，无法撤销；需要时先在“备份与恢复”创建一份备份。”→“接收”才写入 |
| c3 | 发送确认写对方名字；配对码写是哪台的 | ✅ | “确定要将当前设备的全部配置发送到“{name}”吗？对方确认后会覆盖它的配置。”，按钮“发送”；配对码对话框“输入“{name}”上显示的 6 位配对码”，六个格子（一个隐藏输入框，能粘贴），窄对话框里格子变窄 |
| c4 | 所有按钮都是“接收（描边）· 发送（实心）” | ✅ | 设备卡片和手动输入同一个 `_buttons`，高 48 |
| c5 | 拿不到地址写原因和下一步；停止时错误色 | ✅ | 断网图标圆 +“未获取到本机地址”+“请连接 Wi-Fi 或有线网络；Android 需要允许“附近设备 / 局域网”权限，然后点右上角开始”，不再写“扫描此二维码”；停止时“同步服务未运行”和图标用错误色 |
| c6 | 同步中进度条 | ✅ | 顶栏下 2 像素进度条，按钮变灰（v4 已有） |
| c7 | 设备写版本、按平台图标、分隔线 | ✅ | 手机 / 电脑 / 其他三种图标；“地址 · v4”或“3.x 版本的设备”；一张卡片里设备之间一条分隔线（不再卡片套卡片） |
| c8 | 对方请求写名字，按钮“拒绝 / 允许” | ✅ | 认得的设备写“设备 192.168.1.101（PureLive Windows）请求…”，不认得的照 v3 只写地址；点外面不能关 |
| c9 | 扫码页用 U.11a 同一个；输入框能扫码、粘贴链接 | ✅ | 提示“扫描另一台设备“设备同步”页上的二维码”；“手动输入地址”关掉扫码页并把光标放到地址框；相机不可用时写“请检查相机权限后重试，或者直接输入对方设备的地址。” |
| c10 | 组标题在卡片外，字号角色，复制地址 | ✅ | 组标题 13 号主色（同设置组）；“发现的设备”标题右边“正在搜索”转圈；地址 18 号 600、配对码 28 号等宽、字距 6 |
| c11 | 宽屏两列（S2） | ✅ | 宽 ≥840 且不是横屏手机（高度紧凑）时：左“我的设备”，右“发现的设备”“手动输入”，最宽 1120 居中；其余一列最宽 720 |

拿不准的第 2 条：服务没有区分“没连网络”和“没给权限”，说明文字两种都提（设计如此）。

## 没做：macOS 正式版权限文件（U.17b → U.11c）

v4 仓库没有 macOS 工程（`apps/pure_live/` 下只有 `android`、`windows`；计划书第 4 节 macOS“只设计，暂不构建”），没有 `macos/Runner/Release.entitlements` 可改。v3 的这个文件在 `~/ref/v3ref/macos/Runner/Release.entitlements`。以后建 macOS 工程时在 `Release.entitlements` 里加 `com.apple.security.network.server`（调试版 `DebugProfile.entitlements` 已有），需要主控记一笔。

## v3 文件 → v4 文件

| v3 | v4 |
|---|---|
| `modules/remote_receiver/remote_sync_page.dart` | `features/remote_receiver/remote_receiver_page.dart`（页面、配对码对话框、接收预览、选方向）；扫码页 `shared/qr_scan.dart` |
| `modules/remote_receiver/remote_sync_service.dart` | `features/remote_receiver/remote_sync_service.dart`（加 `fetch`、`apply`、`nameOf`，`receive` 仍在） |

## 新设置项

无（“同步账号 Cookie”仍是本页的临时开关，同 v3）。

## 门禁（`ui_baseline.json`）

- `remote_receiver` 直接写的颜色和图标 **11 → 0**；新图标 `syncStart`、`syncStop`、`syncRunning`、`syncNotRunning`、`devicePhone`、`deviceComputer`、`deviceOther`、`lanAddress`、`receive`、`send`。
- 没有新增跨功能引用（预览从 `shared/backup/` 来）。

## 测试

- `apps/pure_live/test/features/remote_receiver/remote_sync_test.dart`：4 → 12 个（原 4 个不改）。新增 8 个：竖屏说明、三组标题在卡片外、复制、配对码、开关、状态、搜索中；设备的平台图标、“地址 · 版本”、三对按钮都是接收在左发送在右；拿不到地址的说明、停止时错误色和“开始”图标；发送（写对方名字、六个格子、带码发送）；接收（先配对码、预览内容、确认后才写入）；对方请求（名字、拒绝 / 允许、点外面不关）；手机顶栏扫码、选方向、二维码带的配对码直接用、“手动输入地址”回到地址框；宽屏两列；横屏一列和 48 顶栏。
- 页面测试用一个记下发送和拉取的服务子类（`_FakeSync`）；真实的发送、接收、配对码仍由原来的服务测试覆盖。

## 全部测试（U.7b、U.11a～c 一起）

- `apps/pure_live`：`flutter test` 497 个，496 个通过，1 个失败：`iptv_page_test.dart` 的“one page: counts, playlists, guides…”断言“今天 HH:mm 更新”，它把页面时钟固定在 2026-10-01 20:00，而同步时间用真实时间；跑测试时已过零点（10-02 00:40），所以显示成日期。和这四个任务无关（没有改 iptv），白天跑应能通过，属时间相关的测试问题，建议 U.9 收尾时把同步时间也接到固定时钟。
- 新增和改动：U.7b 12 个（新文件），`recorder_page_test` −2；U.11a +11；U.11b +6；U.11c +8。
- `packages/live_ui`：91 个通过（原 88 个）。
- `flutter analyze`（`apps/pure_live`、`packages/live_ui`）无问题；`python3 tools/gate/check_ui_structure.py` 通过。
- 没有做 profile 帧时间（这四页是设置类页面，没有长列表和动画；WebDAV 和备份列表按需构建）。
