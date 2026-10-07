# D05 弹幕设置生效

弹幕设置从存储到飞行弹幕层的换算和接线：样式（字号、字重、描边、透明度、速度、区域和留白）、字体、纯文字、帧率（跟随刷新率或手动）、暂停时的弹幕、显示开关、竖屏流的弹幕模式、观看模板、小窗弹幕的 12 项，保证每个设置在直播间、小窗、多画面、电视上“真的生效”，改了立即生效。

## 范围

- 包括：
  - 换算函数：`apps/pure_live/lib/shared/danmaku/danmaku_settings.dart`（`danmakuLookOf`、`DanmakuPausedBehavior`、`danmakuRunning`）、`shared/danmaku/danmaku_templates.dart`（`DanmakuTemplate` 观看模板、`resolvedDanmakuFps`）、`features/live_play/logic/mini_window.dart`（`compactDanmakuFps`、`withoutEmoteCodes`、`CompactDanmakuMetrics`）。
  - 各使用处读哪些设置、怎么传给弹幕层：直播间 `features/live_play/player/player_view.dart` 的 `build`（`:542` 起）、`_danmaku`、`_portraitLook`；小窗 `features/live_play/mini/compact_danmaku.dart`；多画面 `features/multiview/multiview_page.dart`；电视 `tv/room/tv_live_play_page.dart`。
  - 弹幕设置的键、默认值和范围（`packages/live_store/lib/src/settings/settings.dart` 的 `section: 'danmaku'` 一组）的含义要和 3.x 一致（D-018）。
- 不包括（归哪里）：
  - 设置界面（直播间的弹幕设置面板和标签、设置里的弹幕页、观看模板的芯片、小窗弹幕一组）长什么样 → [A08](../../A-界面设计/A08-弹幕界面/README.md)（A08.1、A08.5、A08.6、A08.7）；设置里的“小窗弹幕”页 → A11.3。
  - 弹幕层拿到参数后怎么画 → [D03](../D03-飞行弹幕引擎/README.md)；过滤类设置（合并重复、相似度、斗鱼机器人）→ [D02](../D02-过滤和屏蔽/README.md)；列表样式和礼物开关 → A08.1、D04；点按、长按开关 → A08.4。
  - 字体的下载、注册（`app/fonts.dart`）→ I01.3、J 组；界面刷新率档位本身 → R02。
  - 设置的存储、迁移、备份 → J 组（J02.1）。

## 现状：做到哪、怎么工作的

- 用户看得到的：直播间的弹幕设置（标签、画面上的面板、设置的弹幕页是同一份内容）里改任何一项，画面上**之后进来的**弹幕立即按新样式飞（屏上的照旧飞完，D03.1 c2）；“显示弹幕”关掉时连接也断（`enableDanmakuDisplay` 和 `enablePipDanmaku` 都关时，`room_controller.dart:802`）；画面下栏的弹幕开关（`hideDanmaku`）只藏起画面上的弹幕；弹幕帧率跟随时按“界面刷新率”档位（省电和均衡上限 60、最高 = 设备最高），手动 30～240，实际取刷新率的整数分之一；选了下载的字体就用它；纯文字模式没有表情；“暂停时的弹幕”默认随视频暂停，可改成继续飘过；竖屏直播时“竖屏弹幕”可选只在上四分之一、缩小字号占一半、或隐藏；观看模板一键套用 3.x 的三套样式。小窗和画中画按“小窗弹幕”的 12 项单独设置。
- 内部怎么工作：

```text
SettingsStore（live_store）
  └─ watchSetting(ref, Settings.x)：只重建用到这一项的部件
直播间 PlayerView.build（player_view.dart:542 起）
  danmakuLookOf(ref)（danmaku_settings.dart:11）→ DanmakuLook（字号、字重、速度、透明度、区域、上下留白、描边、字体、纯文字）
  竖屏流：_portraitLook（:814）按 portraitDanmakuMode 改区域和字号；'hidden' 时 visible = false（:686）
  _danmaku（:457）：fps = resolvedDanmakuFps(automatic, configured, refreshRateMode, 设备最高, 当前)（danmaku_templates.dart:210）
                    running = danmakuRunning(播放状态, danmakuPausedBehavior)（danmaku_settings.dart:44）
小窗 CompactDanmakuView（compact_danmaku.dart:153-173 读 19 项）→ CompactDanmakuMetrics（按窗口宽缩放）+ compactDanmakuFps（mini_window.dart:232）
多画面（multiview_page.dart:873-883）：danmakuLookOf + danmakuRunning
电视（tv_live_play_page.dart:458-469）：danmakuLookOf + 显示开关
```

- 完成度（和 3.x 对照）：
  - 一致：所有弹幕设置的键名、默认值、范围（D-018）；改了立即生效；3.x 的三套观看模板和“恢复默认”（`danmaku_templates.dart:42-47`）、保存的模板格式（`savedDanmakuTemplate`，schema 2）；帧率档位（`resolvedDanmakuFps` 照 3.x `danmaku_settings_controller.dart:135-162`）；字体；纯文字；竖屏弹幕模式。
  - D05.1 补回的（登记完成，没有 K90 结果）：主画面的帧率、字体、纯文字。
  - 4.x 新加的：“暂停时的弹幕”（`danmakuPausedBehavior`，A07.10）；帧率取整数分之一（D03.1 c3）。
  - 还缺：多画面不跟帧率（N01.2）；小窗不用弹幕字体、不画自带表情（见“已知问题”）；电视不跟帧率和暂停（A17.4）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/shared/danmaku/danmaku_settings.dart`（53 行） | `danmakuLookOf`（`:11`：9 个样式设置 + 字体 `:12`、`:25` + 纯文字 `:26`）、`DanmakuPausedBehavior`（`:30`，`pause`、`continue`）、`danmakuRunning`（`:44`：播放中为真，暂停时看设置，打开、缓冲、出错、停止都为假） |
| `apps/pure_live/lib/shared/danmaku/danmaku_templates.dart`（231） | `DanmakuTemplate`（`:8`，`of` `:26` 读当前设置、`presets` `:42`：最佳、舒适、密集、恢复默认；`encode`/保存格式 `:85` 起）、`resolvedDanmakuFps`（`:210`，`pip: true` 时下限 15、省电 30） |
| `apps/pure_live/lib/features/live_play/player/player_view.dart` | `build` 读设置（`:542-560`：`hideDanmaku`、`enableDanmakuDisplay`、`enablePipDanmaku`、`portraitDanmakuMode`、`danmakuLookOf`、帧率三项、长按开关、`danmakuPausedBehavior`）；`_danmaku`（`:457`）；`_portraitLook`（`:814`）；`_FpsSettings`（`:823`） |
| `apps/pure_live/lib/features/live_play/mini/compact_danmaku.dart`（220） | 小窗和画中画：读 19 项设置（`:153-173`）、纯文字去掉消息自带的表情代码（`:105`）、弹幕层（`:190`，`DanmakuLook` `:204-213` 没有字体） |
| `apps/pure_live/lib/features/live_play/logic/mini_window.dart`（259） | `CompactDanmakuMetrics`（按窗口宽自动缩放字号、速度、轨道高）、`compactDanmakuFps`（`:232`）、`withoutEmoteCodes` |
| `apps/pure_live/lib/features/multiview/multiview_page.dart` | 多画面的弹幕层（`:873-883`：`danmakuLookOf`、`danmakuRunning`，没有 `fps`） |
| `apps/pure_live/lib/tv/room/tv_live_play_page.dart` | 电视的弹幕层（`:458-469`：`danmakuLookOf`、显示开关） |
| `packages/live_store/lib/src/settings/settings.dart` | 弹幕设置：`hideDanmaku`（`:404`）、`noEmojiMode`（`:407`）、`danmakuTopArea`（`:412`，0）、`danmakuArea`（`:415`，1）、`danmakuBottomArea`（`:419`，0.5）、`danmakuSpeed`（`:428`，120）、`danmakuFontSize`（`:431`，16）、`danmakuFontWeight`（`:434`，500）、`danmakuFontBorder`（`:437`，1.5，0～4）、`danmakuOpacity`（`:446`，1）、`enableDanmakuDisplay`（`:449`）、`enableDanmakuStroke`（`:452`）、`danmakuPausedBehavior`（`:469`）、`danmakuFps`（`:477`，60，30～240）、`danmakuAutoFps`（`:480`，开）、`danmakuFontFamilyName`（`:515`）、小窗 12 项（`:522-581`）、`portraitDanmakuMode`（`:357`，`followGlobal`） |
| `apps/pure_live/lib/app/fonts.dart` | 启动时注册选中的弹幕字体（`restore` `:299` 起，`danmakuFontFamilyName` `:304`） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/shared/danmaku_overlay_test.dart` | 整数分之一的表（`:120`）、手动 30 帧（`:177`）、字体和纯文字（`:266`）、`danmakuRunning`（`:315`） |
| `apps/pure_live/test/features/live_play/live_play_page_test.dart:399` | 直播间把帧率、字体、纯文字传给弹幕层；暂停不进新弹幕 |
| `apps/pure_live/test/features/live_play/live_play_tabs_test.dart` | 弹幕设置标签的分组、单位、模板（A08.1） |
| `apps/pure_live/test/features/live_play/room_refresh_rate_test.dart` | 刷新率和弹幕帧率的联动（R02） |
| `apps/pure_live/test/features/live_play/live_play_mini_window_test.dart` | 小窗弹幕的设置（A07.8） |

## 3.x 基线

- 设置和默认值：`git show v3.2.11:lib/common/services/settings/danmaku_settings_controller.dart`（438 行：默认值 `:7-16`、小窗 `:17-31`、范围限制 `:115-127`、`resolvedDanmakuFps` `:135-162`）。
- 直播间传给弹幕层：`lib/modules/live_play/widgets/video_player/video_controller_panel.dart:786-811`（`BarrageConfig`：`fps` `:798-800`、`noEmojiMode` `:797`、`fontFamily` `:804`）；改设置时 `video_controller.dart:949-978` 重配；竖屏弹幕模式 `video_controller_panel.dart:775-780`。
- 小窗：`lib/modules/live_play/widgets/danmaku/compact_danmaku_overlay.dart`（帧率 `:32`、弹幕字体 `:35`、`:62`、纯文字 `:26`、表情图集 `:86`）。
- 观看模板：`lib/modules/live_play/widgets/danmaku/danmaku_viewing_preset.dart`。
- 必须保留的：键名、默认值、范围（D-018）；改设置立即生效、不清屏；帧率跟随时按“界面刷新率”档位。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| D05.1 登记为“完成”，但记录写明 K90 没验证（CHECKLIST 第 2 节第 3 条结果为空） | [D05.1](D05.1-弹幕设置生效/README.md)“验证” | 不符合 PROCESS 3.2 | 写进本单元报告；建议和 D04.1 的真机验证同一轮补看 |
| 多画面的弹幕层不传 `fps`，每个刷新周期都画 | `features/multiview/multiview_page.dart:878-883` | 不跟弹幕帧率设置（3.x 跟） | [N01.2](../../N-多画面和投屏/N01-多画面/N01.2-多画面弹幕跟随帧率设置/README.md) |
| 小窗和画中画的弹幕不用弹幕字体；也不画自带表情图，“纯文字”只去掉消息自带的表情代码 | `features/live_play/mini/compact_danmaku.dart:204-213`、`:190`、`:105` | 和 3.x 不同（3.x 小窗用弹幕字体和同一个表情图集，`compact_danmaku_overlay.dart:35`、`:62`、`:86`） | 没有任务；建议开新任务（小窗传 `fontFamily` 和表情表，纯文字走 `DanmakuLook.textOnly`） |
| 电视的弹幕层只传样式和显示开关，不跟帧率、不随暂停停 | `tv/room/tv_live_play_page.dart:464-469` | 电视（暂缓）上和手机不一致 | [A17.4](../../A-界面设计/A17-电视界面/A17.4-电视直播间/README.md) |
| `compactDanmakuFps` 和 `resolvedDanmakuFps(pip: true)` 两份同样的规则 | `mini_window.dart:232`、`danmaku_templates.dart:210` | 改一处忘另一处 | 没有任务；下次改帧率规则时合成一个 |
| `repeatedDanmakuWindowSeconds` 设置只限最小 1、没有最大值，靠过滤器使用时限到 30 | `packages/live_store/lib/src/settings/settings.dart:504`、`packages/live_danmaku/lib/src/filters/message_filter.dart:107` | 存进去大于 30 的值显示和生效不一致（3.x 同样在使用处限制） | 照 3.x，不做 |

## 相关决定和规范

- D-018：3.x 的设置键名和含义不变，新设置只加（`danmakuPausedBehavior`、`youtubeShowAllChat`）。
- D-010：刷新率策略；弹幕帧率跟随“界面刷新率”档位。
- D-012：暂停后单击只切控制层；“暂停时的弹幕”（A07.10）。
- D-029：功能清点 F-DM-04、F-DM-05、F-DM-06 由 D05.1 做完，D06.1 改“不做”。
- [specs/UI.md](../../specs/UI.md) 第 3 节第 6 条（标签、画面面板、设置页是同一份弹幕设置）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/shared/danmaku_overlay_test.dart test/features/live_play/live_play_page_test.dart test/features/live_play/live_play_tabs_test.dart`。缺的：多画面、小窗、电视读设置没有“设置改了弹幕层拿到新值”的用例（多画面的帧率等 N01.2 补）。
- 真机：CHECKLIST 第 2 节第 2 条（改区域、透明度、速度、字号、模板，全屏里再调）、第 3 条（帧率 30、字体、纯文字）；第 1 节第 12 条（小窗弹幕按小窗设置显示）。都还没有结果。

## 路线

1. 补 K90 结果：CHECKLIST 第 2 节第 2、3 条（和 D04.1 的真机验证同一轮），通过后 D05.1 的登记才名副其实。
2. N01.2：多画面跟帧率设置。
3. 建议新开：小窗和画中画用弹幕字体、画自带表情图、纯文字走 `textOnly`（和 3.x 一致）；顺手把 `compactDanmakuFps` 合进 `resolvedDanmakuFps`。
4. 以后：电视（A17.4）；“同屏最大条数可以设置”（V01.4，提议）。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [D 弹幕](../README.md)。

- 代码：`shared/danmaku/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| D05.1 | 弹幕设置生效：弹幕帧率、字体、纯文字模式 | 功能 | 完成 | 2026-10-02 | b8462638a | [设计或说明](D05.1-弹幕设置生效/README.md)、[记录](D05.1-弹幕设置生效/record.md) |

<!-- docs:生成结束 -->
