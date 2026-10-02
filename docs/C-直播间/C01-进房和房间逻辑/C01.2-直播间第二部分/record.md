# C01.2 页面：直播间（第二部分）

- 日期：2026-10-01
- 目录：`apps/pure_live/lib/features/live_play/`（15 个文件，约 5100 行；本次新增 9 个、改 5 个），另改 `lib/shared/danmaku/danmaku_settings.dart`、`packages/live_player`（只添加）、`apps/pure_live/pubspec.yaml`、`android/`
- v3 来源：标签 `v3.2.11` 的 `lib/modules/live_play/`（C01.1 没做的部分：`live_play_menu_button.dart`、`record_action_button.dart`、`dialogs/*`、`services/room_external_opener.dart`、`controllers/timer_controller.dart`、`widgets/video_player/{video_controller,video_controller_panel,volume_control,iptv_schedule_dialog,iptv_programme_policy}.dart`、`widgets/danmaku/danmaku_viewing_preset.dart`），`lib/player/core/{playback_lifecycle_coordinator,background_playback_service,background_playback_policy,live_audio_service,live_audio_handler,playback_header_resolver}.dart`，`lib/common/utils/live_url_tool.dart`（`castPlayUrlByRoomId`、`getPlayUrlByRoomId`），`android/` 的 `MainActivity`（`AudioServiceActivity`）和清单
- 用到的模块：N02.1（`DlnaCastController`）、H02.1（`recordingProvider`、`recordNoticeText`）、I01.2（`shareRoom`、`DanmakuSettingsPanel`、`room_texts`）、L01.1（`classifyIptvProgramme`、`evaluateIptvCatchupAvailability`、`buildIptvCatchupUrl`、`resolveGuideReference`、`IptvLibrary.programmes`）、G02.1（`shouldContinueInBackground`、`roomVolumeKey`、`setAudioOnly`）、A01.1（`EmoteText`、设置卡片、`AppStatusView`）

## 做法

| 文件 | 内容 |
|---|---|
| `room_controller.dart`（改） | 加礼物开关（`meta` 的 `live_play.showGifts`）、纯音频 `setAudioOnly`（重开画质时带上）、定时关闭 `setSleepTimer`（到时暂停并提示）、自动助眠 `sleepSessionOnStart`（纯音频 + `asmrSleepMinutes` 定时）、房间音量 `setVolume`/`saveVolume`（3.x 键 `room_vol_<平台>_<房间>`）、网络电视的请求头（`iptvPlayHeaders`：`customIptvUserAgent` 在下，频道自己的请求头在上，同 3.x）、回看 `playCatchup` / `backToLive` |
| `room_menu_button.dart` | 标题栏菜单（3.x `LivePlayMenuButton`）：刷新、直播间信息、节目单（网络电视）、用外部打开、切换直播间、投屏、定时关闭（显示剩余分钟）、房间音量（桌面）、获取直链、分享、在新窗口播放（Windows）；`externalRoomTarget`/`openRoomExternally`（3.x `RoomExternalOpener`） |
| `stream_dialogs.dart` | `showStreamPicker`：选画质（当前画质打勾）→ 取地址 → 选线路 → 复制或投屏（3.x `KnownRoomLinkDialog`，会话型输入提示 `toolbox_session_source`，回看中给回看地址）；`CastDialog`：N02.1 记录写的界面（搜索、刷新、列表、打勾、行尾转圈、红字、提示），打开期间持有组播锁 |
| `record_button.dart` | 录制按钮（3.x `RecordActionButton`）：按任务状态显示“录制 / 已监控 / 录制中”，点开底部菜单：立即录制、等待开播（监控）、停止、删除任务、录制中心；只提示本房间的录制通知；没有录制器（没有 FFmpeg 的版本、测试）时不显示 |
| `room_dialogs.dart` | 定时关闭对话框（3.x 的预设 8 档 + 分钟输入 + 校验）、房间音量对话框（滑块即时生效，确定才保存，取消还原） |
| `room_switcher.dart` | 切换直播间（3.x `PlayOther`）：已开播的关注、关注的回放、观看历史三页，不含当前房间；选中后替换当前页面（`offAndToRoomDetail`） |
| `iptv_guide.dart` | 节目单（3.x `IptvScheduleDialog`）：按房间的节目单键（`epgId`，经 `resolveGuideReference`）读选中节目单的节目，范围是回看天数（默认 2 天）到后天；正在播的高亮并自动滚到，已结束且可回看的标“可回看”，点一下回看；回看中顶部有“返回直播” |
| `background_playback.dart` | `RoomBackgroundPolicy`（3.x `PlaybackLifecycleCoordinator`）：离开应用 1.5 秒后暂停（后台播放打开或助眠中不暂停），回来恢复它暂停的；不可见时 `setPresentationVisible(false)`；后台继续时持有唤醒锁和 Wi-Fi 锁（I01.1 的 `pure_live/background_playback`）；`RoomMediaNotification`（audio_service：标题、主播、封面、播放/暂停、停止）；`PictureInPicture`（`pure_live/pip`）；`DeviceControls`（`pure_live/device_controls`：媒体音量、窗口亮度） |
| `player_gestures.dart` | 手机：画面左半上下滑调亮度、右半调音量（系统媒体音量），中间显示图标、进度条和百分比；鼠标滚轮调房间音量（停 0.6 秒后保存） |
| `danmaku_templates.dart` | 弹幕观看模板（3.x `DanmakuViewingPreset`/`Template`）：三个预设和“恢复默认”、保存当前样式、使用保存的模板；保存格式就是 3.x 的 `savedDanmakuTemplate`（版本 2），坏的模板整个不用 |
| `player_view.dart`（改） | 控制栏加纯音频、锁定（手机全屏）、投屏、画中画（Android）按钮，窄屏时中间一组可横向滚动；全屏顶栏加“正在播放：节目”、节目单、切换直播间；纯音频时画面显示变暗的封面和耳机图标；画中画时只有画面和小窗弹幕（`pipDanmakuFontSize`、`pipDanmakuArea`，`enablePipDanmaku`）；竖屏流按 `portraitDanmakuMode` 隐藏或缩小飞行弹幕 |
| `live_play_page.dart`（改） | 标题栏：关注、录制、菜单；建 `RoomBackgroundPolicy`；画中画时只画播放器；键盘 ↑/↓ 调音量、R 刷新；手机竖排时竖屏流按 `portraitVideoHeight` 加高画面（动画过渡）；离开时把亮度还给系统 |
| `chat_feed.dart`、`chat_panel.dart`（改） | 礼物行（`ChatLineKind.gift`）；聊天文字走 `EmoteText`（`chatSegments`）；弹幕设置页顶部加“在聊天列表显示礼物”开关和模板卡片 |
| `shared/danmaku/danmaku_settings.dart`（改） | `danmakuLookOf` 带上上下留白（`danmakuTopArea`/`BottomArea`，J02.1 已改成 0～300 像素）；面板加两个留白滑块和 `leading` 参数（多画面不传，不受影响） |
| `packages/live_player`（只添加） | `PlaybackSession.setPresentationVisible(visible:)` / `presentationVisible`：看不见时不判断画面停住，重新可见后重新计时（多画面提出的接口，直播间进入后台时也用） |

### 原生部分（Android，照 v3）

| 位置 | 改动 |
|---|---|
| `MainActivity.kt` | 父类 `FlutterActivity` → audio_service 的 `AudioServiceActivity`（同 3.x；引擎缓存，媒体通知和录制在 Activity 销毁后继续）；加通道 `pure_live/pip`（`isSupported`、`enter`，`onPictureInPictureModeChanged` 发 `changed`；比例限制在 1:2.39～2.39:1）和 `pure_live/device_controls`（`getVolume`/`setVolume` 用 `STREAM_MUSIC` 不弹系统音量条，`getBrightness`/`setBrightness`/`resetBrightness` 改窗口亮度）。3.x 用 floating（要本地 AGP 9 补丁）、volume_controller、screen_brightness 三个插件，现在不需要 |
| `AndroidManifest.xml` | 加 audio_service 的 `AudioService`（`mediaPlayback` 前台服务）和 `MediaButtonReceiver`（照 3.x）；Activity 已有 `supportsPictureInPicture`，权限 I01.1 已照 3.x 声明 |
| `pubspec.yaml` | 加 `audio_service: ^0.18.19`（3.x 同款，pub.dev 最新）、`live_cast`；根 `pubspec.lock` 多 `audio_service`、`audio_service_platform_interface`、`audio_service_web`、`audio_session` 四个（`flutter_cache_manager`、`rxdart` 已在锁文件里） |

`flutter build apk --debug` 成功（改完原生后一次 272 秒，最后代码再构建一次），结束后已停 Gradle 守护进程。没有往手机安装。

## 与 v3 的功能对照

| v3 功能（文件） | v4 | 说明 |
|---|---|---|
| 菜单：打开直播间（外部 App/浏览器）（`room_external_opener.dart`） | 有，改进 | 网页地址用适配器给的 `room.link`（33 个平台都有）；Android 先试 App（哔哩哔哩、斗鱼、抖音、虎牙、CC，链接照 3.x），打不开提示后改用浏览器；网络电视不提供 |
| 菜单：切换直播间（`play_other.dart`） | 有 | 三页同 3.x（已开播、关注的回放、观看历史）；换成替换页面，不在原页面里换房间 |
| 菜单/控制栏：投屏（`castPlayUrlByRoomId` → `KnownRoomLinkDialog` → `LiveDlnaPage`） | 有 | 用直播间已有的画质，不再重新取详情和画质 |
| 菜单：定时关闭（`room_timer_dialog.dart`、`timer_controller.dart`） | 有 | 到时暂停并提示（3.x 同）；菜单项显示剩余分钟 |
| 菜单：房间音量（`room_volume_dialog.dart`） | 有（桌面） | 手机用系统音量（手势、音量键），3.x 手机上播放器音量固定 1.0 |
| 菜单：获取直链（`getPlayUrlByRoomId`） | 有 | 同投屏的选择流程，复制后提示 |
| 菜单：分享（`ShareCommandHandler`） | 有 | I01.2 的 `shareRoom`：有系统分享面板时用它，否则复制口令（`share_plus` 由 O03.1 接上后自动用面板） |
| 菜单：本地互动（`local_interaction/*`） | 无 | 留给后续 |
| 菜单：在新窗口播放（Windows） | 有 | I01.1 的 `launchNewWindow` |
| 标题栏：录制按钮（`record_action_button.dart`） | 有 | H02.1 接口；状态文字和颜色用录制中心的 |
| 控制栏：耳机（纯音频） | 有，改进 | 画面显示封面和耳机图标（3.x 黑屏）；切回视频时结束自动助眠（3.x 同） |
| 自动助眠（`enableAsmrSleepMode`，Android） | 有 | 进房即纯音频 + `asmrSleepMinutes` 定时；用同一个定时器（见界面改进） |
| 控制栏：小窗/画中画（`PIPButton`、floating） | 有（Android） | 系统画中画；画中画里只有画面和小窗弹幕 |
| 应用内悬浮小窗（`floatPlay`，flutter_floating）、Windows 小窗 | 无 | 留给后续 |
| 控制栏：锁定（`showLocked`） | 有 | 手机全屏时 |
| 全屏顶栏：时间、电量 | 无 | 留给后续 |
| 全屏顶栏：正在播放的节目、节目单按钮、切换直播间 | 有 | |
| 网络电视节目单、回看、返回直播（`iptv_schedule_dialog.dart`、`iptv_programme_policy.dart`） | 有 | 规则在 L01.1；回看按点播打开（播完不算失败） |
| 网络电视自定义 UA（`playback_header_resolver.dart`） | 有 | 直播和回看都带 |
| 手势：音量、亮度（`volume_control.dart`、`video_controller.dart`） | 有 | 原生通道代替两个插件 |
| 键盘：音量、刷新（`video_keyboard.dart`） | 有 | ↑/↓、R（空格、F、Esc 在 C01.1） |
| 后台播放、前后台切换（`playback_lifecycle_coordinator.dart`、`background_playback_service.dart`） | 有 | 规则和 1.5 秒同 3.x |
| 系统媒体通知（`live_audio_service.dart`、`live_audio_handler.dart`） | 有 | 只在后台播放打开或助眠中显示（见界面改进） |
| 竖屏流自适应（`enablePortraitStreamAdaptation`、`portraitAdaptiveHeight`、`portraitLayoutMode`、`portraitDanmakuMode`） | 部分 | 画面高度、竖屏弹幕模式；竖屏全屏显示模式、方向覆盖按钮、按房间记忆、诊断留给后续 |
| 弹幕模板（`danmaku_viewing_preset.dart`） | 有 | |
| 弹幕上下留白 | 有 | J02.1 已改范围 |
| 弹幕帧率、字体、纯文字模式、斗鱼疑似自动弹幕过滤、画中画弹幕其余细项 | 部分 | 只用了画中画字号和区域；其余留给后续 |
| 画面弹幕的点击/长按交互（`danmaku_message_actions.dart`） | 无 | 聊天列表的长按有（C01.1） |
| 礼物 | 新增 | B-21 |
| 表情（`EmojiManager`） | 部分 | 聊天行走 `EmoteText`；图片要消息模型带表情（见缺的接口） |

## 审查发现的 v3 问题

| # | 问题 | 位置 | 处理 |
|---|---|---|---|
| 1 | 投屏和获取直链要重新取一次房间详情和画质（`KnownRoomLinkDialog` → `ToolBoxDirectLinkFlow`），直播间里明明已经有了；慢的平台要多等几秒，偶尔还因风控失败 | `live_url_tool.dart:405`、`known_room_link_dialog.dart:115` | 用直播间当前的画质列表，只取所选画质的地址 |
| 2 | “打开直播间”按平台硬编码网页地址（25 个分支），没写到的平台（新加的、改过链接格式的）提示“没有官方网页”，和适配器给的 `link` 重复且会不一致 | `room_external_opener.dart:44-210` | 网页地址用适配器的 `link`（http/https、有主机、不带用户名密码才用）；只有 App 跳转按平台写 |
| 3 | 画中画、音量、亮度用三个插件，其中 floating 要在仓库里维护 AGP 9 补丁副本（`plugins/built_in_kotlin/floating`） | `pubspec.yaml:120-188` | 三件事都是几行系统调用，放进 `MainActivity` 的两个通道 |
| 4 | 自动助眠和直播间定时器是两个互不知道的计时器（助眠在 `LiveAudioService`，定时在 `TimerController`），同时开时先到的那个停播，菜单里看不到助眠还剩多久 | `live_audio_service.dart`、`timer_controller.dart`、`asmr_sleep_timer_desc` | 合成一个：助眠就是按 `asmrSleepMinutes` 开的定时器，菜单里显示剩余时间，可以改 |
| 5 | 礼物各平台都上报了，但界面不显示（B-21） | `danmaku_controller.dart` | 聊天列表里的礼物行，可关 |

## 界面改进

- **礼物**：聊天列表里单独样式的一行（礼物图标、送礼人、礼物和数量，第三色），不上飞行弹幕，免得挡画面；弹幕设置页顶部“在聊天列表显示礼物”可关，关掉时已有的礼物行一并移除，选择记住。
- **获取直链和投屏**：一个对话框里先选画质（当前画质打勾，只有一档时跳过）、再选线路（显示地址），取地址时转圈，失败原因写在对话框里；不是先后弹三个对话框。
- **投屏对话框**：搜索进度条、刷新按钮、行尾状态（投屏中转圈、已投屏打勾）、错误红字、同一局域网提示；名字为空显示“未命名 DLNA 设备”。
- **录制按钮**：标题栏直接显示任务状态（录制中为红色），操作放在底部菜单，并显示当前状态；不能录制的版本不显示按钮（3.x 也显示，点了才说不可用）。
- **定时关闭**：预设用可选中的标签；菜单项副标题显示“N 分钟后暂停”；自动助眠和定时关闭合一（问题 4）。
- **纯音频**：画面上显示变暗的封面和耳机图标，一眼知道不是黑屏故障。
- **控制栏**：加纯音频、投屏、画中画、锁定按钮；窄屏时中间一组可以横向滑动，全屏按钮始终在最右边（全屏时还有画质和线路）。
- **全屏顶栏**：标题下显示“正在播放：节目”（回看时“正在回看”），网络电视有节目单按钮，任何房间都有切换直播间按钮。
- **节目单**：打开时自动滚到正在播的节目，节目标“正在播放 / 可回看”，未开始的不能点；回看中顶部有“返回直播”。
- **手势**：调节时画面中间显示图标、进度条和百分比，1 秒后消失；鼠标滚轮也能调音量并记住为房间音量。
- **竖屏流**：手机竖排时画面按设置加高（均衡：最多 3:4 或屏幕 55%；沉浸：最多 9:16 或 75%；兼容：保持 16:9），高度变化有动画。
- **媒体通知**：只在后台播放打开或助眠中显示（3.x 在手机上播放就显示）。前台看直播时通知栏不多一条；需要后台听的设置打开后，通知在进房播放时就出现（Android 不允许应用进入后台后再启动前台服务）。
- **弹幕设置页**：加观看模板卡片（当前样式等于某个预设时高亮）、上下留白滑块。

## 已批准的升级（docs/specs/UPGRADES.md）

| 编号 | 本页做了什么 | 状态 |
|---|---|---|
| B-21（含 C-2、B-9、B-10、B-11、B-23 的礼物） | 礼物显示为聊天行，可关 | 完成（C01.2） |
| B-12、B-13 的表情图片 | 聊天行改用 `EmoteText`（`chatSegments`） | 余下：消息模型带表情片段 |

其他和本页有关的条目（1-1 登录后播放轮播、B-16 酷狗 PK 来源标记、B-7 Cookie 失效提示）没有动，仍在“留给后续”。

## 留给后续（按重要程度）

1. **真机检查**（本次不装手机）：媒体通知和按钮、后台播放的暂停/恢复和唤醒锁、画中画进出（含 1.5 秒的短暂隐藏）、音量/亮度手势、投屏到真电视、外部 App 跳转；`AudioServiceActivity` 缓存引擎后录制在划掉界面后能否继续（H02.1 留下的）。
2. **应用内悬浮小窗**（`floatPlay`，离开直播间时继续小窗播放）和 **Windows 小窗**：要一个比页面活得久的“当前播放”服务（`lib/app`）和 window_manager（O03.1）。
3. **本地互动**（本地弹幕、礼物特效，`local_interaction/*`，约 2400 行；3.x 的 `localInteraction.*` 已在 J02.1 `legacy_values`）。
4. 竖屏的其余部分：竖屏全屏显示模式（`portraitFullscreenDisplayMode`）、方向覆盖按钮和按房间记忆（`portraitRoomOverrides`）、诊断。
5. 弹幕其余设置：帧率、字体、纯文字模式、斗鱼疑似自动弹幕过滤、画中画弹幕的颜色/速度/透明度/数量；画面弹幕的点击和长按操作。
6. 全屏顶栏的时间和电量、全屏里的关注按钮、画面比例的即时切换（现在只在设置里）、Android 预测返回。
7. 快手的 App 跳转（3.x 用房间的 `liveStreamId`，v4 的 `link` 是网页地址）。
8. 移动网络单独的画质偏好（缺网络类型服务，C01.1 已记）。

## 缺的共享服务或接口

| 内容 | 建议 |
|---|---|
| 消息模型没有表情片段：CHZZK 的 `{:name:}` 对应的图片在消息的 `emojis` 表里没上报，YouTube 自定义表情只留了快捷码 | live_core 给 `LiveMessage` 加表情（名字 → 地址），live_danmaku 填上；直播间在 `chat_panel.dart` 的 `chatSegments` 里转成 `ChatEmoteSegment` |
| `share_plus`（`SystemShare.sheet`） | O03.1 接上后分享自动用系统面板 |
| 比页面活得久的播放持有者（悬浮小窗、Windows 小窗） | `lib/app` 加一个当前播放服务，直播间把会话交给它 |
| window_manager | O03.1（Windows 小窗、窗口全屏） |

## 测试

`flutter test`（加速流程，只覆盖主要路径）：新增 12 个用例，原有直播间 14 个和多画面、首页、翻译、共享模块的测试仍全部通过；`flutter analyze` 无问题。

| 文件 | 用例 |
|---|---|
| `test/live_play_more_test.dart`（8） | 礼物行、开关隐藏并记在 `meta`、下次进房读回；纯音频不重开流、助眠进房即纯音频并定时、到时暂停并提示、后台规则；房间音量用 3.x 的键保存；网络电视的 UA 和频道请求头的先后、回看地址（`playseek`）、未开始的节目不能回看、返回直播；离开应用暂停/回来恢复、后台播放打开时不暂停、不可见时不判断画面停住；弹幕模板的预设、保存往返、3.x 缺字段的模板、坏模板；外部打开的目标；竖屏流的画面高度 |
| `test/live_play_more_page_test.dart`（3） | 菜单的定时关闭（剩余分钟显示在菜单里）、获取直链选画质和线路后复制；投屏对话框列出接收器并把所选地址设给它、提示已开始；礼物行显示、设置页关掉礼物写入存储、纯音频按钮显示封面；没有录制器时不显示录制按钮 |
| `packages/live_player/test/session_test.dart`（+1） | 看不见时不判断画面停住，重新可见后重新计时 |

## 合并时注意（冲突点）

- `assets/translations/zh.json`、`en.json`：只加了 18 个 `live_play_*` 键（`live_play_back_to_live`、`live_play_danmaku_bottom_margin`、`live_play_guide_*`（4 个）、`live_play_lock`、`live_play_mute`、`live_play_record_failed`、`live_play_show_gifts`、`live_play_show_gifts_desc`、`live_play_switch_empty`、`live_play_switch_replays`、`live_play_template_load`、`live_play_template_save`、`live_play_timer_left`、`live_play_unlock`、`live_play_unmute`），按键名排序。
- `apps/pure_live/pubspec.yaml`、根 `pubspec.lock`（audio_service 四个包）：O03.1 也会加插件。
- `android/.../MainActivity.kt`（父类改为 `AudioServiceActivity`、两个通道）、`AndroidManifest.xml`（两个 audio_service 组件）：O03.1 的插件也可能改这两处。
- `lib/shared/danmaku/danmaku_settings.dart`：`DanmakuSettingsPanel` 多了 `leading` 参数，`danmakuLookOf` 带上留白（多画面也随之生效）。
- `packages/live_player/lib/src/session.dart`：只加了 `setPresentationVisible`，多画面可以直接用。
- `docs/specs/UPGRADES.md` 的 B-12、B-13、B-21 三行。
