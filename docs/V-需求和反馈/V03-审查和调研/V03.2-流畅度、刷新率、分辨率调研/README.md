# V03.2 流畅度、刷新率、分辨率调研（2026-10-02）：Android 滑动流畅度、刷新率和分辨率适配调研报告

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：性能（调研）
- 来源：用户 2026-10-02 要“上下滑动、左右滑动的流畅度、阻尼感”，并要求调研刷新率和分辨率适配（和问题 01～09 同一天，[V02.2](../../V02-用户反馈和issue/V02.2-用户10月2日的问题/README.md)）；旧文档 `docs/4.0.x/research-smoothness-2026-10-02.md`（标签 `docs-archive-2026-10-02`）
- 相关：决定 D-009（方案 A：能下拉刷新的列表照 3.x 两端回弹）、D-010（刷新率策略）、D-020（往上甩面板不关闭）；去向见文末“结果”

任务拆分见 [TASKS.md](../../../TASKS.md) 的“流畅度和适配”一节（R02.2～A04.1）；报告里的 S5、R5 并进了 D04.1。

- 日期：2026-10-02。代码：master `fb0537cba`，下文路径都相对仓库根目录。仓库只读，没有改动。
- K90 的数据来自今天的只读 adb 查询（`dumpsys display`、`dumpsys SurfaceFlinger`、`getprop`、`settings list`）。没有装包，也没有任何点按。
- 第 2.2 节的滑行数字，是把本机 Flutter 3.47.5 源码里的公式代进去算出来的。

---

## 0. 结论（按影响排序）

| # | 发现 | 改哪里 | 影响 |
|---|---|---|---|
| 1 | **v4 主列表的手感和 v3 不一样。** v3 的热门、分区房间、历史列表套在 `EasyRefresh(child:)` 里，自己没写 physics，所以实际用的是 `_ERScrollPhysics`：它继承 `BouncingScrollPhysics`，两端回弹，按 iOS 方式减速，没有拉伸效果。v4 全部换成了 Android 的 Clamping + 拉伸，下拉刷新也从 v3 的经典头变成了 Material 圆圈。A02.1 c19 已经确认要用经典头，但还没开发 | `shared/rooms/room_grid.dart:599,666,740,746`，以及另外 6 处 `RefreshIndicator` | 最高：这是最常用的滑动面 |
| 2 | 自建拖动松手后速度断开：有的用固定时长曲线（220 ms、180 ms），侧面板干脆直接跳回原位 | `room_swipe.dart:94-111,182`、`portrait_panel.dart:167-173`、`side_panel.dart:66-71`、`room_details.dart` | 高 |
| 3 | 播放时，R02.1 已经在 Flutter 画面上调用 `Surface.setFrameRate`。Android 文档写明，这种 Surface 会忽略窗口的 `preferredRefreshRate`，所以“均衡档操作时升到整数倍里最高”这一步不是我们的请求在起作用 | `MainActivity.kt:771-835`、`platform/display_mode.dart:212-230` | 高 |
| 4 | K90 只有 60/90/120 Hz。25/50 帧没有整数倍，24 帧只有 120 是整数倍；均衡档空闲时 `playbackRefreshRate` 返回 null，交给系统去选 | `platform/display_mode.dart:134-141` | 中高（网络电视、部分直播） |
| 5 | 6 个 TabBarView 翻页用的是 Flutter 默认弹簧（质量 0.5、刚度 100、阻尼比 1.1，大约 0.5 秒才停稳），而且速度过 50 dp/s 就翻页；点标签的动画却只有 220 ms | `live_ui/.../scrolling.dart` | 中高 |
| 6 | 竖屏面板拖动时，每帧都对整个布局 setState，还会重新调用 `player(covered)`，`RoomPlayer` 每帧重建 | `portrait_panel.dart:172`、`live_play_page.dart:1118` | 中高 |
| 7 | 聊天列表每来一条消息就 setState，再在帧后 `jumpTo(maxScrollExtent)` 一次 | `danmaku/chat_list.dart:150-166` | 中（弹幕密集时） |
| 8 | 自建拖动到头就硬停；快滑阈值有 600/800/850/900 四种 | `room_swipe.dart:70`、`side_panel.dart:63`、`logic/room_layout.dart:166-215` | 中 |
| 9 | 有 8 个文件用整屏尺寸判断高度紧凑（`MediaQuery.sizeOf(context).height < 480`），代码里没有高度分档的定义；分屏、小窗、折叠屏铰链都没处理 | `live_ui/.../grid_columns.dart` 和这 8 个页面 | 中 |
| 10 | 厂商把应用压在 60 Hz 时，用户无从得知 | `settings_catalog.dart`、`display_mode.dart` | 中 |
| 11 | 应用字号乘系统字号，最坏能叠到大约 4 倍；直播间详情的拖动把手只有 20 dp 高 | `app/app.dart:247-252`、`room_details.dart:118` | 中低 |
| 12 | 几处小的绘制开销：浮窗拖动时给视频加了 80% 透明、加载转圈用 ShaderMask、亮度和音量每次手指移动都调一次平台方法、封面用 ClipRRect 裁圆角、搜索平台条关掉了拉伸效果 | 见第 4 节 | 低 |

---

## 1. 刷新率

### 1.1 屏幕和系统机制

| 刷新率 | 每帧 | 常见在哪 | 说明 |
|---|---|---|---|
| 30 / 48 | 33.3 / 20.8 ms | LTPO 屏的空闲档；部分 144 Hz 屏带 48/72 Hz 模式 | 一般不作为模式让应用选，由系统或屏幕在空闲时自己降 |
| 60 | 16.7 | 所有机型；省电模式和发热限制时 | 基线 |
| 90 | 11.1 | 中端机；K90 也有 | 60 帧视频会 2、1 交替 |
| 120 | 8.3 | 主流旗舰；K90 | 24/30/60 帧都能整除 |
| 144 | 6.9 | 游戏手机、部分旗舰 | 60 帧会 2、3 交替 |
| 165 | 6.1 | OnePlus 15 | 2025-12 只对 3 个应用开放 |
| 185 及以上 | 5.4 | ROG Phone 9 Pro | 只在 Game Genie 游戏模式下可用；夏普 240 Hz 是老机型 |

- **LTPO**：画面不动时屏幕自己降到 1–10 Hz（Xperia 1 VI 是 1–120，ROG 9 是 1–185）。
- **ARR（自适应刷新率，Android 15 QPR1 起）**：用 `Display.hasArrSupport()` 判断设备是否支持。
  - 系统汇总各个 View 的投票：类别 NORMAL（约 60 Hz）、HIGH，或者具体数值。
  - 触摸会临时升高，fling 时随速度逐渐回落（需要 View 报告 `setFrameContentVelocity`）。
  - 文档原意：小动画不需要高刷，高刷只会更耗电。

| 接口 | 系统版本 | 作用 | 本仓库 |
|---|---|---|---|
| `LayoutParams.preferredRefreshRate` | 6+ | 窗口希望的刷新率。只改刷新率时，官方推荐用它而不是 `preferredDisplayModeId`。**用了 `setFrameRate()` 的 Surface 会忽略它** | 三档策略 + R02.1（`MainActivity.applyPreferredDisplayMode`） |
| `preferredDisplayModeId` | 6+ | 直接指定显示模式，可能触发较重的模式切换 | 固定为 0（沿用 v3） |
| `Surface.setFrameRate(fps, compat, strategy)` | 11+；strategy 参数 12+ | 视频用 `FIXED_SOURCE`；游戏用 `DEFAULT`；界面和滚动用 **`AT_LEAST`（16+）**。默认 `ONLY_IF_SEAMLESS`。暂停时传 0 清除。系统可能选声明值的整数倍，也可能根本不采纳 | R02.1：对 Flutter 的 SurfaceView 声明，只在 12+ |
| ARR 相关：`View.setRequestedFrameRate`、`Window.setFrameRateBoostOnTouchEnabled`、`setFrameContentVelocity` | 15 QPR1+ | 按 View 投票 | 没用。Flutter 的画面不是普通 View，系统看不到它内部的动画和滑动 |
| 游戏默认 60 Hz | 15+ | `appCategory=game` 的应用默认被压到 60 | 没声明 game，保持 |
| SurfaceFlinger 的触摸计时器、空闲计时器、内容检测 | 系统 | 触摸后一段时间内用默认最高刷新率；没有画面更新就降到最低；应用没声明时按图层的更新频率猜 | — |

### 1.2 Flutter 在 Android 上怎么选刷新率

- **引擎自己不投票。** 它跟着 Choreographer 的 vsync 出帧，引擎里没有调用 `setFrameRate`。
  - [#160952](https://github.com/flutter/flutter/issues/160952)（P2，未关闭）：Poco F5、红米等机型上 Flutter 应用被锁在 60 Hz。
  - [#119268](https://github.com/flutter/flutter/issues/119268)（2023-01 至今未关闭）：给应用一个设首选刷新率的接口。
  - [#35162](https://github.com/flutter/flutter/issues/35162)（2020 年关闭，结论是“暂时用 flutter_displaymode”）。
  - 遇到“应用不声明就给 60”的厂商策略时，只能应用自己请求。现有办法有三种：flutter_displaymode（用 `preferredDisplayModeId`，可能触发重切换）、refresh_rate（对 FlutterSurfaceView 投票，窗口兜底）、或者像本仓库这样自己写通道。本仓库的方向是对的。
- **动画按时间计算**，换刷新率不影响速度。可变刷新率下，引擎会把倒退的时间戳夹住，于是可能连续两帧时间戳相同（[#190372](https://github.com/flutter/flutter/issues/190372)，2026-07 提出）。按“每帧时间差累加”的动画（`danmaku_overlay.dart:388`）会出现一帧不动、下一帧走双步。
- **视频是纹理。** mpv 画进 SurfaceProducer，系统只看到 Flutter 这一个 Surface，所以帧率必须声明在 Flutter 画面上（R02.1 已做）。另外，视频每出一帧，引擎都要把上一棵图层树整屏重新光栅化一次（不跑 Dart 的 build）。直播间画面上其他东西越省，视频越稳。
- **Impeller**：3.27 起在 Android 10+（Vulkan）默认开启，着色器和渲染管线在构建时就预编译好了。本仓库 `minSdk 26`，所以 8.x 和 9 会回退到旧的 GL 渲染器。

### 1.3 K90 实测（只读）

- **系统**：Android 17，HyperOS OS4.0.0.33（beta）。1200×2608，480 dpi，缩放 3.0，逻辑尺寸 400×869 dp；顶部挖孔 144 px（48 dp）。
- **显示模式**：只有 **60 / 90 / 120 Hz** 三种，属于同一组，`alternativeRefreshRates` 互相包含，所以三者之间切换都是无缝的。没有 24/48/50/100/144。
  - `hasArrSupport=false`。
  - `frameRateCategoryRate normal=60, high=90`：如果用类别投票，HIGH 在这台机上只给 90，所以要投具体数值。
- **SurfaceFlinger**：内容检测开，触摸计时器 1500 ms，空闲计时器 1100 ms（由平台控制），`enableFrameRateOverride=false`；`game_default_frame_rate_override=60`。
- **DisplayModeDirector**：
  - 有一个 `PRIORITY_MIUI_REFRESH_RATE` 投票，历史记录里上限在 60 和 120 之间来回切。这是 HyperOS 自己的策略，`mAlwaysRespectAppRequest=false`，应用的请求压不过它。
  - 设置项：`user_refresh_rate=120`、`is_smart_fps=0`、`peak_refresh_rate=120`、`thermal_limit_refresh_rate=0`。
  - 推测（待验证）：播放视频时，HyperOS 可能按场景把上限压到 60。
- **对 R02.1 两条“拿不准”的回答**：
  - 第 1 条（K90 支持哪些刷新率）：只有 60/90/120，没有 50/100。
  - 第 2 条（帧率声明和窗口提示同时存在怎么取舍）：按 Android 文档，窗口提示对已声明的 Flutter 画面无效；触摸时能不能升到 120，取决于系统的 1.5 秒触摸加速。

### 1.4 视频帧节奏（每帧停留几个刷新周期）

| 视频 | 60 Hz | 90 Hz | 120 Hz | 144 Hz | 165 Hz |
|---|---|---|---|---|---|
| 24 | 3,2 | 4,4,4,3 | **5（均匀）** | **6（均匀）** | 7…7,6 |
| 25 | 2,3,2,3,2 | 4,3,4,3,4 | 5,5,5,5,4 | 6,6,6,5… | 7,6,7,6,7 |
| 30 | **2** | **3** | **4** | 5,5,5,5,4 | 6,5 |
| 50 | 1,1,1,1,2 | 2,2,2,2,1 | 2,3,2,3,2 | 3…3,2 | 3,3,4 |
| 60 | **1** | 2,1 | **2** | 2,3,2,3,2 | 3,3,3,2 |
| 不均匀时的抖动幅度 | 16.7 ms | 11.1 | 8.3 | 6.9 | 6.1 |

规则：

- 优先选整数倍。
- **没有整数倍时选最高的刷新率**：抖动幅度就是一个周期，周期越短越不明显。25 帧在 120 Hz 下的误差（8.3/40 ≈ 21%）只有 60 Hz 下（42%）的一半。
- 视频只用 `FIXED_SOURCE` 声明，暂停时清 0。
- Flutter 的光栅线程要留出余量：纹理帧赶不上 vsync 截止时间，就会多停一个周期。

K90 的建议策略（改的是 R02.1 已经定下的策略，要在对比页确认）：

| 视频 | 省电（只声明帧率，系统选） | 均衡：空闲 / 操作中 | 最高 |
|---|---|---|---|
| 30、60 | 声明（系统多半选 60） | 60 / 120 | 120 |
| 24 | 声明 | 现在交给系统 → 建议 120 / 120 | 120 |
| 25、50 | 声明 | 现在交给系统 → 建议 120 / 120 | 120 |

### 1.5 耗电

- 高刷耗电主要来自屏幕本身和每帧的渲染。LTPO 屏在画面不动时会自动降，前提是**没有持续出帧**。
- 持续出帧的来源：一直转的加载动画、顶部的进度条、空转的 Ticker。弹幕层没有弹幕时会停（D03.1），这一点已经做到。
- 播放 30/60 帧时，空闲用 60、操作时用 120，是对的：弹幕每个刷新周期都要画，120 Hz 下弹幕的光栅工作量翻倍。
- “最高”档一直用最高刷新率，会明显更耗电，默认保持“省电”。

### 1.6 厂商差异：能做什么，做不到什么

| 厂商 / 系统 | 已知行为 | 应用能做 | 做不到 |
|---|---|---|---|
| 小米、红米、POCO（MIUI / HyperOS） | 系统按应用或场景投票限制上限（K90 实测）；MIUI 早期部分应用最高 60，MIUI 14 起设置里可以强制 120；Flutter #160952 报告的就是这些机型 | 请求；读当前值；提示用户去“设置 → 显示 → 屏幕刷新率” | 绕过系统投票 |
| OnePlus、OPPO、realme | 名单制：不在名单的应用请求被忽略、固定 60（OxygenOS 11 起，ColorOS 化之后 AutoHz 也失效了）；OnePlus 15 的 165 Hz 只对 3 个应用开放 | 同上 | 进名单 |
| 三星 One UI | 旗舰全屏播视频时自动降到 60；One UI 7 起 Good Lock 的 Display Assistant 可以按应用锁 60；游戏归 Game Booster 管 | 声明视频帧率；不把自己声明成游戏 | 用户或系统锁 60 后再提高 |
| 游戏手机（ROG、红魔） | 185 Hz 只在游戏模式；支持的模式列表里可能有 144/165/185 | “最高”档不必追最高模式；视频按整数倍选 | 普通应用用上 185 |
| 原生 Android 15 QPR1+ 带 ARR 的机型 | 默认约 60，靠触摸和 View 报告的 fling 速度升高；Flutter 内部的滑动系统看不见 | 16+ 用 `AT_LEAST` 声明；滚动过程中持续请求（均衡档已经这样做） | 让系统看见 Flutter 内部的动画 |
| 所有机型 | 省电模式、发热都会锁 60 | 读当前值，不做假设 | — |

### 1.7 刷新率改动清单

| 优先级 | 改动 | 怎么验证（工具 / 指标 / 通过标准） |
|---|---|---|
| 高 R1 | 播放中统一走 `Surface.setFrameRate`，不再靠窗口提示。<br>• 播放 + 操作中：声明“整数倍里最高”（如 120）、`FIXED_SOURCE`。<br>• 操作结束：回到视频帧率。<br>• 不播放 + 均衡档操作中或最高档：16+ 用 `setFrameRate(最高, AT_LEAST)`；11–15 保留窗口提示。<br>改 `MainActivity.kt` 的 `applyVideoFrameRate`/`setHighRefreshRate`，以及 `display_mode.dart` 的 `_applyRate` | K90，60 帧直播，均衡档。开开发者选项“显示刷新率”；`adb shell dumpsys SurfaceFlinger \| grep -E "renderRate\|activeMode="`；`dumpsys display` 看 mVotes。<br>通过：拖聊天或面板后 100 ms 内到 120，松手 1.5 s 内回 60，进出直播间不黑屏。<br>要分清是系统触摸计时器的作用还是我们的请求（可选：root 下临时把 `debug.sf.set_touch_timer_ms` 设为 0，测完恢复） |
| 中高 R2 | `playbackRefreshRate`：没有整数倍时取最高；24 帧取 120；同时更新 `room_refresh_rate_test.dart` | 用 ffmpeg 生成带帧号的 24/25/50/60 帧 HLS（`-f lavfi -i testsrc2=rate=25`），`python3 -m http.server` 放出来，网络电视导入 m3u 在 K90 播放。用另一台手机 240 fps 慢动作拍屏，数每帧停留几个周期。<br>通过：120 Hz 下 25 帧只出现 5 和 4；60 帧只出现 2 |
| 中 R3 | 检测厂商限制：均衡档触摸中或最高档时，请求 ≥90 但 `currentRefreshRate` 持续 3 秒是 60，就在“界面刷新率”那一行加提示 | K90 系统刷新率改成“标准”时出现提示，改回“高”时消失 |
| 中低 R4 | 带 ARR 的机型：16+ 用 `AT_LEAST`；要投具体数值，不投类别 | 在 Pixel（Android 16，`hasArrSupport=true`）上连续 fling 3 秒，刷新率不中途掉到 60 |
| 低 R5 | 弹幕层遇到时间差为 0 的帧时跳过、不补偿 | 单元测试喂相同时间戳，位移平滑；可变刷新率机型上用 Perfetto 看 |
| 低 R6 | 保持不声明 `appCategory=game`（Android 15 起游戏默认 60） | 检查 manifest |

---

## 2. 滚动和手势

### 2.1 原生 Android 和 Flutter 3.47.5 对照

| 项 | Android 原生 | Flutter | 本仓库 |
|---|---|---|---|
| 列表到头 | 12 起是拉伸效果 | `MaterialScrollBehavior` + Material 3 → `StretchingOverscrollIndicator`。PR [#173849](https://github.com/flutter/flutter/pull/173849)（2025-12 合并，3.47.5 已包含）移植了 Android 12 的拉伸模拟，快甩到头时也有拉伸 | `AppScrollBehavior` 继承它；`search_widgets.dart:100` 单独关掉了 |
| 滑动减速 | OverScroller 的 spline 曲线，摩擦 0.015 | `ClampingScrollSimulation` 照搬 Android 公式 | `PureLiveScrollPhysics` 在 Android 上用 Clamping |
| iOS | 回弹 | `BouncingScrollPhysics`：越界阻力 0.52(1−x)²；减速是 `FrictionSimulation(0.135)` | iOS、macOS 用 |
| 起拖阈值 | ViewConfiguration 的触摸阈值（通常 8 dp） | 默认 `kTouchSlop` 18，但在 Android 上会用系统给的 `gestureSettings.touchSlop` | 继承 |
| 快滑速度 | 最小 50、最大 8000 dp/s | `kMinFlingVelocity` 50、`kMaxFlingVelocity` 8000 | 继承 |
| 翻页 | ViewPager：速度 ≥400 dp/s 且位移 ≥25 dp 才算快滑，否则要拖过 60%；回位时长 = 4 × 距离 ÷ 速度，最多 600 ms，五次方减速 | `PageScrollPhysics`：速度超过很小的容差就翻页，否则过半才翻；回位用默认弹簧（约 0.5 秒停稳） | 6 个 TabBarView 都用默认 |
| 面板 | — | BottomSheet / Dismissible：≥700 dp/s 算快滑；BottomSheet 过半就关；fling 用质量 1、刚度 500 的临界阻尼弹簧 | `adaptive_panel` 用 Material 的；自建面板是 600/850/900 |
| 弹簧规范 | Material 3：快 0.9/1400、默认 0.9/700、慢 0.9/300（位置类）；效果类 1/3800、1/1600、1/800 | `SpringDescription.withDampingRatio` | 没有统一常量 |

### 2.2 用户期待的“阻尼感”

- **国内系统应用**（HyperOS、ColorOS 等）到头是“越拉越沉、松手回弹”的橡皮筋。
  - 社区移植的 HyperOS 实现（compose-miuix-ui，不是官方）：位移 = R·(x − x² + x³/3)，x = 原始位移 ÷ R，R 是窗口高度，最多拉出 R/3。
  - 回弹是临界阻尼弹簧，周期 0.4 秒（高速时 0.55 秒）；fling 进入越界时速度除以 1.53。
- **原生 Android 12+** 的拉伸效果也是越拉越沉，只是视觉不同。
- **用户真正在意的五点**：
  1. 跟手：1:1，起拖时不跳。
  2. 松手不断速。
  3. 到位时没有拖尾。
  4. 到头有阻力，而不是硬停。
  5. 下拉刷新有手感。
- **v3 的实际手感**（v3 用户的肌肉记忆）：
  - 热门、分区房间、历史：`_ERScrollPhysics`（`easy_refresh-3.5.1/lib/src/physics/scroll_physics.dart:10`，在 `:492` 创建 `BouncingScrollSimulation`），`ERScrollBehavior.buildOverscrollIndicator` 不画拉伸。下拉是经典头，内容会跟着往下走；关注页是 `MaterialHeader(clamping: true)`。
  - 其他页面是 Clamping。
- **两种减速的差别**（按 Flutter 源码公式算，单位 dp）：

| 松手速度 | v4（Clamping，Android） | v3 主列表（Bouncing，iOS） |
|---|---|---|
| 500 dp/s | 58 dp，0.28 s 停 | 250 dp，约 2.2 s 停 |
| 1000 | 194 dp，0.46 s | 499 dp，约 2.5 s |
| 3000 | 1309 dp，1.03 s | 1498 dp，约 3.0 s |
| 6000 | 4361 dp，1.71 s | 2996 dp，约 3.4 s |

### 2.3 推荐参数（放进新文件 `packages/live_ui/lib/src/theme/motion.dart`）

| 场景 | 物理 / 参数 |
|---|---|
| 普通列表（设置、详情等） | Clamping + 拉伸（同 v3），friction 0.015，快滑速度 50–8000，不叠加连续 fling 的动量 |
| 刷新类房间列表（S1，需确认） | 方案 A 照 v3：Bouncing 系，两端回弹，不画拉伸，经典下拉头。触发距离 = 头部高度（v3 的 `layout.height`），回弹弹簧质量 1、刚度 500、阻尼比 1 |
| 自建拖动的越界 | 橡皮筋 d = R·(x − x² + x³/3)；回弹用临界阻尼，刚度约 250（周期 0.4 s） |
| 标签页、横向翻页 | 弹簧质量 1、刚度 600、阻尼比 1（约 0.27 秒停稳，和点标签的 220 ms 对齐）。快滑要求速度 ≥400 dp/s 且位移 ≥25 dp（照 ViewPager），否则过半才翻 |
| 竖屏全屏上下切房间 | 1:1 跟手。阈值保持现在的 1/3 屏，或 ≥800 dp/s 且 ≥48 dp。弹簧质量 1、刚度 400、阻尼比 1，带上松手速度，夹住目标不过冲。松手时就开始连新房间（现在要等 220 ms 动画结束） |
| 面板（三档、侧面板、详情） | 1:1 跟手，越界加阻尼。v3 来的阈值保留（`room_layout.dart:166-179` 的 30% 夹在 72–144、900、28、64、850、24）。v4 自己定的 600 改成 700（和 Flutter BottomSheet 一致）。弹簧质量 1、刚度 500、阻尼比 1（和 BottomSheet 的 fling 相同） |
| 小控件 | Material 3 快速：0.9 / 1400 |

### 2.4 仓库里所有自建的滚动物理、配置和手势

| 位置 | 内容 |
|---|---|
| `packages/live_ui/lib/src/widgets/scrolling.dart` | `PureLiveScrollPhysics`（按平台选 Clamping/Bouncing）、`PureLiveBoundedScrollPhysics`（Clamping，内容变短时夹住位置）、Windows 滚轮控制器、`PureLiveRouteScrollScope`、`pureLiveTabTransitionDuration=220ms` |
| `apps/pure_live/lib/app/app.dart:284-305` | `AppScrollBehavior`：Material 行为（拉伸），鼠标不能拖动列表 |
| `live_ui/.../scrollable_tab_bar.dart:147,220` | 标签条自己的滚动行为（鼠标可以拖），加滚轮横滚 |
| `features/search/search_widgets.dart:100` | `overscroll:false`（只有这一条横条没有拉伸） |
| 直接写 physics 的地方 | `settings_dialogs.dart:52` 和 `tv/widgets/tv_grid.dart:236` 是 Clamping；`platform_areas_view.dart:242`、`room_details.dart:165` 是 AlwaysScrollable；嵌套网格里的 NeverScrollable 有 7 处 |
| TabBarView | `popular_page.dart:211`、`favorite_page.dart:258`、`favorite_areas_view.dart:138`、`platform_areas_view.dart:176`、`chat_panel.dart:109`、`room_switcher.dart:103`；`areas_page.dart:180` 是 NeverScrollable，只能点标签切换（照 v3，避免两层横滑打架） |
| 下拉刷新（`RefreshIndicator`） | `room_grid.dart:666,746`、`favorite_page.dart:549`、`history_page.dart:415`、`platform_areas_view.dart:262`、`web_dav_page.dart:515,535`、`backup_page.dart:294` |
| `player/player_gestures.dart:196-212` | 画面上下滑：左半边亮度、右半边音量；有切房间时分三栏；底部 96 区域上滑退出；滚轮调音量 |
| `player/room_swipe.dart` | 竖屏全屏切房间：没有邻居时硬夹（:70），220 ms easeOutCubic 回位（:94-111,182） |
| `player/player_view.dart:715-730` | `_SwipeUpRegion`：底栏上滑回到面板 |
| `layout/portrait_panel.dart:224-241` | 三档面板把手：`DragStartBehavior.down`，`AnimatedPositioned` 180 ms |
| `layout/room_details.dart:70-125` | 越界下拉关闭（64）；把手拖动（600）；把手 20 dp 高 |
| `shared/panels/side_panel.dart:62-71,119-124` | 标题栏下拉关闭（72/600），回位不带动画 |
| `mini/floating_window.dart:170-200`、`mini/mini_player.dart:233-240` | 浮窗拖动：每次移动 setState，拖动时 80% 透明 |
| `live_ui/.../adaptive_panel.dart` | Material 底部面板（参考基准） |
| `danmaku/chat_list.dart:142-166` | 跟随到底部、`jumpTo` |
| 拖动排序 | `tags_page.dart:276`、`hot_areas_page.dart:227`、`appearance_pages.dart:1196` |
| 其他 | `color_picker.dart:445,458` 的平移拖动；`refresh_rate.dart:213` 被动监听指针 |

### 2.5 滚动和手势改动清单

| 优先级 | 改动 | 怎么验证 |
|---|---|---|
| 最高 S1 | 先定主列表的手感：A 照 v3（Bouncing + 经典头）、B 保持 v4、C 混合（Android 减速 + 两端回弹）。建议 A（原则 1；国内系统应用也是回弹）。在 A02.1 开发中做成一个 live_ui 组件，替换上面 7 处 `RefreshIndicator`；不要整体换成 `BouncingScrollPhysics` 再到处套 | 单元测试固定 500/3000/6000 dp/s 的滑行距离和时长（和上表误差 <1%）；K90 上请用户对比主观手感；下拉的位移–手指距离曲线单调变沉，到头部高度触发，回弹 ≤400 ms |
| 高 S2 | `room_swipe` 回位、三档面板、侧面板、详情面板全部改成带松手速度的弹簧：`AnimationController.unbounded` + `animateWith(SpringSimulation(...))`，夹住目标 | widget 测试：松手后第一帧位移和松手前最后一帧之比在 0.8–1.25 之间，停稳 ≤350 ms；K90 profile 模式下 DevTools 没有红帧 |
| 中高 S3 | 新建 `PureLivePageScrollPhysics` 给 6 个 TabBarView 用：覆盖 `spring`、`minFlingVelocity=400`、`minFlingDistance=25`。不要改 Bounded，标签条也在用它 | 测试：300 dp/s 不翻页、600 dp/s 翻页，停稳 ≤300 ms；K90 斜着上下滑 20 次，一次也不误翻 |
| 中高 S4 | 三档面板：按 `covered` 缓存 player，或者把拖动状态放进只包住面板的子组件 | DevTools 的 Track widget builds：拖 2 秒，`RoomPlayer` 重建 0 次；120 Hz 下 UI 线程 P90 ≤4 ms |
| 中 S5 | 聊天列表改成 `reverse:true`（索引反转），去掉 `jumpTo`；更新合并成每帧一次（或约 15 Hz）；表情只解析一次 | D03.1 的假弹幕源每秒 200 条、持续 60 秒：UI 线程 P90 ≤3 ms（计划书 9.4）；跟随最新时不跳，往上翻时列表不动 |
| 中 S6 | `room_swipe.dart:70`、`side_panel.dart:63` 等硬停处改成橡皮筋；阈值做成常量（v3 来的保留，v4 自己定的统一，需要在对比页确认） | 测试：越界位移单调、不超过 R/3、400 ms 内回到 0 |
| 中 S7 | 详情面板：把手热区扩到 48 dp，下拉时面板跟手，用弹簧关闭 | `meetsGuideline(androidTapTargetGuideline)`；拖 30 dp 时面板跟着移动 30 dp |
| 低 S8 | `portrait_panel.dart:236` 改成 `DragStartBehavior.start`，去掉起拖时约 8 dp 的跳动 | 测试：越过起拖阈值后第一帧位移 ≤1 dp |
| 低 S9 | 亮度和音量合并成每帧最多一次平台调用（`player_gestures.dart:189`） | Perfetto：主线程 binder 调用每个 vsync ≤1 次 |
| 低 S10 | 搜索平台条和其他横条的拉伸效果统一 | 目测 |
| 实验 S11 | 1:1 拖动试开 `GestureBinding.instance.resamplingEnabled`（触摸采样率和刷新率不成整数倍的机型） | 慢动作视频对比抖动和延迟，再决定开不开 |

---

## 3. 分辨率、密度和窗口

### 3.1 设备落到哪个尺寸分档（计划书 5.1）

| 设备 | 缩放 | 逻辑尺寸（dp） | 宽 / 高分档 | 注意 |
|---|---|---|---|---|
| 720p 手机 | 2.0（xhdpi） | 360×800；横屏 800×360 | 紧凑/中等；横屏 中等/紧凑 | 横屏按“横屏手机”排 |
| 1080p 手机 | 2.625–3.0 | 360–411 × 800–915 | 紧凑/中等 | — |
| K90 | 3.0 | 400×869；横屏扣掉挖孔 48 → **821** 宽 | 横屏 **中等**/紧凑 | 不能拿“横屏宽度 ≥840”当判断依据 |
| 1440p 手机 | 3.5–4.0 | 约 411×914 | 同上 | 图片解码大小按 4 倍算 |
| 用户改了“显示大小” | 会变 | 宽 360–450 | 可能跨档 | — |
| 竖屏分屏 | — | 约 400×420 | **紧凑/紧凑** | 不能当成横屏手机 |
| 小窗、自由窗口 | — | 可能 <360 | 紧凑 | 至少不能溢出 |
| 折叠屏内屏 | — | 约 670–840 宽 | 中等（横过来可能刚过 840） | 铰链信息在 `MediaQuery.displayFeatures`，仓库还没用 |
| 2.5K/3K 平板 | 2.0–2.4 | 1280×800 到约 1500 宽 | 大/中等 | Android 17 + API 37 在短边 ≥600 的设备上忽略方向锁定，不能关 |

- **密度档**：ldpi 0.75（基本绝迹）、mdpi 1.0（电视盒子、低端平板）、hdpi 1.5、xhdpi 2.0、xxhdpi 3.0、xxxhdpi 4.0。缩放常常不是整数（2.625、2.75、3.5），细线要用 0 宽边框（发丝线）或 `1/dpr`。
- **8K 和手机无关**：手机已经没有 4K 屏（索尼从 Xperia 1 VI 起改成 FHD+），只需要保证图片解码有上限。

### 3.2 现状要点

- **图片解码**：
  - 房间卡片按宽度 × 缩放，夹在 240–720；头像 48–256；沉浸背景 24 px；弹幕表情按高度 96 解码。
  - 切房间预览（`room_swipe.dart:252-259`）按屏幕宽度解码，却用 `BoxFit.cover` 铺满竖长的屏幕：横版封面要放大约 4 倍，还会被大量裁掉。应该按实际怎么展示来解码：横版直播在竖屏全屏里本来就是 contain。
  - `ImageCache` 没设上限，用的是默认的 1000 张、100 MB。
- **文字缩放**：`AppTextScaler` = 系统的非线性缩放 × 应用的 0.5–2 倍，可能叠到约 4 倍；画面控制层已经限制在 1.3 倍以内。
- **触控区域**：至少 48 dp。

### 3.3 分辨率改动清单

| 优先级 | 改动 | 怎么验证 |
|---|---|---|
| 中 D1 | 在 `grid_columns.dart` 加高度分档，按约束判断；替换那 8 个文件里的 `MediaQuery.sizeOf(...).height < 480`；分屏（紧凑/紧凑）单独处理；折叠屏读 `displayFeatures` | 布局测试覆盖 360×400、400×420、400×869、821×400、673×841、841×673、1280×800、1500×1000，每个尺寸配 1.3/1.5/2.0 倍字号，没有溢出；K90 上 `adb shell wm size 720x1600`、`wm density 320/540` 模拟其他机型，测完 `wm size reset`、`wm density reset` |
| 中 D2 | 切房间预览按展示方式解码；按设备内存设 `imageCache.maximumSizeBytes` | debug 模式开 `debugInvertOversizedImages`，没有反色的图；热门页快速滚动 2 分钟，`adb shell dumpsys meminfo com.mystyle.purelive.v4dev` 预热后 PSS 不再增长 |
| 中 D3 | 在应用根（`app.dart:247-252`）加总体缩放上限（比如 2.0），控制层的 1.3 保留 | `adb shell settings put system font_scale 2.0`，加上应用内 2 倍字号，所有页面不截断；测完设回 1.0 |
| 中低 D4 | 详情把手扩到 48 dp；主要页面加触控区域检查 | widget 测试：`expect(tester, meetsGuideline(androidTapTargetGuideline))` |

---

## 4. 渲染性能（Flutter 3.47 + Impeller）

### 4.1 帧预算和通过标准

| 刷新率 | 60 | 90 | 120 | 144 | 165 | 185 | 200 | 240 |
|---|---|---|---|---|---|---|---|---|
| 每帧（ms） | 16.7 | 11.1 | 8.3 | 6.9 | 6.1 | 5.4 | 5.0 | 4.2 |

- **通过标准**：UI 线程和光栅线程分别 P90 ≤ 一个周期（计划书：120 Hz 下 ≤8 ms），P99 ≤ 1.5 个周期，FrameTimeline 的卡顿帧 <1%，不能连续两帧卡顿。
- **直播间播放时**光栅线程 P90 ≤ 0.6 个周期：视频每一帧都要整屏重画，要留余量。
- K90 在 120 Hz 下给应用的流水线时间是 13.67 ms、SurfaceFlinger 10.33 ms：一帧可以跨周期，但吞吐量仍然是每周期一帧。

### 4.2 卡顿来源和仓库对应位置

| 来源 | Impeller 下的情况 | 仓库里 | 做法 |
|---|---|---|---|
| 着色器编译 | 构建时预编译，渲染管线预先建好；Android 10+ 基本没有 | `minSdk 26`：8.x/9 回退旧渲染器 | 不用做预热；有条件时用一台 9.0 设备看一下 |
| saveLayer（Opacity、ShaderMask、ColorFilter、带 saveLayer 的抗锯齿裁剪） | 离屏缓冲、切换渲染目标 | `floating_window.dart:170`：拖动时视频上 80% 透明；`live_ui/.../loading_styles.dart:173`：ShaderMask 转圈每帧都做；控制层 200 ms 的淡入淡出可以接受 | 去掉浮窗的透明；转圈改成 `Paint.shader` 直接描边 |
| 裁剪 | 比 saveLayer 便宜，但不是免费 | 封面 `ClipRRect`：`room_card.dart:396`、`live_room_card.dart:362,718` | 改用 `borderRadius` 装饰；先在热门页快速滚动时测一下再决定 |
| 模糊（BackdropFilter） | 很贵 | 仓库里没有（计划书 9.3） | 保持 |
| 大图 | 解码和内存都贵 | 见 D2 | — |
| 滚动或拖动中重建 | UI 线程 | 聊天列表（S5）、三档面板（S4）；`JumpButtons` 只在状态翻转时 setState，没问题 | — |
| 一直在动的指示器 | 持续出帧，拉高刷新率 | `room_grid.dart` 加载时顶部的进度条、转圈 | 只在真的在加载时显示 |
| 平台视图 | 混合组合会把光栅线程并进平台线程，帧率下降；HCPP 需要 API 34 + Vulkan（实验阶段） | `shared/in_app_web.dart` 的 InAppWebView | 不要放进滚动列表 |
| 视频纹理 | 每个视频帧都整屏重新光栅化 | 直播间 | 直播间画面保持便宜；弹幕的 Picture 缓存（D03.1）保留 |
| 手势中调平台方法 | 主线程 | 亮度、音量（S9） | — |

### 4.3 在手机上怎么测

1. **DevTools**：`source ~/tools/purelive-env.sh && flutter run --profile --trace-systrace`（测试包 `com.mystyle.purelive.v4dev`，不动 3.x）。
   - Performance 页看帧图，打开 Track widget builds / layouts / paints。
   - 看 Rebuild stats 和性能叠加层。
   - `checkerboardOffscreenLayers` 能标出 saveLayer。
2. **Perfetto**：配置里加 `data_sources { config { name: "android.surfaceflinger.frametimeline" } }` 和 ftrace 的 atrace 类别 `gfx view input`，`atrace_apps: "com.mystyle.purelive.v4dev"`，用 `adb shell perfetto -c - --txt -o /data/misc/perfetto-traces/pl.pftrace` 录 20 秒，拉回来在 ui.perfetto.dev 打开，看 AppDeadlineMissed 和 BufferStuffing。
3. **应用内**：用 `SchedulerBinding.addTimingsCallback` 记录 build、raster、总时长，出 P90/P99（计划书 9.4 的基准场景：热门快速滚动、每秒 50/200 条弹幕、4 路多画面、设置页滚动、进出直播间 20 次）。
4. **刷新率**：开发者选项“显示刷新率”；`dumpsys SurfaceFlinger | grep -E "renderRate|activeMode="`；`dumpsys display` 里 DisplayModeDirector 的 mVotes。
   - `dumpsys gfxinfo` 统计的是普通 View 窗口，对 Flutter 画面不准。
5. **手感**：开发者选项“指针位置”，再用另一台手机 240 fps 慢动作拍屏，对比手指和内容的距离、松手后的速度。
6. **内存和耗电**：`dumpsys meminfo`；`dumpsys batterystats --reset`，固定亮度看 30 分钟后对比（新做法的省电档不能比 v3 的省电档更耗电）。

### 4.4 性能改动清单

| 优先级 | 改动 | 怎么验证 |
|---|---|---|
| 高 P1 | 把计划书 9.4 的基准写成 profile 模式下的集成测试，输出 P90/P99 和卡顿率 | 在 K90 上跑，按 4.1 的标准判定 |
| 高 P2 | 直播间画面保持便宜：去掉浮窗透明，转圈不用 ShaderMask，面板拖动不重建播放器（S4） | 播放 + 聊天滚动时光栅 P90 ≤5 ms（120 Hz）；Perfetto 里没有 saveLayer |
| 中 P3 | 聊天列表（S5） | 同 S5 |
| 低 P4 | 封面裁剪（先测再改） | 热门页快速滚动时光栅 P90 改善超过 0.5 ms 才改 |

---

## 来源

**Android 官方**
- 帧率接口：https://developer.android.com/media/optimize/performance/frame-rate
- 自适应刷新率 ARR：https://developer.android.com/develop/ui/views/animations/adaptive-refresh-rate
- `Surface.setFrameRate` 与 `FRAME_RATE_COMPATIBILITY_AT_LEAST`：https://developer.android.com/reference/android/view/Surface
- Android 15 游戏默认 60 Hz：https://developer.android.com/games/optimize/display-refresh-rate-change
- 多刷新率（触摸计时器、空闲计时器、内容检测）：https://source.android.com/docs/core/graphics/multiple-refresh-rate
- Android 12 拉伸效果：https://developer.android.com/about/versions/12/overscroll
- 窗口尺寸分档：https://developer.android.com/develop/ui/compose/layouts/adaptive/window-size-classes
- Android 16 方向和可调整大小的变化：https://android-developers.googleblog.com/2025/01/orientation-and-resizability-changes-in-android-16.html
- 触控区域 48 dp：https://developer.android.com/guide/topics/ui/accessibility/apps
- ViewPager 源码（翻页阈值）：https://github.com/androidx/androidx/blob/androidx-main/viewpager/viewpager/src/main/java/androidx/viewpager/widget/ViewPager.java
- Material 弹簧规范：https://github.com/material-components/material-components-android/blob/master/docs/theming/Motion.md
- Compose Material 3 MotionScheme：https://developer.android.com/reference/kotlin/androidx/compose/material3/MotionScheme
- Perfetto FrameTimeline：https://perfetto.dev/docs/data-sources/frametimeline

**Flutter 文档、issue 和 PR**
- 性能最佳实践：https://docs.flutter.dev/perf/best-practices
- UI 性能分析：https://docs.flutter.dev/perf/ui-performance
- Impeller：https://docs.flutter.dev/perf/impeller
- Android 平台视图：https://docs.flutter.dev/platform-integration/android/platform-views
- Android 渲染到 Surface 的新接口（SurfaceProducer）：https://docs.flutter.dev/release/breaking-changes/android-surface-plugins
- Android 14 非线性字号缩放：https://docs.flutter.dev/release/breaking-changes/android-14-nonlinear-text-scaling-migration
- 指针重采样 `resamplingEnabled`：https://api.flutter.dev/flutter/gestures/GestureBinding/resamplingEnabled.html
- `ClampingScrollSimulation`：https://api.flutter.dev/flutter/widgets/ClampingScrollSimulation-class.html
- issue #160952、#119268、#35162、#190372：https://github.com/flutter/flutter/issues/160952 、https://github.com/flutter/flutter/issues/119268 、https://github.com/flutter/flutter/issues/35162 、https://github.com/flutter/flutter/issues/190372
- PR #173849（拉伸效果移植）：https://github.com/flutter/flutter/pull/173849

**第三方库**
- https://pub.dev/packages/flutter_displaymode
- https://pub.dev/packages/refresh_rate
- https://pub.dev/packages/easy_refresh （本机 `easy_refresh-3.5.1` 源码）
- compose-miuix-ui（社区移植的 HyperOS 回弹）：https://github.com/compose-miuix-ui/miuix （`utils/Overscroll.kt`、`utils/SpringUtils.kt`）

**厂商和机型**
- MIUI 14 强制 120 Hz：https://www.xatakandroid.com/sistema-operativo/ultima-version-miui-14-trae-gran-novedad-para-xiaomi-permite-forzar-120-hz-todas-apps
- OnePlus 应用名单与 AutoHz 失效：https://www.androidpolice.com/oneplus-refresh-rate-autohz-workaround/ 、https://www.xda-developers.com/autohz-control-app-refresh-rate-oneplus-phones-oneplus-nord/
- OnePlus 11 部分应用卡在 60 Hz：https://piunikaweb.com/2023/02/27/oneplus-11-display-refresh-rate-stuck-at-60hz-on-some-apps/
- OnePlus 15 的 165 Hz：https://m.gsmarena.com/newscomm-70575.php
- 三星按应用限制刷新率：https://www.sammobile.com/news/capping-app-refresh-rate-samsung-galaxy-phones/
- ROG Phone 9 Pro 185 Hz：https://www.gsmarena.com/newscomm-65165.php
- 索尼 Xperia 1 VI 放弃 4K：https://www.androidauthority.com/sony-xperia-1-vi-launches-3443445/

**本机核实（不是网页）**
- Flutter 3.47.5 源码：`scroll_physics.dart`、`scroll_simulation.dart`、`page_view.dart`、`tabs.dart`、`overscroll_indicator.dart`、`bottom_sheet.dart`、`dismissible.dart`、`animation_controller.dart`、`gestures/binding.dart`、`painting/image_cache.dart`。
- v3 源码：`~/ref/v3ref`。
- K90 只读 dumpsys（2026-10-02）。

## 结果

报告的改动清单按优先级拆成 6 个任务（旧编号 P01～P06），4 个当天合并、随构建号 5001 发布，2 个暂停。表里“状态”是 2026-10-07 的登记表。

| 报告条目 | 内容 | 去向 | 状态 |
|---|---|---|---|
| 结论 3、4、10；R1～R4、R6 | 播放中只用帧率声明、没有整数倍取最高、系统限速提示、ARR 机型、不声明游戏类别 | [R02.2](../../../R-性能和流畅度/R02-刷新率/R02.2-刷新率策略修正/record.md)（D-010） | 待真机 |
| R5、S5、P3；结论 7 | 弹幕层时间差为 0 的帧；聊天列表反转、每帧最多一次更新 | [D04.1](../../../D-弹幕/D04-数据流和性能/D04.1-弹幕性能和可读性/README.md) | 待真机 |
| 结论 1；S1、S10 | 主列表手感照 3.x（两端回弹、经典下拉刷新头）；横条拉伸统一 | [A03.1](../../../A-界面设计/A03-动效和手感/A03.1-主列表手感/README.md)（D-009） | 待真机 |
| 结论 2、5；S2（侧面板）、S3 | 侧面板带松手速度的弹簧；翻页阈值照 ViewPager | [A03.2](../../../A-界面设计/A03-动效和手感/A03.2-翻页和面板/README.md)（D-020） | 待真机 |
| 结论 2、6、8；S2（直播间部分）、S4、S6、S7、S8、S9、S11；D2 的切房间预览解码 | 换台、三档面板、详情面板的弹簧和橡皮筋；拖面板不重建播放器；亮度音量合并调用 | [A03.3](../../../A-界面设计/A03-动效和手感/A03.3-直播间拖动手感/README.md) | 暂停（工作区刚开始、未提交） |
| 结论 9、11；D1、D3、D4 | 高度分档、分屏、折叠屏、字号上限、触控区域 | [A04.1](../../../A-界面设计/A04-尺寸和适配/A04.1-尺寸和字号适配/README.md) | 暂停（工作区做了大半、未提交） |
| 结论 12；P1、P2、D2（图片缓存）、P4 | profile 基准；浮窗和转圈不再离屏绘制；图片缓存按内存分档；封面圆角先测再改 | [R01.1](../../../R-性能和流畅度/R01-基准和测量/R01.1-基准测试和渲染开销/record.md)；P4 的决定 → [R01.2](../../../R-性能和流畅度/R01-基准和测量/R01.2-在K90上跑基准/README.md) | R01.1 待真机；R01.2 未开始 |

## 验证

- 调研本身是只读结论；K90 数据来自当天的只读 adb 查询（第 1.3 节），滑行数字是公式推算（第 2.2 节）。
- 每条改动的验证在去向任务里（报告每张改动清单的“怎么验证”一列已写）；真机步骤由 S02.5 阶段 3 汇总（3A 列表和翻页、3B 基准、3C 刷新率）。

## 留下的问题

- A03.3、A04.1 暂停，报告的 S2（直播间部分）、S4、S6～S9、S11、D1、D3、D4 还没落地。
- R01.2 要用 K90 上跑出的数字决定 P4（封面圆角画法）。
- R02.2 记录里的“HyperOS 看视频时可能压 60 Hz”要真机确认（S02.5 的 3C-08），结果可能要改刷新率提示的文字。
