# U.6c 播放设置

- 日期：2026-10-02
- 设计：[docs/ui/compare/U.6c/README.md](../compare/U.6c/README.md)（第 1 版，用户已确认；X1～X4 按建议 A）；计划书 [UI_PLAN.md](../UI_PLAN.md) 第 3、5、7–10 节
- 一并处理的跨任务待同步：U.2j → U.6c（改名“离开直播间时小窗播放”、三个小窗设置去掉“Windows”、加“离开应用时自动画中画”）；U.6b → U.6c（视频页不再有“小窗弹幕”、播放代理只留一处、弹幕字体用 U.6b 的字体页）；U.12d → U.6c（“弹幕关键词过滤”改名“弹幕屏蔽”）；U.14 → U.6c（后台播放、自动助眠权限被拒时的说明）；U.17a → U.6c（“后台播放”iOS 也显示）；U.6a → U.6c（设置行、两栏、搜索照 U.6a）
- 改动的目录：`apps/pure_live/lib/features/settings/`、`packages/live_ui`（只做添加）、翻译文件、门禁基线、文档
- 没有改原生部分，没有构建 APK，没有往手机安装

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 六个页面和入口、全部设置项、3.x 键和默认值、说明、平台差异 | ✅（有偏差） | 视频、竖屏直播适配（视频页的子页）、观看数据与排行口径（视频页的子页）、播放内核、MPV 驱动选项页、小窗弹幕；键都没改。**偏差**：v4 全平台只用 mpv（PLAN §4、M7.1），所以“内核切换”在所有平台都像 v3 的电脑端一样固定显示“Mpv播放器”、不能点，没有“切换播放器”对话框，也没有 Exo 的分支 |
| c2 | 视频页六组：音频、画质、播放行为、后台与助眠（Android）、小窗、弹幕 | ✅（有偏差） | 组和行序照图；画质组末尾多两行 v4 已有的“优先 H.264 编码”（UPGRADES 已批准）和“画面比例”（3.x 的 `videoFitIndex`）。**偏差**：“小窗”组里没有“小窗弹幕”行——U.6a c7（已确认）和跨任务待同步 U.6b → U.6c 都要求视频页这一行去掉、只留设置总览的入口，和本任务 c2 / 按钮 14 冲突，按较新的 U.6a 做 |
| c3 | 改名，键不变 | ✅ | “离开直播间时小窗播放 / 返回离开直播间后，画面缩成应用内小窗继续播放”；“小窗始终置顶”“记住小窗位置和大小”“重置小窗位置和大小”；新文字用新键（`settings_leave_room_mini*`、`settings_pip_on_top*`），3.x 的键还在 |
| c4 | 离开应用时自动画中画（Android、iOS） | ✅ | `autoPipOnLeave`（U.2j 已加），标题改成“离开应用时自动画中画” |
| c5 | 依赖项变灰不消失，写明“打开……后生效”；接管关系 | ✅ | 新的 `SettingRequirement`（`needsOn`/`needsOff`）：自动助眠时长、竖屏自适应高度和布局、三个驱动、小窗弹幕全部行、统一弹幕颜色、小窗弹幕帧率、真实在线平台开关；“开启硬解码”被兼容模式（Android）或自定义驱动接管时写“由……接管”；兼容模式、自定义驱动的说明写明接管什么 |
| c6 | 当前值右边 14 号次要色加箭头，长值换到说明下；单位；弹幕字体 | ✅ | 竖屏页四个选项的值在说明下面（主色，`SettingsLinkRow.valueBelow`）；小窗弹幕 90 px/s、12.0 px、0.35 秒、30 FPS、粗细名；弹幕字体行用 U.6b 的字体行（显示“系统默认”，Windows 是 Microsoft YaHei，不再是“Default”） |
| c7 | 选项对话框统一（主色加勾、点了就关、取消）；时长对话框和定时退出同一个 | ✅ | `showChoiceDialog` 改成 `SettingsChoiceRow`（无单选圆点；U.6b 的主题模式、语言也跟着变，原则 7）；驱动选项是整页，当前项同样主色加勾；时长对话框：说明、快捷时长（点了立即生效并关闭，当前值高亮）、输入框预填当前值、“自定义播放时长”、范围写在框下、超出时变红 |
| c8 | 恢复默认统一：最后一行红字、先确认写明范围、红色按钮、完成提示；内核页只恢复本页 | ✅ | `RestoreDefaultsTile`：内核页（列出恢复哪些，首选清晰度不动）、竖屏页（同时清除记住的直播间方向）、小窗弹幕（顶栏图标改成最后一行，含开关本身，照 3.x 的确认文字） |
| c9 | 播放代理只在网络页改，内核页这一行跳过去 | ✅ | 右边“已开启 / 未开启”；点了打开“网络与代理设置”并高亮“启用播放代理” |
| c10 | 内核页四组，警告改成组下说明 | ✅ | 内核、解码、网络、MPV 高级设置；警告和“MPV 官方文档”（主色链接，打开 mpv.io 手册）在 MPV 组下面；恢复默认单独一行 |
| c11 | 驱动只列当前平台能用的，默认项标“默认” | ✅（有偏差） | Android 解码器按设计图的 9 个（去掉了 v4 原有的 `rkmpp`）；保存的值本平台没有时显示并使用默认值（照 v3 回落）。**拿不准**：打包的 libmpv 实际支持哪些没有核对编译选项，清单照设计图 |
| c12 | 弹幕设置组加“弹幕样式” | ✅ | 打开一页，内容就是直播间弹幕设置用的 `shared/danmaku` 的 `DanmakuSettingsContent`（同一个组件） |
| c13 | 宽屏最宽 720；小窗弹幕页宽 ≥840 或高 <480 左右两栏 | ✅ | 高 <480 且宽 ≥560 时两栏（更窄的横屏仍一栏，避免预览挤没）；一栏时预览最高约 1/3 屏，下面的行单独滚动 |
| c14 | 小窗弹幕分组照 U.2f；自动缩放最小 10 px；说明 | ✅ | 开关单独一张卡 → 样式 → 显示范围 → 流畅度 → 恢复默认；预览在 `live_ui` 新加的 `PipDanmakuPreview`（深色 16:9、按帧率取整刷新、单独重绘层、系统“减少动态效果”时静止）；“最大同时显示数量”用计数行，按住连续变 |
| c15 | 观看数据页只列能开的平台，不支持的收成一行，逐平台说明放进“各平台口径说明” | ✅ | 平台按 `live_core` 的 `audienceCapabilities` 算（v3 的 19 个在前，其余按表序），带平台图标和“来源”一行；选“平台热度优先”时平台开关变灰并写原因；只有热度的平台一行（数量、名字、图标）；口径说明页逐字保留 v3 的说明，后加的平台只写来源 |
| 跨任务 U.14 | 后台播放、自动助眠在权限被拒时的说明 | ✅（接口） | v4 现在没有通知权限的处理；加了 `switchGateProvider`：打开前先问（转圈、开关不能点），被拒时说明变红“通知权限已关闭：在系统设置里允许通知后再打开”，失败时红字照 v3（“更新后台播放设置失败，请重试”），开关保持关。真正的权限申请由 U.14 提供这个接口的实现 |
| 跨任务 U.2j | 小窗置顶失败时说明变红、开关退回 | ✅ | 小窗开着时切换立即生效（`DesktopWindow.setMiniOnTop`），失败退回并红字 |

## 和设计不同的地方

1. 视频页没有“小窗弹幕”行（见 c2）。
2. 内核切换固定为 mpv（见 c1）。
3. Android 解码器清单照设计图（见 c11）。
4. 行首图标：设计图的行没有图标，按 U.6a 的设置行（有图标）画，图标用 v3 每一行的图标（`AppIcons.settings*`、`portrait*`）；小窗弹幕页照 v3 没有图标。
5. 设置总览的“弹幕”行仍打开设置里的弹幕页（U.6a 定的，U.2e 的范围）；所以“显示弹幕”“更换弹幕字体”“屏蔽”在视频页和弹幕页各有一行（同一个设置），搜索会找到两处。

## v3 文件 → v4 文件

| v3（`lib/modules/settings/pages/`） | v4（`features/settings/`） |
|---|---|
| `video_settings_page.dart` | `settings_catalog.dart`（视频一节）、`playback_tiles.dart`（全局静音、需权限的开关、小窗置顶、弹幕样式页）、`settings_editors.dart`（重置小窗位置） |
| `portrait_live_settings_page.dart` | `settings_catalog.dart`（`SettingsSubpage.portrait`）、`playback_tiles.dart`（`RestoreDefaultsTile`） |
| `audience_metric_settings_page.dart` | `settings_catalog.dart`（`SettingsSubpage.audience`）、`audience_pages.dart` |
| `player_kernel_settings_page.dart` | `settings_catalog.dart`（播放内核一节）、`playback_tiles.dart`（内核行、代理行、MPV 说明、驱动行） |
| `mpv_option_page.dart`、`common/utils/mpv_platform_profile.dart` | `playback_tiles.dart`（`MpvOptionPage`）、`settings_editors.dart`（`mpvOptionsFor`、`mpvOptionName`） |
| `pip_danmaku_settings_page.dart` | `playback_tiles.dart`（`PipDanmakuPage`、`PipColorTile`、`PipFpsTile`）、`packages/live_ui/lib/src/widgets/pip_danmaku_preview.dart` |
| `video_settings_page.dart` 的选项和时长对话框 | `settings_dialogs.dart`（`showChoiceDialog`、`SettingsChoiceRow`、`showNumberDialog`） |

## live_ui（只做添加）

- `SettingsRow.titleColor`、`busyColor`；`SettingsLinkRow.valueBelow`；`SettingsGroup.footerWidget`；`SettingsCounterRow` 按住 0.5 秒后每 100 毫秒连续变（改成有状态，接口不变）。
- `PipDanmakuPreview`；`AppIcons` 加播放设置用的图标（`settings*`、`portrait*`）。

## 新增

- 设置：没有（全部用已有的键）。
- 翻译：三个任务合计中英各新加 83 条（`settings_*` 为主），改了 3 条已有的文字：`auto_pip_on_leave`（“离开应用时自动画中画”）、`settings_refresh_on_resume_desc`、`settings_refresh_concurrency_desc`（U.6d 的设计文字）。

## 门禁

- `settings` 直接写的颜色和图标 **126 → 32**（三个任务合计，`tools/gate/ui_baseline.json` 已改）；剩下的在弹幕页（U.2e 的行，25）和日志页（U.11a，7）。
- 没有新增跨功能引用（弹幕样式用的是 `shared/danmaku`）。

## 测试

- `apps/pure_live/test/features/settings/settings_playback_test.dart`：19 个——视频页六组和行序、图标、改名、没有小窗弹幕行、电脑上的小窗三行没有“Windows”；横屏手机 852×393、1280×800、1920×1080 行宽 ≤720；全局静音图标跟着变；依赖项变灰并写原因、打开后可用；时长对话框（快捷时长立即生效并关闭、预填当前值、超出范围不关）；选项对话框主色加勾；弹幕样式打开同一个组件；屏蔽跳路由；后台播放权限被拒红字且不打开；竖屏页三组、变灰、恢复默认确认并清除记住的方向；观看数据页（热度优先时变灰、没有在线人数的平台不出开关、热度平台一行、口径说明页）；内核页四组、内核固定、接管和变灰、驱动选项页 9 个解码器和“默认”、恢复默认不动首选清晰度、代理行跳到网络页；小窗弹幕页（手机一栏预览在上、分组行序、单位、颜色和帧率变灰原因、关掉后全部变灰和“已关闭”；740×360 和 1280×800 两栏；计数加减、恢复默认）。
- `settings_harness.dart`：原 `settings_page_test.dart` 的测试台挪出来给四个文件共用，加了 provider 覆盖和“减少动态效果”（预览静止，帧能稳定）。
- `settings_page_test.dart`：原有测试按新设计改了两处：总览多了“日志管理”一行（U.6e）；主题模式对话框从单选圆点改成“主色 + 勾”的选项行（c7，原则 7）。
- `packages/live_ui/test/settings_playback_widgets_test.dart`：5 个（长值在说明下、红色标题和转圈、按住连续变、预览 16:9 和关闭提示、JSON 树）。
- 没有做 profile 帧时间；预览在测试和“减少动态效果”下静止。
