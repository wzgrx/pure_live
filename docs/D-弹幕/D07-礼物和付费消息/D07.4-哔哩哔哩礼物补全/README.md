# D07.4 哔哩哔哩礼物补全：游客的 SEND_GIFT_V2、图标、舰长等级

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：[V03.5](../../../V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md) 第 2 节哔哩哔哩一行、第 3 节哔哩哔哩、第 6.4 节第 3 条、第 7 节 D07.4；用户 2026-10-09（D-040）
- 相关：依赖 [E05.5](../../../E-直播平台/E05-平台框架和模型/E05.5-统一礼物模型LiveGift/README.md)、[D07.1](../D07.1-礼物过滤连击合并和限速/README.md)（每条都报以后靠它合并）；哔哩哔哩弹幕 D01.2、访客昵称 D01.32；决定 D-013（打码昵称不还原）；任务书 [brief.md](brief.md)

## 目标

1. 登录后的哔哩哔哩礼物有图标、单价、档位，送礼人的粉丝牌和舰长照聊天行一样画；连击的最终数字对。
2. 没登录（访客）也能看到礼物：解出访客收到的 `SEND_GIFT_V2`（现在访客只看得到上舰）。

## 3.x 和现状

| 方面 | 3.x | 现在（V03.5 的行号） | 要做到 |
|---|---|---|---|
| `SEND_GIFT` | 不上报 | `_gift`（`packages/live_danmaku/lib/src/sites/bilibili.dart:757`）：编号、名称、数量、金瓜子总价（只在金瓜子时 `:766`）、连击编号；`tid` 当消息编号 | 加单价 `price`、图标 `gift_info.img_basic`、`medal_info`（粉丝牌、舰长）、`unit`（金瓜子或银瓜子 = 免费） |
| 连击 | — | 同一连击只报第一条（类注释 `:73-74`、`:179-186`），`COMBO_SEND.total_num` 看不到 | 每条都报，`comboKey = batch_combo_id`，`comboTotal` 取 `COMBO_SEND.total_num`；合并交给 D07.1 |
| 访客 | — | `SEND_GIFT_V2`（protobuf）不解；E01.1 实测 32 条，样本里 2 条且内容已删 | 解：第 2 字段打码昵称，第 10 字段（1 编号、2 名称、3 数量、8 金瓜子、9 `tid`、10 时间） |
| 礼物表 | — | 不取 `giftConfig` | 访客的 V2 没有图标时按编号查表（第 2 阶段，接口匿名能取再做） |
| 上舰 | — | `_guard`（`:784`）价格 × 月数，`kind` 由 E05.5 填 `membership` | 舰长等级（舰长、提督、总督）进 `LiveGift` 的名称或等级 |

## 方案

- c1 `SEND_GIFT`：读 `price`、`gift_info.img_basic`、`medal_info`（`fansName`、`fansLevel`、舰长等级进 `badges` 或已有字段，和 D01.32 的粉丝牌一致）、`coin_type`（`silver` → `free`）。
- c2 连击：去掉“只报第一条”的跳过逻辑，每条 `SEND_GIFT` 都报（`comboKey = batch_combo_id`）；`COMBO_SEND` 报一条 `comboTotal = total_num` 的更新（同一个 `comboKey`）。**和 D07.1 第 2 阶段一起或之后合并**，否则列表会一下一行。
- c3（第 2 阶段）访客的 `SEND_GIFT_V2`：先录一份没删内容的样本（未登录、热闹的直播间，按 `fixtures/README.md` 脱敏：打码昵称本来就是打码的，`uid`、房间号照规则替换），再按字段号用 `codec/protobuf.dart` 解；送礼人是打码昵称，照 D-013 不还原、不能“屏蔽此用户”。礼物图标：V2 没有时查 `giftConfig`（匿名能取到才做，进房取一次缓存）。
- 需要选的（D-003）：舰长等级画成什么 → 照聊天行（D01.32）的做法，不另做。
- 不做：盲盒、全站礼物广播 `NOTICE_MSG`（刷屏，C-7 的理由）、进场和点赞。

## 验证

- 自动测试：现有样本 `fixtures/bilibili/danmaku/S13-*`（没有 `SEND_GIFT`，访客收不到）+ 新录的登录态和访客样本。
- 真机：未登录和登录各看一个热闹的直播间。

## 留下的问题

- ~~`SEND_GIFT_V2` 其余字段的含义（样本录到后补进 record.md）~~：录到了（`S13-guest-gifts`），字段表和设计选择（D-003）见 [record.md](record.md)；4、6、11、13～17、24 等字段的含义是推测，没有用。
- 登录态的 `SEND_GIFT` 没有录（没有账号）：解析按协议的字段名，和访客收到的 `COMBO_SEND`、`SEND_GIFT_V2` 对过；维护者登录后可以补录一份。
