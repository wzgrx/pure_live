# D01.32 哔哩哔哩访客昵称提示和登录引导、粉丝牌和头像：任务书

> 本任务的开发已经合并（代码 `2eea8022a`，和 D02.1 一起合并 `944bab5fc`，2026-10-02），现在是“待真机”：剩下的是维护者按 [verify.md](verify.md) 在 K90 上看，以及看出问题时的修补。下面保留开工时的全部要求（原任务单，旧编号 B06），按任务书模板 v2 重排；“现状”一节是合并后读代码写的。

## 背景

- 来源：用户 2026-10-02 的问题 04“哔哩哔哩的弹幕没有用户名字”（[V02.2](../../../V-需求和反馈/V02-用户反馈和issue/V02.2-用户10月2日的问题/README.md)）；审查报告 A-04（[V03.1 全面审查](../../../V-需求和反馈/V03-审查和调研/V03.1-全面审查/README.md)）：解码仓库里的访客录制，确认服务器按连接身份打码，访客帧里只有头像、粉丝牌、财富等级和发送者哈希不打码。
- 现象：未登录（或登录失效）进任意哔哩哔哩直播间，聊天列表和飞行弹幕里所有昵称都是“观***”这类打码昵称；3.x 只在聊天里插一条系统消息说明，没有登录入口；戴粉丝牌的观众看不出牌子。
- 为什么做：哔哩哔哩是最常用的平台；决定 D-013：打码是平台为保护隐私做的，不去还原，做登录引导。
- 依赖和顺序：在 D02.1（打码昵称不能屏蔽）之后，同一分支；和 E06.2 都会改聊天行，错开做。

## 目标和验收

1. c1：访客连接哔哩哔哩弹幕时，聊天列表顶部常驻“访客模式下哔哩哔哩会隐藏昵称 · 去登录”，替换原来每次连接插入的系统消息；点“去登录”打开哔哩哔哩扫码登录（`AppNavigator.toBiliBiliLogin()`），登录成功后弹幕自动重连；Cookie 失效时提示“登录已失效 · 重新登录”。
2. c2：粉丝牌（`user.medal{name, level}` 或 `info[3]`）填进 `LiveMessage.fansName`、`fansLevel`，聊天行显示；卡片样式的聊天行加头像（`user.base.face`）。
3. c3：登录后昵称完整：确认解析顺序在登录态下取到全名（用 `fixtures/bilibili/danmaku/` 的结构写合成样本）。
4. 测试：提示的显示和隐藏；粉丝牌和头像解析；登录态样本取全名。门禁通过。

## 现状（读代码得出，写文件:行）

合并后的代码（2026-10-07 核对）：

- 解析：`packages/live_danmaku/lib/src/sites/bilibili.dart`：`_chat`（`:574`）调 `_medal`（`:615`）、`_avatar`（`:635`）、`_userName`（`:706`）；头像放进 `DanmakuSender`（`:607`，类在 `packages/live_danmaku/lib/src/sender.dart:8`）；打码判断 `isMaskedName`（`:344`，正则 `\*{2,}|＊{2,}` `:341`）。
- 房间：`apps/pure_live/lib/features/live_play/logic/room_controller.dart`：`ChatNameHint`（`:67`）、`maskedChatsForExpiredLogin = 3`（`:259`）、`nameHint`（`:265`）、`_onLoginChanged`（`:281`，Cookie 变化后重取 `danmakuData` 再 `_syncDanmaku(force: true)`）、订阅 `cookieChanges`（`:309`）、打码和全名计数（`:870-886`，只在翻转时通知）。
- 列表：`apps/pure_live/lib/features/live_play/danmaku/chat_list.dart`：`_nameHint`（`:366`）、`ChatNameHintBar`（`:529`，`secondaryContainer` 底、信息图标、两行省略、文字按钮）、`_fans`（`:720`）、卡片头像（`:764-815`）。
- 翻译：`apps/pure_live/assets/translations/zh.json:221`、`:223`、`:225`（en.json 同名键）。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/controllers/danmaku_controller.dart:209-214`：每个会话第一次见到打码昵称时插 `bilibili_guest_name_masked` 系统消息。
- `lib/core/danmaku/bilibili_danmaku.dart:449` 的 `_preferredBilibiliUserName`：取名顺序（4.x 不变）；不解析粉丝牌和头像。
- `lib/modules/live_play/widgets/danmaku/danmaku_list_view.dart:446` 的 `DanmakuItem`：卡片左边 8 像素彩色圆点，没有头像。
- 要保留：取名顺序；聊天行其他样子（A08.1）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 3 节（同一件事一种做法）。
3. 本文件夹的 `README.md`、`record.md`；`docs/D-弹幕/D01-平台弹幕协议/D01.2-哔哩哔哩弹幕/record.md`（“样本”的脱敏说明：打码昵称按原样换成另一个打码名）；`docs/D-弹幕/D02-过滤和屏蔽/D02.1-打码昵称不能屏蔽/README.md`。

## 范围

- 可以改：`packages/live_danmaku`（哔哩哔哩解析、`sender.dart`）；`apps/pure_live/lib/features/live_play/danmaku/`；`features/live_play/logic/room_controller.dart`（只在需要时）；翻译文件；对应测试。
- 不能改：`packages/live_core`（`LiveMessage` 不加字段，见“风险”）；其他组的界面和逻辑；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义；不做任何昵称“还原”（D-013）。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1（已合并） | c2、c3：粉丝牌、头像解析；登录态合成样本 | `bilibili.dart`、`sender.dart`、`live_danmaku.dart`、`bilibili_test.dart` | 访客录制里粉丝牌、头像全部解析出来；冻结对照去掉新字段后和 3.x 一致；登录态取全名 |
| 2（已合并） | c1：提示、登录入口、登录后重连、失效判断；卡片头像 | `room_controller.dart`、`chat_list.dart`、翻译文件、`chat_names_test.dart`、`live_play_controller_test.dart` | 控制器和页面测试通过；全部测试通过 |
| 3（待做） | 真机验证 | `verify.md` | 每一步有结果；通过后登记表改“完成” |

## 测试

- 已有（合并时）：`packages/live_danmaku/test/sites/bilibili_test.dart`（访客录制逐字段、登录态样本、粉丝牌边界、头像地址）；`apps/pure_live/test/features/live_play/live_play_controller_test.dart` 三个（访客、登录失效、其他平台）；`apps/pure_live/test/features/live_play/chat_names_test.dart` 三个（提示和登录重连、失效、粉丝牌和头像）。
- 真机看出问题要修时：先在上面对应的文件里写一个改之前会失败的用例。
- 测试里的定时器至少 1 秒；不访问真实平台。

## 真机验证（维护者在 K90 上做）

步骤和期望见 [verify.md](verify.md)：访客提示、粉丝牌、扫码登录后自动重连和全名、卡片头像、横屏和竖屏全屏的提示条、登录失效。

## 风险和注意

- 头像借用 `LiveMessage.data`：以后别的代码开始读聊天消息的 `data` 时要认得 `DanmakuSender`。
- “登录已失效”是推断：如果哔哩哔哩以后对登录用户也偶尔打码，3 条打码会误报；看真机结果再定阈值。
- 可能冲突的文件：`chat_list.dart`（E06.2、A08.6 也改）、`room_controller.dart`（C01.4、E06.2）、`bilibili.dart`。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 修补走分支 `ai/D01.32` 或本机工作区；提交信息以 `[D01.32]` 开头（英文）；不推 master。
- 提交前：`packages/live_danmaku` 跑 `dart format --output=none --set-exit-if-changed .`、`dart analyze`、`dart test`；`apps/pure_live` 跑 format、`flutter analyze`、全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `next`、`branch`。

## 报告（中文，简洁）

verify.md 每一步的结果；不通过的现象和根因；修补改了哪些文件、加了哪些测试；“需要维护者决定的”三条（头像字段、未点亮粉丝牌、不还原昵称）的结论。
