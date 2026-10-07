# D02.1 哔哩哔哩打码昵称不能“屏蔽此用户”，清理已存的打码屏蔽：任务书

> 本任务的开发已经合并（代码 `40dc22279`，和 D01.32 一起合并 `944bab5fc`，2026-10-02），现在是“待真机”：剩下的是维护者按 [verify.md](verify.md) 在 K90 上看，以及看出问题时的修补。下面保留开工时的全部要求（原任务单，旧编号 B01，热修），按任务书模板 v2 重排；“现状”一节是合并后读代码写的。

## 背景

- 来源：审查报告 B-1（严重）和 A-04（[V03.1 全面审查](../../../V-需求和反馈/V03-审查和调研/V03.1-全面审查/README.md)）。
- 现象：未登录进哔哩哔哩直播间，长按一条“观***”的弹幕选“屏蔽此用户”，之后所有昵称被打码成“观***”的观众（以“观”开头的所有人）在**所有**哔哩哔哩直播间的弹幕都不见了，而且永久生效；列表里所有同名行也被删掉。
- 根因：屏蔽按名字全等（去空白、小写）匹配；屏蔽表全局、持久（`live_store` 的 `block_rules`，所有平台共用）；打码昵称代表一群人。
- 为什么做：第一档热修（严重）；决定 D-013。

## 目标和验收

1. c1：访客看到的打码昵称（`BilibiliDanmakuProtocol.isMaskedName`，如“观***”）在长按弹幕面板、画面弹幕点按面板里不显示“屏蔽此用户”；“复制”“屏蔽关键词”照旧。
2. c2：屏蔽表里已经存着的打码昵称，启动时（只做一次，记在 meta）移除，并在屏蔽管理页顶部提示一次“已清理 N 个打码昵称的屏蔽（它们会误伤其他观众）”。
3. c3：屏蔽管理页添加用户屏蔽时，输入打码昵称给出说明并拒绝（页面没有这个输入框时，在过滤层兜底，见“现状”）。
4. 正常昵称照旧能屏蔽、屏蔽后立即生效。
5. 测试：打码昵称不出现“屏蔽此用户”；清理只跑一次；正常昵称照旧。门禁通过。

## 现状（读代码得出，写文件:行）

合并后的代码（2026-10-07 核对）：

- 面板：`apps/pure_live/lib/features/live_play/danmaku/message_panel.dart:169`（`!isMaskedViewerName(name)`）；列表长按和画面点按都调 `showRoomMessageActions`（`:20`）。原来在 `chat_list.dart` 的 `showChatMessageActions`，A07.12 挪过来。
- 判断和清理：`apps/pure_live/lib/shared/danmaku/masked_blocks.dart`：`isMaskedViewerName`（`:7`）、`MaskedNameBlocks.doneKey`（`:16`）、`noticeKey`（`:19`）、`cleanOnce`（`:24`）、`takeNotice`；启动时 `apps/pure_live/lib/app/startup.dart:79`。
- 说明：`apps/pure_live/lib/shared/danmaku/block_manager.dart`：`_takeMaskedNotice`（`:79`）、`_maskedNotice`（`:90`，键 `block-masked-cleaned`）。
- 过滤层兜底（c3 的替代）：`packages/live_danmaku/lib/src/filters/block_list.dart:20-22`。
- 屏蔽动作本身：`features/live_play/logic/room_controller.dart:997` 的 `blockUser`（不判断打码，只靠面板不给入口）。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/widgets/danmaku/danmaku_message_actions.dart`：除本地弹幕外都有“屏蔽弹幕用户”。
- `lib/modules/live_play/controllers/danmaku_controller.dart:252` 的 `_isBlocked`：整名相同即屏蔽；`:209-214` 用正则 `\*{2,}|＊{2,}` 判断打码，只用来插提示。
- 要保留：正常昵称的屏蔽规则（去空白、不分大小写、整名相同）；屏蔽表和 3.x 的 `blockedDanmakuUsers` 同一份数据（D-018）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`。
3. 本文件夹的 `README.md`、`record.md`；`docs/D-弹幕/D01-平台弹幕协议/D01.32-哔哩哔哩访客昵称和粉丝牌/record.md`（“根因”：访客帧里昵称每个字段都打码）；`docs/A-界面设计/A08-弹幕界面/A08.3-弹幕屏蔽页/README.md`（屏蔽管理的样子）。

## 范围

- 可以改：`apps/pure_live/lib/features/live_play/danmaku/`、`apps/pure_live/lib/shared/danmaku/`（屏蔽管理组件、`masked_blocks.dart`）、`packages/live_danmaku`（只加判断）、`apps/pure_live/lib/app/startup.dart`（只加一处调用）、翻译文件、对应测试。
- 不能改：`packages/live_store` 的表结构（meta 键定义在应用里）；屏蔽管理的布局（A08.3 已确认，不新加“添加用户”输入框）；其他组的界面和逻辑；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1（已合并） | c1 面板不给入口；c3 过滤层兜底 | 面板（当时 `chat_list.dart`）、`block_list.dart` | 长按和点按“观***”没有这一项；`message_filter_test.dart` 打码昵称不屏蔽任何人 |
| 2（已合并） | c2 一次性清理和说明 | `masked_blocks.dart`、`block_manager.dart`、`startup.dart`、翻译 | 清理只跑一次、说明只出现一次 |
| 3（待做） | 真机验证 | `verify.md` | 每一步有结果；通过后登记表改“完成” |

## 测试

- 已有：`packages/live_danmaku/test/message_filter_test.dart:31`；`apps/pure_live/test/shared/masked_blocks_test.dart`（3 个）；`apps/pure_live/test/features/shield/shield_page_test.dart:158`、`:184`；`apps/pure_live/test/features/live_play/live_play_popups_test.dart:980`；`apps/pure_live/test/features/live_play/live_play_page_test.dart:327`。
- 真机看出问题要修时：先在上面对应的文件里写一个改之前会失败的用例。
- 测试里的定时器至少 1 秒；不访问真实平台。

## 真机验证（维护者在 K90 上做）

步骤和期望见 [verify.md](verify.md)：未登录长按和点按打码弹幕、升级后的一次性说明、其他平台正常屏蔽。

## 风险和注意

- 清理在每次安装只跑一次：如果第一次启动时清理失败（只写日志），下次启动会再试（`doneKey` 没写）；不会重复提示。
- 打码判断对所有平台生效：LOOK 直播匿名模式的“观***”同样不能屏蔽（这是对的）。
- 可能冲突的文件：`message_panel.dart`（A07.14 也改面板的打开时机）、`block_manager.dart`（A08 的屏蔽管理）、`startup.dart`。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 修补走分支 `ai/D02.1` 或本机工作区；提交信息以 `[D02.1]` 开头（英文）；不推 master。
- 提交前：`packages/live_danmaku` 跑 `dart format --output=none --set-exit-if-changed .`、`dart analyze`、`dart test`；`apps/pure_live` 跑 format、`flutter analyze`、全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `next`、`branch`。

## 报告（中文，简洁）

verify.md 每一步的结果；不通过的现象和根因；修补改了哪些文件、加了哪些测试。
