# 0026 Android TV 模式：同一安装包内的检测、画布、焦点体系与换台

- 状态：已接受
- 日期：2026-09-28

## 背景

宪法定下“TV 模式在同一安装包内”；principles §5.1 规则 1、§5.3、§6.3 定了 TV 的判定、画布、导航、网格、焦点、字号、主题和遥控器按键；live-room §3.5、multiview、product F-TV-01、F-NEW-04 定了直播间和多画面在 TV 上的行为。旧版只有 Manifest 的 LEANBACK_LAUNCHER 和横幅，没有焦点模型。实现时还有几处会长期影响代码结构的选择：怎么检测电视、画布怎么落到不同分辨率上、焦点体系用什么搭、换台的“来源列表”怎么传、遥控器按键放在哪一层处理。

## 决定

1. **检测走一个小的平台通道，放在单独的 Kotlin 文件。** `TvSupport.kt` 是一个 `FlutterPlugin` + `ActivityAware`，在 `MainActivity.configureFlutterEngine` 里用一行 `flutterEngine.plugins.add(TvSupport())` 注册，通道 `purelive/tv`：`device` 返回 `UiModeManager` 是否为 `UI_MODE_TYPE_TELEVISION`、是否有 `FEATURE_LEANBACK`（或旧的 `FEATURE_TELEVISION`）、是否有触屏、是否有语音识别；`recognizeSpeech` 用 `RecognizerIntent` 调系统语音识别。`main()` 在首帧前取一次，TV 不会先闪一下手机布局。插件形式在 audio_service 缓存引擎、换新 Activity 时自动重新绑定，重复注册会被引擎忽略。
2. **设置 `app.tvMode`（自动 / 开启 / 关闭）和 `app.tvPerformanceMode`，作用域 `device`。** 自动 = 设备报告电视或 leanback；开启照顾投影仪和报错类型的盒子。电视上的选择不能随备份跑到手机上。
3. **TV 表现层放在 `live_ui`，应用只接一个 `TvRoot`。** `TvRoot` 提供 `TvScope`（页面用 `TvScope.of(context)` 判断，不依赖 Riverpod，测试不开 TV 时行为不变）、`TvCanvas`、从一开始就显示焦点框（遥控器没有指针去切换高亮模式）、以及拦掉确认键的按住重复（框架默认会在每次重复时激活一次）。主题用 `PureTheme.tv`：只有深色和纯黑，字阶整体大一级（正文 ≥ 14sp，行高 ≥ 1.4 倍取偶数），图标 32，焦点描边用近白的 onSurface。
4. **画布：缩放而不是重排。** 缩放系数 = min(宽 ÷ 960, 高 ÷ 540)，`FittedBox` 把逻辑 960×540 放大到屏幕，设备像素比同乘（封面仍按物理像素解码），相差 1% 以内不缩放。5% 过扫描边距（48 / 28）作为 MediaQuery 的安全区交给页面，顶栏、底部面板、列表和 `SafeArea` 自动避开，背景铺满。
5. **焦点体系用官方 Focus / Shortcuts / Actions，不引入 `dpad` 包。**
   - `FocusFrame`：卡片和格子的唯一焦点目标（内部的 InkWell 不取焦点），键盘焦点时 3dp 描边，TV 上再放大 1.05 倍并加一级阴影；性能优先模式或系统关闭动画时只描边。确认键在松开时激活，按住 500ms（或菜单键）打开卡片菜单：新款遥控器没有菜单键。
   - `TvGridFocus` + 纯函数 `gridStep`：网格里单轴移动，行尾停住，最左列和第一行交还给页面遍历（去导航轨、筛选条），向下进入较短的末行落在最后一张，并记住原来的列，再向上回到原列。每张卡片一个常驻的 FocusNode，路由的焦点作用域在返回时自动回到进房前那张卡片。
   - `TvNavScaffold`：左侧导航轨，收起 120dp（48 边距 + 72 图标列），获得焦点时展开到 248dp 盖在页面上，不挤压网格；右键进入页面，回到这个入口上次聚焦的控件（没有时取顶栏以下阅读顺序第一个）；页面左边缘按左回导航轨；一级页面按返回先回导航轨，再按一次退出应用、不弹确认（PopScope）。新页面出现时导航器会把焦点停在路由作用域上，脚手架和 `TvRoot` 把它送回导航轨、页面或弹层的第一个控件。
   - 按钮：底色加深之外再加 3dp 近白描边（主题里的 `side`），因为有的按钮自带颜色，单靠底色在电视上看不出。
6. **换台的来源列表随路由传入。** 卡片打开直播间时把所在列表里已加载的开播直播间作为 `RoomOrigin` 放进 go_router 的 `extra`（关注页、发现和分区、搜索结果）；没有时用开播关注，顺序与关注页相同（按人数）。`neighborRoom` 是纯函数：上一个 / 下一个，不在列表里的房间从头或尾进入，两端不循环。换台在同一页面内进行，复用播放会话和视频表面（ADR 0023 决定 2）。TV 的上下键和频道键、桌面 PageUp/PageDown、手机竖屏全屏上下滑（`player.switchRoomGesture`，默认关）都走这一个入口。
7. **直播间的遥控层是页面之上的一层，不改播放器的触屏控制层。** TV 上页面固定全屏、不调用方向锁和系统栏，`PlayerView` 不画触屏控制条和锁，只保留画面、弹幕、提示、失败页；`TvRoomLayer` 在画面之上处理按键：没有控制行和侧栏时，上下换台、左边直播间列表、右边播放设置（弹幕、画质、线路、比例）、确认显示信息栏和控制行、长按确认或菜单键打开设置；控制行或侧栏打开时方向键交给框架在按钮间移动。返回由它的 PopScope 逐级处理（侧栏 → 控制行 → 离开）。按住方向键不连续换台。TV 上播放器音量固定 100%，音量交给遥控器调系统音量。
8. **多画面在 TV 上固定 2×2**，格子用 `FocusFrame`（只描边、描边画在格子内侧，视频不缩放），确认等于点击，长按确认是格子菜单，上下键不换台。
9. **横幅用脚本生成矢量。** `apps/pure_live/tool/tv_banner.py` 用启动图标的电视图形和 Noto Sans CJK SC Bold（SIL OFL）字形轮廓生成 `drawable/tv_banner.xml`（“纯粹直播”）和 `drawable-en/tv_banner.xml`（“Pure Live”），160×90dp 即 xhdpi 320×180，夜蓝底；`--check` 检查是否过期。

## 备选方案与放弃理由

- **`dpad` 包（PLAN §04 列为待评估）**：官方 Focus 体系已经能完成单轴移动、作用域记忆和按键拦截；多一个依赖，还要让它和 Material 组件的焦点共存。
- **把检测写进 MainActivity**：另一条线正在改 MainActivity（后台播放、画中画），独立文件加一行注册，冲突面最小；插件形式还自带 Activity 结果回调，语音识别不用在 MainActivity 里接 `onActivityResult`。
- **每个页面按 960×540 单独做 TV 布局**：页面数量多，维护两套；缩放加少数 TV 专用组件（导航轨、网格焦点、直播间遥控层）覆盖了全部入口。
- **TV 检测只看 `FEATURE_LEANBACK` 或只看 UI 模式**：部分国内盒子只满足其中一个；两者取或，再加手动开关兜底。
- **导航轨展开时挤压页面**：网格会从 4 列变 3 列再变回来，焦点所在的卡片位置跳动。
- **来源列表放进全局状态（最近打开的列表）**：多个入口交替打开时会串；随路由传入与“从哪个入口进来就回到哪里”一致。
- **TV 上沿用触屏控制条**：按钮太小、默认隐藏的时机按触屏设计，方向键在控制条和换台之间会冲突；principles §6.3 要求“左边选去哪、右边调怎么播”的侧栏。
- **TV 播放器音量用“手机默认音量”（0.5）**：遥控器调的是系统音量，播放器再减半会让电视声音偏小且无法用遥控器补回来。
- **PNG 横幅**：每个密度一张，文字改动要重新导出；矢量一份覆盖全部密度，字形转轮廓不随包附带字体。

## 影响

- Manifest：`uses-feature` 触屏和 leanback 均为 `required=false`，MAIN 过滤器加 `LEANBACK_LAUNCHER`，`application` 加 `android:banner`，`<queries>` 加 `RECOGNIZE_SPEECH`（查询是否有语音识别）。首个构建时要在 TV 模拟器或盒子上确认：启动器出现横幅、检测为电视、语音按钮可用。
- 新设置：`app.tvMode`、`app.tvPerformanceMode`（device）、`player.switchRoomGesture`（synced，默认关）；安装偏好 `app.switchGestureHinted`（meta 表，一次性提示）。
- 规格：live-room ZN-3、T-03、T-05 按 principles §6.1 修订（换台手势默认关，开启后竖屏全屏整幅画面换台），新增 D-18（PageUp/PageDown），§3.5 细化为 TV-01～TV-08；multiview 新增 OPS-6；principles §5.3 加实现细则；store §5 登记新设置的作用域。
- 缺口：焦点预览（principles §5.3，可选、默认关）未做，需要单独的预览播放器；低端盒子的格数上限（multiview LYT-1）和“性能优先”是否要默认开启要真机实测；只有关注页的卡片有长按菜单，发现和搜索的卡片菜单（principles §4.2）是全局缺口，不是 TV 专有；TV 真机和 Kotlin 编译未验证（本轮不构建）。
