# E01.6 国内五大平台巡检和修复（持续）：任务书

> 任务书模板 v2。读完这一页和“先读”列的文件就能开工；这是持续任务，每轮照本任务书做一遍，结果追加到 `record.md`。

## 背景

- 来源：docs v0 登记的持续任务（旧编号 T02a.6）。哔哩哔哩、斗鱼、虎牙、抖音、快手是用户每天用的平台（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节，K90 看过），平台改接口、加风控后用户会直接看到“打不开”“搜不到”。
- 现象：上一次人工巡检（2026-09-30～10-01，“国内平台完善”）当场发现三处已经失效的功能：
  - 哔哩哔哩分区页对游客每一页都报风控（3.x 用的 `second/getList` 现在一律回 -352），已换成不签名的 `room/v1/area/getRoomList`（`packages/live_core/lib/src/sites/bilibili/bilibili_site.dart:247-266`）；
  - 虎牙搜索房间、搜索主播全部 `HTTP 403 Not allowed`（不带 User-Agent 被拒），已在 `huya_site.dart:237-268` 带上移动端 UA，`packages/live_net/lib/src/io_http.dart:29-34` 也保留 dart:io 默认 UA；
  - 抖音游戏直播间详情没有分区，已在 `douyin_api.dart` 的 `_detailArea` 修。
  
  这说明一两周不看就可能有功能悄悄坏掉。
- 为什么现在做：第一档。距上次巡检已经两天以上，4.0.0 已发布，用户会直接受影响。
- 已经做过的：五个平台各自的 record.md 里都有“真实环境检查”表（E01.1～E01.5），是本任务清单的起点；那次用的临时程序没进仓库。巡检工具在 [E07.1](../../E07-平台巡检/E07.1-平台巡检工具/README.md)（未开始）。

## 目标和验收

1. 本文件夹有 `CHECKLIST.md`：五个平台 × 下面“清单要覆盖的功能”每一项一行，写明用哪个房间（或怎么从推荐里挑）、请求哪个接口、怎么算正常；E07.1 已定检查项格式时照它的格式。
2. 本文件夹的 `record.md` 有这一轮的结果：每个平台一张表（功能 | 结果 | 说明），格式同 [E01.1 的 record.md](../E01.1-哔哩哔哩/record.md)“真实环境检查”；写明日期时间（UTC）、直连还是代理、匿名、联网总时长。
3. 每个失效项都有：根因（文件:行）、脱敏后的新样本（`fixtures/<平台>/S<nn>-<情况>/`）、改之前会失败的测试、修复提交；修复后重跑这一项，结果写进同一张表。
4. 没修的失效项（例如平台要登录、要签名而拿不到）写明原因，开到对应任务（弹幕到 D01.x，界面到 A/C/I 组），并在登记表的 `note` 里写一句。
5. 门禁通过；修复合并后维护者在 K90 上进对应平台的一个直播间确认能播。

## 现状（读代码得出，写文件:行）

- 适配器在 `packages/live_core/lib/src/sites/{bilibili,douyu,huya,douyin,kuaishou}/`，由 `apps/pure_live/lib/app/platforms.dart:135-152` 建（哔哩哔哩带 `storedUid`，斗鱼带 `StoreDouyuLogin` 和 `forceRenewal`，虎牙、快手带 `preferH264`）。巡检时自己 new，不经过应用：`BilibiliSite(IoLiveHttp())` 这样，Cookie 用 `MemoryCookieVault`（空）。
- 公共调用：`LiveSite` 的 `getRecommendRooms`、`getCategories`、`getCategoryRooms`、`searchRooms`、`searchAnchors`、`getRoomDetail`、`getPlayQualities`，取流用扩展 `resolvePlayUrls`（`packages/live_core/lib/src/live_site.dart:418-430`），线路是 `LivePlayLine`（地址、请求头、格式、租期，`play_line.dart:41`）。
- 弹幕连接在 `packages/live_danmaku/lib/src/sites/<平台>.dart`，登记表 `apps/pure_live/lib/app/platforms.dart:196` 的 `buildDanmakuRegistry`。
- 各平台最容易坏的地方（上次检查和记录里的线索）：

| 平台 | 位置 | 风险 |
|---|---|---|
| 哔哩哔哩 | `bilibili_site.dart:92-184`（buvid、WBI 密钥、`w_webid`、签名和 -352 续签）；`:434-468`（`getRoomPlayInfo`，游客请求 400 实际给 250）；`:498`（弹幕凭据最多 4 次） | 风控码 -352、-412；WBI 算法变；游客画质降级 |
| 斗鱼 | `douyu_site.dart:200-257`（`betard`、靓号读房间页 `window.room_id`、别名 302）；`:363-431`（`getEncryption` 描述符 + `getH5PlayV1` 签名）；`:499-506`（续期） | 签名算法、描述符格式；`betard` 对靓号的回答 |
| 虎牙 | `huya_site.dart:286-300`（`profileRoom`）；`:759`（WUP `getCdnTokenInfoEx`）；`:789`（`anonymousLogin`）；`:237-268`（搜索的 UA） | AntiCode 参数、WUP 结构、搜索拦截 |
| 抖音 | `douyin_site.dart:45`（首页取 `ttwid`）；`douyin_sign.dart`（msToken、a_bogus）；`:531`（`enter`）、`:563`（reflow）；`:222-283`（分区签名和滑块后转 amemv） | 签名被拒、滑块、RSC 页面结构 |
| 快手 | `kuaishou_site.dart:24`、`:121`（游客会话和 `misc2` 上报）；`kuaishou_api.dart:220-232`（房间页 JSON 截取、`isLiving`、`errorType`）；`:312`（搜索 `result` 10） | 游客门禁、页面结构、限流 |

## 3.x 基线

- 3.x 没有巡检，靠 issue。3.x 的接口用法在 `lib/core/site/<平台>/`（`git show v3.2.11:lib/core/site/bilibili/bilibili_site.dart` 等），只用来对照接口原来的样子；修复以 4.x 当前代码为准。
- 不能改变用户看得到的行为（清晰度名称和 id、房间身份、关注分组），除非失效本身就是这些；改了要在 record.md 写明并引用决定。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 8 节合并审查、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`；`fixtures/README.md`（样本格式和脱敏规则；注意它写的 `tools/live_cli` 在 master 上没有，来自归档标签 `v4-archive`）。
3. 本文件夹的 `README.md`，以及五个平台的 record.md 里“真实环境检查”“修好的问题”两节：[E01.1](../E01.1-哔哩哔哩/record.md)、[E01.2](../E01.2-斗鱼/record.md)、[E01.3](../E01.3-虎牙/record.md)、[E01.4](../E01.4-抖音/record.md)、[E01.5](../E01.5-快手/record.md)。
4. [E07.1 的任务书](../../E07-平台巡检/E07.1-平台巡检工具/brief.md)：工具做好了就用工具，清单格式跟它一致。

## 范围

- 可以改：`packages/live_core/lib/src/sites/{bilibili,douyu,huya,douyin,kuaishou}/`、对应的 `packages/live_core/test/sites/*_test.dart`、`fixtures/{bilibili,douyu,huya,douyin,kuaishou}/` 下新加的样本；连接凭据（哔哩哔哩 `getDanmuInfo`、抖音签名、快手 feed 参数）失效时可以改 `packages/live_danmaku/lib/src/sites/<平台>.dart` 和它的测试；本文件夹的 `CHECKLIST.md`、`record.md`。
- 不能改：`live_core` 的公共模型和接口（`live_room.dart`、`live_site.dart`、`sites.dart`）——需要改时停下写进报告；其他平台；应用和界面；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义；已有样本的 `expected.json`（3.x 冻结输出）。
- 不把任何 Cookie、账号、设备号、客户端地址写进仓库（样本按 `fixtures/README.md` 脱敏，门禁 `fixture privacy` 必须通过）。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 写巡检清单 | 五个平台各列：推荐第 1、2 页；分类；一个热门分区第 1、2 页；搜索房间和主播（关键词“英雄联盟”“王者荣耀”）；详情：推荐里取 3 个在播房间，加固定的未开播房间、不存在的房间、平台特有的情况（哔哩哔哩短号 6、轮播房间；斗鱼靓号 1 和别名 `lpl`/`LPL`、轮播 93976；虎牙字母别名 `lpl`、回放房间；抖音用本场 room_id 进房、游戏直播间；快手大小写不同的 `kpl704668133`）；每个在播房间的清晰度和每条线路开头 4～64 KB（FLV 头、TS 同步字节 0x47、fMP4 `ftyp`、m3u8 `#EXTM3U`）；租期；两个房间各 120 秒弹幕（就绪时间、聊天条数、人数次数、有没有重连）。每行写判定标准 | `CHECKLIST.md`（新） | 五个平台都有、每行有判定标准；维护者看过 |
| 2 逐个平台跑一遍 | 有 E07.1 工具就用它；没有就在 scratchpad 写临时 Dart 程序（`dart run`，依赖本仓库的 `live_core`、`live_net`、`live_danmaku`），匿名、只读、直连、不发言；`live.kuaishou.com` 请求间隔 2.5 秒；每个平台联网合计不超过 10 分钟 | `record.md`（新，本轮一节） | 五张结果表写完，失效项列出根因线索 |
| 3 修复失效的 | 每个失效项：录样本并脱敏 → 写改之前会失败的测试 → 改适配器 → 跑本平台测试 → 重跑这一项真实接口；一个平台一个提交 | 对应平台的 `sites/<平台>/`、测试、样本 | 失效项都修好或写明原因开到别的任务；门禁通过 |

每个阶段都能单独合并：阶段 1、2 只有文档；阶段 3 每个平台的修复各自合并。

## 测试

- 修 bug：先写改之前会失败的测试，用新录的样本（`Fixture.load('<平台>', 'S<nn>-<情况>')`，`packages/live_core/test/sites/fixture.dart`）；用例名写失效现象，例如 `'area page: getRoomList answers 30 rooms for guests'`。
- 要改的已有测试：如果平台回答变了导致旧样本的期望不再成立，旧样本和它的测试保留（它记录的是当时的回答），新样本单独测。
- 测试里的定时器至少 1 秒；不访问真实平台（D-017）；用到样本时间的把“现在”固定成录制时间。
- 每个修复的平台跑：`cd packages/live_core && dart test test/sites/<平台>_api_test.dart test/sites/<平台>_site_test.dart`；改了弹幕的再跑 `packages/live_danmaku` 对应测试。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 装合并后的测试包，热门 → 每个修过的平台进一个直播间 | 几秒内出画面和声音，标题、人数正确 |
| 2. 修过分区或搜索的平台：分区 → 一个分区往下翻两页；搜索“英雄联盟” | 列表正常，不重复，不报错 |
| 3. 修过弹幕的平台：停留 1 分钟 | 弹幕列表和画面都有弹幕，没有反复重连 |

## 风险和注意

- 真实接口会受时段影响（凌晨在播房间少、聊天少），结果表写明时间；拿不到在播房间的项写“没测到”，不算正常。
- 别连续高频请求：上次快手在 2.5 秒间隔下没被限流；哔哩哔哩游客容易触发 -352，遇到就停，换时间再跑。
- 修复不能改变用户已存的数据：清晰度 id、房间身份（`SiteIds.caseInsensitiveRoomIds`）、关注分组的规则不变。
- 和 [E07.1](../../E07-平台巡检/E07.1-平台巡检工具/brief.md) 同时做时，清单格式以 E07.1 为准；同一平台的适配器同时只给一个执行者改（D01.x 的弹幕任务也会碰 `live_danmaku/lib/src/sites/<平台>.dart`）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/E01.6` 或本机工作区；提交信息以 `[E01.6]` 开头（英文）；不推 master。
- 提交前：改过的包跑 `dart format --output=none --set-exit-if-changed .`、`dart analyze`、`dart test`；`python3 tools/gate/check_fixtures.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（哪个平台跑完、哪些失效项修了）、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每个平台：正常几项、失效几项、修好几项；每个失效的根因（文件:行）；新样本；测试数量；改了哪些文件；要在真机上看的；没修的和去向；下一轮建议的时间。
