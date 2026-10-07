# E02.12 六间房

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 31-1～31-6）记在 [record.md](record.md)；聊天由 D01.28 接上
- 旧编号：M4.31、M4.U.31、T02b.12
- 相关：模型 [E05.1](../../E05-平台框架和模型/README.md)、[E05.2](../../E05-平台框架和模型/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/README.md)；聊天 D01.28（用 `SixRoomDanmakuArgs`）；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/sixroom/`（`sixroom_api.dart` 1058 行解析和链接，`sixroom_site.dart` 497 行请求编排）；样本 `fixtures/sixroom/`（28 组）

## 目标

把 3.x 的六间房适配器（`lib/core/site/sixroom/` 三个文件共 910 行）重构进 `live_core`。3.x 最严重的问题是“没在本次运行里列过的房间一律打不开”：房间页正则要求 `roomid: '<n>'` 带引号，页面改了以后解析失败，关注刷新、从关注进房、录制、粘贴链接、按房间号搜索全都报错，只有先看过目录或搜索的房间能借 `_known` 缓存打开。共修掉 15 个问题；升级落地后列表改用移动端接口（不再每次下载 1.1 MB 的首页）、头像和标题取对字段、搜索标出直播中。

## 平台接口要点

| 功能 | 接口（匿名，Chrome 140 UA、`Accept-Language: zh-CN`、`Referer`） | 位置 |
|---|---|---|
| 分类 | 一个分类“六间房直播”，六个分区：全部、歌区、舞区、脱口秀、星颜、派对；不发请求 | `sixroom_site.dart:294` |
| 推荐、分区 | 推荐和歌区、舞区、脱口秀、派对：移动端 `coop-mobile-getlivelistnew.php`（`special`、`u0`、`u1`、`u2`、`u8`），每页一个请求，跨页去重；“全部”：首页 `v.6.cn/` 的 `window.__SMARTY_ALL_VARIABLES__.typeList`；星颜：网页 `/subareaIndex/getSubareaIndexNew.php?subarea=10`；这两个一次读全、本地分页，第 1 页重新读、之后 90 秒内共用 | `:301-318` |
| 搜索 | 房间号或链接查房间（不取流）；其他关键词 `search.php?type=use&key=`，超过 15 个字（6.cn 的上限）给空结果；按 `<i class="live">` 标直播中 | `:326-337` |
| 详情 | 先读房间页取用户 id（冷启动时），再 POST 移动端 `coop-mobile-inroom.php`（表单 `av=3.1&…&rid=&ruid=`，回答约 19 万字节）；`flag` 必须是 `001`；私密房（`isPriveRoom`）`private`、黑屏（`blackScreenInfo.msg`）`unplayable`；记住最多 2000 个列过的房间补缺的字段（同一场才补热度、开播时间） | `:407-422` |
| 取流 | 一档 `flv:source`（“FLV 原始线路 · 1024x768 · 2652 kbps”），地址 `https://wlive.6rooms.com/httpflv/v<用户 id>-<场次>[-many].flv`，流名必须对得上主播和场次；请求头为空（3.x 播放层没有六间房分支，实测不需要）；不发请求 | `:460-481`；`sixroom_api.dart:30` |
| 链接 | 纯房间号（2～12 位）和 `v.6.cn`、`m.6.cn` 的 `/<房间号>`、`/profile/<房间号>` | `:496` |

## 3.x 和现状

| 方面 | 3.x（`lib/core/site/sixroom/`） | 现在 | 说明 |
|---|---|---|---|
| 没列过的房间 | `sixroom_api.dart:280-283`、`:383-387` 房间页正则失败，报 `schema` | 先读房间页取用户 id 再 inroom，能打开 | 3.x 问题 1 |
| 头像 | `:447` 读空的 `headPicUrl` 和不存在的 `picuser`，界面显示封面 | inroom 的 `roominfo.uoption.picuser` 等 | 31-1 |
| 详情标题 | `:424` 读不存在的 `roominfo.userMood`，总是昵称，刷新盖掉卡片的签名 | 直播标题，再主播签名 `roomParamInfo.operation.userMood` | 31-2 |
| 搜索 | `:269`、`:338-341` 超过 15 个字报“无权访问”；`:364` 状态总是“未知” | 给空结果；标直播中 | 3.x 问题 4；31-3 |
| 列表 | `:238-262` 每次刷新下载约 1.1 MB 首页，本地筛选 | 移动端列表按分区分页（“全部”、星颜仍读全） | 31-4 |
| 补全 | `:87` 已下播的房间仍显示最近一张卡片的热度 | 同一场才补 | 31-5 |
| 受限 | 显示“未知” | 私密房、黑屏的房间有场次号就是直播中，标 `private`、`unplayable` | 统一原则 |
| 占位 | 昵称空时 `Six Rooms` | 留空 | 统一原则 |
| 网页解析 | `package:html` | `HtmlElement`（`html.dart`） | 不加依赖，结果逐字段相同 |
| 聊天 | 没有，公告写“远端聊天尚待接入” | `live_danmaku/lib/src/sites/sixroom.dart`（D01.28） | 31-6 |

## 结果

- 首次重构（2026-09-28，提交 `98c644829`）：15 个 3.x 问题、12 条有意差异见 record.md；补录了 3.x 自己的请求（首页、在播房间 8838 的房间页和 inroom 等，同一分钟）。
- 升级落地（2026-09-29，`8e55bea2c`）：31-1～31-5 完成，31-6 交给 D01.28；31-4 里“详情改读房间页”受阻（房间页没有关注数和私密房标记，签名字段也不同，所以详情仍读 inroom）；开播时间取 `realstarttime` 和 inroom 的 `liveinfo`；两个公告改通俗。
- 测试：`packages/live_core/test/sites/sixroom_api_test.dart` 24 个 `test(` 写法、`sixroom_site_test.dart` 30 个（多数按样本循环生成）；聊天 `packages/live_danmaku/test/sites/sixroom_test.dart`。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出；没列过的房间能打开、头像和签名、搜索直播中标记、超长关键词、移动端列表的跨页去重、“全部”和星颜的 90 秒快照。
- 真实接口：2026-09-28 20:48～21:03 UTC（北京时间凌晨）逐个试了移动端列表的类型、首页脚本里的分区接口；同一时刻首页 109 个在播房间、移动端合起来 81 个。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节）。

## 留下的问题

- 私密房、黑屏没有真实样本；私密房在播时 inroom 给不给场次号和流名不知道。
- 移动端列表只在凌晨录过，晚高峰的数量没核实。
- inroom 的 `roomlist.content.num` 看起来是热度，可以让没看过卡片的直播间也显示热度（表外发现，没做）。
- 详情每次下载约 19 万字节的 inroom（含观众列表和聊天记录），房间页更小但缺字段（受阻）。
