# D05.1 弹幕设置生效：弹幕帧率、字体、纯文字模式

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为完成，2026-10-02；当时定的档位“必须”、规模中）
- 类型：功能
- 来源：功能清点 F-DM-04（弹幕帧率，有问题）、F-DM-05（弹幕字体，缺失）、F-DM-06（纯文字模式，有问题）（见 [inventory/FEATURES.md](../../../inventory/FEATURES.md)）；C01.2“留给后续”第 5 项；I01.3（弹幕字体）；旧的模块重构任务说明 M13.17 第 3、9 项
- 旧编号：F.2a、T06e.1
- 相关：和 [D03.1](../../D03-飞行弹幕引擎/D03.1-飞行弹幕渲染/README.md)（c3、c8）、[A08.4](../../../A-界面设计/A08-弹幕界面/A08.4-画面弹幕点按和长按/README.md) 一起开发；刷新率 [R02.1](../../../R-性能和流畅度/R02-刷新率/R02.1-刷新率和帧率匹配/README.md)；决定 D-018（键名不变）、D-029（D06.1 的三项由本任务做完）；多画面的帧率留给 [N01.2](../../../N-多画面和投屏/N01-多画面/N01.2-多画面弹幕跟随帧率设置/README.md)
- 评审页：没有单独的（只把 v3 的行为补回来；界面照已确认的 D03.1、R02.1）
- 记录：[record.md](record.md)

## 目标

3.x 的三个弹幕设置在 4.x 里只改了设置面板上显示的数字，画面上的飞行弹幕没有变：弹幕帧率（跟随刷新率或手动 30～240）、弹幕字体（下载的字体）、纯文字模式（不画表情）。做完以后三项都作用到直播间的飞行弹幕（竖屏、横屏全屏、竖屏全屏是同一个弹幕层），多画面和电视的字体、纯文字也自动生效。

## 3.x 和现状

以下三节是开发前写的对照（“v4 现在”指当时的代码），保留原样；现在的代码位置见后面的“结果”。

### v3 的行为（`~/ref/v3ref`，v3.2.11）

| 功能点 | 行为 | 位置 |
|---|---|---|
| F-DM-04 | 弹幕层的 `fps`：跟随时按“界面刷新率”档位算（省电 = min(设备最高, 60)，均衡 = 60，最高 = 设备最高），手动 30～240；改设置、刷新率变化时立即重配 | `modules/live_play/widgets/video_player/video_controller_panel.dart:798-800`；`common/services/settings/danmaku_settings_controller.dart:135-162`；`video_controller.dart:121-129` |
| F-DM-05 | 弹幕层的 `fontFamily` = 设置里的字体 id（`Default` 是系统字体） | `video_controller_panel.dart:804`；`video_controller.dart:91` |
| F-DM-06 | 纯文字模式：表情图不画（直接跳过，不显示代码） | `video_controller_panel.dart:797`；`plugins/flame_barrage/lib/src/layout/mixed_layout.dart:175`、`:201` |

### v4 现在

- 主画面弹幕层不传 `fps`，每个刷新周期都画；设置面板只改显示的数字（`features/live_play/player/player_view.dart:269-273`；`shared/danmaku/danmaku_settings_content.dart:214-246`）。
- `DanmakuLook` 没有字体、纯文字（`shared/danmaku/danmaku_settings.dart:10-21`），弹幕层的文字样式不带字体（`danmaku_overlay.dart:201-206`）。
- 弹幕层不认识表情代码，`[笑哭]` 原样显示成文字（`danmaku_overlay.dart:207-211`）；`noEmojiMode` 只进模板（`danmaku_templates.dart:36`）。

### 差别和根因

| 编号 | 差别 | 根因 |
|---|---|---|
| P1 | 弹幕帧率设置不生效 | C01.2 搬弹幕层时只给小窗加了 `fps` 参数，主画面没传（`player_view.dart:271`） |
| P2 | 弹幕字体不生效 | `DanmakuLook` 没有字体字段，`danmakuLookOf` 不读 `danmakuFontFamilyName`（`danmaku_settings.dart:10-21`） |
| P3 | 纯文字模式对飞行弹幕无效 | 弹幕层只画纯文字，没有表情图，也就没有“去掉表情”这一步（`danmaku_overlay.dart:207`） |

## 方案（开发前定的）

### 要做的改动

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 修复 | 帧率：照 D03.1 的 c3（跟随时按 v3 档位算上限，再取当前刷新率的整数分之一；手动值生效），直播间主画面和全屏都传；刷新率变化时立即重算 | P1 |
| c2 | 修复 | 字体：照 D03.1 的 c8，`DanmakuLook.fontFamily`，`Default` 用系统字体 | P2 |
| c3 | 修复 | 纯文字：照 D03.1 的 c8，表情图照 D03.1 的 c1（字号 × 1.3）；纯文字模式跳过表情（照 v3，不显示代码），去掉后为空的不飞 | P3 |

多画面（`features/multiview/`）、电视用同一个弹幕层和 `danmakuLookOf`，字体和纯文字自动生效；帧率要它们自己传（不在本任务的目录，见记录）。

### 需要选的

无（照 v3，D03.1、R02.1 已确认）。

### 当时计划的测试和验证

- 组件测试：手动 30 帧时 60 赫兹下每秒重绘约 30 次；跟随时 120 赫兹、上限 60 → 隔一帧画一次；字体名传到弹幕文字；纯文字时表情不画、只剩表情的弹幕不飞。
- K90：当时 TASKS 第 5 节 5.2 第 3 条，现在是 [CHECKLIST](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 2 节第 3 条；profile 模式看一次帧时间。

### 风险和性能

- 没有新常驻任务；帧率封顶后光栅次数减少。
- 3.x 的键 `danmakuFps`、`danmakuAutoFps`、`danmakuFontFamilyName`、`noEmojiMode` 名字和含义不变。

## 结果

- 实际做的（详见 [record.md](record.md)“逐条对照”，c1～c3 全部做到），现在的代码位置（2026-10-07 核对）：

| 编号 | 做到的 | 现在的位置 |
|---|---|---|
| c1 帧率 | 直播间把 `resolvedDanmakuFps`（跟随时按 3.x 档位：省电 min(设备最高, 60)、均衡 60、最高 = 设备最高；手动 30～240）传给弹幕层，弹幕层再取当前刷新率的整数分之一；刷新率取 `DisplayMode.info`，变了立即重算 | `apps/pure_live/lib/shared/danmaku/danmaku_templates.dart:210`（`resolvedDanmakuFps`）；`apps/pure_live/lib/features/live_play/player/player_view.dart:475-482`；`apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart:130`（`danmakuFrameDivisor`）、`:432-438` |
| c2 字体 | `danmakuLookOf` 读 `danmakuFontFamilyName`，`Default` 或空用系统字体；字体在启动时由字体服务注册，注册名就是 id | `apps/pure_live/lib/shared/danmaku/danmaku_settings.dart:12`、`:25`；`apps/pure_live/lib/app/fonts.dart:299-310`（`restore`） |
| c3 纯文字 | `noEmojiMode` 开时弹幕层跳过表情段（照 3.x 不显示代码），只剩表情的不飞；关时表情是图（1.3 × 字号） | `danmaku_settings.dart:26`（`textOnly`）；`danmaku_overlay.dart:373`（`_segments`） |

- 根因（record“根因”）：C01.2 把弹幕层换成自己的画法时只搬了样式数值：主画面没传 `fps`，`DanmakuLook` 没有字体和纯文字两个字段，弹幕层也没有表情图，所以三个设置只有设置面板和模板在读。
- 偏差：无。多画面当时不在可改目录：字体和纯文字自动有（同一个 `danmakuLookOf`），帧率没传（记录“合并时注意”）→ N01.2。
- 没有新设置；`danmakuFps`、`danmakuAutoFps`、`danmakuFontFamilyName`、`noEmojiMode` 的键名和含义不变（D-018）。
- 提交：代码 `0451ac8c6`（和 D03.1、A08.4、O05.1 同一个），合并 `1071b4e25`（2026-10-02）；登记表写的 `b8462638a` 是记录提交。
- V03.3 核对（2026-10-03）：F-DM-04、F-DM-05、F-DM-06 改“完成”，依据就是本任务（D06.1 因此改“不做”，D-029）。

## 验证

- 自动测试：`apps/pure_live/test/shared/danmaku_overlay_test.dart`：整数分之一的表（`:120`）、手动 30 帧 60 Hz 下每秒约 30 次和 120 Hz 隔帧画（`:177`）、字体和纯文字和表情图（`:266`）；`apps/pure_live/test/features/live_play/live_play_page_test.dart:399`：设置改成手动 30、选字体、纯文字后弹幕层拿到 30、字体名、纯文字，暂停后不再进新弹幕。
- 真机：**没有 K90 结果**。记录“没验证的”写的是 CHECKLIST 第 2 节第 3 条（固定 30 帧看起来是否均匀、下载的字体是否用上、表情是否消失），结果一栏是空的；登记表却是“完成”（写进本单元报告，建议和 D04.1 的真机验证同一轮补看，或改回“待真机”）。

## 留下的问题

- 真机结果：见上，CHECKLIST 第 2 节第 3 条。
- 多画面的飞行弹幕不跟帧率设置：[N01.2](../../../N-多画面和投屏/N01-多画面/N01.2-多画面弹幕跟随帧率设置/README.md)。
- 应用内小窗和画中画的弹幕不用弹幕字体：`features/live_play/mini/compact_danmaku.dart:204-213` 的 `DanmakuLook` 没有 `fontFamily`；3.x 小窗用同一个弹幕字体（`git show v3.2.11:lib/modules/live_play/widgets/danmaku/compact_danmaku_overlay.dart:35`、`:62`）。没有任务，建议开新任务（和“小窗画自带表情图”一起，见 [D03 的已知问题](../../D03-飞行弹幕引擎/README.md)）。
- 电视直播间的弹幕层不传帧率：A17.4。
- `compactDanmakuFps`（`features/live_play/logic/mini_window.dart:232`）和 `resolvedDanmakuFps(pip: true)` 是两份同样的规则：没有任务，下次改帧率规则时合成一个。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
| 2026-10-02 | 写功能对比（v3、v4、根因、改动），和 D03.1、R02.1 一起开发 |
| 2026-10-02 | 开发完成（和 D03.1 一起），待 K90 验证 |
| 2026-10-07 | 文档 v2：按功能说明模板补上信息行、结果、验证、留下的问题，开发前的对照保留 |
