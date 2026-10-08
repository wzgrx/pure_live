# D03 飞行弹幕引擎

画面上飘过的弹幕怎么画：轨道和排队、速度按时间算、帧率上限、透明度和描边、排版缓存、表情图片、暂停和停住、点中命中；直播间、应用内小窗和画中画、多画面、电视都用同一个弹幕层。

## 范围

- 包括：
  - 弹幕层 `apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart`（`DanmakuOverlay`、`DanmakuLook`、`danmakuFrameDivisor`）的绘制和调度：轨道、排队、入场、速度、时钟、帧率、Picture 缓存、表情图解码、撤回、`running`/`held`。
  - 弹幕层的几个使用处传了什么参数（`fps`、`refreshRate`、`running`、`emotes`、`maxVisible`）：直播间 `features/live_play/player/player_view.dart` 的 `_danmaku`、小窗 `features/live_play/mini/compact_danmaku.dart`、多画面 `features/multiview/multiview_page.dart`、电视 `tv/room/tv_live_play_page.dart`。
  - 表情的切分（`shared/danmaku/emotes.dart` 的 `chatSegments`，聊天列表和弹幕层共用）在弹幕层里的用法。
- 不包括（归哪里）：
  - 设置怎么换算成弹幕层的参数（`danmakuLookOf`、`resolvedDanmakuFps`、`danmakuRunning`）和设置“真的生效” → [D05](../D05-弹幕设置生效/README.md)。
  - 点中弹幕以后打开什么面板、画面手势怎么问弹幕层、控制条范围不命中 → [A08.4](../../A-界面设计/A08-弹幕界面/A08.4-画面弹幕点按和长按/README.md)；双击弹幕时面板一闪 → [A07.14](../../A-界面设计/A07-直播间界面/A07.14-双击飞行弹幕面板一闪/README.md)。
  - 本地弹幕的样式（顶部、底部固定、发光、斜体）和礼物横幅 → [A08.2](../../A-界面设计/A08-弹幕界面/A08.2-本地互动/README.md)（画法在这个文件的 `_placeLocal`，规则归 A08.2）。
  - 小窗弹幕的 12 项设置和它们的尺寸换算（`CompactDanmakuMetrics`）→ A07.8、A08.1；聊天列表 → [D04](../D04-数据流和性能/README.md)；弹幕从哪来、哪些能上屏 → D01、D02。
  - 刷新率（`DisplayMode`、帧率声明）→ R02。

## 现状：做到哪、怎么工作的

- 用户看得到的：弹幕从右往左飘，16 号字、500 字重、黑色描边 1.5、每秒 120 像素（默认，照 3.x）；60、90、120、144 Hz 下一样快、匀速；改字号、速度等设置后屏上的照旧飞完，新来的用新样式；一下来很多条时排队（最多 120 条、等 5 秒），每帧最多进 4 条，同屏最多 48 条；表情（哔哩哔哩 `[笑哭]` 等）是图片；纯文字模式没有表情；视频暂停时平台弹幕停住（可在“暂停时的弹幕”改成继续飘），自己发的本地弹幕照常飞；点中一条弹幕打开面板时整层停住，关了继续；平台撤回的弹幕从画面上消失。
- 内部怎么工作：

```text
LiveRoomController.flying（room_controller.dart:217，过滤后的聊天，同步流）
  → DanmakuOverlayState._add（:357）：不可见、暂停（非本地）、停住时不收；chatSegments 切成文字和表情，纯文字去掉表情
  → _pending 队列（最多 120 条）→ _wake 启动 Ticker
_tick（:398）每个 vsync：
  时间差累加到两条时钟：_media（平台弹幕，暂停或停住时不走）、_free（本地弹幕，只在停住时不走）
  相同时间戳的帧不走、下一帧不补双步（R5）
  飞出左边的移除并释放 Picture
  _enter（:444）：丢掉等了 5 秒以上的；最多进 4 条；表情图没解码完的先等
    _place（:463）选轨道：空轨道优先，否则最后一条离右边缘 ≥ 40、空出最多的；比前一条快就减速
    _render（:567）→ 缓存命中直接用，否则 _record（:585）排版一次、录成 Picture
  到了帧率间隔（danmakuFrameDivisor，:130）才让 _DanmakuPainter 重画；没事可做就停 Ticker
_DanmakuPainter（:984）：每条只 translate + drawPicture，不排版、不开离屏层
```

  - 整层 `IgnorePointer`（`:673`）；命中由画面手势层调 `messageAt`（`:292`）来问。
  - 外面套 `ClipRect` 和 `RepaintBoundary`（`player_view.dart:462-463`），弹幕重画不带着视频和控制层。
- 完成度（和 3.x 对照）：
  - 一致：默认样子和轨道高度、排队和上限、透明度进颜色（描边按平方根）、排版一次录成 Picture、改设置不清屏、暂停不进新弹幕、本地弹幕照常、点中停住、表情图片、纯文字模式。
  - 比 3.x 好（D03.1 确认的改动）：帧率上限取刷新率的整数分之一（3.x 在 90、144 Hz 时步子一大一小，H1）、时钟用微秒不取整（H2）、不带 Flame 引擎（H3）、可变刷新率下重复时间戳不跳（D04.1 c4）。
  - 和 3.x 不同：表情图第一次出现要等解码（3.x 进房预载）。
  - 还缺：K90 上的性能数字（D03.1 设计第 9.4 节的五项都没测）；多画面不跟帧率设置（N01.2）；电视不跟帧率、不随暂停停（A17.4）；小窗不画应用自带的表情图（见“已知问题”）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart`（1022 行） | `DanmakuLook`（`:14`，字号、字重、速度、透明度、区域、上下留白、描边、轨道高 `lane` `:70`、表情高 `emoteSize` `:73`、字体、纯文字）；`danmakuFrameDivisor`（`:130`）；`DanmakuOverlay`（`:151`，参数 `messages`、`retractions`、`look`、`visible`、`maxVisible` 默认 48、`fps`、`refreshRate`、`color`、`running`、`held`、`emotes`）；`DanmakuOverlayState`（`:211`：`maxPending` 120 `:213`、`maxPendingAge` 5 秒 `:216`、`perFrame` 4 `:220`、`laneGap` 40 `:223`、`rectOf` `:283`、`messageAt` `:292`、`_add` `:357`、`_segments` `:373`、`_tick` `:398`、`_enter` `:444`、`_place` `:463`、`_placeLocal` `:513`、`_render` `:567`、`_record` `:585`）；`_Ink`（`:700`，透明度进颜色 `:719`）；`_Rendered`（`:813`，引用计数）；`_Pictures`（`:835`，96 张）；`_EmoteImages`（`:861`，160 张，96 像素高）；`_Flying`（`:936`）；`_DanmakuPainter`（`:984`）；`retracts`（`:1017`） |
| `apps/pure_live/lib/shared/danmaku/emotes.dart`（161） | `EmoteTable`（`:18`，预编正则 `:46`）、`EmoteLibrary`（`:56`，五个平台的自带表）、`chatSegments`（`:122`，每条消息解析一次） |
| `apps/pure_live/lib/features/live_play/player/player_view.dart` | 读表情表（`:229`）、`_danmaku`（`:457` 起：`fps` `:475`、`refreshRate` `:482`、`running` `:484`、`held`、`emotes`）、`held` 的来源（`_openMessage`，A08.4） |
| `apps/pure_live/lib/features/live_play/mini/compact_danmaku.dart`（220） | 小窗和画中画的弹幕层（`:190`）：自己的轨道高和速度（`CompactDanmakuMetrics`）、`maxVisible`、统一颜色、`compactDanmakuFps`、`running`；纯文字只去掉消息自带的表情代码（`:105`） |
| `apps/pure_live/lib/features/live_play/logic/mini_window.dart` | `compactDanmakuFps`（`:232`，和 `resolvedDanmakuFps(pip: true)` 同一规则）、`withoutEmoteCodes` |
| `apps/pure_live/lib/features/multiview/multiview_page.dart` | 多画面的弹幕层（`:878`）：只传 `look`、`running`，没有 `fps`、`emotes` |
| `apps/pure_live/lib/tv/room/tv_live_play_page.dart` | 电视直播间的弹幕层（`:464`）：只传 `look`、`visible` |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/shared/danmaku_overlay_test.dart`（13） | 轨道和居中；各刷新率每秒 120 像素；整数分之一的表；R5 位移序列；手动 30 帧；改样式不清屏；透明度进颜色和只排版一次；排队和过期；字体、纯文字、表情图；命中和停住；`danmakuRunning`；暂停时本地弹幕；撤回 |
| `apps/pure_live/test/features/live_play/live_play_page_test.dart` | 直播间把帧率、字体、纯文字传给弹幕层；暂停不进新弹幕；点中弹幕停住（A08.4） |
| `apps/pure_live/test/features/live_play/chat_benchmark_test.dart`（1） | 整个直播间每秒 200 条时的构建次数和帧耗时（带弹幕层；调试模式，只能前后对比，D04.1） |
| `apps/pure_live/test/features/live_play/live_play_mini_window_test.dart` | 小窗弹幕（A07.8） |

## 3.x 基线

- 引擎：本地补丁版 flame_barrage 0.0.4（`git show v3.2.11:pubspec.yaml:60-61`，`plugins/flame_barrage/`）：`core/barrage_engine.dart`（642 行，自己的 Ticker 按设定帧率推进 `:133-181`，没有弹幕时停 `:127-131`，位置 = 速度 × 经过时间 `:363-366`，Picture 缓存 `:464-469`、`:589-611`）、`core/engine_clock.dart:6`（取整到毫秒）、`scheduler/track_manager.dart:14`（轨道高）、`scheduler/track_allocator.dart:24-36`（选轨道）、`scheduler/speed_strategy.dart`（不追尾）、`layout/mixed_layout.dart`（透明度和描边 `:10-13`、`:107-110`，表情 `:175-221`）。
- 直播间传的参数：`lib/modules/live_play/widgets/video_player/video_controller_panel.dart:786-811`（每 0.05 秒最多一条、同屏 48、排队 120、5 秒、缓存 96/72/320）；暂停不放新弹幕 `video_controller.dart:183`；点中暂停 `:132-149`。
- 小窗：`lib/modules/live_play/widgets/danmaku/compact_danmaku_overlay.dart`（94 行，用同一个表情图集 `:86`，纯文字 `:26`）。
- 详细的对照和 3.x 的三个问题（H1～H3）在 [D03.1 的设计](D03.1-飞行弹幕渲染/README.md)“v3 的样子”“v3 的问题”。
- 必须保留的：默认样子（字号、字重、描边、速度、区域、留白）、轨道高度规则、同屏 48 条、排队 120 条 5 秒、改设置不清屏、暂停时本地弹幕照常（[specs/UI.md](../../specs/UI.md) 第 9.3 节：弹幕只描边不加模糊）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| D03.1 设计要求的 K90 性能数字（每秒 200 条时界面线程 P90、光栅时间、速度和均匀度、PSS）一个都没测；登记表却是“完成” | [D03.1](D03.1-飞行弹幕渲染/README.md)“以后在 K90 上怎么测”“实现和验证” | Picture 缓存够不够快（H-B）没有依据 | 并入 [D04.1 的 verify.md](../D04-数据流和性能/D04.1-弹幕性能和可读性/verify.md)；写进本单元报告 |
| 应用内小窗和画中画不画应用自带的表情图（没传 `emotes`），哔哩哔哩、斗鱼等的 `[笑哭]` 在小窗里是文字；小窗的“纯文字”也只去掉消息自带的表情代码，去不掉自带表的代码 | `features/live_play/mini/compact_danmaku.dart:190`（没有 `emotes:`）、`:105` | 和 3.x 不同（3.x 小窗用同一个表情图集，`compact_danmaku_overlay.dart:86`） | [D03.3](D03.3-小窗和画中画的弹幕/README.md)（2026-10-07 登记，连同弹幕字体、放大后变大） |
| 多画面的弹幕层不传 `fps`，每个刷新周期都画；也不传 `emotes` | `features/multiview/multiview_page.dart:878-883` | 不跟弹幕帧率设置（3.x 跟）；表情是文字 | 帧率：[N01.2](../../N-多画面和投屏/N01-多画面/N01.2-多画面弹幕跟随帧率设置/README.md)；表情：没有任务，建议 N01.2 一起做 |
| 电视的弹幕层只传 `look`、`visible`：不跟帧率、不随暂停停、没有表情图 | `tv/room/tv_live_play_page.dart:464-469` | 电视（暂缓）上和手机不一致 | [A17.4](../../A-界面设计/A17-电视界面/A17.4-电视直播间/README.md) |
| 表情图第一次出现要等解码，这一条比别的晚进场 | `danmaku_overlay.dart:451` | 弹幕多时略晚 | 不做；要改时进房预读常用表情 |
| `compactDanmakuFps` 和 `resolvedDanmakuFps(pip: true)` 是两份同样的规则 | `features/live_play/logic/mini_window.dart:232`、`shared/danmaku/danmaku_templates.dart:210` | 以后改一处忘了另一处 | 没有任务；D05 下次改帧率规则时合成一个 |
| 弹幕层注释和测试名里还用旧编号（`U.2h`、`F.2a`、`B08 c4`、`B02 c3`、`docs/TASKS.md/U.2h`） | `danmaku_overlay.dart:124-150`、`danmaku_overlay_test.dart` | 按注释找文档要先查 [MAPPING.md](../../MAPPING.md) | Z 组一次性替换 |

## 相关决定和规范

- D-003：D03.1 的待选 H-A～H-D 由维护者按建议 A 定（自己的画法、先录 Picture、改设置不清屏、整数分之一）。
- D-010：刷新率策略（播放中只用帧率声明）；弹幕层只读当前刷新率，不去改它。
- D-012：暂停后单击只切控制层；“暂停时的弹幕”设置（A07.10）决定 `running`。
- [specs/UI.md](../../specs/UI.md) 第 9.2、9.3 节（弹幕层单独一个重绘边界、只描边不加模糊）；附录 A 第 2、6 条（控制条范围不命中、点中弹幕打开菜单）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/shared/danmaku_overlay_test.dart test/features/live_play/live_play_page_test.dart`。测试里用假的 vsync 时间推进（`tester.pump(Duration)`），按 60/90/120/144 Hz 断言每秒位移；缺的：真机的光栅时间和内存（测试环境测不到）。
- 真机：S02.2 冒烟看到飞行弹幕带表情图（2026-10-02）；CHECKLIST 第 2 节第 2 条（改区域、透明度、速度、字号、模板，全屏里再调）、第 3 条（帧率 30、字体、纯文字）、第 7 条（表情）还没填；性能数字见 D04.1 的验证。

## 路线

1. D04.1 的真机验证里一起测弹幕层的 profile 数字（每秒 200 条、120 Hz），不达标再考虑 H-B 的图片缓存（开新任务）。
2. N01.2：多画面跟帧率设置（顺带传表情表）。
3. [D03.3](D03.3-小窗和画中画的弹幕/README.md)（第二档，中）：小窗和画中画用弹幕字体、画自带表情图、纯文字走 `textOnly`（和 3.x 一致），放大后弹幕跟着变大（上限 2 倍，上游 `b2cca41c7`），补直播间 48 条上限的测试。
4. 以后：电视的参数（A17.4）；“按住弹幕让它停住”（V01.3）、“同屏最大条数可以设置”（V01.4）是提议，确认后再开任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [D 弹幕](../README.md)。

- 代码：`shared/danmaku/danmaku_overlay.dart`
- 进度：`███████████████████░` 97%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| D03.1 | 飞行弹幕渲染：选型和优化，速度按时间算 | 性能 | 完成 | 2026-10-02 | b8462638a | [设计或说明](D03.1-飞行弹幕渲染/README.md)、[记录](D03.1-飞行弹幕渲染/record.md)、[评审页](D03.1-飞行弹幕渲染/page/01-说明.jpg) |
| D03.2 | 飞行弹幕里的表情图片 | 功能 | 完成 | 2026-10-02 | 0451ac8c6 | [设计或说明](D03.2-飞行弹幕里的表情图片/README.md) |
| D03.3 | 小窗和画中画的弹幕：放大后跟着变大，用弹幕字体，画表情图 | 功能 | 待真机 | 2026-10-08 | — | [设计或说明](D03.3-小窗和画中画的弹幕/README.md)、[任务书](D03.3-小窗和画中画的弹幕/brief.md)、[记录](D03.3-小窗和画中画的弹幕/record.md) |

<!-- docs:生成结束 -->
