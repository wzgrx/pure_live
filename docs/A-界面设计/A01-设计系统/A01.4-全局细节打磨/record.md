# A01.4 全局细节打磨：记录

- 日期：2026-10-08
- 执行者：Claude（Opus 5.5）
- 分支和提交：本机工作区，代码提交 `24142b783`
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 不留单字行 | 做了 | `live_ui` 新函数 `withoutOrphan`（`theme/text_wrapping.dart`）：每段最后两个汉字之间插 U+2060（标点留在后面，照样跟着前一个字），其他文字最后一个空格换成不换行空格。用在设置行说明（`HighlightedText(explanation: true)`，设置搜索的高亮照常）、`SettingsNote`、状态页说明（大、小两种）、`StatusBanner`、全部平台面板说明、长按弹幕面板的两条说明。标题不用。块屏蔽页自己的 `_note` 和各页面里直接写的 `Text` 没有改，以后遇到再换 |
| c2 设置行说明不截断 | 做了 | 设置行说明默认最多 3 行（原来 2 行）；超过 40 字的 8 条说明改短（见下表）。另加测试：设置目录里每条说明、每个设置页的说明不超过 40 字（汉字算 1，其他字符算 0.5） |
| c3 标点 | 做了 | 空状态标题去掉句号（`tags_empty_title`，英文同）；英文 `area_rooms_missing_area` 作标题，句号去掉。状态页说明是整句，原来没句号的 14 条加上（zh“。”、en“.”），默认说明 `status_empty_subtitle` 和 `live_ui` 里的默认文字一起改。i18n 测试扫描代码里所有 `AppStatusView` 的标题和说明，加上所有 `*_empty_title` |
| c4 图标含义 | 做了 | 见下“图标清单” |
| c5 最小字号 12 | 做了 | 多画面小格（空格）改成“＋ 点击选台”并排：圆 28、图标 20、字 12，不再被 `FittedBox` 缩到约 7 号；小格里选中的那格用短的“正在选台”（新键 `multiview_pick_target_short`）。主题的 `labelSmall` 改成和小字号一样大（原来小一档，默认 11）；标签上的数字徽标、切换直播间卡片封面上的角标（10.5）和封面上的标题（11）、本地互动的称号小块和“直播预览”、竖屏诊断、多画面“省流”角标都改成 12。`UI.md` 第 8.2 节写了这条规则（任务书写的“第 4 节”实际是 8.2 节“文字”） |
| c6 计数位置 | 做了 | 屏蔽关键词输入框的“0/40”右边贴住输入框右下角（Material 默认缩进 18，看起来飘向“添加”按钮），仍在框下面 |

## 改短的说明

| 键 | 原来 | 现在 |
|---|---|---|
| `account_douyu_force_renew_desc` | 打开后，播放中的斗鱼大约每 5 分钟在关键帧处静默换一次地址，避免“每 5 分钟断一次”。只在遇到这种情况时打开。 | 播放中的斗鱼约每 5 分钟静默换一次地址，避免每 5 分钟断一次；遇到才打开 |
| `asmr_sleep_mode_desc` | 开启后，进入新的直播间会自动切换为纯音频，并按下方时长停止播放；耳机按钮只切换当前直播间 | 新进的直播间自动切成纯音频，按下方时长停止；耳机按钮只切换当前直播间 |
| `auto_pip_on_leave_desc` | 在直播间看画面时回到桌面或切到别的应用，直接进入画中画；纯音频、暂停、未开播时不进入 | 看画面时回到桌面或切到别的应用，直接进入画中画；纯音频、暂停、未开播时除外 |
| `auto_start_boot_desc` | 恢复上次录制中、排队、重连或等待开播的任务；保留已停止、已完成和失败状态。关闭自动检测时，仅检查一次。 | 恢复上次录制中、排队、重连或等待开播的任务；关闭自动检测时只检查一次 |
| `match_video_frame_rate_desc` | 看直播时让屏幕刷新率是视频帧率的整数倍（30、60 帧用 60 或 120 Hz），画面更匀；只在不闪屏时切换 | 让屏幕刷新率是视频帧率的整数倍，画面更匀；只在不闪屏时切换 |
| `portrait_fullscreen_swipe_switch_desc` | 从关注、热门、分区或搜索结果进入直播间时，在竖屏全屏的画面中间上滑换到下一个、下滑换到上一个 | 从关注、热门、分区或搜索进的直播间，竖屏全屏时在画面中间上滑下一个、下滑上一个 |
| `record_danmaku_desc` | 在录像旁保存同名 .xml 弹幕文件（B 站格式，可用 DanmakuFactory、PotPlayer 等加载）；需要平台已接入远端弹幕 | 在录像旁存同名 .xml 弹幕文件（B 站格式）；平台需已接入弹幕 |
| `use_github_origin_for_updates_desc` | 开启后，版本检查和安装包下载仅连接 GitHub 官方地址，适合已配置网络代理的用户；关闭时自动提供镜像线路。 | 检查更新和下载安装包只连 GitHub 官方地址，适合配了代理的用户；关闭时用镜像 |

英文对应的几条也改短了。超过 40 字但不是设置行说明的（`settings_asmr_timer_hint` 是对话框提示，`tags_empty_hint` 是空状态说明）没有改。

## 图标清单（设置页，改动的和保留的重名）

改了的：

| 用途（`AppIcons`） | 原来 | 现在 | 原因 |
|---|---|---|---|
| 手机端默认音量 `settingsPhoneVolume` | 电话听筒 `phone_line` | 音量 `volume_up_line` | 像通话音量（R2-06） |
| 电脑端默认音量 `settingsDesktopVolume` | 电脑 `computer_line` | 音量 `volume_up_line` | 和手机端同一个意思 |
| 启用应用层代理 `settingsAppProxy` | 四个圆 `apps_line` | 地球 `global_line` | 四个圆是“平台显示”；地球 = 网络和代理（和“自定义网络代理”入口、播放器代理一样） |
| 切换语言（新 `settingsLanguage`） | 地球（借用网络代理的） | 翻译 `translate_2` | 地球留给网络 |
| 录制文件夹用拼音 `recordPinyin` | 翻译 `translate_2` | 输入法 `input_method_line` | 翻译给了语言 |
| 房间卡片设置 `roomCardSettings` | 四宫格 `layout_grid_line` | 卡片 `gallery_view_2` | 四宫格是多画面；“多画面”开关改用 `AppIcons.multiview` |
| 新直播间自动助眠 `settingsAutoSleep` | 月亮 `moon_clear_line` | 睡眠 `zzz_line` | 月亮是主题模式 |
| 弹幕样式 `settingsDanmakuStyle` | 调色板 `palette_line` | 弹幕设置 `chat_settings_line` | 调色板是外观和主题颜色 |
| 更换弹幕字体 `settingsDanmakuFont`、字体 `appFont` | 字号 `font_size`、字体颜色 `font_color` | 都是字体 `font_family` | 字号留给“精细化字号微调”；两个“字体”是同一个意思 |
| 普通页自适应视频高度 `portraitHeight` | 行列表 `view_agenda_outlined` | 高度 `height_rounded` | 行列表是卡片布局 |
| 界面刷新率 `settingsRefreshRate` | 速度表 `speed_up_line` | 脉冲 `pulse_line` | 速度表是硬件解码 |
| 启动时窗口大小 `settingsWindowSize` | 比例 `aspect_ratio_line` | 窗口 `window_line` | 比例是画面比例 |
| 自动检查更新 `settingsAutoUpdate` | 刷新 `refresh_line` | 云下载 `download_cloud_2_line` | 和关于页“在线更新”一样；刷新留给刷新 |
| 斗鱼登录后强制续期 `settingsDouyuRenew` | 刷新 | 钥匙 `key_2_line` | 是登录凭据，不是刷新列表 |
| 改回默认下载目录 `settingsDownloadReset`、重置卡片布局 `resetLayout` | 刷新、重启 | 恢复默认 `arrow_go_back_line` | 和其他“恢复默认”一样 |
| 返回应用时刷新关注 `settingsRefreshOnResume` | 重启 `restart_line` | 刷新 `refresh_line` | 是刷新 |
| 录制自动重连 `recordReconnect` | 刷新 | 循环 `loop_right_line` | 和录制中心“重连中”一样 |
| 录制切片 `recordSegment` | 胶片 `film_line` | 剪刀 `scissors_cut_line` | 胶片是视频 |
| 定时退出时长 `settingsExitMinutes` | 闪电秒表 `timer_flash_line` | 秒表 `timer_line` | 和“定时退出”同一个意思；闪电秒表留给录制超时 |
| 平台账号 `platformAccounts` | 无障碍小人 `accessibility_line` | 账号 `account_box_line` | 无障碍小人不是账号 |

保留的重名（同一个意思）：网络 = 地球（网络代理入口、两个代理、WebDAV 地址、网页登录）；视频 = 胶片（视频分组、优先 H.264）；播放器内核 = 芯片（入口、自定义驱动）；存储 = 数据库（缓存分组、缓存大小、录制总大小上限）；平台 = 四格（平台显示、平台入口）；清晰度 = HD（首选清晰度、录制清晰度）；缩略图 = 图片（自动刷新、立即刷新）；间隔 = 时钟（各个刷新间隔、开播检测间隔）；画中画 = 画中画（离开应用自动画中画、小窗跟随画面比例；离开直播间小窗、小窗弹幕）；刷新 = 刷新箭头（关注自动刷新、刷新分组、返回应用时刷新、重新计算、重新读取）；恢复默认 = 回退箭头。

## 根因

- 01 单字行：Flutter 的换行没有 `text-wrap: pretty`，中文每个字都可以断行，说明长度刚好多出一个字时就剩一个字一行。
- 02 截断：`SettingsRow.subtitleMaxLines` 默认 2（`settings_row.dart` 原 `:282`），几条说明 42～57 字，393 宽放不下两行。
- 03 句号：`tags_empty_title` 的翻译带了句号；状态页说明有的带有的不带，没有规则。
- 04 图标：A01.3 按“3.x 在这个位置用的图标”命名，3.x 本身就一图多义（地球 = 语言和网络、四宫格 = 卡片和多画面、刷新箭头 = 六个意思）。
- 05 小字：多画面小格的占位内容是竖排（圆 40 + 字 13），小格高约 74、上面让出 26 给编号，只剩约 40，`FittedBox(scaleDown)` 把整块缩到约 0.55 倍。主题的 `labelSmall` 比小字号小一档（11）。
- 06 计数：Material 把计数和输入文字对齐（右缩进 内边距 14 + 4），旁边紧挨“添加”按钮时看起来飘在两者之间。

## 改了哪些文件

- `packages/live_ui`：`theme/text_wrapping.dart`（新）、`live_ui.dart`、`widgets/settings_row.dart`、`widgets/status_view.dart`、`widgets/status_banner.dart`、`widgets/tab_label.dart`、`theme/live_theme.dart`、`icons/app_icons.dart`、`scope.dart`
- `apps/pure_live/lib`：`features/settings/settings_catalog.dart`、`features/settings/appearance_pages.dart`、`features/multiview/widgets/cell_view.dart`、`shared/danmaku/block_manager.dart`、`features/popular/popular_page.dart`；直播间里的四个小文件只改了字号或说明（`danmaku/message_panel.dart`、`local_interaction/local_chat_line.dart`、`local_interaction/local_style_panel.dart`、`switch_room/room_switch_tiles.dart`、`player/portrait_diagnostics.dart`），没碰 `player_view.dart`、`live_play_page.dart`；多画面只改小格，没碰 `multiview_page.dart`
- 翻译 zh、en；`docs/specs/UI.md` 第 8.2、8.4 节

## 新设置、翻译键、门禁基线

- 新翻译键：`multiview_pick_target_short`（zh“正在选台”、en“Picking”）。没有删键，没有改设置键。

## 测试

- 新增：`live_ui` `text_wrapping_test.dart`（5 个：拼接规则、英文、不改的情况、实际排版里最后一行不少于两个字、各组件用上了）；`design_system_test.dart` 一个（设置图标一义）；`apps/pure_live` `i18n_test.dart` 一个（状态页标点）、`settings_page_test.dart` 一个（说明不超过 40 字）、`multiview_page_test.dart` 一个（小格字 12、图标 20、没有缩小）、`shield_page_test.dart` 加计数位置的断言。
- 改了：说明文字现在带连接符，约 45 处 `find.text` 改成 `find.text(withoutOrphan(...))`，4 处 `textContaining` 改用 `support.dart` 新加的 `findWords`；说明行数 2 → 3、`labelSmall` 10 → 11（字号 11 时）、图标对照表 4 行。
- 通过：`live_ui` 191 个，`apps/pure_live` 868 个，全部通过。

## 真机上要看的

| 步骤 | 期望 |
|---|---|
| 1. 设置 → 平台显示与授权 | “首选直播平台”说明最后一行是“平台”两个字，不是一个“台” |
| 2. 热门 → ⌄ | 面板说明一行 |
| 3. 设置 → 视频 | 说明都完整（“耳机按钮…”“纯音频、暂停、未开播时除外”看得到）；“手机端默认音量”是喇叭图标；“新直播间自动助眠”是 zzz |
| 4. 设置 → 外观 | “切换语言”是翻译图标、“房间卡片设置”是卡片图标、“字体”是字体图标 |
| 5. 设置 → 自定义网络代理 | “启用应用层代理”是地球 |
| 6. 标签管理（空） | 标题“暂无自定义标签”没有句号；说明带句号 |
| 7. 多画面 1+3 | 三个小格是“＋ 点击选台”一行，字和设置页的小字一样大 |
| 8. 直播间 → 屏蔽管理 | “0/40”右边和输入框右边对齐，在框的右下角 |
| 9. 长按弹幕 → 屏蔽这个词 | 说明没有单独一个“示” |
| 10. 切换直播间面板 | 封面上的角标和标题字比原来大一点，没有挤出角标 |

## K90 复查（2026-10-08，master 521163209）和跟进

- 看过：设置“平台显示与授权”“视频”（说明没有单字行、最多 3 行完整、新图标）、多画面 1+3 小格（“⊕ 点击选台”清楚）、屏蔽管理“0/40”在输入框右下角、切换直播间卡片角标没有挤出来。
- 跟进两处（维护者直接改）：
  - “全局静音”和“手机端默认音量”都是音量图标：“全局静音”这一行固定用静音图标（`playback_tiles.dart` 的 `GlobalMuteTile`），开关显示开没开。
  - 全部平台面板里“SHOWROOM”在 K90 上被截成“SHOWRO...”：平台名改成放不下时略微缩小（`FittedBox`），不再截断（`popular_page.dart` 的 `_PlatformTile`）。
