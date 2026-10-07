# R03 内存和图片

应用用多少内存、会不会越用越多：解码后的图片缓存上限和按显示尺寸解码、弹幕和聊天的缓存上限、播放器的缓冲，以及长时间播放、快速滚动、反复进出直播间之后内存是否稳定。

## 范围

- 包括：
  - 解码图片缓存的上限：`apps/pure_live/lib/app/bootstrap.dart:31-77`（`configureDecodedImageCache`、`decodedImageBudget`、`readTotalMemoryBytes`），启动时设在 `PaintingBinding.instance.imageCache` 上。
  - 图片按显示尺寸解码（`memCacheWidth`、`ResizeImage`）：卡片封面 `packages/live_ui/lib/src/widgets/live_room_card.dart:246-249`（240～720）、头像 `avatar.dart:80`（48～256）、氛围背景 `ambient_backdrop.dart:39`、切换直播间 `features/live_play/switch_room/room_switch_tiles.dart:219`、上下滑换房的封面 `player/room_swipe.dart:255`、分区图 `features/areas/area_artwork.dart:200`、录制卡片 `features/recorder/recorder_task_card.dart:339`、发布历史 `features/version/release_history_view.dart:382`、电视封面 `tv/widgets/tv_area_card.dart:73`、弹幕表情 `shared/danmaku/danmaku_overlay.dart:893`（高 96）。
  - 内存里有上限的缓存：聊天记录 500 条（`ChatFeed`，D04.1）、飞行弹幕录好的 Picture 96 个、表情图 160 个（`danmaku_overlay.dart:839`、`:867`）、mpv 的前向缓冲 32 MiB + 后向 4 MiB（每个播放器，`packages/live_player/lib/src/mpv_options.dart:142-147`）。
  - 测量：进出直播间的常驻内存（R01 基准的 `room_enter_exit_20`）、`dumpsys meminfo` 的 PSS、长时间播放的趋势。
- 不包括（归哪里）：
  - 图片的磁盘缓存（flutter_cache_manager）、它走不走代理、“清除缓存”“刷新封面”的功能 → [Q02](../../Q-网络和代理/Q02-代理和镜像/README.md)（代理）、J 组（数据工具 `features/settings/data_tools.dart`）。
  - 帧时间 → [R01](../R01-基准和测量/README.md)；弹幕数据流的性能 → D04；多画面最多几格 → N01。
  - 录制占用的磁盘空间 → H03。

## 现状：做到哪、怎么工作的

- 用户看得到的：几乎没有直接的界面；表现为热门来回滑时封面不反复闪（缓存住了）、低端机不因为图片缓存被系统杀掉。
- 内部怎么工作：
  1. 启动时（`AppBootstrap.start`，`bootstrap.dart:98-103`）在 Android 上读 `/proc/meminfo` 的 `MemTotal`：电脑 240 张 / 72 MiB；手机内存 ≤4 GiB 或读不到 160 张 / 48 MiB（3.x 的值，约 40 张封面）；>4 GiB 320 张 / 128 MiB（约 110 张封面，R01.1 c3）。
  2. 卡片封面按卡片的物理宽度解码（最大 720 宽，约 1.1 MiB 一张），所以 128 MiB 能放约 110 张。
  3. 飞行弹幕：每条弹幕排版一次录成 Picture，最近用的 96 个留着（3.x 的 `pictureCacheMaxSize`）；表情图解码一次（高 96）、最多 160 个，超出时释放最早的（`dispose`）。聊天列表最多 500 条（D04.1）。
  4. 播放器：每个播放器 mpv 内存缓存最多 32 MiB 前向 + 4 MiB 后向（`demuxer-donate-buffer=no`，后向不借前向的空间）；多画面 4 格就是 4 份。关掉直播间后引擎留 45 秒（复用），然后释放（G02）。
- 完成度（和 3.x 对照）：
  - 一致：图片缓存的低档数值、弹幕 Picture 96 个、聊天 500 条、mpv 缓冲数值。
  - 改动：大内存手机的图片缓存放宽（R01.1 c3，“需要维护者决定的”还没回复）；封面、头像都按显示尺寸解码（3.x 部分地方没有）。
  - **没有任何真机数字**：长时间播放、快速滚动、反复进出直播间后的内存都没测过（specs/UI.md 9.4“连续进出 50 个直播间不增长”没判定）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/app/bootstrap.dart` | `configureDecodedImageCache`（`:34`）、`largeImageBudgetAbove` 4 GiB（`:43`）、`decodedImageBudget`（`:54`）、`readTotalMemoryBytes`（`:65`）；启动时调用（`:100-103`） |
| `packages/live_ui/lib/src/widgets/live_room_card.dart` | 封面解码宽度（`:246`，240～720）、`LiveNetworkImage`（`:248-253`） |
| `packages/live_ui/lib/src/widgets/network_image.dart` | `LiveNetworkImage`：`CachedNetworkImage`，`memCacheWidth`、无淡入、换地址时保留旧图 |
| `packages/live_ui/lib/src/widgets/avatar.dart:80` | 头像解码宽度 48～256 |
| `apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart` | 录好的弹幕 Picture 最近 96 个（`:839`）、表情图最多 160 个（`:867`，`capacity` `:864`）、表情按高 96 解码（`:893`） |
| `apps/pure_live/lib/features/live_play/danmaku/chat_feed.dart` | `ChatFeed` 最多 500 条（D04.1 的文件） |
| `packages/live_player/lib/src/mpv_options.dart:142-147` | mpv 内存缓存：`cache-secs` 6、`demuxer-max-bytes` 32 MiB、`demuxer-max-back-bytes` 4 MiB、不借用前向缓冲 |
| `apps/pure_live/lib/features/settings/data_tools.dart` | `ImageCacheTools`（`:29`）：清内存和磁盘、刷新封面、定时刷新不在屏幕上的封面（3.x `CacheController`） |
| `apps/pure_live/integration_test/perf/bench_app.dart:401` | `residentMiB`（`ProcessInfo.currentRss`），基准 `room_enter_exit_20` 每次退出后记一次 |

测试：`apps/pure_live/test/image_cache_budget_test.dart`（3：分档、`MemTotal` 解析、设到缓存上）；`apps/pure_live/test/shared/danmaku_overlay_test.dart`（弹幕层缓存，D03.1）；`apps/pure_live/test/features/live_play/chat_feed_test.dart`（500 条上限，D04.1）；基准 `room_enter_exit_20`（R01.1）。没有长时间播放的内存测试。

## 3.x 基线

- `git show v3.2.11:lib/common/global/initialized.dart:31-35`：`configureDecodedImageCache`（手机 160 / 48 MiB、电脑 240 / 72 MiB，注释写着 960×540 的封面解码后约 2 MiB）。
- `lib/plugins/cache_manager.dart:29-30`：磁盘缓存 320 个、30 分钟过期（4.x 用默认管理器，见 Q02）。
- `lib/player/utils/live_buffer_policy.dart`：mpv 缓冲数值（同 4.x）。
- specs/UI.md 第 9.4 节“v3 基线（归档 v4 实测）”：Android 直播间 PSS 462 MB；Windows 首页 481 MB、一个直播间 801 MB、3 格多画面 1054 MB。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 没有内存的真机数字：长时间播放、快速滚动、进出直播间都没测 | — | specs/UI.md 9.4、9.2 第 5 条没判定 | R03.1；R01.1 的基准先给第一批（`room_enter_exit_20`） |
| ≤4 GiB 设备的图片缓存：R01.1 保留 3.x 的 48 MiB，任务单举例 64 MB，维护者没表态 | `bootstrap.dart:54-59` | — | R03.1 测完后一起定 |
| 多画面 4 格时 mpv 缓冲最多 4 × 36 MiB | `mpv_options.dart:145-146` | 低端机多画面可能内存紧张 | R03.1 测多画面；N01 按设备能力限格数 |
| 磁盘缓存用默认管理器（200 个、30 天），3.x 是 320 个、30 分钟 | `packages/live_ui/lib/src/widgets/network_image.dart:46` | 磁盘占用和新鲜度和 3.x 不同（另有代理问题） | 随 Q02 的“图片走应用代理”任务一起改 |

## 相关决定和规范

- [specs/UI.md](../../specs/UI.md) 第 9.2 节第 2、5 条（图片按显示尺寸解码；图片缓存有上限；进出直播间 20 次内存不持续增长）、第 9.4 节（连续进出 50 个直播间不增长；v3 基线 PSS 462 MB）。
- [V03.2 调研](../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md) 第 3.3 节 D2（按设备内存设图片缓存；`debugInvertOversizedImages`；热门快速滚动 2 分钟 PSS 不再增长）、第 4.3 节第 6 条（`dumpsys meminfo`）。
- D-017、D-019。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/image_cache_budget_test.dart`；弹幕和聊天的上限在 D 组的测试里。
- 真机：R01.1 verify 第 5、12 步（进出直播间的常驻内存、热门快速滚动 2 分钟的 PSS）；R03.1 的完整测量。

## 路线

1. R01.1 的 verify 给出进出直播间 20 次的第一批数字。
2. R03.1（第三档）：长时间播放（1 小时）、快速滚动、进出 50 个直播间、多画面 4 格的内存曲线；有增长就找泄漏（DevTools 的内存快照）；同时定 ≤4 GiB 设备的缓存值。
3. 以后：Windows 的内存（specs/UI.md 的 v3 基线有 Windows 数字，X01）。新想法写进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [R 性能和流畅度](../README.md)。

- 代码：`app/bootstrap.dart`、图片组件
- 进度：`░░░░░░░░░░░░░░░░░░░░` 0%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| R03.1 | 内存：长时间播放和快速滚动后内存稳定 | 性能 | 未开始 | — | — | [设计或说明](R03.1-内存/README.md)、[任务书](R03.1-内存/brief.md) |

## 还没完成的

- **R03.1 内存：长时间播放和快速滚动后内存稳定**（未开始，第三档，规模 中）

<!-- docs:生成结束 -->
