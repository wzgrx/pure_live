# U.6c 播放设置：设计（第 1 版）

- 状态：待确认（第 1 版，2026-10-01）
- 范围：视频设置、播放内核设置、MPV 驱动选项页、竖屏直播适配、小窗弹幕、观看数据与排行口径六页和它们弹出的对话框；U.2j 交来的小窗设置改名和“离开应用时自动画中画”开关
- 对应：[TASKS.md](../../TASKS.md)、[INVENTORY.md](../../INVENTORY.md#u6c)（U.6c-01～15）、[TASK_FILES.md](../../TASK_FILES.md#u6c)
- 评审页：claude.ai 私有页面（只有项目所有者能打开）；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)（共用部分 [src/smock.py](src/smock.py)）
- 图片：v3 按 `v3.2.11` 代码还原（文字取自 `assets/translations/zh.json`）；平台图标取自 `packages/live_ui/assets/platforms/`
- 和 U.6a 的关系：设置总览、统一的设置行组件在 U.6a 定。新设计先用 U.2f 已确认的弹幕设置那套行（`.sec`、`.grp`、`.swr`、`.sl`），U.6a 定下来后对齐（行首图标、行高、分组卡片的样子以 U.6a 为准）

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| U.6c-11 | 视频设置 | 设置总览“视频” | 竖屏、横屏、宽屏 | Android / iOS / 电脑三种行组合；后台播放、自动助眠、小窗置顶申请中（开关不能点）和失败（说明变红） |
| U.6c-13 | 首选清晰度、移动网络首选清晰度对话框 | 视频设置两行 | 对话框 | 选中项 |
| U.6c-12、15 | 自动助眠播放时长对话框 | 视频设置（Android） | 对话框 | 默认、输入超出范围、保存中、保存失败 |
| U.6c-14 | 重置小窗位置和大小确认 | 视频设置（Windows） | 对话框 | — ；完成后提示“已清除保存的小窗位置和大小” |
| U.6c-05 | 播放内核设置 | 设置总览“播放器内核” | 竖屏、横屏、宽屏 | Mpv / IJK / Fvp / Exo（Exo 没有代理和 MPV 部分）；电脑上内核固定；兼容模式、自定义驱动开关时的接管关系 |
| U.6c-06 | 切换播放器对话框 | 内核切换（Android、iOS） | 对话框 | 选中项 |
| U.6c-07、08 | 网络代理配置对话框 | 内核页“网络代理设置” | 对话框 | 关（输入框变灰）、开、端口不对 |
| U.6c-02 | MPV 驱动选项页（视频输出、音频输出、硬件解码器） | 内核页三行 | 竖屏、宽屏 | 选中项 |
| U.6c-09 | 竖屏直播适配 | 视频设置一行 | 竖屏、横屏、宽屏 | Android 多“小窗跟随真实画面比例” |
| U.6c-10 | 竖屏的四个选项对话框 | 竖屏页四行 | 对话框 | 选中项；恢复默认后提示“已恢复默认设置” |
| U.6c-03 | 小窗弹幕 | 设置总览、视频设置 | 竖屏（预览在上）、宽屏 ≥840（左右两栏）、窄横屏 | 开、关（v3 其他设置消失）、保留平台颜色开关、帧率跟随开关 |
| U.6c-04 | 恢复小窗弹幕默认值确认 | 小窗弹幕顶栏 | 对话框 | — |
| — | 统一弹幕颜色取色 | 小窗弹幕 | 对话框 | 组件在 U.6b（`app_color_picker_dialog.dart`） |
| U.6c-01 | 观看数据与排行口径 | 视频设置一行 | 竖屏、横屏、宽屏 | 热度优先 / 在线优先；平台支持 / 不支持 |

## v3 的样子

**行的组件**（`common/widgets/widget_extensions.dart`）：组标题 12 号粗体、主色 65%（`:21-36`）；分组卡片是 `surfaceContainerHighest` 15% 底、圆角 20、行间 0.5 的几乎看不见的分隔线（`:38-112`）；开关行 `SwitchListTile`，图标 22 主色、标题 15 号 600、说明 12 号黑 75%，说明默认一行省略（`isLong` 才换行，`:114-152`）；跳转行 `ListTile`，右边默认是 20 号 40% 灰的箭头，传了 `trailing` 就换成它（`:154-258`）；滑块行标题 15 号 600、数值 13 号粗体主色小胶囊（`:352-454`）；内容最宽 960 居中（`:8`）。顶栏标题居中 20 号 600（`style/theme.dart:115-121`）；对话框底色 `surfaceContainerHigh`、圆角 24（`:177-183`）。

**视频设置**（`video_settings_page.dart:74-298`）：音频设置（全局静音，图标随开关在 `volume_mute_line` / `volume_up_line` 之间换；手机端默认音量 50% 或电脑端默认音量 100%）→ 画质设置（首选清晰度 `hd_line`，右边“原画”12 号主色；移动网络清晰度 `signal_tower_line`，右边 13 号）→ 播放行为设置（竖屏直播适配 `stay_current_portrait_rounded`、观看数据与排行口径 `groups_2_rounded`，右边 24 号箭头；Android：后台播放 `music_2_line`、新直播间自动助眠 `moon_clear_line`、自动助眠播放时长 `timer_2_line` “1 小时”；退出小窗播放 `picture_in_picture_2_line`；Windows：Windows 小窗始终置顶 `pushpin_line`、记住小窗位置和大小 `terminal_window_fill`（默认开）、重置小窗位置和大小 `reserved_line`；自动全屏 `fullscreen_line`；Android：屏幕常亮 `lightbulb_line`（默认开））→ 弹幕设置（显示弹幕 `chat_smile_2_line`、小窗弹幕、更换弹幕字体 `font_size`“当前字体: Default”、弹幕关键词过滤 `filter_2_line`）。后台播放、助眠、置顶切换时开关不能点，失败时说明变成红字（`:327-432`）。

**对话框**：首选清晰度是 `AlertDialog`，标题 15 号粗体，圆点 + 文字，底部“取消”（`:434-503`）；自动助眠时长：说明、10 个快捷时长（15 分钟…1 天）、输入框（1 分钟至 365 天）、取消 / 保存（`:577-714`）；重置小窗位置：取消 / 红色“重置”（`:521-564`）。

**播放内核设置**（`player_kernel_settings_page.dart:25-118`）：核心内核设置（内核切换 `toggle_line` 右边“Mpv播放器”；网络代理设置 `global_line` 右边“已开启 / 未开启”，Exo 时没有；开启硬解码 `speed_up_line`；Windows 且 Mpv：启用 RTX VSR `image_edit_line`；播放器强制销毁 `shut_down_line`）→ 只有 Mpv 时：一条分隔线、Android 的“兼容模式”`shield_check_line`（不在卡片里）、“MPV 高级设置”标题（`equalizer_line` 18 + 15 号粗体主色）、警告文字和“MPV 官方文档”链接、红字“重置”（窄于 420 时上下排，`:207-281`）、卡片（自定义驱动与硬件加速 `code_box_line`；视频输出驱动(--vo) `movie_line`、音频输出驱动(--ao) `volume_up_line`、硬件解码器(--hwdec) `cpu_line`，当前值写在说明行，右边 `arrow_right_s_line`）。切换播放器是 `SimpleDialog` 列表行 + 圆点（`:284-336`）；网络代理配置对话框：启用播放代理开关、代理主机 (Host)、端口 (Port)、“确认”（`:354-441`）。

**驱动选项页**（`mpv_option_page.dart:15-57`）：一张卡片，每行圆点图标 22 + 14 号文字，点了就选。选项来自 `mpv_platform_profile.dart`：iOS 只给自己的；Android 的视频输出和解码器用全部选项（12 个、27 个），音频输出只给 Android 的 5 个。

**竖屏直播适配**（`portrait_live_settings_page.dart:16-171`）：识别与普通页布局（智能识别、自适应高度、布局模式“均衡（推荐）”）→ 全屏、小窗与弹幕（全屏方向“跟随直播源（推荐）”、竖屏全屏画面模式“沉浸背景（推荐）”、Android 的小窗跟随真实画面比例、竖屏弹幕布局“跟随全局”、记住单个直播间方向）→ 诊断与恢复（显示识别状态、恢复竖屏适配默认设置）。四个选项对话框：圆点图标 + 文字，没有按钮（`:183-220`）；恢复默认点了直接恢复，提示“已恢复默认设置”（`:156-166`）。

**小窗弹幕**（`pip_danmaku_settings_page.dart`）：顶栏右边 `restart_alt_rounded`“恢复小窗弹幕默认值”，先确认（主色按钮，`:21-54`）。宽 ≥840 左右两栏（左边说明和预览，宽 43% 最多 520），否则说明 + 预览（高 = min(16:9, max(96, 可用高度 × 31%))）+ 下面单独滚动的列表（`:28-151`）。列表一张卡片：小窗显示弹幕；（打开时才有）纯文字模式、根据小窗尺寸自动缩放、保留平台弹幕颜色、（关掉保留颜色才有）统一弹幕颜色、字体大小 8–24、字体粗细、滚动速度（像素/秒）20–400、透明度、画面顶部占用高度、最大同时显示数量 1–20（`CountButton`：主色实心减加按钮）、发送间隔 0.05–2、“弹幕帧率 · 跟随界面刷新率策略”开关和（关掉才有）帧率滑块 15–240，跟随时只显示“30 FPS”（`:153-321`）。默认值 `danmaku_settings_controller.dart:17-29`。预览：深色渐变 16:9、圆角 16，最多 20 条“小窗弹幕预览 n”加一个表情，关掉时中间显示“小窗弹幕已关闭”（`:501-678`）。

**观看数据与排行口径**（`audience_metric_settings_page.dart`）：卡片显示与排行方式（两个单选：平台热度优先 / 真实在线人数优先，默认热度）→ 排行规则说明 → 真实在线平台开关：写死的 19 个平台（`:7-27`），每行“人”或“火”图标、名字、“来源：…”加逐平台说明（三四行）；不支持的平台开关永远关着点不动（`:163`）→ 说明。默认开的 8 个平台见 `app_settings_controller.dart:11-20`。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 页面照 v3 一一对应；视频设置重新分组；依赖项变灰；恢复默认和选项对话框统一；代理只在一处改；观看数据页只列能开的平台 | 待评审 |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [对比：视频设置（手机竖屏）](page/02-对比-视频设置-手机竖屏-完整内容.jpg)、[宽屏、横屏](page/03-对比-视频设置-宽屏-横屏.jpg)
- [对比：播放内核设置和驱动选项页](page/04-对比-播放内核设置和驱动选项页.jpg)
- [对比：竖屏直播适配](page/05-对比-竖屏直播适配.jpg)
- [对比：小窗弹幕](page/06-对比-小窗弹幕.jpg)、[宽屏、窄横屏](page/07-对比-小窗弹幕-宽屏-窄横屏.jpg)
- [对比：观看数据与排行口径](page/08-对比-观看数据与排行口径.jpg)
- [对比：对话框](page/09-对比-对话框.jpg)
- [v3 的问题](page/10-v3-的问题.jpg)
- [改了什么](page/11-改了什么.jpg)
- 每个按钮是干什么的、怎么用：[视频设置](page/12-每个按钮是干什么的-怎么用-视频设置.jpg)、[播放内核](page/13-每个按钮是干什么的-怎么用-播放内核.jpg)、[竖屏直播适配](page/14-每个按钮是干什么的-怎么用-竖屏直播适配.jpg)、[小窗弹幕](page/15-每个按钮是干什么的-怎么用-小窗弹幕.jpg)、[观看数据和对话框](page/16-每个按钮是干什么的-怎么用-观看数据和对话框.jpg)
- [各客户端](page/17-各客户端.jpg)
- [需要你选的](page/18-需要你选的.jpg)
- [性能要点](page/19-性能要点.jpg)
- [拿不准的地方、交给其他任务的](page/20-拿不准的地方-交给其他任务的.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-video.jpg](v3-video.jpg)、[v4-video.jpg](v4-video.jpg)、[v4-video-n.jpg](v4-video-n.jpg) | 视频设置，Android 完整内容 |
| [v3-video-wide.jpg](v3-video-wide.jpg)、[v4-video-wide.jpg](v4-video-wide.jpg) | 1280×800，Windows |
| [v3-video-land.jpg](v3-video-land.jpg)、[v4-video-land.jpg](v4-video-land.jpg) | 手机横屏 852×393 |
| [v3-kernel.jpg](v3-kernel.jpg)、[v4-kernel.jpg](v4-kernel.jpg)、[v4-kernel-n.jpg](v4-kernel-n.jpg) | 播放内核设置，Android、Mpv |
| [v3-mpv-option.jpg](v3-mpv-option.jpg)、[v4-mpv-option.jpg](v4-mpv-option.jpg)、[v4-mpv-option-n.jpg](v4-mpv-option-n.jpg) | 硬件解码器选项页，Android |
| [v3-portrait.jpg](v3-portrait.jpg)、[v4-portrait.jpg](v4-portrait.jpg)、[v4-portrait-n.jpg](v4-portrait-n.jpg) | 竖屏直播适配 |
| [v3-pip.jpg](v3-pip.jpg)、[v4-pip.jpg](v4-pip.jpg) | 小窗弹幕第一屏 |
| [v3-pip-full.jpg](v3-pip-full.jpg)、[v4-pip-full.jpg](v4-pip-full.jpg)、[v4-pip-full-n.jpg](v4-pip-full-n.jpg) | 小窗弹幕完整内容 |
| [v3-pip-wide.jpg](v3-pip-wide.jpg)、[v4-pip-wide.jpg](v4-pip-wide.jpg) | 小窗弹幕 1280×800 |
| [v3-pip-narrow.jpg](v3-pip-narrow.jpg)、[v4-pip-narrow.jpg](v4-pip-narrow.jpg) | 小窗弹幕 740×360 |
| [v3-audience.jpg](v3-audience.jpg)、[v4-audience.jpg](v4-audience.jpg)、[v4-audience-n.jpg](v4-audience-n.jpg)、[v4-audience-info.jpg](v4-audience-info.jpg) | 观看数据与排行口径；新：各平台口径说明 |
| [v3-dialogs.jpg](v3-dialogs.jpg)、[v4-dialogs.jpg](v4-dialogs.jpg)、[v4-dialogs-n.jpg](v4-dialogs-n.jpg) | 全部对话框 |

## v3 的问题

| 编号 | 问题 | 位置 |
|---|---|---|
| P1 | “播放行为设置”一组 11 行混着三类设置；小窗设置分在三处；“小窗弹幕”在总览和视频设置各一个入口 | `video_settings_page.dart:160-259`、`:272-278`；`settings_page.dart:95-100` |
| P2 | “退出小窗播放 / 返回时是否保留悬浮窗”字面意思反了；桌面小窗设置写着“Windows” | `video_settings_page.dart:216-244` |
| P3 | 依赖别的设置的行照常可点，看不出没生效（自动助眠时长、三个驱动、竖屏自适应高度和布局、观看数据的平台开关） | `video_settings_page.dart:203-215`；`media_kit_adapter.dart:266-300`；`live_play_content.dart:562-572` |
| P4 | 当前值字号、位置不统一，箭头三种，弹幕字体显示“Default” | `video_settings_page.dart:133-151`、`:166`、`:283`；`player_kernel_settings_page.dart:201` |
| P5 | 弹幕样式只能在直播间里调 | `video_settings_page.dart:263-294` |
| P6 | 宽屏内容最宽 960，开关离文字太远 | `widget_extensions.dart:8` |
| P7 | 播放代理两处都能改，字段名不同，对话框“确认”只是关闭 | `player_kernel_settings_page.dart:61-74`、`:354-441`；`network_proxy_settings_page.dart:164-184` |
| P8 | 兼容模式、自定义驱动会接管“开启硬解码”，页面上看不出 | `media_kit_adapter.dart:266-300` |
| P9 | MPV“重置”不确认、没提示，还会重置首选清晰度等本页以外的设置 | `player_kernel_settings_page.dart:239-261`；`player_settings_controller.dart:256-267` |
| P10 | 内核页版式乱：兼容模式不在卡片里，组标题两种样子，多一条分隔线，警告对比度低 | `player_kernel_settings_page.dart:125-151`、`:214` |
| P11 | Android 上列出别的平台才有的驱动和解码器 | `mpv_platform_profile.dart:31-41`；`player_consts.dart:51-116` |
| P12 | 恢复默认三处三种做法，竖屏页不确认 | `portrait_live_settings_page.dart:156-166`；`pip_danmaku_settings_page.dart:21-54` |
| P13 | 选项对话框四种样子，当前项不是“主色 + 勾” | `video_settings_page.dart:444-492`；`portrait_live_settings_page.dart:183-220`；`player_kernel_settings_page.dart:284-336` |
| P14 | 小窗弹幕关掉后其他设置消失；颜色、帧率行跟着开关出现消失 | `pip_danmaku_settings_page.dart:177`、`:199`、`:295-315` |
| P15 | 小窗弹幕数值没有单位，帧率跟随时只剩“30 FPS” | `pip_danmaku_settings_page.dart:207`、`:235`、`:289-315` |
| P16 | 窄横屏预览 96 高，设置只剩一百多像素 | `pip_danmaku_settings_page.dart:68-69` |
| P17 | 小窗弹幕说明只写 Android 和 Windows | `zh.json` `pip_danmaku_desc` |
| P18 | 观看数据页 19 个平台里 10 个是点不动的开关 | `audience_metric_settings_page.dart:7-27`、`:163` |
| P19 | 能给在线人数的 11 个平台不在列表里 | 同上；`live_room.dart` `audienceCapabilities` |
| P20 | 平台说明是接口字段名；没有平台图标 | `zh.json` `audience_*_detail`；`audience_metric_settings_page.dart:144` |

## 改动（待确认）

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 保留 | 六个页面和进入方式、全部设置项、3.x 存储键和默认值、说明文字、平台差异 | — |
| c2 | 修改 | 视频设置分成音频、画质、播放行为、后台与助眠（Android）、小窗、弹幕六组；小窗弹幕只在“小窗”组 | P1 |
| c3 | 修改 | 离开直播间时小窗播放；小窗始终置顶、记住 / 重置小窗位置和大小去掉“Windows”（键不变） | P2 |
| c4 | 增强 | 离开应用时自动画中画（Android、iOS，默认关；随 U.2j J1） | — |
| c5 | 修改 | 依赖项变灰不消失，写明“打开……后生效”；兼容模式、自定义驱动写明接管什么 | P3、P8、P14 |
| c6 | 修改 | 当前值在右边 14 号次要色加箭头，放不下换到说明下面；数值带单位；弹幕字体显示“默认” | P4、P15 |
| c7 | 修改 | 选项对话框统一（主色加勾、点了就关、底部取消）；时长对话框和 U.6d 定时退出同一个 | P13 |
| c8 | 修改 | 恢复默认统一：最后一行红字、先确认并列出范围、红色按钮、完成提示；内核页只恢复本页 | P9、P12 |
| c9 | 修改 | 播放代理只在“网络与代理设置”改，内核页这一行跳过去 | P7 |
| c10 | 修改 | 内核页分内核、解码、网络、MPV 高级设置四组，警告改成组下说明 | P10 |
| c11 | 修改 | 驱动和解码器只列当前平台能用的，默认项标“默认” | P11 |
| c12 | 增强 | 弹幕设置组加“弹幕样式”，打开直播间里同一个弹幕设置 | P5 |
| c13 | 修改 | 宽屏最宽 720；小窗弹幕页宽 ≥840 或高 <480 时左右两栏 | P6、P16 |
| c14 | 修改 | 小窗弹幕分组照 U.2f；自动缩放最小 10 px；说明改成系统画中画、桌面小窗和应用内小窗 | P14、P17 |
| c15 | 修改 | 观看数据页只列能开的 20 个平台（带图标），不支持的 13 个收成一行，逐平台说明放进“各平台口径说明” | P18、P19、P20 |

## 按钮的作用和用法

见对比页“每个按钮是干什么的、怎么用”五节（视频设置 1–18、播放内核 1–12、竖屏 1–10、小窗弹幕 1–15、观看数据 1–5 和对话框 1–3），编号和 `v4-*-n.jpg` 一致。操作方式照 v3：开关点了立即生效；选项对话框点了就关；申请权限、设置窗口层级时开关先不能点，失败时说明变红、开关退回。

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 同图；后台与助眠、屏幕常亮、兼容模式只有 Android；横屏最宽 720 居中，小窗弹幕页高度不够时左右两栏 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 最宽 720 居中；电脑上是电脑端默认音量和桌面小窗三项，内核只有 MPV，Windows 有 RTX VSR；悬停高亮，Tab 和方向键移动，空格切换开关 |
| 电视 | U.15i 出图：pure_live_TV 的视频、内核、观看数据各有一节（`features/settings/pages/video_settings_section.dart`、`player_kernel_settings_section.dart`、`audience_metric_section.dart`），用同一个行组件和对话框的电视样式；移动网络清晰度、后台、助眠、小窗、自动全屏、屏幕常亮在电视上本来就没有（`video_settings_section.dart:13-16`） |
| 苹果平台 | iOS、iPadOS 同 Android 排法，照 v3 没有后台播放、助眠、屏幕常亮、兼容模式，默认内核 IJK；自动画中画受系统设置影响。macOS 同 Windows，没有 RTX VSR，硬件解码照 v3 固定关闭 |

## 待选

- X1 恢复默认放在哪：建议 A 每页最后一行；B 顶栏图标。
- X2 设置里加“弹幕样式”入口：建议 A 加；B 不加。
- X3 观看数据页不提供在线人数的平台：建议 A 收成一行，说明放进“各平台口径说明”；B 每个平台一行，开关换成“只有热度”文字。
- X4 内核页的“网络代理设置”：建议 A 跳到“网络与代理设置”；B 保留对话框但和那一页同一组输入框。

## 拿不准的地方

1. Android 打包的 libmpv 实际支持哪些视频输出和解码器（图里按 no、auto、auto-safe、yes、auto-copy、vulkan、mediacodec 画），开发时从编译选项取。
2. v3 滑块高度、两行 ListTile 最小高度 72 按 Flutter 默认值画，和真机可能差几个像素。
3. v3 预览里每条弹幕后面有一个表情，图里省略。
4. 竖屏页的“记住单个直播间方向”在智能识别关着时是否还起作用（播放器里手动指定方向），没在真机上确认，所以没有让它变灰。

## 交给其他任务的

- U.6a：总览的“小窗弹幕”入口和视频设置里的重复（建议总览不再单列）；总览“视频”的说明“调整解码器、弹幕、屏幕比例与亮度性能”和页面内容对不上；横屏手机顶栏 64 高、一屏只看到两三行；统一行组件定下来后这里的行跟着对齐。
- U.6d：“网络与代理设置”页要能直接定位到“播放器内核代理”部分（c9）；自动助眠时长对话框和定时退出时长对话框统一，点快捷时长的做法随 U.6d 的 Y2（图里按 A：立即生效）。
- 工具：新设计和 v3 的竖屏页用到 Material Outlined 图标，`tools/ui/mock/fonts.txt` 需要加 `MaterialIconsOutlined.woff2`（这次放进了本机缓存，见 `src/smock.py` 的 `@font-face`）。
