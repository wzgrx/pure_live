# A07.24 小窗重构和增强：记录

- 执行：维护者（Claude）在本会话里直接做，没有子代理（用户 2026-10-14“后续禁止使用子代理”）。
- 工作区：`.claude/worktrees/mini-refactor`，分支 `mini-refactor`，从 `a051aeadd`（4.1.0 发布完）开始。

## 根因

- P1：`inAppMiniScale` 的上限是 `min(屏幕短边 × inAppMiniMaxFraction(0.9), 可用空间)`，可用空间 `inAppMiniRoom` 又扣了左右各 16；`inAppMiniOffset` 也总留 16 的边距。两处叠起来，横屏画面的小窗在 393 宽的手机上最多约 353 宽。
- P2：`_FloatingWindowState` 的 `onDragUpdate` 每次 `setState`，整个 `build`（`LayoutBuilder` → `ListenableBuilder` → `StreamBuilder` → 读五个设置 → 新建 `MiniPlayerSurface` 和 `LiveVideoView`）重跑；松手只记当前位置。
- P3：自动画中画由直播间页的 `_AutoPip` 布防，条件里有“直播间页在最上面”；页面关掉交给小窗后没人布防。
- P4：`_onTapUp` 在按钮显示时直接 `onBackToRoom`。
- P7～P9：原生只设比例和动作；`setPlaying` 只合并动作；没有改比例的方法。

## 改法

见 [README.md](README.md)“设计”c1～c11 和“结果”。要点：
- 几何是纯函数（`logic/mini_window.dart`），小窗只读它。
- 小窗的外框由 `_frame`（`ValueNotifier<int>`）驱动，`MiniPlayerSurface` 只在房间、设置、画中画状态变化时新建；拖角换角走 `ValueListenable<MiniGripCorner?>`，不重建画面。
- `PictureInPicture.setAutoEnter` 带 `owner`：只有最后布防的人能撤防。
- `sourceRectHint` 用 `View.devicePixelRatio` 换成物理像素；直播间页在切成“只有画面”之前取位置。

## 新设置、翻译键、门禁基线

- 没有新设置（沿用 `floatWindowSize`、`floatWindowLandscapeScale`、`floatWindowPortraitScale`、`enablePipDanmaku`、`autoPipOnLeave`）。
- 新翻译键 `mini_window_system_pip`（中“切到画中画”，英“Picture-in-picture”）。
- 新图标资源（Android）：`ic_pip_volume_off.xml`、`ic_pip_volume_up.xml`。

## 测试

`apps/pure_live/test/features/live_play/live_play_mini_window_test.dart`（41 个全过）：
- 规则：无级缩放到满宽（393 / 220.08）、竖屏画面高到可用空间、满宽不留边距、收边只露 40、拖动范围、松手落点（贴近边、甩过中线、超过一半收边、满宽留中间）。
- 小窗：拖角拉到满宽（宽 393、左 0、记住的缩放）、缩回 250（任何大小都能停）、拖动中 `MiniPlayerSurface` 是同一个对象（不重建）、同一个播放器；松手贴左边、拉出屏幕收边、点那条拉回、下一个小窗在上次的位置。
- 交互：单击显示、再单击隐藏且不回直播间、双击回直播间（同一个播放器）；静音和还原；220×124 没有主播名和底边按钮，满宽时有，主播名就是房间的 nick；弹幕开关改 `enablePipDanmaku`；不是 Android 时没有画中画按钮。
- 画中画（模拟通道）：直播间页进入时先发标题再进入，位置是画面不是整页；竖屏首帧后发 `update` 改比例；系统静音动作让音量变 0 再还原，`setPlaying` 带 `muted`；小窗开着自动画中画由小窗布防、位置是小窗；小窗按钮进入后整屏、只有画面、同一个播放器；回来变回原大小；关掉小窗撤防。
- 原有的 A07.8、A07.22、D03.3、A08.12、B02 等小窗测试改了三处：“按钮显示时再点回直播间”改成双击（c6）、拖动后等滑动动画结束、A07.22 的 0.9 上限测试换成 A07.24 的满宽。

## 门禁

（合并前跑，结果写在这里）

## 真机上要看的

见 [verify.md](verify.md) 的 18 步；重点：满宽缩放、拖动手感、收边、双击回去、小窗转画中画、画中画从画面长出来、比例跟随、系统静音按钮、从画中画回来控制条（O02.1）。
