# U.14 系统界面（Android）

- 日期：2026-10-02
- 设计：[docs/ui/compare/U.14/README.md](../compare/U.14/README.md)（第 1 版，用户已确认；X1～X4 按建议 A）
- 和 F.0a 一起做（权限、分享接收、剪贴板口令、播放代理，记录 [F.0a](../../features/records/F.0a.md)）
- 范围：Android 的 c1～c15；c16（Windows、Linux 照 v3 不加系统通知、任务栏按钮、系统媒体控制）本来就不用改
- 改动的目录：`apps/pure_live/android/`（插件、服务、资源）、`lib/app/`、`lib/platform/`、`lib/shared/`、`features/settings/`（接上权限）、`features/live_play/logic/background_playback.dart`（见“和合并有关的”）、`packages/live_ui`（一个图标）、翻译
- 构建：`flutter build apk --debug` 通过（只构建，没有安装）

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 保留播放通知内容、类别、两个按钮；录制前台服务；系统画中画；分享的几条路；权限先说明再请求 | ✅ | 没动的照旧；分享接收和权限说明是 F.0a 新接的 |
| c2 | 通知小图标换成单色图：播放是电视，录制是录制圆点 | ✅ | `drawable/ic_stat_playback.xml`（设计的 GLYPH 转成矢量图）、`ic_stat_recording.xml`（Remix record-circle）；媒体通知 `androidNotificationIcon: 'drawable/ic_stat_playback'` |
| c3 | 录制通知写清楚、系统计时、类别名“录制”、点了打开录制中心 | ✅ | 一个：“正在录制 · 晚风 / 深夜电台 · 原画”；几个：“正在录制 N 个直播间 / 晚风、星河长明”；`setUsesChronometer` 从最早的开始时间走；Dart 在任务变化时算出文字，有变化才发（`AndroidRecordKeepAlive.refresh`），不每秒刷新；类别 `pure_live_recording` 改名“录制”（3.x 是 “Recording”，同一个 id，升级后名字跟着变） |
| c4 | “停止录制”（几个时“全部停止”）和“录制中心” | ✅ | “停止录制”经前台服务 → `stopAll` → 录制中心同样的 `stopTask`（已录的保存）；“录制中心”和点通知都打开 `RoutePath.kRecordPage` |
| c5 | 被系统停掉、录制失败时发“录制已停止” | ✅（有偏差） | 新类别“录制提醒”；Android 停掉服务（6 小时时限、被杀）一定发，别的失败只在应用不在前台时发（在前台时应用自己提示）；文字“系统给后台录制的时间用完了。已录下的 5:52:10 已保存，回到应用可以重新开始。”；按钮“打开录制中心”。**偏差**：点开只到录制中心，没有定位到那条任务（U.7a 的录制中心没有定位接口，不在本任务范围） |
| c6 | 媒体按钮名称中文 | ✅ | `mediaControls`：播放、暂停、停止（图标仍用 audio_service 的） |
| c7 | 画中画加“暂停 / 播放” | ✅ | `RemoteAction`，房间播放状态变化时更新（`PictureInPicture.bindPlayback`），点了回到 Dart 调房间的暂停、继续；进画中画、自动画中画、更新参数都带上 |
| c8 | 电视放大到约六成、加单色层 | ✅ | 前景内缩 16% → 2%（电视约占可见圆的 60%）；`<monochrome>` 用同一个电视矢量图（`ic_launcher_monochrome.xml`） |
| c9 | 系统启动画面同 U.3c 的底色、图标不带白圈、和启动页 Logo 一样大；13 起按应用的深浅色；11 及以下同底色 | ✅（有偏差） | 底色是默认主题（种子 2E6FE0）的表面色：浅 `#FAF8FF`、深 `#121318`；`windowSplashScreenAnimatedIcon` 用 `icon.png`，在 288 dp 的图标框里占 150 dp（和启动页 Logo 一样），不设图标底色所以没有白圈；13 起 `setSplashScreenTheme` 跟“主题模式”（跟随系统时用系统的）；11 及以下窗口底色同色。**偏差**：自选主题色、纯黑深色时仍是默认底色（系统启动画面拿不到应用的主题色，设计“拿不准”第 6 条） |
| c10 | 没有能打开的链接时提示“分享的内容里没有能打开的直播间链接”；只有文件格式不对才说“仅限 M3U 或 TXT” | ✅ | `ShareIntake` |
| c11 | 收到链接马上提示“正在打开分享的直播间…” | ✅（有偏差） | 用应用的提示条，**没有转圈**，3 秒后自己消失（不是“打开后消失”：提示条没有关闭的接口，在 `routes/` 里，不在可改范围）；解析失败、平台下线照 v3 |
| c12 | 权限说明用通用对话框，文字照 v3 | ✅ | `showPermissionDialog`：`AlertDialog` + `DialogButtonsTheme` + `DialogKeys`，标题左对齐，“取消”和主按钮在右下 |
| c13 | 永久拒绝时“通知权限已关闭”和“去设置”，回来再查一次 | ✅ | 文字照设计图；“去设置”打开本应用的通知设置，回到应用后再查，开了就把开关打开；还是关的就照 U.6c 红字 |
| c14 | 第一次录制而通知关着时说明一次；所有文件权限先说明 | ✅ | 见 F.0a 的 c6 |
| c15 | 长按图标：搜索直播、录制中心、最近看过的两个直播间 | ✅（有偏差） | 动态快捷方式（开发包的包名不同，静态快捷方式写不了包名），跟历史记录走，变了才更新。**偏差**：直播间用统一的电视图标，没有用主播头像（要下载头像，留到以后）；要先打开过一次应用才出现 |

## 和设计不同的地方

1. c5 点开不定位到任务（见上）。
2. c9 自选主题色时启动画面仍是默认底色。
3. c11 提示条没有转圈，3 秒后消失。
4. c15 直播间快捷方式没有头像；快捷方式是动态的。

## 测试

- `test/platform/system_surfaces_test.dart` 9 个：录制通知的文字（一个、几个、计时起点）；保活把文字发给 Android、没变不发、“停止录制”停全部、停了不再更新；“录制已停止”的文字；什么时候发提醒、每次失败只发一次、只停正在录的；媒体按钮中文；画中画按钮（变化才发、点了暂停 / 继续、离开房间去掉）；资源文件（小图标、启动图标内缩和单色层、启动画面的颜色和图标、快捷方式文字）。
- 分享提示（c10、c11）、权限对话框（c12、c13、c14）、快捷方式（c15）的测试在 F.0a 的记录里（`intake_test.dart`、`permission_prompts_test.dart`）。

## 要在 K90 上看的（原生部分，测试代替不了）

1. 状态栏：后台播放时是单色电视，录制时是录制圆点（不是白色圆块）；媒体卡片的按钮读屏念中文。
2. 录制一个、两个直播间：通知标题和文字、顶上的计时（HyperOS 的样子）、“停止录制 / 全部停止”能停、“录制中心”和点通知打开录制中心；系统设置里的通知类别是“纯粹直播播放”“录制”“录制提醒”。
3. 后台录制中让系统停掉（或强行停止服务）：出现“录制已停止 · 主播”。
4. 画中画点一下：有暂停 / 播放按钮，能用，图标跟着变；HyperOS 的画中画菜单可能不同。
5. 桌面：图标里的电视变大；原生 Android 13 起打开主题图标会变色（HyperOS 可能不读单色层）；长按图标出现搜索直播、录制中心和最近看过的两个直播间，点了都能到。
6. 冷启动：系统启动画面是浅色 `#FAF8FF`（深色 `#121318`）底加 Logo，没有白圈，接着的启动页底色一样；在设置里改主题模式后，下次冷启动跟着变。
7. 分享、权限见 F.0a 记录。

## 和合并有关的

- 改了 `features/live_play/logic/background_playback.dart`（c2、c6、c7 只能在这里接），只加不改原逻辑。
- `MainActivity.kt` 加了插件注册、画中画动作和接收器、`setSplashTheme`；`RecorderForegroundService.kt` 重写了通知部分（`RecordWords`）；`RecorderPlugin.kt` 加 `update`、`alert`、`stopAll`。
- 资源：`raw/keep.xml` 让发布版的资源压缩留住只在 Dart 里按名字用的 `ic_stat_playback`；新 `values-v31`、`values-night-v31`、`values-night/colors.xml`、`drawable-nodpi/splash_logo.png`（`assets/icons/icon.png` 的副本）和几个矢量图；`ic_launcher.xml`、`launch_background.xml`、`strings.xml` 改了。
