# R01.2 在 K90 上跑基准，按数字决定封面圆角画法：任务书

## 背景

- 来源：R01.1 c4（P4）的约定“封面圆角先用基准测，光栅 P90 改善超过 0.5 毫秒才改成装饰圆角”（`docs/R-性能和流畅度/R01-基准和测量/R01.1-基准测试和渲染开销/record.md` “逐条对照”c4、“需要维护者决定的”第 2 条）；V03.2 调研 4.4 节 P4；[specs/UI.md](../../../specs/UI.md) 第 9.3 节“圆角用装饰不用裁剪”。
- 现象：用户看不到问题；热门、分区、关注每张卡片的封面都是一个 `ClipRRect` 裁剪层，快速滑动时光栅线程多做裁剪（量级没测过）。
- 为什么现在做：第二档；规模小；R01.1 的基准已经合并，跑一次就能决定，同时给出第一批 K90 帧数字。
- 已经做过的：R01.1（基准、`cover_corners_*` 三种画法的对比场景，`2ec6f598e`）。

## 目标和验收

1. K90 上完整跑两次基准，`record.md` 写下两次控制台的 9 行和 JSON 文件名；同时把它们追加到 R01.1 的 `record.md`（R01.1 verify 第 1 部分的第 7 步）。
2. `record.md` 写清判定：两次 `cover_corners_clipOverFade` 和 `cover_corners_decoration` 的 raster P90，差值，结论（改 / 不改）和理由。
3. 不改：任务完成，没有代码改动。
4. 改：`packages/live_ui/lib/src/widgets/live_room_card.dart:362` 改成装饰圆角，外观、占位、失败状态、下播变暗和以前一样；新加的层树测试通过、现有卡片测试不改断言照样通过；改后再跑一次基准，`hot_scroll` 的 raster P90 下降、没有新的卡顿。
5. 测试和门禁通过（改了时）。

## 现状（读代码得出，写文件:行）

- 卡片封面：`packages/live_ui/lib/src/widgets/live_room_card.dart:352-362`：`AspectRatio(16/9)` 里的 `Stack`，第一个子组件 `ClipRRect(borderRadius: radius, child: coverImage())`（注释“The only clip of the card (U.4a, performance)”）；下播时上面一层 `DecoratedBox(color: offlineDim, borderRadius: radius)`（`:363-366`，本来就是装饰圆角）；平台、回放、人数等小块在上面。
- `coverImage()`（`:240-255`）：地址为空时占位；否则 `LayoutBuilder` 算解码宽度 `(width × dpr).round().clamp(240, 720)`，返回 `LiveNetworkImage(url:, memCacheWidth:, placeholder:, error:)`。
- `LiveNetworkImage`（`packages/live_ui/lib/src/widgets/network_image.dart`）：`CachedNetworkImage(imageUrl:, cacheKey: config.imageCacheKey(url), httpHeaders: config.imageHeaders?.call(url), cacheManager: config.imageCacheManager, fit: cover, memCacheWidth:, filterQuality: low, fadeInDuration: zero, fadeOutDuration: zero, useOldImageOnUrlChange: true, placeholder:, errorWidget:)`。即使淡入时长是 0，octo_image 仍给图套一层 `FadeTransition`（不透明度 1），它是重绘边界，所以裁剪变成独立的层。
- 基准：`apps/pure_live/integration_test/perf_test.dart:246-268` 的 P4 场景，对三种画法各测一次；`CornerGrid`（`:287`）用本机 300 张不同的封面（`ResizeImage(MemoryImage)`，解码宽度同卡片），`clipOverFade`（`:312`）= `ClipRRect` + `FadeTransition(kAlwaysCompleteAnimation)` + `Image`，`clip`（`:319`）= 只有 `ClipRRect`，`decoration`（`:323`）= `BoxDecoration(borderRadius:, image: DecorationImage(...))`。
- 跑法和判定：R01.1 的 [verify.md](../R01.1-基准测试和渲染开销/verify.md) 第 1 部分；结果在 `apps/pure_live/build/perf/perf-<时间>.json` 的各场景 `rasterMs.p90`。
- 旧位置：R01.1 记录和 V03.2 调研写的 `room_card.dart:396` 已过时（`packages/live_ui/lib/src/widgets/room_card.dart` 现在是 126 行的数据类）。

## 3.x 基线

- 3.x 的卡片封面也是 `ClipRRect` 裁圆角（V03.2 调研 4.2 节“裁剪”一行）；`git show v3.2.11:lib/common/widgets/` 下的房间卡片组件。3.x 没有帧基准，没有数字可比。
- 要保留：卡片的外观（圆角半径、占位、失败、下播变暗）、解码宽度、缓存行为（`LiveUiScope` 的缓存管理器、请求头、缓存代号）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 3.3 节阶段、第 10 节真机、第 14 节规则）。
2. `docs/specs/UI.md` 第 9 节；`docs/specs/ENGINEERING.md`（`live_ui` 的依赖规则）。
3. 本文件夹的 `README.md`；`docs/R-性能和流畅度/R01-基准和测量/README.md`；`docs/R-性能和流畅度/R01-基准和测量/R01.1-基准测试和渲染开销/record.md`（“偏差和原因”第 2 条、“要在 K90 上看的”）和 `verify.md`；`docs/V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md` 第 4 节。
4. 代码：`packages/live_ui/lib/src/widgets/live_room_card.dart`、`network_image.dart`；`apps/pure_live/integration_test/perf_test.dart`、`perf/frame_report.dart`。

## 范围

- 可以改：`packages/live_ui/lib/src/widgets/live_room_card.dart`（只改封面的圆角画法，c3）、必要时 `network_image.dart`（加一个返回 `ImageProvider` 的方法，供装饰用）；`packages/live_ui/test/`；本文件夹的 `record.md`；R01.1 的 `record.md`（只追加 K90 结果）。
- 不能改：卡片的布局、尺寸、颜色和其他小块；其他组件里的 `ClipRRect`（另开任务）；基准本身（除非发现它测错了，改了要在记录里写明）；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 跑基准 | c1 K90 上完整跑两次；c2 判定 | `record.md`、R01.1 的 `record.md` | 验收第 1、2 条；不改时验收第 3 条，任务完成 |
| 2 判定并记录（要改时） | c3 封面改装饰圆角：`DecoratedBox` + `DecorationImage(CachedNetworkImageProvider(...))`，占位和失败放在底下一层（图片到达前、失败时露出）；c4 再跑一次基准对比 | `live_room_card.dart`、`network_image.dart`（如需）、`packages/live_ui/test/` | 验收第 4、5 条 |

每个阶段都要能单独合并（门禁通过、不留半截功能）。

## 测试

- 只在阶段 2 加（`packages/live_ui/test/`，例如 `live_room_card_test.dart`）：
  - `the cover is rounded by decoration, not by a clip`：pump 一张有封面的卡片（测试用内存图片或假的缓存管理器），断言封面区域没有 `ClipRRect`（或层树里没有 `ClipRRectLayer`），有带 `borderRadius` 和 `DecorationImage` 的 `DecoratedBox`；改之前会失败。
  - `placeholder and error still show`：地址为空、图片失败时显示占位。
  - `offline dim keeps its rounded corners`：下播卡片的变暗层还在。
- 现有的卡片测试（`packages/live_ui/test/` 里 `LiveRoomCard` 的用例、`apps/pure_live/test/features/popular/popular_test.dart`）不改断言照样通过。
- 定时器至少 1 秒；不访问真实网络。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 按 R01.1 的 verify.md 第 1 部分跑完整基准两次（`--dart-define=PERF_HZ=120`，跑的时候不碰手机） | 两次都 7 个测试通过；各 9 行结果 |
| 2. 比较两次的 `cover_corners_clipOverFade` 和 `cover_corners_decoration` 的 raster P90 | 记下差值；两次都 >0.5 毫秒才进入阶段 2 |
| 3. （改了时）装改后的测试包，看热门、分区、关注的卡片 | 圆角、占位、加载失败、下播变暗都和以前一样；快速滑动没有闪烁 |
| 4. （改了时）再跑一次基准 | `hot_scroll` 的 raster P90 比第 1 步低；没有新的 FAIL |

## 风险和注意

- 基准会把 profile 基准包装成 `com.mystyle.purelive.v4dev`，覆盖手机上现有的测试包；跑完重装。只点测试包（D-019）。
- 两次结果差得多时（例如另一个场景也波动 >1 毫秒），说明手机状态不稳（温度、后台），等手机凉下来再跑，不要用一次的数字下结论。
- 装饰圆角会失去 `CachedNetworkImage` 的 `useOldImageOnUrlChange`（换地址时保留旧图），要在底层自己保留，或接受换地址时短暂露出占位——在记录里写清。
- 可能冲突的文件：`live_room_card.dart`（A09 浏览界面的任务、A02 组件任务）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/R01.2` 或本机工作区；提交信息以 `[R01.2]` 开头（英文）；不推 master。
- 提交前（改了代码时）：`packages/live_ui` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。
- 构建 profile 包和跑基准时不要同时跑门禁；跑完 `./gradlew --stop`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（跑了几次、判定到哪）、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

两次基准的 9 行结果（或文件名）；P4 的差值和结论；改了的话改了什么、前后对比、测试数量（改之前失败几个）；其他场景里明显不达标的（交给哪个组）；要在真机上再看的；可能冲突的文件。
