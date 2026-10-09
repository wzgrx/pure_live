# D07.3 斗鱼礼物目录（betard）和礼物字段

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：[V03.5](../../../V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md) 第 2 节斗鱼一行、第 3 节斗鱼、第 7 节 D07.3；用户 2026-10-09（D-040）
- 相关：依赖 [E05.5](../../../E-直播平台/E05-平台框架和模型/E05.5-统一礼物模型LiveGift/README.md)；斗鱼弹幕 [D01.3](../../D01-平台弹幕协议/README.md)；斗鱼平台 E01.2；礼物行 A08.11；任务书 [brief.md](brief.md)

## 目标

斗鱼的礼物有单价、图标和档位：火箭显示火箭的图、算“很值钱”，荧光棒、陪伴印章这类背包免费礼物算免费；礼物行能带上送礼人的等级和粉丝牌。

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 礼物 | 不上报 | `dgb` 在 `packages/live_danmaku/lib/src/sites/douyu.dart:182` 分发、`gift` `:301`：编号、名称、数量、连击 `hits`、收礼人（`DouyuGift`） | 加单价、图标、档位、免费、等级、粉丝牌 |
| 礼物表 | — | 进房已请求 `betard`（`packages/live_core/lib/src/sites/douyu/douyu_api.dart:346`），不读 `room_gift.gift`；样本 `fixtures/douyu/S05-offline/body.json` 有 13 个：名称、`price`（分）、`unit`、`pc_icon`（相对路径）、`gift_effect` | 读进来，按编号查 |
| 表里没有的 | — | 样本 `S13-live`、`S15-gifts` 实际收到的 824 粉丝荧光棒、陪伴印章、精英宝典不在 `betard` 的表里 | 只显示名称；第 2 阶段核实完整礼物接口 |
| 背包礼物 | — | `gfid` 为 0 时编号在 `pid` | 编号取 `pid`，算免费 |
| 送礼人 | — | `dgb` 有 `level`、`bnn`/`bl`（粉丝牌）、`ic`（头像），没留 | 填 `userLevel`、`fansName`、`fansLevel` |

## 方案

- c1 礼物表：`douyu_api.dart` 的 `betard` 回答里取 `room_gift.gift`，做成 `编号 → (名称, 单价分, 图标地址, 动画编号)` 的表，随房间详情交给弹幕参数（`DouyuDanmakuArgs` 加一个字段，或解析器构造时传入）；`pc_icon` 拼成完整地址（前缀从样本和网页核实）。解析在平台层，不在界面线程。
- c2 `dgb`：查表填 `unitPrice`（分）、`totalValue` = 单价 × `gfcnt`、`unit = fen`、`iconUrl`；`gfid` 0 → 用 `pid`、`free = true`；`comboKey` = 送礼人 + 编号 + `hits` 所在的连击（`hits` 回到 1 时新连击），`comboTotal` = `hits` × 每次数量；`userLevel` ← `level`，`fansName`/`fansLevel` ← `bnn`/`bl`。
- c3（第 2 阶段）完整礼物接口：从斗鱼网页脚本找礼物目录接口（`gift.douyucdn.cn` 一类，V03.5 没核实），能匿名取到就进房时取一次、缓存在平台适配器里（和 `betard` 的表合并）；取不到就在 record.md 写清，表里没有的礼物只显示名称、按免费处理还是按 `normal` 处理由维护者定（建议 `normal`、不标免费）。
- 不做：特效动画（`eid`/`eic`、`gift_effect`，留编号给以后）；贵族开通。

## 验证

- 自动测试：用 `S05-offline/body.json` 和 `S13-live`、`S15-gifts` 的样本。
- 真机：斗鱼热门直播间看到火箭这类付费礼物有图、荧光棒不显示价值。

## 定稿（2026-10-09，D-003 由执行者定，理由见 [record.md](record.md)）

- 礼物目录三处合并：`betard` 的 `room_gift`（随房间详情，不多发请求）、房间礼物列表 `gift.douyucdn.cn/api/gift/v3/web/list?rid=`（154 个）、平台道具表 `webconf.douyucdn.cn/resource/common/prop_gift_list/prop_gift_config.json`（1585 个背包道具，粉丝荧光棒在里面）。第 2 阶段的答案：完整礼物接口匿名能取到，`betard` 的表只有老编号（火箭 196），样本里收到的礼物都要靠后两个。
- 后两个在弹幕连接开始时后台取，`DouyuSite` 内存缓存（房间 30 分钟、最多 16 个房间，道具表 6 小时，失败 5 分钟后再试），在另一个 isolate 解析；取不到就是以前的样子。
- 图标前缀 `https://gfs-op.douyucdn.cn/dygift/`（核实过；`gfs-test-op` 的地址不用）。鱼翅价格单位是分；鱼丸礼物和背包道具算免费、不填价值；表里没有的礼物 `normal`、不标免费。
- 样本：`fixtures/douyu/S17-gift-list`、`S18-prop-config`（匿名、无 Cookie，删减到测试要的礼物）。

## 留下的问题

- `gfid` 0 的背包道具（陪伴印章 `pid` 3410、钻粉月饼）没有图：道具表按 `gfid` 编号，没找到按 `pid` 查的公开接口。它们都是免费的，不影响价值。
- 活动礼物（精英宝典、精英令）活动过了就不在房间的列表里，只显示名称。
- 斗鱼聊天（`chatmsg`）的等级和粉丝牌还没读（任务书不许改聊天解析），要的话开 D01 的任务。
