# A07.24 小窗重构和增强

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：界面
- 来源：用户 2026-10-14：“现在需要增强小窗功能，先分析一下现在小窗功能有什么问题？”；“小窗，还有一个问题，不支持无级别拉伸放大，应该可以支持放大到手机宽一样，需要你全面重构，增强小窗功能”
- 相关：[A07.8 小窗](../A07.8-小窗/README.md)（三种小窗的设计 c1～c10）、[A07.22 小窗改大小](../A07.22-小窗改大小和尺寸设置/README.md)（拖角和两指缩放、横竖各记一份）、[O02 画中画](../../../O-Android系统集成/O02-画中画/README.md)（已知问题）、[O01.3 后台播放](../../../O-Android系统集成/O01-通知和前台服务/O01.3-后台播放增强/README.md)、决定 D-001、D-003、D-018；任务书 [brief.md](brief.md)、记录 [record.md](record.md)、真机步骤 [verify.md](verify.md)

## 分析出的问题（2026-10-14，读代码）

| 编号 | 问题 | 位置（改之前） | 影响 |
|---|---|---|---|
| P1 | 放大有上限：长边最多屏幕短边 × 0.9，还要扣左右各 16 的边距，拉不到手机那么宽 | `logic/mini_window.dart` `inAppMiniMaxFraction`、`inAppMiniRoom` | 用户说的“不支持无级别拉伸、应该能放大到手机宽” |
| P2 | 拖动时每移一点整个小窗重建（布局、读设置、视频组件），松手停在原地，没有惯性、不吸边 | `mini/floating_window.dart:230-233` 的 `setState` | 拖动掉帧、不跟手（A07.8 早就记过） |
| P3 | 小窗开着时离开应用，画面就没了：自动画中画只认“直播间页在最上面” | `logic/mini_window.dart:309-320` `shouldAutoEnterPip` | 开着后台播放只剩声音，没开就停 |
| P4 | 按钮显示时再点画面任何地方就回到直播间 | `mini/mini_player.dart:283-289` | 想点按钮旁边、想拖一下时误跳 |
| P5 | 按钮少：没有静音、弹幕开关、切到画中画，看不出是谁的直播间 | `mini/mini_player.dart` 按钮层 | — |
| P6 | 只能关掉，没有“先收到边上”这种让开的办法 | — | — |
| P7 | 画中画进入动画从整个窗口缩，Android 12+ 改大小时视频会被淡入淡出 | `MainActivity.kt` 没有 `setSourceRectHint`、`setSeamlessResizeEnabled(false)`（O02 已知问题） | 进入时一闪整页、改大小时一闪 |
| P8 | 画中画里画面比例变了（换清晰度、竖屏首帧），只有开着“离开应用时自动画中画”才改窗口比例 | `mini/room_mini_window.dart:286-290`；原生没有单独的更新方法（O02 已知问题） | 黑边或被裁 |
| P9 | 画中画只有播放 / 暂停按钮，没有标题（Android 13+ 能显示） | `MainActivity.kt` `pictureInPictureActions` | — |
| P10 | 画中画回来控制条卡住（O02.1）、A07.22 都还没上真机 | — | 要在 K90 上看 |

## 设计（维护者按 D-003 定，不出评审页）

| 编号 | 内容 | 理由 |
|---|---|---|
| c1 | 缩放没有档位、没有 0.9 上限：长边从 160（竖屏画面宽 120）到“能放下的最大”——横屏画面宽到和屏幕一样宽，竖屏画面高到上下留白之间；窗口和屏幕一样宽时左右不留 16 的边距 | 用户要的“放大到手机宽一样”；中间任何大小都能停（拖角、两指都是连续的）；“小窗大小”三档和横竖各记一份的缩放（A07.22）保留，键不变 |
| c2 | 拖动、缩放、松手后的滑动只改外框的位置和大小（`ValueNotifier` 驱动 `Positioned`），画面那棵树不重建 | P2 的根因是每次移动都 `setState` 整个窗口 |
| c3 | 松手按手指速度再滑 0.18 秒的距离，然后贴到更近的一边（窗口和屏幕一样宽时留在中间），上下在留白之间；动画 260 毫秒 easeOutCubic，系统要求少动画时直接到位 | 常见的悬浮视频手感；不会停在屏幕中间挡内容 |
| c4 | 拖出屏幕边超过一半（或往一边用力甩），收到那一边，只露 40 宽，照常播放；点露出的那条拉回来，也可以直接拖出来 | P6：临时让开又不停播 |
| c5 | 下一次打开的小窗出现在上一个停的地方（拖过的位置或收边），应用重启后回到右下角 | 用户放好的位置不用每次重拖 |
| c6 | 单击画面显示 / 隐藏按钮，双击回到直播间；鼠标悬停显示，双击回去 | P4：3.x 的“按钮显示时再点就回去”误触多；双击是视频小窗的常见手势 |
| c7 | 右上角“静音”和“关闭”并排；窗口宽到 240 起，顶上中间写主播名；高到 170、宽到 240 起，底边（避开拖角那一角）出“弹幕开关”和“画中画” | P5；小窗口里按钮太多会把画面全挡住，放大以后才出 |
| c8 | 静音只把播放器音量设成 0、再点还原，不改这个直播间记住的音量；弹幕开关就是设置“小窗显示弹幕”（`enablePipDanmaku`），三种小窗共用 | 不新增设置 |
| c9 | 开着“离开应用时自动画中画”时，应用内小窗在播放就由小窗自己布防，离开应用直接进系统画中画，从小窗那块长出来；点小窗的“画中画”按钮也一样。画中画里小窗变成整屏只有画面（系统画按钮），回来变回原来的小窗；同一个播放器，不重新打开 | P3 |
| c10 | 布防有“谁布的谁才能撤”：直播间页关掉交给小窗时，页面的撤防不会撤掉小窗刚布的 | 不然交接时被撤掉 |
| c11 | 画中画参数一处组装：比例、`sourceRectHint`（按钮进入时取画面在屏幕上的位置，必须在页面切成只有画面之前取）、动作（播放 / 暂停 + 静音 / 取消静音）、Android 12+ 自动进入和关掉无缝缩放、Android 13+ 标题（主播名）和副标题（直播间标题）；新加 `update` 方法，画中画里画面比例变了就更新窗口 | P7～P9 |

## 结果

- 代码：
  - `apps/pure_live/lib/features/live_play/logic/mini_window.dart`：`inAppMiniRoom`（整宽）、`inAppMiniScale`（无 0.9 上限）、`MiniDock`、`inAppMiniDockPeek`、`inAppMiniOffset`（满宽不留边距、收边）、`inAppMiniDragOffset`、`inAppMiniSettle`、`inAppMiniFlingSeconds`。
  - `mini/floating_window.dart`：`_FloatingWindow` 重写（`_Layout`、`_frame`、`_grip`、滑动动画、收边、记住位置、自动画中画布防、画中画按钮、画中画时整屏）。
  - `mini/mini_player.dart`：单击 / 双击、静音、主播名、弹幕开关、画中画按钮；拖角改成跟着 `ValueListenable` 换角。
  - `mini/room_mini_window.dart`：画面位置、标题、画中画里跟随比例、布防带主人。
  - `logic/background_playback.dart`：`PictureInPicture` 的 `enter`、`update`、`setAutoEnter` 带画面位置和主人，静音动作；`RoomBackgroundPolicy` 绑定静音。
  - `logic/room_runtime.dart`：`FloatingRoom.placement`。
  - `player/player_view.dart`：告诉小窗画面在哪。
  - Android：`MainActivity.kt` 画中画参数统一、`update`、静音动作；`res/drawable/ic_pip_volume_off.xml`、`ic_pip_volume_up.xml`。
- 翻译：新键 `mini_window_system_pip`；静音、弹幕开关沿用 `live_play_mute`、`live_play_unmute`、`live_play_hide_danmaku`、`show_danmaku`。
- 测试：见 [record.md](record.md)。

## 留下的问题

- 其他品牌手机的画中画（OPPO、vivo、华为）没有设备，`setSourceRectHint` 的效果只能在 K90 上看。
- 画中画回来控制条卡住（O02.1）这次没碰，K90 上一起复验。
- 桌面小窗（Windows）只跟着改了单击 / 双击和新按钮（没有拖角和收边，系统窗口自己拖）。
