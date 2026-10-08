# D07.7 要先录样本的平台补礼物：SOOP、SHOWROOM、TwitCasting、PandaTV、FC2、酷狗、六间房、LOOK、Kick

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：[V03.5](../../../V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md) 第 2 节、第 3 节、第 7 节 D07.7、第 8 节；用户 2026-10-09（D-040）
- 相关：依赖 [E05.5](../../../E-直播平台/E05-平台框架和模型/E05.5-统一礼物模型LiveGift/README.md)；各平台弹幕 D01；样本规则 `fixtures/README.md`；任务书 [brief.md](brief.md)

## 目标

协议里有礼物、匿名能收到、但仓库样本里没录到礼物字段的 9 个平台，先录真实样本，确认字段后解成礼物。

## 3.x 和现状（V03.5 第 2 节）

| 平台 | 协议里有（未录样本或字段不知道） | 现在 | 要做到 |
|---|---|---|---|
| 酷狗 | 礼物 601（`SENDGIFT`，负载 `GiftEffectSocketMsg.Content`，字段没有文档；实测见过 29 条没留样本） | 只回 ack（`kugoulive.dart:170`、`:436`） | 从网页脚本找字段、录样本、解 |
| 六间房 | 礼物 201（样本只留 `typeID`） | 不报（`sixroom.dart:284`） | 录内容、解（飞屏在 D07.2） |
| LOOK | 云信自定义消息 102（礼物和点歌同一种，字段不知道） | 不报（`looklive.dart:438-466`） | 录样本、区分礼物和点歌 |
| SOOP | 星气球（별풍선）、广告气球、视频气球、订阅（服务号按网页播放器资料推断 18、33、87、105、91/93，未核实） | 只有聊天（`soop.dart:104-108`），样本约 24 秒、没有这些服务 | 录样本；星气球的数量就是价值（`unit = starBalloon`）；订阅是通知 |
| PandaTV | 후원 `SponCoin`、`ItemCoin`（`{nick, id, coin}`），归档 v4 做过 | 只有聊天（`pandalive.dart:103`） | 录样本、解 |
| SHOWROOM | 礼物 `t` 2、11、17（`g` 编号、`n` 数量、`gt` 类型；名称、单价、图标要礼物表） | 只有评论（`showroom.dart:31`） | 录样本、取礼物表 |
| TwitCasting | 礼物只发给带 `gift=1` 的地址（`item{id, name, image, effectCommand}`、`isPaidGift`） | 不要（`twitcasting.dart:22-23`） | 加 `gift=1`、录样本、解 |
| FC2 | `system_comment` 里的打赏 `tip_amount`、礼物 `gift_id`（名称要 `gift_list`） | 不报（`fc2live.dart:128`） | 录样本、解 |
| Kick | `KicksGifted`（按公开客户端库：`gift.name`、`gift.amount`，100 Kicks = 1 美元） | 已经上报（`kick.dart:164`），但没有样本 | 录样本核对字段（E05.5 已统一文字） |

## 方案

- 每个平台的步骤一样：① 录样本（海外开代理；按 `fixtures/README.md` 脱敏，`meta.json` 写清录了什么、删了什么）→ ② 在 record.md 写字段表（推断的标“推断”）→ ③ 解成 `LiveGift`（单位、免费、连击键能填就填）→ ④ 冻结输出和测试。
- 四个阶段按地区分（国内、韩国、日本、其他），每个阶段可以单独合并；**也可以拆成每个平台一个任务**（在 D07 新登记，标题写“接 D07.7”）。
- 某个平台录不到礼物（例如服务号推断错了）时在 record.md 写清，那个平台不做，不影响其他平台。
- 不做：快手（C-16）、YY（C-20）、LiveMe、TikTok、CC（受阻），京东（没有礼物系统）。

## 验证

- 自动测试：每个平台的样本对照。
- 真机：每个平台抽一个热闹的直播间看。

## 留下的问题

- SOOP 的服务号、酷狗 601、六间房 201、LOOK 102 的字段都是推断或不知道的（V03.5 第 8 节）。
