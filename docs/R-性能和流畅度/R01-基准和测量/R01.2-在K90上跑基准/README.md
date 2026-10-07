# R01.2 在 K90 上跑基准，按数字决定封面圆角画法

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：性能
- 来源：[R01.1](../R01.1-基准测试和渲染开销/README.md) 的 c4（P4）：“封面圆角先用基准测一下，光栅 P90 改善超过 0.5 毫秒才改成装饰圆角”；R01.1 当时不能在手机上跑，留了 `cover_corners_*` 三种画法的对比；[V03.2 调研](../../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md) 4.4 节 P4
- 旧编号：T14a.2
- 相关：前置 R01.1（基准，`2ec6f598e`）；[specs/UI.md](../../../specs/UI.md) 第 9.3 节“圆角用装饰不用裁剪”；卡片组件归 A02（`live_ui`）；任务书 [brief.md](brief.md)

## 目标

- K90 上跑一次 R01.1 的基准，得到第一批真机帧数字（同时完成 R01.1 的 verify 第 1 部分）。
- 用 `cover_corners_clipOverFade`（现在卡片的画法）和 `cover_corners_decoration`（装饰圆角）的光栅 P90 差决定：差 >0.5 毫秒就把卡片封面改成装饰圆角，否则保持 `ClipRRect`，结论写进记录。
- 用户看到的变化：改了的话，热门、分区、关注快速滑动时光栅时间少一些（外观不变）；不改则没有变化。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 卡片封面的圆角 | `ClipRRect` 裁剪 | `packages/live_ui/lib/src/widgets/live_room_card.dart:362`：`ClipRRect(borderRadius: radius, child: coverImage())`，注释“The only clip of the card”；`coverImage`（`:240-255`）是 `LiveNetworkImage`（`network_image.dart`，`CachedNetworkImage`，`fadeInDuration: Duration.zero`） | 按数字决定 |
| 为什么裁剪可能贵 | — | `ClipRRect` 默认 `Clip.antiAlias` 不做 saveLayer，但 cached_network_image（octo_image）给异步到达的图套了一层不透明度为 1 的 `FadeTransition`，`RenderAnimatedOpacity` 在 alpha>0 时是重绘边界，于是封面成了独立的裁剪层（R01.1 记录“偏差 2”） | 基准里 `clipOverFade` 就是这种组合，`clip` 是只有裁剪，`decoration` 是 `BoxDecoration` 带圆角画图 |
| 列表行的平台标志 | — | `live_room_card.dart:718`：16 像素平台标志的 `ClipRRect`（半径 5） | 太小，不在本任务范围 |
| 文档里的旧位置 | — | R01.1 记录和 V03.2 调研写的 `room_card.dart:396` 已过时：`packages/live_ui/lib/src/widgets/room_card.dart` 现在只是数据类（126 行），没有裁剪 | 以 `live_room_card.dart:362` 为准 |

## 方案

- c1 按 R01.1 的 [verify.md](../R01.1-基准测试和渲染开销/verify.md) 第 1 部分在 K90 上跑完整基准（`flutter drive --profile … --dart-define=PERF_HZ=120`），连跑两次，取两次的 `cover_corners_*` 的 raster P90。
- c2 判定：`clipOverFade` 的 raster P90 减 `decoration` 的 raster P90，两次都 >0.5 毫秒才改。
- c3（只在 c2 判定要改时）：`live_room_card.dart:362` 改成装饰圆角——封面用 `DecoratedBox(decoration: BoxDecoration(borderRadius: radius, image: DecorationImage(image: CachedNetworkImageProvider(url, maxWidth: cacheWidth, cacheManager: …, headers: …), fit: BoxFit.cover, filterQuality: FilterQuality.low)))`，占位和失败状态在底下另放一层；保持 `LiveUiScope` 的缓存管理器、请求头、缓存代号和 `memCacheWidth` 等价的解码宽度；下播变暗那一层本来就是装饰圆角，不动。
- c4 记录：两次的 9 行结果、判定和理由；改了的话前后对比（再跑一次基准）。

## 性能任务：测量

| 指标 | 改之前 | 目标或结果 | 怎么测 |
|---|---|---|---|
| `cover_corners_clipOverFade` 的 raster P90 | 待测 | — | 基准 JSON，两次 |
| `cover_corners_decoration` 的 raster P90 | 待测 | — | 同上 |
| 两者之差 | 待测 | >0.5 毫秒才改 | 同上 |
| 改后 `hot_scroll` 的 raster P90（改了才测） | c1 的值 | 下降，且不出现新的卡顿 | 再跑一次基准 |

## 验证

- 自动测试：只在 c3 改代码时加——`packages/live_ui/test/` 里卡片封面的层树断言（没有 `ClipRRectLayer`、有带圆角的 `DecoratedBox`）、占位和失败状态照旧显示；现有卡片测试不改断言照样通过。
- 真机：c1 本身就是 K90 上的测量；改了的话手动看热门卡片的圆角、占位、下播变暗都和以前一样。

## 留下的问题

- 平台标志的小裁剪（`:718`）和其他组件里的 `ClipRRect`（`features/areas/area_card.dart:84`、`features/recorder/recorder_task_card.dart:326`、`features/iptv/iptv_cards.dart:501`）不在本任务里；如果 c2 证明装饰圆角明显更省，在 A02 开任务统一。
