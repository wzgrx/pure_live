# N01.2 多画面的飞行弹幕跟随弹幕帧率设置

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：V03.3（2026-10-03）核对功能清点时发现：F-MV-05（多画面弹幕）原来记“完成”，但 D05.1 记录的“合并时注意”写着“多画面不在本批目录：它的弹幕层自动有字体和纯文字，帧率仍然每个刷新周期都画”，一直没有任务；F-MV-05 因此改成“部分”，登记本任务（登记表 `from`：“V03.3 功能清点 F-MV-05；D05.1 记录‘合并时注意’”）。之后 D03 子分类页发现多画面也不传表情表、O05 子分类页发现多画面不看“屏幕常亮”设置，都建议在这里顺带（可选，见“方案”）。
- 相关：D05.1（直播间的弹幕帧率、字体、纯文字，[记录](../../../D-弹幕/D05-弹幕设置生效/D05.1-弹幕设置生效/record.md)）；D03.1（弹幕层按刷新率的整数分之一画）；N01.1（多画面）；A13.2（多画面界面）；O05.1（屏幕常亮）；任务书 [brief.md](brief.md)

## 目标

多画面里每一格的飞行弹幕和直播间一样，按“弹幕帧率”设置画（“弹幕帧率跟随界面刷新率”开时按界面刷新率的档位，关时用手动的 30～240），不再每个刷新周期都画。4 格同时有弹幕时，帧率设低能省电。可选：表情显示成图片（同直播间）、跟随“屏幕常亮”设置。

## 3.x 和现状

| 方面 | 3.x（文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 多画面弹幕的帧率 | `git show v3.2.11:lib/modules/multiview/multiview_page.dart:1306-1308`：`fps: settings.danmakuAutoFps.v ? settings.resolvedDanmakuFps(refreshRateMode: …) : settings.danmakuFps.v.clamp(30, 240)` | `apps/pure_live/lib/features/multiview/multiview_page.dart:877-882`：`DanmakuOverlay(messages:, retractions:, look:, running:)`，没有 `fps`、`refreshRate`；`DanmakuOverlay`（`shared/danmaku/danmaku_overlay.dart`，`fps` 参数 `:159`、字段 `:185`、`refreshRate` `:188`）在 `fps` 为 null 时每个刷新周期都画（`:433` 用 `danmakuFrameDivisor` `:130`） | 照直播间传 `fps` 和 `refreshRate` |
| 直播间（对照） | `lib/modules/live_play/widgets/video_player/video_controller_panel.dart:786-811` | `features/live_play/player/player_view.dart:457-490`：`ValueListenableBuilder<DisplayModeInfo?>(DisplayMode.info)` 里 `fps: resolvedDanmakuFps(automatic:, configured:, mode:, maxRefreshRate:, currentRefreshRate:)`、`refreshRate:`、`emotes: _emotes`；三个设置在 `:551-555` 读（`danmakuAutoFps`、`danmakuFps`、`refreshRateMode`）；`_FpsSettings` `:824`；`resolvedDanmakuFps` 在 `shared/danmaku/danmaku_templates.dart:210` | — |
| 字体、纯文字 | 3.x 多画面同样跟设置（`multiview_page.dart:1305-1312`） | 已跟：`multiview_page.dart:873` 的 `danmakuLookOf(ref)` | 不变 |
| 表情（可选） | 3.x 多画面的弹幕组件同直播间 | 没传 `emotes`，表情显示成文字；直播间 `player_view.dart:212-236` 按平台取 `EmoteTable` | 传选中格平台的表情表 |
| 屏幕常亮（可选） | media_kit `Video` 默认常亮，3.x 多画面不看设置（`multiview_page.dart:994`） | `widgets/cell_view.dart:92` 的 `LiveVideoView` 没传 `keepScreenOn`（默认 `true`）；直播间 `player_view.dart:503-516` 传设置 | 传 `Settings.enableScreenKeepOn` |

## 方案

- c1 `multiview_page.dart:868-884` 的弹幕 `Consumer` 里照 `player_view.dart` 读 `Settings.danmakuAutoFps`、`Settings.danmakuFps`、`Settings.refreshRateMode` 和 `DisplayMode.info`（`ValueListenableBuilder<DisplayModeInfo?>`），算 `resolvedDanmakuFps(...)` 传给 `DanmakuOverlay.fps`，并传 `refreshRate`。
- c2 有共同部分可以提一个小函数或组件（例如在 `shared/danmaku/` 里根据设置和显示信息算帧率），直播间和多画面共用，避免两处各写一遍；直播间的行为不变。
- c3（可选，维护者同意后做）表情：多画面格子的弹幕层传选中格平台的 `EmoteTable`（和直播间同一个来源）。
- c4（可选，维护者同意后做）屏幕常亮：`cell_view.dart:92` 传 `keepScreenOn: watchSetting(ref, Settings.enableScreenKeepOn)`（3.x 不跟，这是改进，要写进记录）。

## 性能任务：测量

| 指标 | 改之前 | 目标或结果 | 怎么测 |
|---|---|---|---|
| 4 格、开着弹幕时的 UI 线程帧时间 | 待测（每个刷新周期都画） | 帧率设 30 时明显下降 | profile 构建，`adb shell dumpsys gfxinfo com.mystyle.purelive.v4dev` 的 percentile，对比改前改后 |

## 验证

- 自动测试：`apps/pure_live/test/features/multiview/multiview_page_test.dart`（`:301` 已有取格子里 `DanmakuOverlay` 的写法）加：手动 30 帧时格子里的 `DanmakuOverlay.fps` 是 30；跟随界面刷新率、界面刷新率“省电”时是 60；改设置后不重进多画面就变。可选阶段各加一个用例。
- 真机：待真机（任务书的真机步骤）。

## 留下的问题

- 无（表情和屏幕常亮是否做，由维护者在开工前决定；不做的话留在 N01 子分类页的已知问题里）。
