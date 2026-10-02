# T09a.5 通用和网络

- 日期：2026-10-02
- 设计：[docs/T09/T09a/T09a.5/README.md](README.md)（第 1 版，用户已确认；Y1～Y4 按建议 A）
- 一并处理的跨任务待同步：T17a.1 → T09a.5（“关闭窗口时：询问 / 最小化到托盘 / 退出应用”合成一项；开机窗口尺寸默认值 1280 × 720、范围跟窗口最小尺寸；“新建独立播放窗口”说明改成“首页菜单和直播间菜单里显示‘在新窗口打开’”）；T19a.1 → T09a.5（“界面刷新率”iPhone Pro 也显示）；T19b.1 → T09a.5（Mac 上不显示“关闭窗口时”）；T10a.2（“三方认证”改名“平台账号”，T09a.2 已做）；T06f.1（本地互动入口，T09a.2 已接到 `RoutePath.kLocalInteraction`，这次没有改动）
- 改动的目录、行组件、对话框见 [T09a.4.md](../T09a.4/record.md)（三个任务共用）

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| d1 | 四页和入口、设置项、3.x 键和默认值、平台差异 | ✅ | 键都没改；开机启动、开机窗口尺寸、关闭窗口时、新建独立播放窗口只在 Windows（Linux、macOS 照 v3 没有，是否加归 T17a.1）；界面刷新率在 Android、Windows 和高刷 iPhone / iPad |
| d2 | 通用页分显示、启动、更新、窗口（电脑）、定时退出 | ✅ | 组序和行序照图：界面刷新率 → 开机启动、开机窗口尺寸、启动动画 → 自动检查更新、GitHub 更新源 → 关闭窗口时、新建独立播放窗口 → 应用定时退出、退出前等待时间 |
| d3 | Windows 动态刷新率并进界面刷新率，“重新检测”放进对话框 | ✅ | Windows 的说明“当前显示器 1920 × 1080 · 60 Hz（最高 144 Hz），换显示器时自动更新”；对话框左下角“重新检测”（有显示模式通道的平台） |
| d4 | 档位写在右边，说明只写 Hz | ✅ | 右边“省电 / 均衡 / 最高”；手机说明“当前 60 Hz，最高 120 Hz”；对话框里每档“档位名 · 耗电”加 v3 的整段说明，顶上 v3 的提示 |
| d5 | “关闭窗口时”三选一，键不变 | ✅ | 每次询问 = `dontAskExit` 关；最小化到托盘 / 退出应用 = `dontAskExit` 开 + `exitChoose`；“最小化”照实际行为写“缩到托盘，直播照常”（有托盘时藏到托盘，否则最小化，`DesktopShell._close`） |
| d6 | 时长对话框统一 | ✅ | 和 T09a.4 的自动助眠同一个：标题和行名都是“退出前等待时间”，点快捷时长立即生效并关闭，当前值高亮，输入框“自定义时长”、“输入 1～525600 分钟”；定时退出开着时这一行的说明显示剩余时间（每秒只重建这一行） |
| d7 | 开机窗口尺寸“应用”实心按钮、写明立即生效、当前尺寸高亮 | ✅ | 预设 1080 × 720、1280 × 720（720P · 默认）、1600 × 900、1920 × 1080（1080P）、2560 × 1440（2K）；范围“宽度 400～16384 · 高度 300～16384；点‘应用’后窗口立即变成这个大小”，最小值取设置和 `DesktopShell.minimumSize` 里大的那个（T17a.1 改了窗口最小尺寸，这里自动跟上）；完成提示“设置已应用” |
| d8 | 平台页两组，首选平台带图标 | ✅（有偏差） | 平台、账号和标签两组照图。**偏差**：v4 自己加的三项（显示不可播放的直播、Twitch 语言筛选、斗鱼登录后强制续期，UPGRADES 已批准）设计里没有，保留为第三组“发现与列表”；原来这一页的 IPTV 链接去掉（总览“直播来源”组已有）；观看数据两行挪到视频页（T09a.4 c15） |
| d9 | 首选直播平台对话框：统一选项对话框、图标、搜索照 v3 | ✅ | 搜索框、“没有匹配的平台”；选项行同 T09a.4 的“主色 + 勾” |
| d10 | 刷新设置两组，间隔紧跟开关、关着时变灰写明 | ✅ | 关注列表（开启关注自动刷新、刷新间隔时间、返回应用时刷新关注、首页并发刷新任务）、直播缩略图（自动刷新直播缩略图、缩略图刷新间隔）；间隔照 v3 用选项对话框（12 档、8 档） |
| d11 | “返回应用时刷新关注” | ✅ | 新键 `settings_refresh_on_resume`；说明“从后台返回应用时自动刷新关注列表” |
| d12 | 并发数行内加减 1–20，说明写默认和建议值 | ✅ | 计数行，按住连续变，点数字可输入 |
| d13 | 网络页统一行，地址端口关着时变灰不消失，≥420 并排 | ✅ | 开关用设置行；输入框关着时变灰；宽 ≥420 地址和端口 3:2 并排；输入停 0.5 秒后保存（v3 每个字写一次）；端口不在 1–65535 时框下红字、不保存 |
| d14 | 网络页可直接打开并定位到播放器内核代理 | ✅ | 内核页那一行打开网络页并高亮“启用播放代理”；`SettingsSection.byName('network')` 照旧可以从路由参数打开 |

## 和设计不同的地方

1. 平台页多一组 v4 自己的平台选项（见 d8）。
2. 刷新页末尾保留 v4 的“历史记录”一组（观看记录上限，3.x 的 `historyLimit`），设计图没画。
3. 苹果平台：iOS 上界面刷新率只在显示器高于 60 Hz 时出现（`SettingsEnv.fastDisplay`，读 Flutter 的显示器刷新率）；v4 没有 iOS 的显示模式通道，说明里的 Hz 用系统报告的刷新率。macOS 的“登录时打开”（T19b.1）没有做：开机启动这一行现在只在 Windows。

## v3 文件 → v4 文件

| v3（`lib/modules/settings/pages/`） | v4（`features/settings/`） |
|---|---|
| `general_settings_page.dart` | `settings_catalog.dart`（通用一节）、`settings_editors.dart`（`RefreshRateTile`、`StartupTile`、`WindowSizeTile`、`CloseWindowTile`、`AutoExitTile`、`AutoExitMinutesTile`、`AutoExitTimer`） |
| `platform_settings_page.dart` | `settings_catalog.dart`（平台一节）、`settings_editors.dart`（`PreferPlatformTile`） |
| `refresh_settings.dart` | `settings_catalog.dart`（刷新一节）、`settings_tiles.dart`（`SettingCounterTile`） |
| `network_proxy_settings_page.dart` | `settings_catalog.dart`（网络一节）、`settings_editors.dart`（`ProxyEditorTile`） |
| `plugins/utils.dart` 的关窗口询问 | 设置项在 `CloseWindowTile`；对话框本身在 `app/desktop/desktop_window.dart`（T17a.1，没改） |

## 需要 T17a.1 知道的

- 关窗口的设置照旧写 `dontAskExit` + `exitChoose`，`DesktopShell._close` 不用改。
- 开机窗口尺寸对话框的最小值读 `DesktopShell.minimumSize`（现在 400 × 300）；T17a.1 把窗口最小改成 360 × 400 后，这里的范围说明自动变成“宽度 400～16384 · 高度 400～16384”（宽度仍受设置的最小 400 限制）。

## 测试

- `apps/pure_live/test/features/settings/settings_general_test.dart`：9 个——手机通用页四组和行序、刷新率档位在右边和 Hz 说明、对话框选档；定时退出（剩余时间在等待时间行、时长对话框快捷时长、关掉停止）；Windows（五组、关闭窗口时三选一写两个键、窗口尺寸预设高亮、超出范围、应用和提示）；iOS 高刷才显示刷新率；平台页两组、图标、搜索和空结果、选平台、标签跳路由；刷新页（变灰写原因、12 档对话框、计数加减）；按住连续加；网络页（关着时变灰、输入保存、端口红字不保存、窄屏上下排、宽屏并排）。
- 原 `settings_page_test.dart` 里“其他页面保留原来的行”一组改名为“playback, general and data pages”，三个用例照旧通过。
