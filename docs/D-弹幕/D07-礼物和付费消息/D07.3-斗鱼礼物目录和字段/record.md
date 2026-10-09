# D07.3 斗鱼礼物目录（betard）和礼物字段：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区 `worktree-agent-a300348f855a14265`）
- 分支和提交：`worktree-agent-a300348f855a14265`，基于 master `10cdbe49a`（含 E05.5、D07.1、A08.11）；代码一次提交 `5b0352d25`（两个阶段一起，见“偏差”），文档一次提交
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)；真机：[verify.md](verify.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 验收 1 进房时从 `betard` 读礼物表，不多发请求 | 做了：`DouyuApi.roomGifts`，`roomDetail` 同一份回答顺带读出，放进 `DouyuDanmakuArgs.gifts` | |
| 验收 2 `unitPrice`、`totalValue`、`unit = fen`、`iconUrl`、`tier`；背包礼物编号取 `pid`、`free` | 做了：`DouyuDanmakuProtocol.gift` 按 `gfid` 查目录；背包（`gpf` 1，或 `gfid` 0 带 `pid`）编号取 `pid`、`free = true`、`DouyuGift.backpack` | 档位不是存的字段，是 E05.5 的 `giftTierOf` 算出来的 |
| 验收 3 `comboKey`、`comboTotal` 按 `hits`；`userLevel`、`fansName`、`fansLevel` | 做了：连击照 E05.5、D07.1（`hits` 是礼物累计数，`comboTotal = hits`；任务书写的“`hits` × 每次数量”和样本不符：粉丝荧光棒 `gfcnt` 10 时 `hits` 10、20、30…，所以不乘）；等级 `level`、粉丝牌 `bnn`、粉丝牌等级 `bl`（没有粉丝牌时不填等级） | 背包礼物的连击键从“送礼人:名称”变成“送礼人:pid”（编号变了） |
| 验收 4 表里没有的礼物照旧显示名称，不报错 | 做了：只有名称、`unit = other`、不标免费、`normal`；`gfn` 空时用目录里的名称 | |
| 验收 5 第 2 阶段：完整礼物接口 | 做了：找到两个匿名能取的接口（下一节），连弹幕时后台取、缓存，补进目录 | |
| c1 `pc_icon` 前缀核实 | 做了：`https://gfs-op.douyucdn.cn/dygift/`（火箭的 `pc_icon` 在这里 200 image/png，在 `gfs-test-op` 404；礼物列表的 `picUrlPrefix` 也是它） | |
| 不做：特效、贵族开通 | 没做 | `betard` 的 `gift_effect` 编号留在 `DouyuGiftInfo.effect` |

## 根因

- `dgb` 包里本来就没有单价和图标（`packages/live_danmaku/lib/src/sites/douyu.dart` 的 `gift`，`gfid`、`gfn`、`gfcnt`、`hits`…），4.x 进房请求的 `betard`（`packages/live_core/lib/src/sites/douyu/douyu_api.dart` 的 `roomDetail`）里的 `room_gift` 没读。
- 只读 `betard` 也不够：它的表是房间模板里的老礼物（样本 13 个，火箭编号 196），**样本里实际收到的礼物一个都不在里面**：`S13-live` 125 条全是背包道具（119 条粉丝荧光棒 824、稳 520、陪伴印章和钻粉月饼 `gfid` 0），`S15-gifts` 有国庆快乐 24644、精英宝典 22171、精英令 23643。现在的礼物编号是礼物列表里的（火箭 20004），背包道具在平台的道具表里。

## 数据从哪来（第 2 阶段的核实结果）

2026-10-09 用 curl 匿名、不带 Cookie 各取一次（直连）：

| 来源 | 地址 | 内容 | 什么时候取、存多久 |
|---|---|---|---|
| `betard` 的 `room_gift.gift` | `www.douyu.com/betard/<rid>`（进房本来就请求） | 房间模板的付费礼物，12～13 个；`price`（`unit` 2 是鱼翅，单位分；`unit` 1 是鱼丸）、`pc_icon` 相对路径、`gift_effect` | 随房间详情，不多发请求 |
| 房间礼物列表 | `gift.douyucdn.cn/api/gift/v3/web/list?rid=<rid>` | 这个房间礼物栏的全部礼物，154 个（445 KB）；`priceInfo.price`（`priceType` `YUCHI` 是分，`YUWAN` 是鱼丸）、`picUrlPrefix` + `basicInfo.giftPic` | 弹幕连接开始时后台取；每个房间 30 分钟，最多 16 个房间 |
| 平台道具表 | `webconf.douyucdn.cn/resource/common/prop_gift_list/prop_gift_config.json`（JSONP） | 背包道具 1585 个（1.4 MB，gzip 约 200 KB），按 `gfid` 编号（824 粉丝荧光棒、520 稳）；`name`、`bimg`、`pc_full_icon`、`himg` | 同上；全平台一份，6 小时 |

- 三张表的编号互不重复（核对过：列表 154 个和道具 1585 个没有一个重合；`betard` 的老编号 196 等也不在列表里）。合并顺序 `betard` → 列表 → 道具，同一个编号后面的为准。
- 仍然没有的：精英宝典、精英令（活动礼物，2026-10-09 已不在这个房间的列表里），`gfid` 0 的背包道具（陪伴印章 `pid` 3410、钻粉月饼 `pid` 4096：道具表按 `gfid` 编号，没有按 `pid` 的）。它们照旧只显示名称；背包来的照样算免费。
- 没找到按 `pid` 查背包道具的公开接口；以后录到再补（不影响价值，背包道具都是免费的）。

## 设计选择（D-003，维护者授权由执行者定）

1. **三处合并，后两处后台取**：只用 `betard` 的话样本里一个礼物都对不上，所以加了列表和道具表；它们由 `DouyuDanmakuArgs.moreGifts` 在弹幕连接开始时取（不放进 `getRoomDetail`：刷新、录制、多画面都调它，不该多等两个请求）。取到之前进来的礼物按 `betard` 的表（多半只有名称），取到之后的有价值和图。同一份参数重连不再取。
2. **缓存在 `DouyuSite` 的内存里**：照它签名描述符（`_descriptorFor`）的做法——同时要的人共用一个请求、过期再取、失败的忘掉；`live_net` 没有响应缓存，`live_store` 是持久数据（关注、设置），1.4 MB、平台随时会改的目录不进数据库。失败算空目录，5 分钟内不再试，免得每次重连都打两次。
3. **在另一个 isolate 里解析**（`Isolate.run`）：道具表 1.4 MB 的 JSON 不在界面线程解（规范的每帧 3 毫秒）。
4. **单位**：鱼翅的价格就是分（火箭 50000 = 500 元，和 E05.5 的 `fen` 一致）；鱼丸礼物（`betard` `unit` 1、列表 `YUWAN`：100 鱼丸、超大丸星）算免费、不填价值——鱼丸是平台送的、不能折成钱。
5. **背包道具算免费**（任务书）：`gpf` 1 或 `gfid` 0 带 `pid` 的都是。道具表里的 `pc`（粉丝荧光棒 10）不当价值用；免费的不填 `unitPrice`、`totalValue`，所以礼物行不显示价值、不加档位条，D07.1 超过每秒上限时先丢它们。
6. **表里没有的礼物**：按 README 的建议 `normal`、不标免费（精英宝典这类活动礼物多半是付费的，但不知道多少钱）。
7. **只按 `gfid` 查目录**，`gfid` 0 时不拿 `pid` 去查（编号空间不同，会查错）。
8. **图标**：`betard` 用 `pc_icon`（静态 png），列表用 `giftPic`，道具表依次用 `bimg`、`pc_full_icon`、动图 `himg`；`gfs-test-op` 上的地址一律不用（核实 404，道具表里有几个占位图在那里）。
9. **等级和粉丝牌只填礼物**：任务书不许改斗鱼聊天的解析，`chatmsg` 照旧不填（3.x 也不填）。现在礼物行（A08.11）不画粉丝牌，所以界面上看不出区别；长按礼物行的面板会显示等级。以后聊天也要等级、粉丝牌时另开 D01 的任务。
10. **不带 Cookie、不带设备号**：两个新接口匿名就能取，请求头只有 UA 和 Referer。

## 改了哪些文件

- `packages/live_core/lib/src/sites/douyu/douyu_api.dart`：`DouyuDanmakuArgs` 加 `gifts`、`moreGifts`；新类 `DouyuGiftInfo`、`DouyuGiftCatalog`；`roomGifts`、`giftList`、`propGifts`；`roomDetail` 多返回 `gifts`；常量 `giftPictureBase`、`giftListUrl`、`propGiftUrl`
- `packages/live_core/lib/src/sites/douyu/douyu_site.dart`：`moreGifts(rid)` 和缓存（`giftListLifetime` 30 分钟、`propTableLifetime` 6 小时、`giftRetryAfter` 5 分钟、`giftListRooms` 16）
- `packages/live_danmaku/lib/src/sites/douyu.dart`：`DouyuGift` 加价值、图标、免费和 `backpack`；`decode`/`read`/`gift` 带目录；连接拿参数里的目录，后台补上 `moreGifts` 的（`DouyuDanmakuConnection.gifts`）
- 样本：`fixtures/douyu/S17-gift-list/`（10 个礼物，删减记在 `meta.json` 的 `trimmed`）、`fixtures/douyu/S18-prop-config/`（4 个道具）；原始回答的 SHA-256 和长度在 `meta.json`。回答里没有个人信息（礼物目录，没有用户字段；响应头没有客户端地址），`fixture privacy` 通过。
- 测试：`packages/live_core/test/sites/douyu_api_test.dart`、`douyu_site_test.dart`；`packages/live_danmaku/test/douyu_test.dart`；`apps/pure_live/test/features/live_play/douyu_gift_catalog_test.dart`（新）

## 新设置、翻译键、门禁基线

- 都没有。

## 测试

- `live_core`：新增 9 个——`betard` 的 13 个礼物（火箭 50000 分、完整图标地址、特效 143、鱼丸免费）、`roomGifts` 读不了的条目、礼物列表（火箭 20004、国庆快乐 10 分、100 鱼丸免费）、列表出错的类型、道具表（JSONP、粉丝荧光棒的图、测试域名的不用、出错的类型）、合并；`DouyuSite`：参数带 `betard` 的 12 个、两个同时要只发一次请求、不带 Cookie、过期各自重取、失败算空且 5 分钟后再试、空房号只取道具表、最多 16 个房间。
- `live_danmaku`：新增 9 个、改 2 个——付费礼物（火箭 precious、小心心 10 个 1 元 normal、飞机 precious、赞 ×100 valuable）、`betard` 的老编号、鱼丸免费、`S15-gifts` 全部 57 条带目录（国庆快乐 90 分、粉丝荧光棒免费有图、精英宝典只有名称、陪伴印章 `pid` 3410 免费）、带不带目录连击键和数字一样、`gfn` 空用目录名、没有目录时和以前一样；连接：先用 `betard` 的、`moreGifts` 到了之后的礼物有价、只取一次；取失败照常连着。改的两个：`S13-live` 第一条礼物多了等级和粉丝牌（39、集团军 22），125 条都是背包、免费；`S15-gifts` 的陪伴印章编号 3410。
- 应用：新增 6 个（`douyu_gift_catalog_test.dart`，真实解析器 + 样本目录 + A08.11 礼物行）：火箭有图、“500 元”、precious 条；赞 ×100“10 元”valuable、小心心 ×3“0.3 元”；国庆快乐 ×9“0.9 元”有图、粉丝荧光棒有图没价值、100 鱼丸没价值；精英宝典和没有目录时照旧；D07.1 合并：`S13-live` 带目录和不带目录一样 26 行、0 条丢弃；火箭连击 3 下一行“1500 元”。原来的 `gift_line_test.dart`、`gift_combiner_test.dart`、`chat_benchmark_test.dart` 没改、照过。
- 门禁结果见文末。

## 真机上要看的

- 见 [verify.md](verify.md)：斗鱼热门直播间，付费礼物有图、有“N 元”、贵的有档位条；粉丝荧光棒有图、没有价值；连击照旧一行涨数、价值跟着涨；再进同一个房间一开始就有图；长按礼物行有送礼人的等级。取不到目录时照旧只有名称，由自动测试守着。

## 偏差

- 两个阶段一次提交：第 1 阶段（`betard`）单独做完时样本里没有一个礼物能对上，测不出“有价有图”，所以和第 2 阶段一起做、一起提交。
- 任务书写的分支名是 `ai/D07.3`，这次在本机工作区的分支上做（AGENTS.md 允许）。

## 提交和门禁

- `5b0352d25` [D07.3] Price and picture Douyu gifts from the room's gift catalogue
- 文档提交：本记录、verify.md、README、登记表和生成的文档。
- `bash tools/gate/gate.sh --all` 在文档提交 `9e37d3e18` 上通过（`gate: passed (all, 14 members)`，日志 `scratchpad/d073-1791512427/gate.log`）。合并后要再运行一次 `python3 tools/docs/docs.py`（登记表和生成的文档）。
