# D08.5 三档礼物特效：小飘屏、横幅、大礼物座驾动效（参考 flame_barrage）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：[V03.6](../../../V-需求和反馈/V03-审查和调研/V03.6-弹幕系统和本地互动体验/README.md) 第 2.1 节（flame_barrage 一行）、第 2.2 节 P7、第 4 节 E9、第 5.5 节第二、三段（做法 A）；用户 2026-10-09 点名“特效”（D-040）
- 相关：依赖 [D08.4](../D08.4-本地礼物连击和数量/README.md)（横幅队列）；礼物横幅界面 [A08.2](../../../A-界面设计/A08-弹幕界面/A08.2-本地互动/README.md)（c9）；飞行弹幕 D03（不进弹幕层）；决定 D-018、D-040；规范 specs/UI.md 第 9.3 节；任务书 [brief.md](brief.md)

## 目标

本地礼物的特效按价格分三档：小礼物一条从右往左飞过画面上方的飘屏；中礼物现在的横幅；大礼物横幅 + 一段 2～3 秒的“座驾”动效（火箭、飞机、流星这类，纯 Canvas 画）。设置里的“礼物特效”从开关改成“全部 / 只要大礼物 / 关”。

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 特效 | 一种横幅（大礼物更大）、模糊光晕（`v3.2.11:lib/modules/live_play/pages/live_play_page.dart:47-92`） | 一种横幅、去掉了模糊（`local_interaction/local_gift_effect.dart:54-123`，A08.2 c9）；`data['effect']` 只有 `full`、`ticker`、`none`（`logic/local_interaction.dart` 的 `sendGift`） | 三档 |
| 设置 | `localInteraction.enableGiftEffects`（开关） | 同（`packages/live_store/lib/src/settings/settings.dart:1264`） | 键保留；新键存三选一 |
| 可借的 | — | flame_barrage 的八种座驾（`~/ref/flame_barrage/lib/src/effect/motion/`：`rocket_launch_effect.dart`、`airplane_effect.dart`、`meteor_streak_effect.dart`、`ufo_effect.dart`、`dragon_swim_effect.dart`、`horse_riding_effect.dart`、`ghost_drift_effect.dart`、`magic_carpet_effect.dart`，加 `barrage_fx_particle.dart`；9 个文件 1841 行，MIT），3.x 和上游都没接上 | 借其中 2～3 种的画法 |

## 方案（做法 A，D-003 维护者选 A）

- c1 分档按价格（不按平台）：小 < 100；中 100～999；大 ≥ 1000 或礼物标了 `big`（`LocalCatalog` 的常量）。
- c2 设置：新键 `localInteraction.giftEffectLevel`（`all`、`bigOnly`、`off`）；旧的 `localInteraction.enableGiftEffects` 不改不删（D-018）：新键没有值时按旧键读（开 = `all`、关 = `off`），改新键时同时写旧键（`off` → 关，其余 → 开），覆盖回 3.x 照样对。默认 = 现在的样子（`all`）。设置页的开关换成三选一。
- c3 小档飘屏：一行“🌶 Pure Live 送出 辣条 ×N”从右往左飞过画面上方（用本地弹幕已有的顶部轨道，`LiveMessagePlacement.top` 的滚动版，或在 `LocalGiftLayer` 里自己画一条），只在画面上。
- c4 大档座驾：横幅 + 2～3 秒的动效，借 flame_barrage `effect/motion/` 里火箭、飞机、流星三种的画法（重写成 `CustomPainter`，不引入 Flame；文件头保留 MIT 版权声明和来源提交），按礼物选（例如火箭礼物用火箭，其他大礼物轮流）。画在 `LocalGiftLayer` 自己那一层，不进弹幕层，不影响平台弹幕的帧时间。
- c5 规范：只用合成层动画和描边，不用模糊（UI.md 第 9.3 节）；系统要求减少动态时三档都只有横幅。
- c6 性能：K90 120 Hz 下 profile 构建量帧时间（大礼物动效期间界面线程和光栅线程 ≤ 8 毫秒/帧），数字记进 verify.md。

## 定稿的选择（D-003，维护者定，2026-10-09）

c1～c6 照上面做；任务书没写死、开发时定下的：

| 编号 | 选择 | 理由 |
|---|---|---|
| h1 | **按一个的价格分档**（`LocalGiftTier.of`，`LocalCatalog.giftTierMedium` 100、`giftTierBig` 1000），不按连击的总价、不按平台；标了 `big` 的一律大档；不知道价格的（D08.4 以前的消息没带价格）按中档。通用礼物“城堡”（2000，没标 `big`）因此也是大档 | 礼物是什么就是什么档：一个横幅连击时数量往上涨，按总价会半路从飘屏变成座驾；按总价算 520 根辣条也成了火箭。各平台的价格表 `big` 和 ≥ 1000 本来就重合（8 个大礼物都 ≥ 1000） |
| h2 | **三档进同一个队列**（D08.4 的 `LocalGiftQueue`，一次一个、按送出的顺序、最多 5 个），每档自己的时间（`durationOf`）：小 4 秒、中 3 秒（`effectDuration`，3.x 的 3 秒）、大 4 秒 | 不改连击和排队；同一时刻画面上最多一个特效，帧时间有上界，飘屏和横幅不会叠在一起 |
| h3 | **小档的飘屏画在 `LocalGiftLayer` 自己那一层**，不用本地弹幕的顶部轨道：一行“🌶 Pure Live 送出 辣条 ×N”（礼物色的细胶囊，`LocalGiftFlyer`），在那块地方的顶上 8 处，从右边外面飞到左边外面，4 秒；快进来、中间慢（三分之一的速度，好读）、快出去 | 弹幕层归 D03、任务书不让改；“本地弹幕显示到画面”关着时也要有；这一层已经躲开控制层、挖孔和右边的面板 |
| h4 | 飘屏连击：同一行接着飞（`ValueKey(serial)`），“×N”跳一下（`GiftCountPulse` 的 1.8 倍），剩下的路重新用满 4 秒（队列也重新算 4 秒），所以一直连点时它飞得越来越慢、停在画面里；不退回右边 | 退回去会跳一下；连击时一直看得到数字 |
| h5 | **座驾三种：火箭、飞机、流星**（`LocalGiftVehicle`），按礼物固定：火箭类（斗鱼超级火箭、虎牙一号）用火箭，大航海、嘉年华、Hype Train、城堡用飞机，守护、守护皇冠、签名气球用流星，以后新加的礼物按 id 的字母定；三种都用得到。不“轮流” | 同一个礼物每次一样（各处一致）；任务书举的例子“火箭礼物用火箭” |
| h6 | 座驾在**大横幅后面**、整块地方里飞（火箭从下面升起、飞机从左边爬升着飞过、流星从右上划到左下炸开），裁在那块地方里（不进控制层、挖孔、面板）；2.8 秒（`LocalGiftVehicle.duration`，最后的烟和火星也散完），大档横幅 4 秒，所以座驾走了横幅还在 1.2 秒；连击不重放 | 横幅的字在前面读得清；任务书“2～3 秒” |
| h7 | **画法**：`CustomPainter`（`repaint` 接动画，外面 `RepaintBoundary`），每帧只重画自己这一层、不重建；身体（火箭、飞机、流星的头和尾巴）按尺寸录成一张 `Picture`，每帧平移旋转着画；位置和粒子都是时间的公式（没有每帧的粒子对象、`Paint`、`Path`，同一时刻和同一种子画出来一样，测试能直接画任意一帧），同时活着的粒子 20～30 个（上限 64）；只有实心圆和渐变，没有模糊；颜色放在 `live_ui` 的 `GiftEffectColors`（门禁规则 2：功能代码不写色值） | 任务书“不要每帧分配对象”“几十个以内”；UI.md 第 9.3 节 |
| h8 | **不加依赖**：不用 Flame、Rive、Lottie，全是代码画的；`pubspec` 没动 | 默认“不加重依赖”；三种座驾几百行代码就够，动画文件反而要加运行库和资源 |
| h9 | 中档**还是原来的横幅**，什么都不加 | 默认“全部”时中档礼物和以前一模一样（D-040 尽量少变） |
| h10 | 设置：新键 `localInteraction.giftEffectLevel`（`all`、`bigOnly`、`off`，默认 `all`）；**旧开关先说了算**：`enableGiftEffects` 关着就是“关”（不管新键），开着按新键（新键是 `off` 但旧开关又被打开——3.x 装回来改的——按“全部”）；改三选一时两个键一起写（关 = 关，其余 = 开）。界面：设置页和互动面板“画面上”一组里同一个组件 `LocalGiftEffectsChoice`：标题、说明，下面三个选择片“全部 / 只要大礼物 / 关”（字大时换行） | D-018 旧键不改含义；任务书“新键没有值时按旧值、改新值同时写旧值”，再多一条：3.x 装回来关掉开关照样生效 |
| h11 | “只要大礼物”：小、中礼物只进列表（没有飘屏、没有横幅），大礼物照旧；送出时定（消息的 `effect`，3.x 的值：大档 `full`、其余 `ticker`、不显示 `none`），已经排着的不受后来改设置的影响 | 和 3.x 的开关一样在送出时定 |
| h12 | **减少动态时三档都是静止的横幅**（小、中是小横幅，大档是大横幅），不放大进场、数字不跳；每档的时间照旧（小 4 秒、中 3 秒、大 4 秒） | 任务书；和 D08.4 g12 一样，减少动态只改样子，排队、连击、计时不变 |
| h13 | **应用内小窗和画中画没有特效**（`PlayerView` 在小窗和画中画里换成 `MiniPlayerSurface`，没有这一层），队列照走，回到直播间时还排着的接着播 | 那么小的画面会被特效整个盖住；礼物只能在直播间的面板里送 |
| h14 | 2 倍字：横幅照 D08.4 整个缩小；飘屏的字最多放大 1.3 倍（UI.md 第 8.2 节画面上控制层的字），保持一条细条；座驾按那块地方的短边定大小（短边 ÷ 180，夹在 0.55～1.4），竖屏小画面上也整个看得到 | 不压画面；三种布局都在里面 |

## 实现和验证

- 代码：
  - `logic/local_gift_tier.dart`（新）：`LocalGiftTier`（三档、各自的时间、`of`、`ofGift`）、`LocalGiftEffectLevel`（`all`、`bigOnly`、`off`、`shows`）。
  - `logic/local_catalog.dart`：`giftTierMedium`、`giftTierBig`。
  - `logic/local_interaction.dart`：`LocalGiftData.tier`；`giftEffectLevel`（读旧开关和新键、两个一起写）；`sendGift` 的 `effect` 按档和三选一。
  - `logic/local_gift_queue.dart`：`LocalGiftShow.tier`；`logic/local_room_session.dart`：队列的 `durationOf` 按档。
  - `effects/local_gift_flyer.dart`（新）：`LocalGiftFlyer`（`Flow` 平移）、`LocalGiftFlyerLine`、`localGiftFlyerPath`。
  - `effects/local_gift_vehicle.dart`（新，带 flame_barrage 的 MIT 声明）：`LocalGiftVehicle`、`LocalGiftVehicleScene`（画一帧、录身体）、`LocalGiftVehicleView`。
  - `local_gift_effect.dart`：`LocalGiftLayer.tiered`（默认的画法）；大档横幅按档。
  - `local_interaction_panel.dart`：`LocalGiftEffectsChoice`；`local_interaction_settings_page.dart` 用它。
  - `packages/live_store/lib/src/settings/settings.dart`：`localInteractionGiftEffectLevel`；`packages/live_ui/lib/src/theme/live_colors.dart`：`GiftEffectColors`。
  - 翻译 3 条新的（`local_gift_effects_all`、`local_gift_effects_big_only`、`local_gift_effects_off`），`local_gift_effects_desc` 改了说明；没有删键（D-024）。
- 借的代码：flame_barrage `lib/src/effect/motion/` 的 `rocket_launch_effect.dart`、`airplane_effect.dart`、`meteor_streak_effect.dart`、`barrage_fx_particle.dart`（MIT，Copyright (c) 2026 bobobo，提交 `3eddae8`），只借画法（形状、颜色、粒子的样子），用 `CustomPainter` 重写，没有引入 Flame、没有照搬它的引擎；版权声明在 `local_gift_vehicle.dart` 文件头。
- 测试、帧时间和真机上要看的：[record.md](record.md)。
