# A07.16 京东直播间用平台给的模糊图作背景：设计（第 1 版，定稿）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 范围：京东直播的直播间里用到“封面”作背景的几处：竖屏流的沉浸背景（竖屏全屏、横屏全屏和宽屏里的竖屏流）、纯音频的封面、恢复播放时的暗封面
- 对应：已批准升级 [28-3](../../../specs/UPGRADES.md)（“进房后封面用列表卡片的封面，模糊图只作背景”）；平台任务 [E02.9 京东直播](../../../E-直播平台/E02-其他国内平台/E02.9-京东直播/record.md)（问题 4、升级落地 28-3）；沉浸背景的设计在 [A07.2](../A07.2-竖屏流和竖屏全屏/README.md)
- 评审页：没有（定稿说明见“各版的经过”：只换背景图的来源，样子沿用已确认的 A07.2 c12 沉浸背景和 C01.2 暗封面）
- 来源：V03.3 核对升级表时，28-3 的界面部分写着“直播间设计没有背景图的位置 → 未排”，开了本任务

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| A07.16-01 | 京东竖屏流的沉浸背景 | 京东直播间，竖屏全屏（画面模式“沉浸背景”“平衡填充”） | 竖屏 | 播放中 |
| A07.16-02 | 京东竖屏流在横屏全屏、宽屏里的两边背景 | 横屏全屏；宽屏（平板、Windows）的直播间 | 横屏、宽屏 | 播放中 |
| A07.16-03 | 京东纯音频的封面 | 直播间菜单 → 纯音频 | 竖屏、横屏、宽屏 | 播放中、暂停 |
| A07.16-04 | 京东恢复播放时的暗封面 | 断网恢复、刷新时 | 竖屏、横屏、宽屏 | 恢复中 |

## 3.x 的样子和问题

- 3.x 的京东平台（`git show v3.2.11:lib/core/site/jdlive/jd_live_api.dart`）：列表卡片的封面是 `indexImage`（`:234`），进房的播放接口给的封面是 `blurredImg`（`:264`，一张平台做好的模糊画面）；`enrich`（`:49-60`）只在详情封面为空时才用卡片的，所以**进房后房间的封面总是模糊图**，并随关注存下（E02.9 记录问题 4）。
- 3.x 的直播间背景：`lib/modules/live_play/widgets/layout/live_play_content.dart:521-526` 用 `resolvePortraitFullscreenBackgroundUrl`（`:606-618`）按“详情封面 → 房间封面 → 详情头像 → 房间头像”取第一个，京东取到的就是模糊图；画在 `PortraitFullscreenPresentation`（`:623-671`，每帧实时模糊，A07.2 的 Q6）。
- 问题：P1 模糊图当了封面，关注页、观看历史的卡片也变成模糊图（E02.9 问题 4，平台层 28-3 已改）；P2 平台层改了以后，直播间的背景只能用卡片封面，**没见过卡片时**（从关注进、应用重启后、粘贴链接进）京东房间没有封面，背景退到头像（播放接口也没有头像）再退到纯渐变。

## v4 现在

- 平台层（E02.9，28-3 已做）：`packages/live_core/lib/src/sites/jdlive/jdlive_api.dart:86-88` 的 `JdLiveRoom.background`（播放接口的 `blurredImg`，`:480`），`cover` 只用卡片的 `indexImage`；`getRoomDetail`（`jdlive_site.dart:333`）给的 `LiveRoom.data` 就是带 `background` 的 `JdLiveRoom`。应用里没有读它的代码（`apps/pure_live/lib` 搜 `JdLiveRoom` 没有结果）。
- 沉浸背景：`apps/pure_live/lib/features/live_play/player/player_view.dart:494-497` 的 `_cover`（房间封面，没有就头像），`:522` 画 `AmbientBackdrop(cover: _cover)`；`packages/live_ui/lib/src/widgets/ambient_backdrop.dart:17` 的 `AmbientBackdrop` 把封面按 24 像素宽解码再放大（`ambientCoverDecodeWidth`，一次模糊）、放大 1.14 倍、盖 15% 黑。
- 纯音频、恢复中：`apps/pure_live/lib/features/live_play/player/player_status.dart:321`、`:351` 的 `_DimmedCover(url: room.cover)`。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 0 版 | 只有上面的核对和建议，还没出图 | — |
| 第 1 版（2026-10-08） | 定稿：c1～c3 按建议，X1、X2 选 A（D-003，维护者按建议定）。不出图：四处的样子（`AmbientBackdrop` 的渐变、放大 1.14 倍、15% 黑罩；暗封面）都是已确认的设计，只换图的地址；图的观感就是 3.x 京东直播间的模糊画面 | 按 D-003 定，用户可以推翻 |

## 对比页（按章节导出）

无：没有新的布局和控件，不出评审页（第 1 版说明）。

## 单张图

无：同上。改前改后的差别只在背景是哪张图：没见过卡片时 v4 现在是纯渐变，改后是平台的模糊画面（和 3.x 一样）。

## 确认的改动

已确认（第 1 版，D-003）：

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 修改 | 直播间取背景图时，京东房间（`room.data is JdLiveRoom` 且 `background` 不空）**先用 `background`**，再按现在的“封面 → 头像”；`AmbientBackdrop` 不用改（模糊图再低清放大一次看起来一样） | P2 |
| c2 | 修改 | 纯音频和恢复中的暗封面（`_DimmedCover`）同样先用 `background`；语音直播的封面（A07.20，同一个 `AudioOnlyCover`）跟着一样 | P2 |
| c3 | 保留 | 卡片、关注、观看历史的封面仍只用卡片封面（28-3 平台层的改动不回退） | P1 |

## 按钮的作用和用法

无：只换背景图，没有新控件。

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 竖屏全屏、横屏全屏的竖屏流、纯音频、恢复中四处 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 宽屏直播间里的竖屏流两边背景，同一个 `AmbientBackdrop` |
| 电视 | 电视直播间（A17.4）用同一个取背景的函数，以后做电视时接上 |
| 苹果平台差异 | 无 |

## 待选和决定

- X1：取背景的函数放哪。**定：A**（D-003）。A（建议）放在应用里（`apps/pure_live/lib/features/live_play/logic/` 加 `roomBackdropOf(LiveRoom)`，认 `JdLiveRoom`），不改模型；B 在 `LiveRoom` 加通用的 `backdrop` 字段（E05 模型扩展，要考虑 3.x JSON 兼容和关注存储）。理由：只有京东一个平台给模糊图，A 改动小、不动存储。
- X2：见过卡片时也优先用模糊图吗。**定：A**（D-003）。A（建议）是：模糊图是平台对当前画面做的，比卡片封面更接近正在播的画面；B 只在没有封面时用。

## 实现和验证（开发后补）

- 2026-10-08 做完（待真机）：`apps/pure_live/lib/features/live_play/logic/room_backdrop.dart` 的 `roomBackdropOf(room, {orAvatar})`（京东模糊图 → 封面 → 头像）；沉浸背景（`player_view.dart` `_cover`）、纯音频和语音直播的封面（`player_status.dart` `AudioOnlyCover`）用它；恢复中、未开播等状态的暗封面用 `orAvatar: false`（其他平台照旧只用封面）。根因、测试和真机步骤见 [record.md](record.md)。
