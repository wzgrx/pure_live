# A07.7 直播间的状态：设计（第 1 版，已确认并完成）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 范围：直播间没在正常播放时画面区域和信息行、弹幕区的样子——加载中、未开播（含封禁、轮播、状态未知）、获取失败、播放中断、断流重连、受限、纯音频、回放播完；网络电视的节目单和回看。下面的界面清点表是这一批出图的清单
- 对应：[TASKS.md](../../../TASKS.md)、[inventory/UI.md](../../../inventory/UI.md#a077)、[inventory/UI_FILES.md](../../../inventory/UI_FILES.md#a077)；依赖 [A07.1](../A07.1-竖屏普通布局/README.md)（E2、E3、E5 已确认，直接沿用），全屏照 [A07.4](../A07.4-横屏全屏/README.md)，宽屏照 [A07.5](../A07.5-宽屏左右分栏/README.md)，弹法照 [A07.6](../A07.6-直播间弹窗/README.md)
- 评审页：claude.ai 私有页面；源文件 [page.json](page.json)（`tools/ui/mock/page.py` 生成），效果图源文件 [src/gen.py](src/gen.py)
- 图片：v3 按 `v3.2.11` 代码还原（文字取自 `assets/translations/zh.json`，`tools/ui/strings.py`）；画面、头像、频道图标是示意图片
- 旧编号：U.2g、T05i.1；相关决定 D-003（Z1～Z4 按建议 A）

## 界面清点表

| 编号 | 界面 | 从哪出现 | 形态 | 状态 |
|---|---|---|---|---|
| A07.7-01 | 加载中（`VideoLoading`、播放器占位） | 进房、刷新、换清晰度和线路、播放器重建 | 竖屏、横屏全屏、宽屏 | 进房中；连接直播流（新）；加载较慢（新） |
| A07.7-02 | 未开播（`NotLivingVideoWidget`，INVENTORY 的 A07.7-01） | 进房或刷新时平台说没在播 | 竖屏、宽屏；全屏头部变体（返回、切换直播间、时间） | 未开播；已封禁；轮播（v4 数据）；状态未知 |
| A07.7-03 | 获取直播间信息失败（`RoomLoadFailedWidget`） | 直播间详情请求失败 | 三种 | 按原因：网络、风控、接口变化；直播间不存在 |
| A07.7-04 | 播放已中断（`PlaybackFailureOverlay`，INVENTORY 的 A07.7-02）+ 错误提示条 | 播放器报错 | 三种 | 中断；重试中；重试失败 |
| A07.7-05 | 断流重连 | 播放中断流，播放器自动恢复 | 三种 | v3 没有界面；新设计第 N 次、有无可换线路 |
| A07.7-06 | 受限 | 在播但取不到流（需要登录、付费、订阅、私密、仅 App、地区、密码、年龄、没给地址） | 三种 | v3 一直转圈 + 提示条；新设计按受限类型 |
| A07.7-07 | 纯音频（`buildAudioOnlyUI`） | 上栏耳机按钮、ASMR 自动纯音频 | 三种 | 纯音频；正在恢复实时画面 |
| A07.7-08 | 回放已播完（新） | 录播、回看放完 | 三种 | — |
| A07.7-09 | 网络电视节目单（`IptvScheduleDialogContent`） | 网络电视上栏节目单按钮 | 三种 | 加载中；加载失败；没有节目；没配置节目单来源（新分出）；列表；回看中；切换中 |
| A07.7-10 | 网络电视回看中 | 点节目单里过去的节目 | 三种 | 回看中；返回直播 |
| A07.7-11 | 状态附带的提示条 | 上面各状态 | 三种 | 见“提示条”一节 |

## 3.x 的样子和问题

文件在 `git show v3.2.11:lib/modules/live_play/...`（下面省略这个前缀）。

**画面区域选哪个占位**（`widgets/layout/live_play_video.dart:33-41,63-73`）：还没有播放器时，`isLoading` → 加载；有 `loadError` → 获取失败；`isLiving` 为真 → 加载，否则 → 未开播。有播放器以后画面由 `VideoPlayer` 画，播放器报错时盖一层 `PlaybackFailureOverlay`（`video_player.dart:45-57`）。

**信息行和弹幕区**：没成功时信息行是 56 高的空白（`resolution_selector/resolutions_row.dart:18-20`），弹幕区（四个标签和列表）整块不显示（`layout/live_play_content.dart:593-595`）。网络电视不显示信息行和弹幕区，只有画面靠上（`live_play_content.dart:60-66`、`:569`）。

**加载**：黑底，中间 24 像素的转圈（`video_player/video_loading.dart:9-13` → `common/widgets/app_status_view.dart:387-391`），样子和颜色来自设置“加载样式”，默认是带渐隐的圆环（`app_status_view.dart:497-530`）。没有文字，没有按钮；全屏时也只有这个（`live_play_content.dart:510-515`）。用链接进房、还不知道名字时，顶栏关注按钮的位置是 18 像素转圈（`layout/live_play_header.dart:75-82`）。

**未开播**（`widgets/placeholder/not_living_video_widget.dart`）：
- 头部（至少 55 高，45% 黑渐变，`:22-45`）：全屏时有返回 `Icons.arrow_back_rounded`（`:47,88-97`）；标题（14 号白字，标题、主播名、房间号依次取，`:49-60,143-149`）；全屏时再有切换直播间 `Icons.swap_horiz_outlined` 和时间（`:62-82`）。
- 中间三行白字：“无法播放直播”（16 号）、“该房间未开播或已下播”、“请切换其他直播间进行观看吧”（14 号）（`:119-132`）。没有按钮。
- 同时弹提示条“当前主播未开播或已下播”；封禁时弹“服务器错误,请稍后获取”（`controllers/live_play_controller.dart:788-790`）。判定未开播时退出全屏（`:782-784`）。

**获取直播间信息失败**（`live_play_video.dart:79-110`）：`Icons.error_outline_rounded`（36，白 70%）、“获取直播间信息失败,请重新获取”（白字）、浅色按钮 `refresh_rounded`“重试”。同时弹同一句提示条（`live_play_controller.dart:731-732`）。平台说状态未知时也走这里（`:817-848`）。

**播放已中断**（`video_player/playback_failure_overlay.dart`）：整片 33% 黑（`0x55000000`，`:49`，盖在控制栏上面）；中间卡片最宽 360、深灰 `0xEE202124`、圆角 12、内边距 12（`:51-60`）：“播放已中断”（16 号白字）、“重新加载直播间以获取最新播放源。”（13 号白 70%）、主色按钮 `Icons.refresh`“重试”，重试中按钮变灰（`:64-83`）。同时按错误类型弹提示条：网络连接失败、播放源异常、当前播放器解码失败、播放器异常、播放器初始化失败、视频渲染失败、播放器状态异常、未知播放错误（`video_controller.dart:732-757`）。

**断流重连**：播放器在 `player_manager.dart` 里自动恢复（刷新地址、换线路、换引擎），界面上没有任何提示；播放中的缓冲没有指示（`media_kit_adapter.dart:973-976` 用 `NoVideoControls`）。

**在播但放不了**（受限）：取清晰度或地址失败时弹提示条“无法读取视频信息 / 读取视频信息失败 / 无法读取播放地址”（`controllers/player_controller.dart:585-587,599-607,649-651`），`success=false` 但 `isLiving=true`，画面一直是加载转圈（`live_play_video.dart:72`）。弹幕其实已经连上（`live_play_controller.dart:748-756`），只是弹幕区被藏起来。

**纯音频**（`player/core/player_manager.dart:3292-3477`）：画面高度小于 500 时紧凑排（`:3297-3305`）；底层是头像放大铺满、22% 透明度、`#273047` 颜色滤镜（`:3310-3320`），上面一层深色斜向渐变（`:3326-3333`）；中间头像圆框（紧凑时 50–76，否则 100，白 15% 描边、外发光，`:3349-3370`，带一次 0.95→1.05 的缩放）、标题（紧凑 14 / 22 号粗体）、主播名小胶囊（11 / 13 号）、“纯音频模式”胶囊（耳机 `Remix.headphone_line`）；从纯音频切回时胶囊变蓝，转圈 +“正在恢复实时画面”（`:3416-3460`）。上栏耳机按钮变黄 `#FFD166`、`Remix.headphone_fill`（`video_controller_panel.dart:1927-1953`）。

**网络电视**：
- 画面上栏：标题（16 号粗体）下多一行“正在播放: 节目名”（白 85%）（`video_controller_panel.dart:340-371`）；标题后多一个节目单按钮 `Icons.assignment_outlined`（`:375-386`）。回看时这一行仍是直播中的节目。
- 节目单是居中对话框（`AlertDialog`，圆角 16，`:438-458`）：宽度屏幕宽 >600 时 460，否则 88%（受对话框边距限制，竖屏实际 313）；高度屏幕高 ≤600 时 92%，>800 时 550，否则 65%（`iptv_schedule_dialog.dart:46-53`）。
- 头部：`Remix.calendar_todo_line`（22，主色）+“电视节目表预告”（15 号粗体）+ `Remix.close_line`（20）（`:235-291`）；分隔线。
- 回看中时头部下是整行主色按钮 `Remix.live_line`“返回直播”，切换中转圈（`:63-71,200-233`）。
- 列表：读取节目单前后 3 天（往前 2 天、往后 1 天，`video_controller.dart:323-324,1022-1025`）；每行固定高 84，窄时（竖屏）上下排、120 高（`iptv_schedule_dialog.dart:108-113`）；行里是时间小块（`HH:mm`，正在播放的主色加粗）、标题（14 号，最多 3 行）、状态：正在直播是主色小标签 `Remix.live_line`“正在直播”（10 号白字），过去的节目 `Remix.history_line`（可回看灰 60%，不可回看禁用色，悬停说明“该节目不在可回看范围内”）（`:325-455`）；正在播放（回看时是正在回看）的一行主色淡底、细边（`:381-389`）。打开时滚到正在播放的一行在最上面（`:174-188`）；每 30 秒整体刷新一次（`:29-34`）；切换中顶上一条细进度条（`:163-169`）。
- 加载中：转圈；失败：`Remix.error_warning_line`（错误色）+“数据加载失败”+“重试”；空（含没配置节目单来源，`video_controller.dart:1013-1017`）：`Remix.inbox_line` +“暂无后续节目排班信息”（`iptv_schedule_dialog.dart:78-101`）。
- 点节目（`video_controller.dart:1099-1215`）：没开始 → 提示“该节目尚未开播”；正在播 → 返回直播；过去的、可回看 → 关对话框、提示“正在为您加载回看节目: 节目名”；不可回看 → 提示“该节目不在可回看范围内”；返回直播后提示“已返回直播”；失败提示“无法播放直播”“无效播放地址”。

**手势和快捷键**：没有播放器时（加载、未开播、获取失败、受限）画面上没有控制层，手势和快捷键（R 刷新等）都不起作用；播放中断、重连、纯音频时控制层照常（A07.4、A07.5 的快捷键）。

**按宽度分支**：未开播头部只在全屏时有返回、切换直播间、时间；节目单对话框宽度以 600 为界；纯音频以画面高 500 为界；宽屏（>680）时这些画面放在左侧画面区，右栏在没成功时空白。

**设计时 v4 的样子**（2026-10-01，`apps/pure_live/lib/features/live_play/player/player_status.dart`，行号是当时的）：已经有 `RoomStatusLayer`：“正在进入直播间…”、未开播（封面 + 头像 + 刷新）、获取失败按原因、受限原因、E3 重连、E5 纯音频封面、回放已播完、暂停时画面中间大暂停图标（v3 没有）；网络电视节目单是底部面板（`dialogs/iptv_guide.dart:35-41`，v3 是对话框），网络电视画面撑满剩余高度、下面放信息行（`live_play_page.dart:320-342`）；网络电视顶栏不显示录制按钮（`layout/room_header.dart:77-80`，v3 有）。

**3.x 的问题**

| 编号 | 问题 | 位置 |
|---|---|---|
| S1 | 加载只有一个 24 像素的转圈，不说在等什么；卡住时画面上没有任何按钮 | `video_loading.dart:13`、`live_play_video.dart:36-41` |
| S2 | 加载、未开播、出错时信息行 56 高空白，弹幕区整块空白，标签也不见 | `resolutions_row.dart:18-20`、`live_play_content.dart:593-595` |
| S3 | 全屏时加载只剩黑底转圈，没有返回键 | `live_play_content.dart:510-515` |
| S4 | 未开播三行字说一件事，还另弹提示条；叫人切换直播间却只有全屏头部有按钮，也没有刷新 | `not_living_video_widget.dart:47,62-82,119-132`、`live_play_controller.dart:788-790` |
| S5 | 留在未开播的直播间，开播了也不会播 | `live_play_controller.dart:682-735` |
| S6 | 判定未开播就强制退出全屏 | `live_play_controller.dart:782-784` |
| S7 | 封禁显示成“未开播”，提示条却是“服务器错误,请稍后获取” | `live_play_controller.dart:788-790` |
| S8 | 在播但放不了：只弹 3 秒提示条，画面一直转圈，没有原因和下一步 | `player_controller.dart:585-587,599-607,649-651`、`live_play_video.dart:72` |
| S9 | 播放中断的卡片不写原因（原因只在提示条），只有重试 | `playback_failure_overlay.dart:64-83`、`video_controller.dart:732-757` |
| S10 | 三种出错三个样子；暗化盖住控制栏 | `playback_failure_overlay.dart:49-58`、`live_play_video.dart:79-110`、`not_living_video_widget.dart:107-140` |
| S11 | 断流重连时画面停住，没有提示 | `media_kit_adapter.dart:975`、`player_manager.dart:249-265` |
| S12 | 纯音频用透明度、颜色滤镜、模糊阴影和缩放动画；标题、名字和上栏、顶栏重复 | `player_manager.dart:3310-3375` |
| S13 | 网络电视竖屏画面下面一大片空白 | `live_play_content.dart:60-66`、`:569` |
| S14 | 节目单是盖住画面的对话框，要点按钮才看得到 | `video_controller_panel.dart:438-458`、`iptv_schedule_dialog.dart:48-53` |
| S15 | 节目单没有日期；能回看的节目在上面看不见；竖屏一屏四个；不可回看的说明只在悬停时有 | `video_controller.dart:323-324`、`iptv_schedule_dialog.dart:108-122,174-187,373-376` |
| S16 | 回看时画面上看不出在回看，上栏还写直播中的节目；返回直播只在节目单里 | `video_controller_panel.dart:359-369`、`iptv_schedule_dialog.dart:63-71` |
| S17 | 没配置节目单来源也显示“暂无后续节目排班信息” | `video_controller.dart:1013-1017`、`iptv_schedule_dialog.dart:95-100` |
| S18 | 画面上写了还弹提示条（未开播、获取失败） | `live_play_controller.dart:732,788-790` |

必须保留的操作习惯（[specs/UI.md](../../../specs/UI.md) 附录 A）：第 7 条（返回链：节目单面板也先关）、第 16 条（R 刷新；没在播放时也能用）。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 18 种画面状态一个组件；三种形态的整屏对比；网络电视节目单和回看；四处选择 | 2026-10-01 确认全部设计，Z1～Z4 按建议 A |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [对比：画面区域的每一种状态](page/02-对比-画面区域的每一种状态.jpg)
- [对比：竖屏（加载、未开播、播放中断）](page/03-对比-竖屏-加载-未开播-播放中断.jpg)
- [对比：竖屏（重连、受限、纯音频）](page/04-对比-竖屏-重连-受限-纯音频.jpg)
- [对比：横屏全屏](page/05-对比-横屏全屏.jpg)
- [对比：宽屏](page/06-对比-宽屏-平板-Windows-Linux-iPad-macOS.jpg)
- [网络电视：节目单和回看](page/07-网络电视-节目单和回看.jpg)
- [v3 的问题](page/08-v3-的问题.jpg)
- [改了什么](page/09-改了什么.jpg)
- [每个按钮是干什么的、怎么用](page/10-每个按钮是干什么的-怎么用.jpg)
- [各客户端](page/11-各客户端.jpg)
- [需要你选的](page/12-需要你选的.jpg)
- [性能要点](page/13-性能要点.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-states.jpg](v3-states.jpg)、[v4-states.jpg](v4-states.jpg)、[v4-states-n.jpg](v4-states-n.jpg) | 画面区域的全部状态（竖屏尺寸）：v3 10 种 / 新设计 18 种 / 按钮编号 |
| [v3-p-loading.jpg](v3-p-loading.jpg)、[v4-p-loading.jpg](v4-p-loading.jpg) | 竖屏加载（用链接进房，名字还不知道） |
| [v3-p-offline.jpg](v3-p-offline.jpg)、[v4-p-offline.jpg](v4-p-offline.jpg)、[v4-p-offline-n.jpg](v4-p-offline-n.jpg) | 竖屏未开播 |
| [v3-p-failed.jpg](v3-p-failed.jpg)、[v4-p-failed.jpg](v4-p-failed.jpg) | 竖屏播放中断 |
| [v3-p-reconnect.jpg](v3-p-reconnect.jpg)、[v4-p-reconnect.jpg](v4-p-reconnect.jpg) | 竖屏断流重连 |
| [v3-p-restricted.jpg](v3-p-restricted.jpg)、[v4-p-restricted.jpg](v4-p-restricted.jpg) | 竖屏受限（付费） |
| [v3-p-audio.jpg](v3-p-audio.jpg)、[v4-p-audio.jpg](v4-p-audio.jpg) | 竖屏纯音频 |
| `v3-l-*.jpg`、`v4-l-*.jpg`（loading、offline、failed、reconnect、restricted、audio）、[v4-l-offline-n.jpg](v4-l-offline-n.jpg) | 横屏全屏 852×393，同上六种 |
| `v3-w-*.jpg`、`v4-w-*.jpg`（同上六种） | 宽屏 1280×800 |
| [v3-p-iptv.jpg](v3-p-iptv.jpg)、[v3-p-iptv-guide.jpg](v3-p-iptv-guide.jpg)、[v4-p-iptv.jpg](v4-p-iptv.jpg)、[v4-p-iptv-catchup.jpg](v4-p-iptv-catchup.jpg)（及 `-n`） | 网络电视竖屏：v3 空白 / v3 对话框 / 新设计节目单 / 新设计回看中 |
| [v3-l-iptv-guide.jpg](v3-l-iptv-guide.jpg)、[v4-l-iptv-guide.jpg](v4-l-iptv-guide.jpg)（及 `-n`） | 网络电视横屏回看中 |
| [v3-w-iptv-guide.jpg](v3-w-iptv-guide.jpg)、[v4-w-iptv.jpg](v4-w-iptv.jpg)（及 `-n`） | 网络电视宽屏 |
| [v3-guide-states.jpg](v3-guide-states.jpg)、[v4-guide-states.jpg](v4-guide-states.jpg)（及 `-n`） | 节目单的加载、失败、空、没配置来源 |

## 确认的改动

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 保留 | 状态出现的时机和判断；“加载样式”设置；播放中断时控制栏可用；自动恢复逻辑；耳机变黄；节目单的点法和加载、失败、空 | — |
| c2 | 修改 | 一个画面状态组件（图标或转圈、一句话、一句原因、最多两个按钮），各形态同一个 | S10 |
| c3 | 增强 | 转圈下写“正在进入直播间…”“正在连接直播流…” | S1 |
| c4 | 增强 | 8 秒还没画面：“比平时慢，可以换一条线路试试”+ 换线路、重试 | S1（Z4） |
| c5 | 修改 | E2 占位；标签照常可用；没在播放时画面上不显示上下栏 | S2 |
| c6 | 修改 | 全屏非播放状态保留精简上栏（返回、时间电量、标题、切换直播间、录制、菜单） | S3 |
| c7 | 修改 | 未开播：封面 + 头像 + 一句话 + 切换直播间、刷新；不弹提示条；“未开播”标签；弹幕区显示公告 | S4、S18 |
| c8 | 增强 | 未开播时每 60 秒查一次，开播自动播放 | S5（Z2） |
| c9 | 修改 | 全屏中下播留在全屏 | S6（Z3） |
| c10 | 修改 | 封禁、轮播、状态未知、不存在、获取失败各写各的 | S7 |
| c11 | 增强 | 受限写原因和下一步（去登录、在平台打开、重试、切换直播间）；红框标签；弹幕照常 | S8 |
| c12 | 修改 | 播放中断：原因写在画面上，重试、换线路；不弹提示条；暗化 60% 不盖控制栏 | S9、S10 |
| c13 | 保留 | 重连照 E3，加 45% 暗化 | S11 |
| c14 | 保留 | 纯音频照 E5；保留“正在恢复实时画面”；去掉透明度、滤镜、模糊、缩放 | S12 |
| c15 | 增强 | 回放已播完：从头播放、切换直播间 | 原则 4 |
| c16 | 修改 | 节目单：竖屏在画面下方，横屏右侧面板，宽屏占右栏可收起；同一个组件 | S13、S14（Z1） |
| c17 | 修改 | 节目单按日期分组、正在播的在第三行、“回看”文字、超范围变灰、直播红标签、“可回看 N 天”、标题改“节目单” | S15 |
| c18 | 增强 | 回看中：画面角标、上栏副标题、节目单顶上的条和“返回直播”；不弹提示条 | S16 |
| c19 | 修改 | 没配置节目单来源：“还没有节目单”+ 去导入节目单 | S17 |

## 按钮的作用和用法

| 编号 | 控件 | 怎么用 |
|---|---|---|
| 1 | 切换直播间 | 打开切换窗口换一个直播间；在未开播、封禁、受限、不存在、回放播完的画面上 |
| 2 | 刷新 | 重新取直播间信息，开播了就开始播放；键盘 R |
| 3 | 重试 | 获取失败、播放中断、地区受限、没给地址时重新加载；节目单读取失败时重读节目单 |
| 4 | 换线路 | 换下一条线路（有多条时才有）：加载较慢、重连中、播放中断 |
| 5 | 去登录 | 打开这个平台的登录，登录后回来自动重试 |
| 6 | 在平台打开 | 跳平台 App 或网页（同菜单里的“打开直播间”） |
| 7 | 从头播放 | 录播、回看放完后重看 |
| 8 | 节目单按钮 | 竖屏回到正在播的节目；横屏打开右侧节目单；宽屏展开收起的栏 |
| 9 | 节目 | 过去的回看，正在播的返回直播，没开始的提示，变灰的提示不在回看范围 |
| 10 | 返回直播（节目单顶上） | 结束回看 |
| 11 | 回看角标 | 点“返回直播”回到直播，点其他地方打开节目单 |
| 12 | 收起节目单栏（宽屏） | 同 A07.5 收起聊天栏的把手 |
| 13–16 | 返回、切换直播间、录制、菜单（全屏没在播放时） | 同 A07.4 |
| 17 | 公告“展开” | 展开完整公告 |
| 18 | 关闭（横屏节目单面板） | 关闭；返回键、Esc、点画面也可以 |
| 19 | 去导入节目单 | 打开网络电视管理的节目单导入 |

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 竖屏、横屏全屏如图；竖屏画面矮时省掉状态图标 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 状态组件在左边画面里，右栏照 A07.5；网络电视节目单占右栏；悬停显示名称；R 刷新或重试（没在播放时也能用），Esc 关面板、退全屏，节目单上下键、回车 |
| 电视 | 同一组件的电视样式（字号大一级、按钮可聚焦、默认焦点在第一个按钮）；未开播的“切换直播间”“刷新”对应 pure_live_TV 的未开播页；节目单放进右键打开的设置面板（A17.4、A17.5） |
| 苹果平台差异 | 同宽屏；iPhone 全屏时避开灵动岛一侧安全区；macOS Cmd+R |

## 待选和决定

- Z1 网络电视节目单：**A** 竖屏画面下方、横屏右侧、宽屏右栏；B 照 v3 弹对话框。→ 选 A（2026-10-01）。
- Z2 未开播时：**A** 每 60 秒查一次、开播自动播放；B 照 v3 手动刷新。→ 选 A。
- Z3 全屏时下播：**A** 留在全屏；B 照 v3 退出全屏。→ 选 A。
- Z4 加载较慢：**A** 8 秒后提示并给换线路、重试；B 照 v3 只转圈。→ 选 A。

## 提示条

| v3 提示条 | 位置 | 新设计 |
|---|---|---|
| 当前主播未开播或已下播 | `live_play_controller.dart:788-790` | 去掉（画面上写了） |
| 服务器错误,请稍后获取（封禁） | 同上 | 去掉；画面写“该直播间已被平台封禁或关闭” |
| 获取直播间信息失败,请重新获取 | `:732`、`:820`、`:825` | 去掉（画面上写原因） |
| 无法读取视频信息 / 读取视频信息失败 / 无法读取播放地址 | `player_controller.dart:586,606,650` | 去掉；画面写受限原因或“平台没有给出可播放的直播流” |
| 网络连接失败等 8 种播放错误 | `video_controller.dart:741-757` | 去掉；写在播放中断画面上 |
| 无效播放地址 | `live_play_controller.dart:855` | 保留（网络电视地址为空） |
| 该节目尚未开播 / 该节目不在可回看范围内 | `video_controller.dart:1111,1128,1153` | 保留 |
| 正在为您加载回看节目: 节目名 / 已返回直播 | `video_controller.dart:1168,1205` | 去掉（角标和节目单顶上的条说明了） |
| 无法播放直播（回看、返回直播切换失败） | `video_controller.dart:1165,1172,1202,1209` | 改为画面上的播放中断状态 |

## 新文字（要加进 i18n）

正在连接直播流…；比平时慢，可以换一条线路试试；去登录；开播后这里显示弹幕；节目单；可回看 {n} 天；不支持回看；正在回看: {节目}；正在回看 · {日期} {时间}；回看；回看中；回看 {时间}；今天 / 昨天 / 明天 · {M}月{d}日 {周几}；正在读取节目单…；节目单读取失败；去导入节目单；这个频道在节目单里没有节目。其余文字是 v3 或 v4 已有的词条（`stream_not_live`、`live_play_offline_hint`、`live_play_banned`、`live_play_carousel`、`live_play_status_unknown`、`live_play_error_*`、`room_mark_*_hint`、`live_play_reconnecting`、`live_play_switch_line`、`live_play_open_in`、`live_play_audio_only_playing`、`restoring_live_video`、`live_play_replay_ended`、`live_play_replay_again`、`playback_failure_title`、`error_*`、`live_tag`、`return_to_live`、`iptv_no_guides`、`iptv_no_guides_desc`、`no_upcoming_programs`、`load_failed`、`program_scheduled_hint`、`catchup_unavailable`）。

## 拿不准的地方（设计时记下的）

1. **v3 断流时有没有转圈**：代码里播放中的缓冲没有任何指示（`NoVideoControls`），只有播放器被彻底释放后重建时才显示占位转圈（`player_manager.dart:3501-3502,3575-3579`）。A07.1 的 E3 写的“v3 只显示转圈”可能指进房和重建；图里按代码画成“画面停住、没有提示”，请对照 3.x 真机。
2. **v3 全屏未开播头部什么时候出现**：判定未开播时会先退出全屏（`live_play_controller.dart:782-784`），带返回和切换直播间的头部（`not_living_video_widget.dart:47,62-82`）只在退出前一瞬或电脑窗口内全屏时可能看到；图里照代码画了。
3. **宽屏 v3 画面外的底色**：照 A07.5 的还原画成黑底（代码里 16:9 画面外是页面底色），和 A07.5 一致，没单独核对。
4. **v3 提示条的样子**：没找到 v3 自定义样式，按 `flutter_smart_dialog` 5.3.0 默认（黑底、圆角 20、离底 50、3 秒）画。
5. **网络电视的录制按钮**：v3 有，v4 现在隐藏（`room_header.dart:77-80`）；图里照 v3 画，是否支持录网络电视不在本任务范围。
6. **“换线路”图标**：`AppIcons` 里还没有，图里用 Material `alt_route`；需要在 A01.3 加一个 `switchLine`。“已封禁”用 `block`、“状态未知”用 `help_outline`，也要加进 `AppIcons`。
7. **“去登录”跳到哪**：账号页里这个平台的登录（A12.2 还没设计）。
8. **可回看天数**：取频道的 catchup-days；频道没写时头部建议不显示天数，只在不支持回看时写“不支持回看”。
9. **v4 现在暂停时画面中间的大暂停图标**（`player_status.dart`）v3 没有，不在本任务范围，留给 A07.1/U.2c 决定。
10. **“画面矮时省掉图标”的界线**：图里竖屏 16:9（221 高）省掉了加载、播放中断的图标，但未开播的头像、受限的锁保留；开发时按画面高度 <260 省掉图标、受限和未开播保留头像或锁，具体数值待开发时按 1.3 倍字体验证。

## 文件对照（v3 → v4）

| v3 | v4 |
|---|---|
| `widgets/layout/live_play_video.dart`、`widgets/video_player/video_loading.dart`、`widgets/placeholder/not_living_video_widget.dart`、`widgets/video_player/playback_failure_overlay.dart` | `features/live_play/player/player_status.dart`（`RoomStatusLayer`） |
| `player/core/player_manager.dart` 的 `buildAudioOnlyUI` | `features/live_play/player/player_status.dart`（`AudioOnlyCover`） |
| `widgets/video_player/iptv_schedule_dialog.dart`、`iptv_programme_policy.dart` | `features/live_play/dialogs/iptv_guide.dart`；`packages/live_iptv` |
| `controllers/live_play_controller.dart`（`_handleNotLiveRoom`、`_handleUnknownStatus`）、`controllers/player_controller.dart`（`getPlayQualites`） | `features/live_play/logic/room_controller.dart`（`RoomStage`）、`logic/reconnect_watch.dart` |
| `resolution_selector/resolutions_row.dart`（没成功时空白） | `features/live_play/layout/room_info_bar.dart`（E2 占位） |

## 实现和验证

**实现**（详见 [record.md](record.md)；2026-10-01，和 A08.1（弹幕标签的状态）一起合并，合并提交 `381ff16f1`“Merge U.2e and U.2g: chat tab states and room states”；登记表记的是记录提交 `05793a4c8`）

分工：竖屏、横屏全屏、宽屏的排法当时由 A07.2～A07.5 同时改；这里只做画面状态组件、状态逻辑和接入点，以及网络电视的节目单和回看（包括它在三种布局的位置）。

| 编号 | 做到 | 现在的代码和说明 |
|---|---|---|
| c1 | ✅ | 转圈用用户的“加载样式”（`LoadingStyles`，没设颜色时白色） |
| c2 | ✅ | `packages/live_ui/lib/src/widgets/video_state_view.dart:38` 的 `VideoStateView`（转圈或图标或主播头像 → 一句话 → 原因 → 最多两个按钮，第一个白底、第二个描边；可选 45% / 60% 暗化；`compact` 省掉图标）；画面高 <260 省图标，未开播的头像和受限的锁保留 |
| c3 | ✅ | “正在进入直播间…”→“正在连接直播流…”（`live_play_connecting_stream`） |
| c4 | ✅ | `apps/pure_live/lib/features/live_play/player/player_status.dart:32` 的 `RoomStatusLayer` 里 8 秒计时（`slowAfter`）；只有一条线路时只有“重试”；A07.10 后“画面已经出来后的缓冲”不再算加载较慢 |
| c5 | ✅ | 上下栏按 `logic/room_status.dart:185` 的 `pictureHasControls`（只有打开了直播流才显示） |
| c6 | ✅（当时部分） | 全屏精简上栏 `PlayerTopBar.reduced`：去掉纯音频、投屏、小窗；时间电量、录制、菜单由 A07.4 合并时接上 |
| c7 | ✅ | 未开播：封面 + 头像 + 一句话 + 切换直播间、刷新；不弹提示条；信息行“未开播”标签（`layout/room_info_bar.dart:80` 的 `offlineMark`）；弹幕区公告卡片 + “开播后这里显示弹幕”（`danmaku/chat_list.dart:930` 的 `RoomNoticeState`） |
| c8 | ✅ | v4 原有的 `refreshDetail`（`logic/room_controller.dart:325-327` 的 60 秒定时器，`:758`）；“进后台时停止”没有另做 |
| c9 | ✅ | v4 本来就不退出全屏；有测试 |
| c10 | ✅ | 不存在只给“切换直播间”；状态未知“刷新”在前 |
| c11 | ✅ | 需要登录：去登录、重试；付费、订阅、私密、仅 App、密码、年龄：在{平台}打开、切换直播间（网络电视改为重试、切换直播间）；地区、没给地址：重试、切换直播间；受限房间弹幕照常连、不再每 60 秒整个重新加载 |
| c12 | ✅ | 播放中断：原因写在画面上，重试、换线路；暗化 60% 不盖控制栏（状态层在控制层下面） |
| c13 | ✅ | 重连 45% 暗化；次数后来按 A07.10 c4 由播放会话报告 |
| c14 | ✅（有偏差） | `player_status.dart:333` 的 `AudioOnlyCover`；播放会话不报告“第一帧”，“正在恢复实时画面”显示到画面尺寸重新报告或最多 3 秒 |
| c15 | ✅ | 从头播放、切换直播间 |
| c16 | ✅ | `dialogs/iptv_guide.dart:78` 的 `IptvGuideView` 一个组件三处：竖屏 16:9 画面下（`live_play_page.dart:1174-1198`）、宽屏右栏可收起（`:1144-1172`）、全屏右侧面板 `RoomPanelKind.guide`；上栏节目单按钮 `_revealGuide`（`:678`） |
| c17 | ✅ | `logic/iptv_guide_rows.dart:59` 的 `guideEntries`：按日期分组、行高 52、正在看的在第三行；每 30 秒刷新标记；频道没写天数时不显示天数，不支持回看时写“不支持回看” |
| c18 | ✅ | 回看角标 `CatchupBadge`（`player_status.dart:388`，“回看 19:30 · 返回直播”）；回看失败显示为画面上的播放中断 |
| c19 | ✅ | “还没有节目单”+ 去导入节目单（路由 `/iptv`），和“这个频道在节目单里没有节目”分开 |

- Z1～Z4 都按 A（见 c16、c8、c9、c4）。
- `live_ui` 的添加：`VideoStateView`；`AppIcons.switchLine`（`alt_route`）、`banned`、`statusUnknown`、`login`、`guideTitle`、`catchup`、`liveNow`、`guideEmpty`、`guideFailed`、`add`、`unfoldLeft` 等；颜色角色 `OnVideoColors.dimLight`（45%）、`buttonInk`、`buttonFill`、`buttonOutline`、`avatarRing`，`InkOnColor.contrastOn` / `contrastMutedOn`。
- 新增的文字：`live_play_connecting_stream`、`live_play_slow_hint`、`live_play_go_login`、`live_play_catchup_badge`、`live_play_guide_*`（节目单 13 条）、`live_play_weekday_1`～`7`、`live_play_chat_after_live`；改了 `live_play_guide_failed` 的中文（“读取节目单失败”→“节目单读取失败”）。
- 门禁：`live_play` 直接写的颜色和图标 9 → 8（和 A08.1 合计）。
- 没做的（记录）：全屏精简上栏的时间电量、录制、菜单（A07.4 接上）；宽屏节目单栏的把手（A07.5 合并后换成同一个 `_ColumnHandle`）；未开播检查在应用进后台时停止（现在仍在后台照查，见子分类 README 已知问题）；“去登录”先跳账号页，回来自动重试（具体到平台的登录在 A12.2）；暂停时画面中间的大暂停图标（后来 A07.10 定为 ▶ 圆底）；网络电视顶栏的录制按钮；电视（A17.4、A17.5）。

**验证**

- 自动测试：`apps/pure_live/test/features/live_play/live_play_states_test.dart`（新，当时 19 个，现在 21 个）：逻辑（加载、连接、较慢；未开播、封禁、轮播、状态未知的文字和按钮顺序；获取失败和不存在；受限各类型；播放中断、重连、纯音频、恢复、播完；只有打开了直播流才有上下栏；节目单分组、各行状态、第三行、日期、可回看天数）；直播间里（加载时文字和转圈、没有上下栏、标签可用；未开播的头像、按钮、不弹提示条、“未开播”标签、公告；受限的按钮和弹幕照常；较慢 8 秒；全屏未开播的精简上栏；宽屏状态在左边）；网络电视（竖屏节目单在画面下面、宽屏右栏收起和展开、全屏右侧 360 面板、Esc 先关面板、节目单四种状态）。`packages/live_ui` +3（`VideoStateView`）。改了 1 处原有断言（不存在的直播间没有“重试”）。当时 `apps/pure_live` 310 个全部通过。
- 真机：没有逐项看（S02.2、S02.3 没测网络电视；[CHECKLIST](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 3 条（断网重连）、第 4 条（未开播）、第 9 条（纯音频）、第 17 条（网络电视节目单和回看）还没有结果）。
- 留下的问题和去向：真机验证 → 和直播间其他真机一起补；未开播检查在后台照跑 → 无任务（逻辑归 C01，见报告）；“去登录”到具体平台 → A12.2。
