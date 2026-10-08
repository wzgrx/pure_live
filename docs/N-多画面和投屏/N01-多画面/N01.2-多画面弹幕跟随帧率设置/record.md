# N01.2 多画面的飞行弹幕跟随弹幕帧率设置：记录

- 日期：2026-10-08
- 执行者：Claude（本机工作区，没有推送）
- 分支和提交：本机工作区分支，提交 `[N01.2] …`
- 任务书：[brief.md](brief.md)；说明：[README.md](README.md)。阶段 2（c3 表情图、c4 屏幕常亮）按 D-035 一起做了

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 | 做了 | 多画面选中格的 `DanmakuOverlay` 拿到 `fps` 和 `refreshRate`：读“弹幕帧率”“弹幕帧率跟随界面刷新率”“界面刷新率”三个设置和 `DisplayMode.info`，改了马上生效，不用退出多画面 |
| c2 | 做了 | 共用部分：`danmakuFrameRate(...)`（`shared/danmaku/danmaku_templates.dart`，帧率 + 显示器当前刷新率，同一个 `resolvedDanmakuFps`）和 `DanmakuFrameRateBuilder`（`shared/danmaku/danmaku_settings.dart`，监听三个设置和显示信息）。直播间 `player_view.dart` 改用 `danmakuFrameRate`，算法和结果不变 |
| c3 | 做了（D-035） | 多画面弹幕层传选中格平台的表情表：新的共用组件 `EmoteTableBuilder`（`shared/danmaku/emotes.dart`，和直播间同一个 `emoteLibraryProvider`；表没读完时先空、读完再画；换了平台重读；页面关了或换了平台不 `setState`） |
| c4 | 做了（D-035） | 格子的 `LiveVideoView` 传 `keepScreenOn: Settings.enableScreenKeepOn`（`MultiviewCellView.keepScreenOn`，默认 `true`）。3.x 多画面总是常亮，这是改进（D-035） |

## 根因

- `multiview_page.dart:877-884` 的 `DanmakuOverlay(messages:, retractions:, look:, running:)` 没有传 `fps`、`refreshRate`、`emotes`；`fps` 为 null 时弹幕层每个刷新周期都画（`danmaku_overlay.dart` 的 `danmakuFrameDivisor`）。D05.1 只改了直播间。
- `widgets/cell_view.dart:92` 的 `LiveVideoView` 没传 `keepScreenOn`，用了默认的 `true`。

## 改了哪些文件

- `apps/pure_live/lib/features/multiview/multiview_page.dart`、`widgets/cell_view.dart`
- `apps/pure_live/lib/shared/danmaku/danmaku_templates.dart`（`danmakuFrameRate`）、`danmaku_settings.dart`（`DanmakuFrameRateBuilder`）、`emotes.dart`（`EmoteTableBuilder`）
- `apps/pure_live/lib/features/live_play/player/player_view.dart`（改用 `danmakuFrameRate`，行为不变）
- 测试：`apps/pure_live/test/features/multiview/multiview_page_test.dart`（`_pump` 加了可选的 `overrides`）

## 新设置、翻译键、门禁基线

- 无新设置、无新翻译键；门禁基线不变。

## 测试

- 新增 3 个（`multiview_page_test.dart`“N01.2”一组）：手动 30 帧时格子的 `fps` 是 30，不退出改成 45 跟着变；跟随、120 Hz 显示器、“省电”是 60 且 `refreshRate` 是 120，“性能”是 120；选中哔哩哔哩格时弹幕层的表情表就是哔哩哔哩的表（和直播间同一个库）；关掉“屏幕常亮”后格子的 `LiveVideoView.keepScreenOn` 是 false。
- 改之前失败：3 个（`fps` 为 null、表情表为空、常亮仍是 true）。
- 直播间的已有测试没改，照样通过。全部通过：`apps/pure_live` 全部 `flutter test`；`dart analyze --fatal-infos`、格式、`check_ui_structure.py`、`docs.py --check`。

## 真机上要看的

1. 设置 → 弹幕 → 关“弹幕帧率跟随界面刷新率”，“弹幕帧率”选 30；首页 → 多画面，放 2 个弹幕多的直播间，打开弹幕：飞行弹幕按 30 帧动（比直播间默认的 120 帧顿一点），没有跳动或停住。
2. 不退出多画面，回设置把“弹幕帧率”改成 60 再回来：弹幕变顺，不用重进。
3. 打开“弹幕帧率跟随界面刷新率”，设置 → 通用 → 界面刷新率选“性能”：弹幕恢复最流畅（120）。
4. 进一个直播间再回多画面：两边的弹幕帧率一致。
5. 4 格都放弹幕多的直播间，profile 构建下 `adb shell dumpsys gfxinfo com.mystyle.purelive.v4dev`，帧率 30 和 120 时各记一次：30 时 UI 线程帧时间的分位数应明显低于 120（数字由维护者补在这里；本次没有构建、没有上机）。
6. 选中一个有表情的哔哩哔哩直播间：多画面弹幕里的表情是图片，和直播间一样。
7. 设置 → 视频 → 关“屏幕常亮”，多画面播放，不碰手机等过系统的灭屏时间：屏幕按系统超时熄灭；打开“屏幕常亮”后播放时不灭。

## 性能数字

- 改前改后的帧时间：待真机（见上面第 5 步）。

## 可能和别的任务冲突的文件

- `multiview_page.dart`（A13.2、A07.10 改过 `:868-884` 一段）；`player_view.dart`（A07 系列）；`shared/danmaku/emotes.dart`（D03.3 也用 `EmoteTableBuilder`）。
