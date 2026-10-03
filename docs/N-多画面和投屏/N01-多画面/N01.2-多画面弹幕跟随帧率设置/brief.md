# N01.2 多画面的飞行弹幕跟随弹幕帧率设置：任务书

## 背景

- 来源：V03.3（2026-10-03）核对功能清点 F-MV-05；D05.1 记录“合并时注意”早就写了“多画面……帧率仍然每个刷新周期都画（要传 `fps` 时在 `multiview_page.dart` 照直播间写）”。
- 现象：设置 → 弹幕 → 关掉“弹幕帧率跟随界面刷新率”、“弹幕帧率”选 30，直播间的飞行弹幕按 30 帧动，多画面里的仍按屏幕刷新率（K90 上 120）动。
- 为什么现在做：第二档；和 3.x 的行为不一致（3.x 多画面跟设置），改动小。
- 已经做过的：D05.1（直播间）、D03.1（弹幕层支持整数分之一帧率）、N01.1（多画面）。

## 目标和验收

1. 多画面每格的 `DanmakuOverlay` 拿到和直播间同样算法的 `fps` 和 `refreshRate`。
2. 改设置（弹幕帧率、是否跟随界面刷新率、界面刷新率档位）立即生效，不用退出多画面。
3. 直播间的弹幕行为不变（已有测试照旧通过）。
4. 新测试通过；门禁通过。

## 现状（读代码得出，写文件:行）

- `apps/pure_live/lib/features/multiview/multiview_page.dart:868-885`：`danmaku: showDanmaku ? Consumer(builder: … DanmakuOverlay(messages: _controller.flying, retractions: _controller.retractions, look: look, running: …)) : null`；`look` 来自 `danmakuLookOf(ref)`（`:873`，已有字体和纯文字）。
- `apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart:159`、`:184-185`：`fps` 是可选的帧率上限，null 时每个刷新周期都画；`:130` 的 `danmakuFrameDivisor` 按刷新率的整数分之一。
- 直播间：`apps/pure_live/lib/features/live_play/player/player_view.dart:456-480`（`ValueListenableBuilder<DisplayModeInfo?>(valueListenable: DisplayMode.info, …)` 里算 `resolvedDanmakuFps` 并传 `refreshRate`）；`:552-554` 读三个设置；`:824` 的 `_FpsSettings` 记录类型。
- `apps/pure_live/lib/shared/danmaku/danmaku_templates.dart:210-230` 的 `resolvedDanmakuFps({automatic, configured, mode, maxRefreshRate, currentRefreshRate, pip})`。

## 3.x 基线

- `git show v3.2.11:lib/modules/multiview/multiview_page.dart`：`:1296-1312` 的弹幕配置，`:1306-1308` 帧率 `settings.danmakuAutoFps.v ? settings.resolvedDanmakuFps(refreshRateMode: SettingsService.to.app.refreshRateMode) : settings.danmakuFps.v.clamp(30, 240)`，`maxVisibleCount: 48`。必须保留的：多画面的弹幕和直播间用同一组设置。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`。
3. 本文件夹的 `README.md`；`docs/D-弹幕/D05-弹幕设置生效/D05.1-弹幕设置生效/record.md`；`docs/D-弹幕/D03-飞行弹幕引擎/D03.1-飞行弹幕渲染/record.md` 的 c3。

## 范围

- 可以改：`apps/pure_live/lib/features/multiview/multiview_page.dart`；需要提共用函数时 `apps/pure_live/lib/shared/danmaku/`（只加，不改直播间的行为）；`apps/pure_live/test/features/multiview/multiview_page_test.dart`。
- 不能改：直播间的弹幕层和布局；`packages/live_danmaku`；设置项（不加新设置）；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1、c2：多画面传 `fps`、`refreshRate`；必要时提共用函数 | `multiview_page.dart`、`shared/danmaku/`、`multiview_page_test.dart` | 验收 1～4 |

## 测试

- 改之前会失败：`multiview_page_test.dart` 新用例“手动 30 帧时格子的弹幕层 `fps` 是 30”（现在是 null）。
- 再加：跟随界面刷新率、界面刷新率是“省电”时是 60；改设置后不重进多画面，`fps` 跟着变。
- 测试里的定时器至少 1 秒；不访问真实平台（用 `multiview_support.dart` 的假会话）。
- `apps/pure_live` 跑 `flutter analyze`、全部 `flutter test`、`dart format --output=none --set-exit-if-changed .`。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 设置 → 弹幕 → 关“弹幕帧率跟随界面刷新率”，“弹幕帧率”选 30；进多画面放 2 个有弹幕的直播间 | 飞行弹幕按 30 帧动（明显比直播间默认的 120 帧顿一点），没有跳动或停住 |
| 2. 打开“弹幕帧率跟随界面刷新率”，设置 → 通用 → 界面刷新率选“最高（设备上限）” | 弹幕恢复流畅 |
| 3. 进一个直播间再回多画面 | 两边的弹幕帧率一致 |

## 风险和注意

- 多画面每格一个弹幕层，`DisplayMode.info` 的监听不要每格各建一份重型对象；用 `ValueListenableBuilder` 即可。
- 可能冲突的文件：`multiview_page.dart`（A13.2 的界面任务和 A07.10 改过暂停时的弹幕，`:870-881` 一段）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/N01.2` 或本机工作区；提交信息以 `[N01.2]` 开头（英文）；不推 master。
- 提交前：`dart format --output=none --set-exit-if-changed .`、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

做到没有；测试数量；改了哪些文件；要在真机上看的；可能冲突的文件。
