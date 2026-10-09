# D08.5 三档礼物特效：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区，没有推送、没有合并）
- 分支和提交：工作区分支 `worktree-agent-a9d1e713625198026`，起点 master `721813c51`（D08.4 合并）；提交 `7d5ea51d8`（阶段 1：分档、三选一设置）、`60f369a54`（阶段 2～3：飘屏、座驾、帧时间测试）、`14e81c313`（文档）
- 任务书：[brief.md](brief.md)；设计和每条选择的理由：[README.md](README.md)“方案”c1～c6、“定稿的选择”h1～h14（维护者按 D-003 定）；来源：V03.6 第 2.2 节 P7、第 4 节 E9、第 5.5 节第二、三段

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 1 三档：小（< 100）飘屏；中（100～999）横幅；大（≥ 1000 或 `big`）横幅 + 2～3 秒座驾 | 做了 | 按一个的价格（h1）；三档进同一个队列，各自的时间小 4 秒、中 3 秒、大 4 秒（h2）；座驾 2.8 秒 |
| 2 新设置 `localInteraction.giftEffectLevel`（默认 `all`），旧键照读照写，设置页三选一 | 做了 | 旧开关关着一律按“关”读（多做一条：3.x 装回来关掉照样生效，h10）；互动面板“画面上”一组也换成同一个三选一 |
| 3 借 flame_barrage 的火箭、飞机、流星，重写成 `CustomPainter`，保留 MIT 声明，不引入 Flame | 做了 | 位置和粒子改成时间的公式、身体录成 `Picture`（h7）；颜色放进 `live_ui` 的 `GiftEffectColors` |
| 4 只画在 `LocalGiftLayer`；不用模糊；减少动态时只有横幅 | 做了 | 飘屏也画在这一层，不用本地弹幕的顶部轨道（h3）；小窗和画中画没有特效（h13） |
| 5 K90 profile 帧时间 ≤ 8 毫秒/帧 | 待真机 | 主机上的帧时间见下面“帧时间”；K90 的数字由维护者量，记进 verify.md |
| 6 文字走翻译 | 做了 | 3 条新键，`local_gift_effects_desc` 改了说明 |

## 根因

- 新功能。3.x（`v3.2.11:lib/modules/live_play/pages/live_play_page.dart:47-92`）和 4.x 原来（`local_gift_effect.dart` 的 `LocalGiftBanner`）只有一种横幅，大礼物大一点：P7。

## 存储和设置

- 新设置 `localInteraction.giftEffectLevel`（`StringSetting`，`allowed` 三个值，默认 `all`，`localInteraction` 一节，`SettingScope.synced`：进备份和设备同步）。旧的 `localInteraction.enableGiftEffects` 键和含义不变（D-018），改三选一时一起写；D08.5 以前的备份、3.x 的数据里只有旧开关，读出来照旧（开 = 全部，关 = 关）。
- `settings_defaults_test.dart` 的 `newInV4` 加了一行；`tools/docs/settings_audit_notes.py` 加了两个键的说明，`settings_audit.py` 重新生成 J01.2 的 settings.md；`docs/inventory/OWNERS.toml` 不用改（`localInteraction` 一节已经归 D08，`owners.py` 重新生成 OWNERS.md）。`settings_catalog.dart` 不用改：本地互动的设置在自己的页（`RoutePath.kLocalInteraction`），设置搜索只收那一页的入口。
- 没有表结构变化。

## 改了哪些文件

- `apps/pure_live/lib/features/live_play/local_interaction/logic/local_gift_tier.dart`（新）：`LocalGiftTier`、`LocalGiftEffectLevel`。
- `apps/pure_live/lib/features/live_play/local_interaction/logic/local_catalog.dart`：`giftTierMedium`、`giftTierBig`。
- `apps/pure_live/lib/features/live_play/local_interaction/logic/local_interaction.dart`：`LocalGiftData.tier`、`giftEffectLevel`、`sendGift` 的 `effect`。
- `apps/pure_live/lib/features/live_play/local_interaction/logic/local_gift_queue.dart`：`LocalGiftShow.tier`。
- `apps/pure_live/lib/features/live_play/local_interaction/logic/local_room_session.dart`：队列的 `durationOf`；导出 `local_gift_tier.dart`。
- `apps/pure_live/lib/features/live_play/local_interaction/effects/local_gift_flyer.dart`（新）、`effects/local_gift_vehicle.dart`（新，MIT 声明）。
- `apps/pure_live/lib/features/live_play/local_interaction/local_gift_effect.dart`：`LocalGiftLayer.tiered`（默认），大横幅按档。
- `apps/pure_live/lib/features/live_play/local_interaction/local_interaction_panel.dart`：`LocalGiftEffectsChoice`（替换“显示本地礼物特效”开关）；`local_interaction_settings_page.dart` 用它。
- `packages/live_store/lib/src/settings/settings.dart`：新设置。
- `packages/live_ui/lib/src/theme/live_colors.dart`：`GiftEffectColors`。
- 翻译（zh、en，按键名排序）：新 `local_gift_effects_all`（“全部”）、`local_gift_effects_big_only`（“只要大礼物”）、`local_gift_effects_off`（“关”）；改 `local_gift_effects_desc`（“小礼物从画面上方飘过，中礼物横幅，大礼物横幅加座驾动效”）。没有删键（D-024）；没有新图标。
- 测试：新 `apps/pure_live/test/features/live_play/local_gift_effects_test.dart`、`local_gift_effects_benchmark_test.dart`、`packages/live_store/test/local_gift_effects_test.dart`；改 `local_gift_combo_test.dart`（辣条是小档：时间 4 秒；“有动态时横幅的数字跳”改用小电视）、`local_interaction_test.dart`（#8 的时间；清空记录前先滚到按钮，面板高了一点）、`local_history_test.dart`（同样先滚到“只看本直播间”）、`packages/live_store/test/settings_defaults_test.dart`。
- 文档：本文件夹 README（h1～h14、实现）、本记录；D08 子分类 README（代码地图、已知问题、测试）；A08.2 README“实现和验证”补一条；`docs/tasks.toml`；生成的文件（docs.py、owners.py、settings_audit.py）。
- 没改：弹幕层（`danmaku_overlay.dart`）、平台礼物（D07）、平台适配（D07.7 在做）、3.x 键的含义、依赖（`pubspec` 没动）、版本号。

## 测试

- `apps/pure_live/test/features/live_play/local_gift_effects_test.dart`（20 个）：
  - 分档 4 个：价格 10/50/99 小、100/500/999 中、1000 起大，标了 `big` 的大，价格不知道的中；所有平台的礼物：标了 `big` 的都是大档、100 以下都是小档，通用礼物“城堡”是大档；三档的时间 4/3/4 秒，座驾 2～3 秒、比大档横幅短；座驾按礼物固定、三种都用得到；三选一哪档显示、存的值读错时按“全部”。
  - 三选一和旧开关 3 个（内存库）：没存新键时开 = 全部、关 = 关；选“只要大礼物”存新键并打开旧开关，选“关”关掉旧开关；旧开关被 3.x 打开 = 全部，被关掉 = 关；旧的写法还能用；送出时 `effect` 按档和三选一（`ticker`/`full`/`none`，城堡没标 `big` 也是 `full`）。
  - 座驾画法 1 个：三种座驾在三个尺寸上每一帧（120 Hz × 2.8 秒）都画得出、不抛异常、粒子 1～64 个；2.8 秒以后和释放以后什么都不画。
  - 直播间 12 个（整个直播间页、假时钟、打开动画）：
    - 小档：只有飘屏，没有横幅；飘屏的道就是躲开控制层的那块地方；在顶上 8 处从右往左飞、中间慢；4 秒后没了、队列空。
    - 小档连击：同一个飘屏（同一个 State），“×2”，不退回右边，从第二次算 4 秒才走。
    - 中档：只有横幅，3 秒。
    - 大档：座驾在横幅后面（Stack 第一个）、大小就是那块地方；连击不重放（同一个 State），“×2”；2.8 秒后座驾没了、横幅还在；第二次送出后 4 秒横幅走。
    - 混着送：辣条、小电视、超级火箭排队：飘屏 4 秒 → 横幅 3 秒 → 火箭 + 横幅 4 秒，一次一个。
    - 减少动态：三档都只有横幅、不放大进场，各自的时间以后走。
    - “只要大礼物”：辣条、小电视没有特效、大航海有；改成“关”以后超级火箭也没有；列表 4 行都在。
    - 横屏全屏 + 右边面板开着：那块地方在面板左边、上下躲开控制层；飘屏的道和座驾都在里面，横幅也在里面。
    - 系统字体 2 倍，竖屏小画面和横屏全屏各 1 个：飘屏在上下两条中间、高度 < 60（字最多 1.3 倍）；座驾就是那块地方；横幅在里面；没有溢出。
    - 互动面板：三个选择片，默认“全部”；点“只要大礼物”存下、旧开关开；点“关”旧开关关。
  - 设置页 1 个：旧开关关着时选中的是“关”；点“全部”两个键都写。
- `apps/pure_live/test/features/live_play/local_gift_effects_benchmark_test.dart`（2 个）：见下面“帧时间”。
- `packages/live_store/test/local_gift_effects_test.dart`（3 个）：键、默认值、三个值、读错的值按 `all`、同步；备份带上新键和旧开关、恢复回来；D08.5 以前的备份只有旧开关，新键没存。
- 跑过：`apps/pure_live` 的 `test/features/live_play/`、`test/features/settings/`、`test/shared/`、`test/i18n_test.dart`；`packages/live_store`、`packages/live_ui` 全部；`flutter analyze`（应用和两个包）没有问题。

## 门禁

- 2026-10-09 本机 `bash tools/gate/gate.sh --all`（提交 `14e81c313`，D08.5 的全部代码和文档）：`gate: passed (all, 14 members)`，一次通过。

## 帧时间（主机，debug 模式，只能互相比，不能和手机的 profile 构建比）

`flutter test test/features/live_play/local_gift_effects_benchmark_test.dart`，2026-10-09，WSL2：

```text
D08.5 vehicle paint, 120 Hz, 2800 ms each:
  rocket landscape 852x237: paint mean 0.013, P50 0.013, P90 0.017, P99 0.051, max 0.110 ms; at most 29 particles
  airplane landscape 852x237: paint mean 0.010, P50 0.008, P90 0.010, P99 0.042, max 0.649 ms; at most 20 particles
  meteor landscape 852x237: paint mean 0.009, P50 0.007, P90 0.012, P99 0.069, max 0.164 ms; at most 26 particles
  rocket inline 400x121: paint mean 0.011, P50 0.011, P90 0.016, P99 0.034, max 0.050 ms; at most 29 particles
  airplane inline 400x121: paint mean 0.008, P50 0.008, P90 0.010, P99 0.048, max 0.094 ms; at most 20 particles
  meteor inline 400x121: paint mean 0.012, P50 0.006, P90 0.011, P99 0.026, max 1.822 ms; at most 26 particles
D08.5 room at 120 Hz, landscape fullscreen 852x393, 480 frames each:
  nothing: frame mean 0.287, P50 0.034, P90 0.084, P99 1.371, max 91.918 ms; 1.3 builds a frame
  small gift (the line, 4 s): frame mean 0.493, P50 0.404, P90 0.642, P99 2.179, max 6.706 ms; 0.0 builds a frame; effect widgets built: none
  big gift (the vehicle 2.8 s and the banner 4 s): frame mean 0.476, P50 0.286, P90 1.018, P99 3.635, max 6.362 ms; 0.1 builds a frame; effect widgets built: LocalGiftVehicleView 1
```

- 画一帧座驾平均 0.01 毫秒左右（一张录好的身体 + 20～30 个圆），同时活着的粒子最多 29 个。
- 直播间里飘屏和座驾动的时候每帧几乎不建部件（480 帧里座驾的部件只建了 1 次：结束时），只重画自己那一层（`RepaintBoundary` 里的 `Flow`、`CustomPaint`）；帧时间比什么都没有时多 0.2 毫秒左右（主机 debug）。
- “nothing”一行的最大值 92 毫秒是第一帧（主机上第一次光栅化）。
- K90 profile 构建的界面线程、光栅线程帧时间：待真机（下面第 5 步）。

## 真机上要看的

K90（`com.mystyle.purelive.v4dev`，profile 构建；每次点按前确认前台是测试包；不碰 3.x 和正式包）：

1. 进一个在播的哔哩哔哩直播间 → 右上角菜单 → 本地互动体验，送一个“辣条”（10）：画面上方（控制层下面一点）一条“🌶 Pure Live 送出 辣条 ×1”从右边飞进来，中间慢、读得清，4 秒左右从左边飞出去；没有横幅。
2. 送一个“小电视”（100）：画面中间原来的横幅，3 秒，和以前一样。
3. 加币后送一个“大航海”（1980）：大横幅，后面一架飞机从左下爬升着飞过、拖着白色尾迹，2～3 秒；横幅再停 1 秒多才走。换到斗鱼直播间送“超级火箭”：火箭从下面升起、喷火冒烟；快手“守护”：流星从右上划到左下、炸开。平台弹幕照常飞、不卡。
4. 连点辣条 5 下：同一条飘屏，“×N”每次跳一下，飘屏越飞越慢、停在画面里，最后一下以后 4 秒走；连点大航海：飞机不重新飞，横幅数字跳。
5. profile 构建，开着性能浮层（或 `flutter run --profile` 的 DevTools 帧图）送大礼物：座驾飞的 2.8 秒里界面线程和光栅线程每帧 ≤ 8 毫秒（120 Hz）；送小礼物同样看飘屏的 4 秒。数字记进 verify.md。
6. 连着送辣条、小电视、大航海：飘屏 → 横幅 → 飞机 + 横幅，一个完了再下一个，不叠在一起。
7. 横屏全屏、控制层显示时送大礼物和小礼物：飘屏、座驾都不压上下两条按钮、不进左右挖孔；打开右边的本地互动面板再送：都在左边剩下的地方里。
8. 竖屏小画面送大礼物和小礼物：飘屏在画面上方一条、座驾在画面里，都没被裁坏；系统字体调到最大再看一遍：横幅缩小、飘屏的字只大一点。
9. 设置 → 本地用户与互动 →“画面上”：“显示本地礼物特效”下面三个选择片；选“只要大礼物”：辣条、小电视只进列表，大航海照旧；选“关”：都没有。直播间互动面板“画面上”同一个三选一，两边改了互相跟着变。
10. 系统设置 → 无障碍 → 移除动画：三档都是不动的横幅（辣条小横幅、大航海大横幅），没有飘屏、没有座驾，数字不跳。
11. 在画中画或应用内小窗里（之前排着几个礼物）：小窗上没有特效；回到直播间时还排着的接着播。
12. 覆盖安装 3.x 再装回来（可选）：3.x 里“显示本地礼物特效”关掉后回到 4.x，三选一是“关”。
