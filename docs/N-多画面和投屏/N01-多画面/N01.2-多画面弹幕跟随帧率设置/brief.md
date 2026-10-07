# N01.2 多画面的飞行弹幕跟随弹幕帧率设置：任务书

## 背景

- 来源：V03.3（2026-10-03）核对功能清点 F-MV-05；D05.1 记录“合并时注意”早就写了“多画面……帧率仍然每个刷新周期都画（要传 `fps` 时在 `multiview_page.dart` 照直播间写）”。之后 D03 子分类页（多画面不传表情表）、O05 子分类页（多画面不看“屏幕常亮”）各发现一处同类的“少传一个参数”，作为可选阶段放进来。
- 现象：设置 → 弹幕 → 关掉“弹幕帧率跟随界面刷新率”、“弹幕帧率”选 30：直播间的飞行弹幕按 30 帧动，多画面里的仍按屏幕刷新率（K90 上 120）动。可选部分：多画面里的弹幕表情显示成文字（直播间是图片）；设置 → 视频 → 关掉“屏幕常亮”，多画面播放时照样不灭屏。
- 为什么现在做：第二档；和 3.x 的行为不一致（3.x 多画面跟弹幕帧率设置），改动小；4 格同时画弹幕时按 120 帧画是白费电。
- 已经做过的：D05.1（直播间的帧率、字体、纯文字）、D03.1（弹幕层支持整数分之一帧率）、N01.1（多画面）、A13.2（多画面界面）、A07.10（格子里的“暂停时的弹幕”，同一段代码）、O05.1（直播间的屏幕常亮）。

## 目标和验收

1. 多画面每格的 `DanmakuOverlay` 拿到和直播间同样算法的 `fps` 和 `refreshRate`。
2. 改设置（弹幕帧率、是否跟随界面刷新率、界面刷新率档位）立即生效，不用退出多画面。
3. 直播间的弹幕行为不变（已有测试照旧通过）。
4. （可选 c3，维护者同意后）多画面的弹幕表情和直播间一样显示成图片。
5. （可选 c4，维护者同意后）多画面跟随“屏幕常亮”设置：关掉时播放中也按系统超时灭屏，打开时播放和缓冲时常亮。
6. 新测试通过；门禁通过；`tools/gate/ui_baseline.json` 不增加。

## 现状（读代码得出，写文件:行）

- 多画面：`apps/pure_live/lib/features/multiview/multiview_page.dart:868-884`：`danmaku: showDanmaku ? Consumer(builder: … DanmakuOverlay(messages: _controller.flying, retractions: _controller.retractions, look: look, running: danmakuRunning(...))) : null`；`look` 来自 `danmakuLookOf(ref)`（`:873`，已有字体和纯文字），`pausedBehavior`（`:874`）。没有 `fps`、`refreshRate`、`emotes`。
- 弹幕层：`apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart`：`fps` 参数（`:159`）和字段（`:185`），`refreshRate`（`:188`），`emotes`（`:164`，默认 `EmoteTable.empty`，字段 `:203`）；`fps` 为 null 时每个刷新周期都画；`danmakuFrameDivisor`（`:130`）按刷新率的整数分之一，`:433` 算间隔。
- 直播间（照抄的对象）：`apps/pure_live/lib/features/live_play/player/player_view.dart:457-490`（`_danmaku`：`ValueListenableBuilder<DisplayModeInfo?>(valueListenable: DisplayMode.info, …)` 里 `fps: resolvedDanmakuFps(automatic:, configured:, mode:, maxRefreshRate:, currentRefreshRate:)`、`refreshRate:`、`emotes: _emotes`）；三个设置在 `:551-555` 读；`_FpsSettings`（`:824`）；表情表 `_emotes`（`:212`，`:231-236` 按平台取、取不到时等下载）；屏幕常亮 `:503-516`（`keepScreenOn: watchSetting(ref, Settings.enableScreenKeepOn)`）。
- `apps/pure_live/lib/shared/danmaku/danmaku_templates.dart:210-232` 的 `resolvedDanmakuFps({automatic, configured, mode, maxRefreshRate, currentRefreshRate, pip})`：手动时夹到 30～240；跟随时按 `performance` / `balanced` / 省电取设备最高刷新率或 60。
- 格子的视频：`apps/pure_live/lib/features/multiview/widgets/cell_view.dart:92`：`LiveVideoView(session: session, outputSize: …)`，没传 `keepScreenOn`（`packages/live_player/lib/src/video_view.dart:28` 默认 `true`）。
- 选中的格：`logic/multiview_controller.dart` 的 `selectedIndex`（`:238`）、`_danmakuTarget`（`:861`）——弹幕只连选中格的房间，表情表按这个房间的平台取。

## 3.x 基线

- `git show v3.2.11:lib/modules/multiview/multiview_page.dart:1296-1312` 的弹幕配置，`:1306-1308` 帧率 `settings.danmakuAutoFps.v ? settings.resolvedDanmakuFps(refreshRateMode: SettingsService.to.app.refreshRateMode) : settings.danmakuFps.v.clamp(30, 240)`，`maxVisibleCount: 48`。
- 3.x 多画面的格子用 media_kit 的 `Video`（`:994`），它默认常亮，不看“屏幕常亮”设置——所以 c4 是改进，不是还原。
- 必须保留的：多画面的弹幕和直播间用同一组设置。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`。
3. 本文件夹的 `README.md`；`docs/N-多画面和投屏/N01-多画面/README.md`（已知问题）；`docs/D-弹幕/D05-弹幕设置生效/D05.1-弹幕设置生效/record.md`；`docs/D-弹幕/D03-飞行弹幕引擎/D03.1-飞行弹幕渲染/record.md` 的 c3；`docs/O-Android系统集成/O05-方向、刷新率、常亮/README.md`（屏幕常亮）。

## 范围

- 可以改：`apps/pure_live/lib/features/multiview/multiview_page.dart`；（c4）`apps/pure_live/lib/features/multiview/widgets/cell_view.dart`；需要提共用函数或组件时 `apps/pure_live/lib/shared/danmaku/`（只加，直播间的行为不变；改了 `player_view.dart` 去用共用函数也可以，但断言不变）；`apps/pure_live/test/features/multiview/multiview_page_test.dart`、`multiview_support.dart`。
- 不能改：直播间的弹幕层和布局的行为；`packages/live_danmaku`、`packages/live_player`；设置项（不加新设置）；其他组的界面和逻辑；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么（对应 README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1、c2：多画面传 `fps`、`refreshRate`；必要时提共用函数 | `multiview_page.dart`、`shared/danmaku/`、`multiview_page_test.dart` | 验收 1～3、6 |
| 2（可选） | c3 表情表；c4 屏幕常亮 | `multiview_page.dart`、`widgets/cell_view.dart`、测试 | 验收 4、5；维护者在开工前说做不做，不做就只交阶段 1 |

## 测试

- 改之前会失败：`multiview_page_test.dart` 新用例“手动 30 帧时格子的弹幕层 `fps` 是 30”（现在是 null）；写法照 `:296` 的用例（`_pump`、`_pick`、点 `multiview-danmaku`、`tester.widget<DanmakuOverlay>(_inCell(1, find.byType(DanmakuOverlay)))`）。
- 再加：跟随界面刷新率、界面刷新率是省电（`powerSaving`）时是 60；在测试里 `services.store.settings.set(Settings.danmakuFps, 45)` 后不重进多画面，`fps` 跟着变成 45。
- 可选阶段：表情表不为空（选中格的平台有表情时）；`Settings.enableScreenKeepOn` 关时格子的 `LiveVideoView.keepScreenOn` 是 `false`。
- 测试里的定时器至少 1 秒；不访问真实平台（用 `multiview_support.dart` 的假会话和假弹幕）。
- `apps/pure_live` 跑 `flutter analyze`、全部 `flutter test`、`dart format --output=none --set-exit-if-changed .`。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 设置 → 弹幕 → 关“弹幕帧率跟随界面刷新率”，“弹幕帧率”选 30；首页 → 多画面，放 2 个弹幕多的直播间，打开弹幕 | 飞行弹幕按 30 帧动（明显比直播间默认的 120 帧顿一点），没有跳动或停住 |
| 2. 不退出多画面，回设置把“弹幕帧率”改成 60 再回来 | 弹幕变顺，不用重进 |
| 3. 打开“弹幕帧率跟随界面刷新率”，设置 → 通用 → 界面刷新率选“性能” | 弹幕恢复最流畅（120） |
| 4. 进一个直播间再回多画面 | 两边的弹幕帧率一致 |
| 5. 4 格都放弹幕多的直播间，profile 构建下 `adb shell dumpsys gfxinfo com.mystyle.purelive.v4dev`，分别在帧率 30 和 120 时各记一次 | 30 时 UI 线程帧时间的分位数明显低于 120 时（数字写进 record.md） |
| 6.（做了 c3）选中一个有表情的哔哩哔哩直播间 | 弹幕里的表情是图片，和直播间一样 |
| 7.（做了 c4）设置 → 视频 → 关“屏幕常亮”，多画面播放，不碰手机等过系统的灭屏时间 | 屏幕按系统超时熄灭；打开“屏幕常亮”后播放时不灭 |

## 风险和注意

- 多画面每格一个弹幕层，`DisplayMode.info` 的监听不要每格各建一份重型对象；`ValueListenableBuilder` 即可（只有选中的格在画弹幕，其他格的 `flying` 是同一个流）。
- 表情表要等下载时（`player_view.dart:231-236` 的做法）注意格子换台和页面销毁后不要 `setState`。
- c4 改变了 3.x 的行为（3.x 多画面总是常亮），记录里写清；如果维护者认为多画面就该常亮，不做 c4。
- 可能冲突的文件：`multiview_page.dart`（A13.2 的界面任务和 A07.10 改过暂停时的弹幕，`:868-884` 一段）；`player_view.dart`（提共用函数时，A07 系列的直播间任务也改它）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/N01.2` 或本机工作区；提交信息以 `[N01.2]` 开头（英文）；不推 master。
- 提交前：`dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`apps/pure_live` 全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`（登记表现在没有写阶段，开工时按上表补上：做不做阶段 2 由维护者定）。

## 报告（中文，简洁）

做到没有（阶段 1；阶段 2 做没做）；测试数量（改之前失败几个）；改了哪些文件；帧时间改前改后的数字；要在真机上看的；可能冲突的文件。
