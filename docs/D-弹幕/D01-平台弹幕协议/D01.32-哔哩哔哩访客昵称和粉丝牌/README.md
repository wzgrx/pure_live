# D01.32 哔哩哔哩访客昵称提示和登录引导、粉丝牌和头像

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为待真机，2026-10-02，提交 `2eea8022a`，合并 `944bab5fc`）；当时定的规模中
- 类型：功能（弹幕数据 + 聊天列表上的一条提示；界面照已确认的 A08.1 聊天列表，不另出图）
- 来源：用户 2026-10-02 的问题 04“哔哩哔哩的弹幕没有用户名字”（[V02.2](../../../V-需求和反馈/V02-用户反馈和issue/V02.2-用户10月2日的问题/README.md)）；审查报告 A-04（[V03.1 全面审查](../../../V-需求和反馈/V03-审查和调研/V03.1-全面审查/README.md)，同时写了 B-1）
- 旧编号：B06、T06d.2
- 相关：决定 D-013（打码昵称不去还原，做登录引导）；同一分支先做的 [D02.1](../../D02-过滤和屏蔽/D02.1-打码昵称不能屏蔽/README.md)（打码昵称不能屏蔽）；协议 [D01.2](../D01.2-哔哩哔哩弹幕/README.md)；框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)（`DanmakuSender`）；聊天列表的样子 [A08.1](../../../A-界面设计/A08-弹幕界面/A08.1-弹幕列表和弹幕设置页/README.md)；之后的 [D04.1](../../D04-数据流和性能/D04.1-弹幕性能和可读性/README.md) 改了提示的通知方式（只在状态翻转时通知）
- 任务书 [brief.md](brief.md)；记录 [record.md](record.md)；真机验证 [verify.md](verify.md)

## 目标

未登录看哔哩哔哩直播，聊天里所有昵称都是“观***”。查下来**不是解析漏了字段，是服务器按连接身份打码**（访客连接收到的每条 `DANMU_MSG` 里，能放昵称的字段全是打码的，`LOG_IN_NOTICE` 明说“为保护用户隐私，未登录无法查看他人昵称”）。所以不去还原（D-013），而是：

1. 访客进哔哩哔哩直播间时，聊天列表顶上常驻一条“访客模式下哔哩哔哩会隐藏昵称 · 去登录”，点了去扫码登录，登录成功后弹幕自动用新身份重连、昵称完整；
2. 登录还在但昵称仍被打码（Cookie 失效）时提示“登录已失效，哔哩哔哩隐藏了昵称 · 重新登录”；
3. 访客帧里**不打码**的粉丝牌和头像解析出来：昵称前显示“牌子名 等级”，卡片样式的聊天行用头像代替小圆点。

## 3.x 和现状

| 方面 | 3.x（`git show v3.2.11:lib/...`，文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 访客提示 | 每次连接第一次见到打码昵称时插一条系统消息“哔哩哔哩访客连接会隐藏弹幕昵称；登录该平台后使用其返回的完整昵称”（`modules/live_play/controllers/danmaku_controller.dart:209-214`，正则 `\*{2,}|＊{2,}`）；没有登录入口 | `LiveRoomController.nameHint`（`apps/pure_live/lib/features/live_play/logic/room_controller.dart:265`，枚举 `ChatNameHint` `:67`）：哔哩哔哩直播间、弹幕开着、没有哔哩哔哩 Cookie → `guest`；聊天列表顶上 `ChatNameHintBar`（`features/live_play/danmaku/chat_list.dart:529`，选择在 `_nameHint` `:366`），按钮调 `AppNavigator.toBiliBiliLogin()`（`:371`）；系统消息不再插 | 常驻提示 + 一键登录（做到） |
| 登录后重连 | 没有（要手动刷新直播间） | 订阅 `store.secrets.cookieChanges`（`room_controller.dart:309`）→ `_onLoginChanged`（`:281`）：重新取房间详情拿新的弹幕凭据，再强制重连（`_syncDanmaku(force: true)`） | 扫码成功就重连（做到） |
| 登录失效 | 没有 | 有 Cookie 但这次连接已收到 3 条打码昵称、一条全名都没有（`maskedChatsForExpiredLogin` `room_controller.dart:259`，计数 `:870-886`）→ `loginExpired` | 推断式提示（做到，见“偏差”） |
| 昵称取法 | `_preferredBilibiliUserName`（`core/danmaku/bilibili_danmaku.dart:449`，调用 `:380`） | `_userName`（`packages/live_danmaku/lib/src/sites/bilibili.dart:706`）：`user.base.name` → `origin_info.name` → 顶层 `uinfo` → `data.uinfo` → `info[2][1]`，取第一个不打码的；打码判断 `isMaskedName`（`:344`，正则 `:341`） | 顺序同 3.x，登录后取到全名（做到，测试用合成样本） |
| 粉丝牌 | 不解析，列表不显示 | `_medal`（`bilibili.dart:615`）：先 `info[0][15].user.medal{name, level}`，再 `info[3]`（`[等级, 牌子名, …]`），等级 0 不写；填 `LiveMessage.fansName`、`fansLevel`；列表 `_fans`（`chat_list.dart:720`）画成小标签 | 做到 |
| 头像 | 不解析；卡片左边是 8 像素彩色圆点（`modules/live_play/widgets/danmaku/danmaku_list_view.dart:446`） | `_avatar`（`bilibili.dart:635`）：`user.base.face`，没有再 `origin_info.face`，转 https，`hdslb.com` 加 `@96w_96h.jpg`；放进 `LiveMessage.data` 的 `DanmakuSender`（`packages/live_danmaku/lib/src/sender.dart:8`，`bilibili.dart:607`）；卡片样式有头像时 24dp 圆形头像代替圆点、名字用弹幕颜色（`chat_list.dart:764-815`） | 做到（紧凑样式不加头像） |

## 结果

- 改动清单（任务书的 c1～c3，全部做到，详见 [record.md](record.md)“逐条对照”）：
  - c1 访客常驻提示和登录引导：`ChatNameHint`、`nameHint`、`ChatNameHintBar`；提示在空状态上面也显示，列表和提示放在同一个 `Column` 里，提示出现或消失时列表不重建、不丢滚动位置；Cookie 一变就重取凭据重连。
  - c2 粉丝牌和头像：`_medal`、`_avatar`、`DanmakuSender`；卡片样式头像 24dp（`CommonAvatar`，加载失败时显示名字首字）。
  - c3 登录后昵称完整：照 `fixtures/bilibili/danmaku/S13-protover2-paired` 第一条真实 `DANMU_MSG` 复制，只把 uid 和三处昵称换成登录后的样子，解析出全名和 uid。
- 根因核对（record“根因”）：两份未登录的真实录制（S13-live 房间 5050 的 44 条、S13-protover2-paired 房间 1700301235 的 66 条）逐字段看过：`info[2]`、`user.base.name`、`origin_info.name` 全打码，uid 全 0，`dm_v2` 为空，顶层没有 `uinfo`；只有头像、粉丝牌不打码。醒目留言（`SUPER_CHAT_MESSAGE`）的 `user_info.uname` 本来就是全名。
- 偏差（record“偏差”）：
  1. 头像没有加到 `LiveMessage`（`live_core` 不在可改范围），借用 `data`；哔哩哔哩聊天的 `data` 原来为空，过滤、录制、多画面都不读它。
  2. “登录已失效”是推断（同一连接 3 条打码、0 条全名）；文字比任务书多半句原因。
  3. 重连凭据用 `site.getRoomDetail` 重新取（多一次详情请求），房间控制器不依赖哔哩哔哩的类型。
  4. 没解析 `LOG_IN_NOTICE`（会和顶上的提示重复）。
- 后来的改动：D04.1 让控制器不再为每条聊天通知，`nameHint` 只在**翻转时**通知（第 3 条打码昵称、之后第一条全名，`room_controller.dart:881-886`），聊天列表经 `_RoomFacts`（`chat_list.dart:500`）只在提示变化时重建。
- 没有新设置。翻译键 3 个：`bilibili_guest_names_hidden`、`bilibili_login_expired_short`、`bilibili_login_again`（`apps/pure_live/assets/translations/zh.json:221`、`:225`、`:223`）；“去登录”用已有的 `live_play_go_login`；3.x 的 `bilibili_guest_name_masked`（`:220`）不再用，按约定保留（D-024）。
- 没有做的“绕过”：用同场进场、点赞消息里的“头像 + 全名”对上访客弹幕，或从发送者摘要反推 uid 查名字——平台明说为保护隐私而隐藏，而且只能对上进过场、点过赞的人，默认头像会撞（D-013）。
- 提交：代码 `2eea8022a`（`feat(danmaku): Bilibili guest name hint with login, fan badges and avatars`），和 D02.1 一起合并 `944bab5fc`（2026-10-02）。

## 验证

- 自动测试（新增 10 个、改 4 个，record“测试”）：
  - `packages/live_danmaku/test/sites/bilibili_test.dart`：两份访客录制里每条弹幕每个字段都打码、uid 0，粉丝牌和头像照样解析出来（有牌子的 61 / 41 条，和 `info[3]` 一致，`:538` 起）；登录态合成样本取全名和 uid；粉丝牌的来源和边界（`info[3]` 兜底、等级 0、名字不是文字）；头像地址（https、尺寸、已有尺寸不再加、非 http 不要）。4 个和 3.x 的冻结对照去掉了新加的粉丝牌和头像（3.x 不读）。
  - `apps/pure_live/test/features/live_play/live_play_controller_test.dart`（`:253`、`:270`、`:296`）：访客有提示、不再插系统消息、弹幕关掉后没有提示；登录后 2 条打码不提示、3 条提示失效、来一条全名就消失，退出登录后用访客凭据重连；其他平台没有提示、别的平台 Cookie 变化不重连。
  - `apps/pure_live/test/features/live_play/chat_names_test.dart`（3 个，`:123`、`:161`、`:182`）：提示在聊天行上面、点“去登录”打开扫码页、写入 Cookie 后重取详情重连、提示消失；失效提示和“重新登录”；粉丝牌小标签，卡片样式头像 24dp 代替圆点、没头像照旧。
- 真实接口：仓库没有登录态的真实录制，“登录后昵称完整”只有合成样本，**在线没有验证**。
- 真机：**待真机**，步骤在 [verify.md](verify.md)（record“要在 K90 上看的”6 条）。

## 留下的问题

- 是否在 `live_core` 的 `LiveMessage` 上加正式的头像字段（现在借用 `data`）：需要维护者决定；没有任务，等第二个平台要头像时再定。
- 未点亮的粉丝牌（`is_light` 为 0，S13-live 里 10 条）现在和点亮的画法一样，网页上是灰的：需要维护者决定要不要区分；没有任务。
- 访客收到的礼物是 `SEND_GIFT_V2`（protobuf），现在不解析：见 [D01.2](../D01.2-哔哩哔哩弹幕/README.md)“留下的问题”。
- 用进场、点赞消息还原昵称：不做（D-013）。
