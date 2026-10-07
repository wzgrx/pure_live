# R03.1 内存：长时间播放和快速滚动后内存稳定：任务书

## 背景

- 来源：[specs/UI.md](../../../specs/UI.md) 第 9.2 节第 5 条、第 9.4 节“连续进出 50 个直播间不增长”；V03.2 调研 3.3 节 D2（热门快速滚动 2 分钟 PSS 预热后不再增长）、4.3 节第 6 条；2026-10-02 登记（旧编号 T14d.1）。
- 现象：没有用户报告的具体问题；4.x 没有任何内存的真机数字，不知道长时间挂直播、来回翻列表后会不会涨。
- 为什么现在做：第三档（PLAN 第三档）；排在 R01.1 的 K90 基准之后（它会先给出进出直播间 20 次的数字）。
- 已经做过的：R01.1 c3（图片缓存按内存分档，`2ec6f598e`）；D04.1（聊天 500 条、每帧最多通知一次）；D03.1（弹幕 Picture 缓存）；C02.1（播放器复用）；G02.1（停止后 45 秒释放引擎、创建中被释放）。

## 目标和验收

1. `record.md` 有五个场景的内存曲线表（时间 × TOTAL PSS、Java Heap、Native Heap、Graphics），每个场景写设备状态（亮度、网络、房间）和预热后的增长量。
2. 判定写清：场景 1、3 预热后 PSS 增长 <30 MB；场景 2、4、5 每小时 <50 MB；直播间稳定时 PSS 和 v3 基线 462 MB 的对比。
3. 不达标的：找到原因（文件:行）并修掉，修复有改之前会失败的测试，修后复测达标；找不到原因的写明排查过程和下一步。
4. `debugInvertOversizedImages` 检查：列出所有超尺寸解码的图（应为 0），有的修掉。
5. ≤4 GiB 设备的图片缓存值有结论（保留 48 MiB 或改 64 MiB），写进记录；改了的话 `decodedImageBudget` 和 `image_cache_budget_test.dart` 一起改。
6. 测试和门禁通过（改了代码时）。

## 现状（读代码得出，写文件:行）

- 图片缓存：`apps/pure_live/lib/app/bootstrap.dart:34-39`（`configureDecodedImageCache`）、`:43`（4 GiB 分界）、`:54-59`（`decodedImageBudget`：电脑 240 / 72 MiB；手机 ≤4 GiB 或未知 160 / 48 MiB；>4 GiB 320 / 128 MiB）、`:65-77`（读 `/proc/meminfo`）；启动时调用 `:100-103`。
- 解码尺寸：卡片封面 `packages/live_ui/lib/src/widgets/live_room_card.dart:246`（物理宽度，240～720）；头像 `packages/live_ui/lib/src/widgets/avatar.dart:80`（48～256）；氛围背景 `ambient_backdrop.dart:39`；切换直播间 `apps/pure_live/lib/features/live_play/switch_room/room_switch_tiles.dart:219`（160～720）；换房封面 `features/live_play/player/room_swipe.dart:255`；分区图 `features/areas/area_artwork.dart:200`；录制卡片 `features/recorder/recorder_task_card.dart:339`；发布历史 `features/version/release_history_view.dart:382`（72）；弹幕表情 `shared/danmaku/danmaku_overlay.dart:893`（高 96）。
- 有上限的缓存：飞行弹幕 Picture 最近 96 个（`danmaku_overlay.dart:839`）、表情图 160 个（`:864`，超出时 `dispose`）；聊天 500 条（`features/live_play/danmaku/chat_feed.dart`）。
- 播放器：`packages/live_player/lib/src/mpv_options.dart:142-147`（`cache-secs` 6、`demuxer-max-bytes` 32 MiB、`demuxer-max-back-bytes` 4 MiB、`demuxer-donate-buffer=no`）；停止后 45 秒释放引擎（`packages/live_player/lib/src/session.dart:343-367`）；`PlayerStandby` 只留一个（`features/live_play/logic/player_standby.dart:15`）；本地中继一个服务、输入关掉即释放（`packages/live_media/lib/src/relay/loopback_relay.dart:37`）。
- 进出直播间：`live_play_page.dart` 的 `dispose` 和 `RoomRuntime.dispose`（释放控制器、弹幕连接、刷新率声明、后台策略）。
- 已有的测量：基准 `room_enter_exit_20`（`apps/pure_live/integration_test/perf_test.dart:218`，每次退出后 `residentMiB`，假播放器，不含 mpv）。

## 3.x 基线

- `git show v3.2.11:lib/common/global/initialized.dart:31-35`：图片缓存 160 / 48 MiB（手机）。
- specs/UI.md 第 9.4 节“v3 基线（归档 v4 实测）”：Android 直播间 PSS 462 MB；Windows 首页 481 MB、一个直播间 801 MB、3 格多画面 1054 MB。
- 3.x 在 K90 上是用户的正式包，**不能拿来测**；需要 3.x 的同场景数字时，用 G03.1 任务书写的改包名构建（`com.mystyle.purelive.v3bench`），可选。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 3.3 节、第 5 节、第 10 节、第 14 节）。
2. `docs/specs/UI.md` 第 9 节；`docs/V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md` 第 3.3、4.3 节。
3. 本文件夹的 `README.md`；`docs/R-性能和流畅度/R03-内存和图片/README.md`；`docs/R-性能和流畅度/R01-基准和测量/R01.1-基准测试和渲染开销/record.md`（偏差 1：图片缓存的来历）。
4. 代码：上面“现状”列的文件。

## 范围

- 可以改：只为修本任务找到的泄漏或超尺寸解码，改动所在的文件（预计在 `apps/pure_live/lib/features/live_play/`、`shared/`、`packages/live_ui/lib/src/widgets/`、`packages/live_player/lib/src/`、`packages/live_media/lib/src/relay/`）和它们的测试；`apps/pure_live/lib/app/bootstrap.dart`（只改 `decodedImageBudget` 的数值）和 `apps/pure_live/test/image_cache_budget_test.dart`；可以新建 `tools/perf/meminfo_series.py`（把 `dumpsys meminfo` 的输出汇总成表）；本文件夹的 `record.md`。
- 不能改：mpv 的缓冲数值（会影响弱网，归 G03.1）；聊天 500 条、Picture 96 个等 3.x 数值（D 组）；界面；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。修复超出上面目录的，写进报告由维护者决定。

## 方案和阶段

登记表没有写阶段，开工时按下表补上（`stages = ["测量", "找泄漏并修", "定缓存值并复测"]`）。

| 阶段 | 做什么（对应 README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 测量 | c1 五个场景；c5 `debugInvertOversizedImages` 检查 | `record.md`；可选 `tools/perf/meminfo_series.py` | 验收第 1、2、4 条的数据齐全 |
| 2 找泄漏并修 | c3：DevTools 内存快照比对、原生堆排查；修复和测试 | 视原因而定（“范围”内） | 验收第 3 条；没有泄漏时写“无”并跳到阶段 3 |
| 3 定缓存值并复测 | c4 定 ≤4 GiB 的缓存值；修过的场景复测 | `bootstrap.dart`、`image_cache_budget_test.dart`（改了时）、`record.md` | 验收第 5、6 条 |

每个阶段都要能单独合并（门禁通过、不留半截功能）。

## 测试

- 修泄漏时先写改之前会失败的测试，例如：
  - `apps/pure_live/test/features/live_play/`：`closing a room releases its session, relay inputs and subscriptions`（假引擎、假平台，进房再退出，断言会话 `stop` 被调用、`PlayerStandby` 只留一个、弹幕连接关闭、订阅取消）；
  - `apps/pure_live/test/shared/danmaku_overlay_test.dart`：缓存超过上限时释放；
  - 具体用例按找到的原因写。
- 改缓存值时：`image_cache_budget_test.dart` 的分档断言。
- 定时器至少 1 秒；不访问真实平台。

## 真机验证（维护者在 K90 上做）

准备：profile 包（`com.mystyle.purelive.v4dev`）；亮度 50%、Wi-Fi、不充电；`adb -s 192.168.1.2:5555 shell dumpsys meminfo com.mystyle.purelive.v4dev`（循环脚本按间隔记录，输出存本机，汇总表写进记录）。进房自动化：`adb shell am start -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT "<直播间链接>" com.mystyle.purelive.v4dev`，出画面后 5 秒 `adb shell input keyevent KEYCODE_BACK`（每次前确认前台是测试包）。

| 步骤 | 期望 |
|---|---|
| 1. 热门页快速来回滚动 2 分钟，每 15 秒记一次 | 预热后 PSS 增长 <30 MB |
| 2. 一个弹幕多的直播间（哔哩哔哩或斗鱼热门）连续播 1 小时，每 30 秒记一次 | 每小时增长 <50 MB；记下稳定时的 PSS，和 462 MB 对比 |
| 3. 连续进出 50 个直播间（5 个平台 × 10 个房间），每次退出后记一次 | 第 5 次之后增长 <30 MB |
| 4. 多画面 4 格（国内平台）30 分钟，每 30 秒记一次 | 每小时增长 <50 MB；记绝对值 |
| 5. 开后台播放，进直播间后锁屏 30 分钟，每 30 秒记一次 | 每小时增长 <50 MB |
| 6. debug 包：`debugInvertOversizedImages = true`（只在本机临时改，不提交），走一遍热门、分区、关注、直播间、切换直播间面板、录制中心 | 没有反色的图 |

## 风险和注意

- PSS 受系统回收影响大：每个场景开始前 `adb shell am force-stop` 再启动；同一场景跑两次，看趋势不看单点。
- 1 小时、50 次进出耗时长，手机会发热；记下温度（`dumpsys thermalservice`），发热严重时分几次跑。
- `debugInvertOversizedImages` 只在 debug 构建有效，不要提交打开它的改动。
- 修泄漏可能碰到其他组的文件（直播间、弹幕、播放）：只改泄漏那一处，写进报告；可能冲突的文件：`live_play_page.dart`、`room_controller.dart`、`danmaku_overlay.dart`、`session.dart`。
- 只点测试包（D-019）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/R03.1` 或本机工作区；提交信息以 `[R03.1]` 开头（英文）；不推 master。
- 提交前（改了代码时）：改过的包跑 `dart format --output=none --set-exit-if-changed .`、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（测完哪几个场景、正在查哪个增长）、更新登记表的 `done`、`next`、`branch`。原始的 `dumpsys` 输出不进仓库。

## 报告（中文，简洁）

五个场景的结论（增长量、稳定值）；和 v3 基线的对比；找到的泄漏（根因、文件:行）和修复、测试数量（改之前失败几个）；超尺寸解码的图；≤4 GiB 缓存值的结论；改了哪些文件；要在真机上再看的；需要维护者决定的；可能冲突的文件。
