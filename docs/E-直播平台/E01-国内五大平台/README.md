# E01 国内五大平台

哔哩哔哩、斗鱼、虎牙、抖音、快手五个平台的适配器：推荐、分类和分区、搜索、房间详情、清晰度和线路、开播状态、醒目留言（哔哩哔哩、虎牙）、登录用的接口、链接。用户每天在用的就是这五个，排在 E 组最前面；它们的定期巡检和修复也在这里（E01.6）。

## 范围

- 包括：
  - `packages/live_core/lib/src/sites/{bilibili,douyu,huya,douyin,kuaishou}/` 的全部代码（解析 `*_api.dart`、请求编排 `*_site.dart`、抖音签名 `douyin_sign.dart`），和它们在 `apps/pure_live/lib/app/platforms.dart:141-150` 的构造参数。
  - 每个平台的链接规则（`LiveSiteLinks` 的方法写在 `*_site.dart` 里，公共部分在 E04）。
  - 登录相关的平台接口：哔哩哔哩扫码三个接口（`bilibili_site.dart:545-582`）、斗鱼续期（`douyu_site.dart:472-506`）、抖音账号（`douyin_site.dart:743`）；Cookie 只读，存储在 J、K 组。
  - 样本 `fixtures/<平台>/` 和测试 `packages/live_core/test/sites/<平台>_*_test.dart`。
  - 五个平台的真实接口巡检和修复（E01.6）。
- 不包括（归哪里）：
  - 弹幕协议、连接和弹幕凭据的使用（`packages/live_danmaku/lib/src/sites/<平台>.dart`）→ [D01](../../D-弹幕/D01-平台弹幕协议/README.md)（D01.2～D01.6，另一位在写）；E01 只给弹幕要的参数（哔哩哔哩的 `getDanmuInfo` 凭据、抖音的 `DouyinDanmakuArgs` 和签名、快手的 feed 参数、虎牙的 `topSid`）。
  - 模型、平台接口、注册表 → [E05](../E05-平台框架和模型/README.md)；链接解析的公共部分 → [E04](../E04-链接解析和分享口令/README.md)；巡检工具 → [E07](../E07-平台巡检/README.md)。
  - 账号页和登录界面（扫码、网页登录、Cookie 页）→ K 组和 A 组；播放（H.265 改写、租期续签、换线）→ G 组；录制 → H 组；App 跳转（快手 `liveStreamId`）→ C03.1。

## 现状：做到哪、怎么工作的

- 用户看得到的（2026-10-07）：五个平台的播放和弹幕在 K90 上看过（2026-10-01 两轮真机，[FEATURES.md](../../inventory/FEATURES.md) 第 14 节）：

| 平台 | 播放 | 搜索 | 分区 | 登录 | 特有的 |
|---|---|---|---|---|---|
| 哔哩哔哩 | 完成，K90 看过 | 直播和未开播、主播 | 12 类、462 个分区 | 扫码、网页、Cookie | 轮播单独成状态（游客播放的平台层已做，界面 E06.2）；游客请求蓝光实际给超清，画质按钮显示实际档 |
| 斗鱼 | 完成，K90 看过 | 直播和未开播、主播 | 完成 | Cookie、续期 | 靓号、字母别名不分大小写；签名 `getH5PlayV1` |
| 虎牙 | 完成，K90 看过 | 只搜直播中、主播 | 完成 | Cookie | 字母别名；回放房间（3-1）；播放 UA 读镜像上的配置 |
| 抖音 | 完成，K90 看过 | 只搜直播中 | 完成，新增游戏分区（C-12） | Cookie | 关注身份是 `web_rid`（3.x 的 room_id 启动时迁移）；竖屏比例预判（G04.1） |
| 快手 | 完成，K90 看过 | 直播和未开播、主播 | 完成 | Cookie | 游客会话；房间页没有标题，进房用卡片的（A-3）；App 跳转 |

- 内部怎么工作（每个平台都一样分两层）：
  - `*_api.dart` 是纯函数：输入是回答的文字和状态码，输出 `LiveRoom`、`LiveCategory`、`LivePlayQuality`、`LivePlayLine` 或抛 `SiteError`，测试直接喂样本；
  - `*_site.dart` 管请求：会话（Cookie 一变就重建）、签名、重试、并发时只取一次密钥（哔哩哔哩 buvid 和 WBI、斗鱼描述符、虎牙匿名 uid、抖音 `ttwid`、快手游客会话）；
  - 应用建一次、一直复用（`SiteRegistry`）；直播间按 E05 的流程调用（详情 → 画质探测 → `resolvePlayUrls` → 线路带请求头和租期 → 播放会话在租期前续签）。
- 完成度（和 3.x 对照）：
  - 一致的：3.x 能用的功能都在，行为以 3.x 的冻结输出（`fixtures/<平台>/*/expected.json`）为准，差异逐条写在各平台 record.md 的“与 v3 的有意差异”。
  - 确认过的改动：UPGRADES 1-1～5-x 和附录 C 里这五个平台的条目（2026-09-29 升级落地、2026-10-01 国内平台完善），以及 3.x 问题的修复（哔哩哔哩搜索封面地址拼错、搜不到未开播主播；抖音综合搜索永远失败；快手简介当标题等）。
  - 还缺：定期巡检（E01.6，未开始）；几处受阻的附录 C 条目（见“已知问题”）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `sites/bilibili/bilibili_api.dart`（926 行）、`bilibili_site.dart`（660） | 游客身份和 WBI（`:92-184`）、分类和分区（`:233-266`）、推荐（`:291`）、搜索（`:328`、`:337`）、详情（`:377`）、开播状态和醒目留言（`:400`、`:406`）、画质和取流含轮播（`:415-468`）、弹幕凭据（`:498`）、扫码（`:545-582`）、链接（`:600-625`）；任务 [E01.1](E01.1-哔哩哔哩/README.md) |
| `sites/douyu/douyu_api.dart`（883）、`douyu_site.dart`（568） | 分类、分区、推荐、搜索（`:136-182`）、详情和靓号、别名（`:202-257`）、画质和取流签名（`:275-413`）、续期（`:472-506`）、链接（`:527-555`）；[E01.2](E01.2-斗鱼/README.md) |
| `sites/huya/huya_api.dart`（1307）、`huya_site.dart`（853） | 分类和列表（`:190-214`）、搜索和 UA（`:237-268`）、`profileRoom` 详情（`:286-361`）、醒目留言（`:366`）、播放 UA（`:402`）、画质和取流（`:412-602`）、签名和 WUP 令牌（`:645-750`）、匿名 uid（`:774-784`）、链接（`:813-829`）；`packages/live_core/lib/src/tars.dart`（TARS/WUP）；[E01.3](E01.3-虎牙/README.md) |
| `sites/douyin/douyin_api.dart`（1265）、`douyin_site.dart`（867）、`douyin_sign.dart`（437） | `ttwid`（`:171`）、分类和分区（`:211-283`，滑块后退到 amemv）、推荐（`:326`）、搜索（`:376-468`）、详情三条路 enter / 房间页 / reflow（`:502-560`）、弹幕参数（`:604`）、开播时间（`:624-638`）、取流（`:686-717`）、账号（`:743`）、链接（`:761-804`）；签名纯 Dart；[E01.4](E01.4-抖音/README.md) |
| `sites/kuaishou/kuaishou_api.dart`（862）、`kuaishou_site.dart`（453） | 游客会话和上报（`:24`、`:105-123`）、分类和分区（`:210-247`）、推荐（`:291`）、搜索（`:305-321`）、详情（`:328-365`）、取流（`:373-395`）、链接（`:433`）；[E01.5](E01.5-快手/README.md) |
| `apps/pure_live/lib/app/platforms.dart` | 构造参数（`:141-150`）、弹幕表（`:202-211`）、抖音旧关注的身份迁移（`:265-277`） |

测试和样本：

| 平台 | `*_api_test.dart` / `*_site_test.dart`（`test(` 写法） | 接口样本 `fixtures/<平台>/S*` |
|---|---|---|
| 哔哩哔哩 | 32 / 30 | 34 组 |
| 斗鱼 | 45 / 35 | 33 组 |
| 虎牙 | 66 / 35 | 25 组 |
| 抖音 | 46 / 56 | 22 组 |
| 快手 | 42 / 36 | 24 组 |

（弹幕的样本在 `fixtures/<平台>/danmaku/`、测试在 `packages/live_danmaku/test/`，归 D01。）

## 3.x 基线

- `git show v3.2.11:lib/core/site/<平台>/`：哔哩哔哩 `bilibili_site.dart`（884 行）；斗鱼 `douyu_site.dart`（691）、`douyu_utils.dart`（657）；虎牙 `huya_site.dart`（1377）、`huya_request_params.dart`、`huya_transport_policy.dart`、`huya_utils.dart`；抖音 `douyin_site.dart`（904）、`douyin_search.dart`（599）、`douyin_audience.dart`（58），签名 `lib/core/utils/douyin/abogus.dart`、`lib/core/danmaku/xbogus.dart`；快手 `kuaishou_site.dart`（598）。
- 链接规则在 `lib/common/utils/live_url_tool.dart`（E04）。
- 必须保留：清晰度名称和 id（录制任务、偏好按它们选）；房间身份（关注、观看记录）；3.x 的设置键名（`preferH264` 等，D-018）；分区 id（关注的分区）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 没有定期巡检，平台改接口后要等用户反馈 | — | 上一轮一次就发现 3 处失效 | [E01.6](E01.6-国内五大平台巡检和修复/README.md)（第一档，用 E07.1 的工具） |
| 哔哩哔哩轮播在直播间里不能播（平台层已有） | `apps/pure_live/lib/features/live_play/logic/room_controller.dart:387-392` | 轮播房间只能看“轮播”两个字 | E06.2 第 1 阶段 |
| 哔哩哔哩禁言通知（C-3）、斗鱼进房补醒目留言（C-5）、虎牙贵族通知（C-11）受阻：没录到样本或找不到接口 | 弹幕层 | 少几种通知 | UPGRADES 写“未排”，录到样本后归 D01.2、D01.3、D01.4 |
| 快手登录后的直播搜索（C-17） | `kuaishou_site.dart:305` | 游客搜不到直播 | 未排：要用户的登录 Cookie（V03.3“需要维护者决定”） |
| 付费、私密房间没有真实样本（斗鱼、虎牙、抖音、快手），按网页代码或接口含义实现 | 各 `*_api.dart` 的受限类型 | 受限类型可能不准 | 巡检时遇到就录样本（E01.6） |
| 虎牙别名房间号是否不分大小写没实测 | `packages/live_core/lib/src/sites.dart:223` | 大小写不同时可能出现两个关注 | E01.6 巡检时试 |
| 虎牙播放 UA 依赖 GitHub 镜像上的 `assets/play_config.json` | `huya_site.dart:394-402` | 镜像都不通时用内置 UA | 没有任务管 |
| 记录里写的斗鱼设置键 `douyuForceRenewal` 和代码不一致，实际是 `douyuForceRenew` | `packages/live_store/lib/src/settings/settings.dart:117`；`douyu_site.dart:73` 的注释 | 按注释找设置会找不到 | 写进本组报告（注释是代码，Z 组顺手改） |

## 相关决定和规范

- D-001（照 3.x 逐个重构）、D-013（哔哩哔哩打码昵称不还原，弹幕层）、D-017（样本测试，不访问真实平台）、D-018（设置键名不变）。
- [specs/UPGRADES.md](../../specs/UPGRADES.md)：第 1～5 节（五个平台各自的条目）、附录 C（C-1～C-17）、统一原则（受限类型、默认编码）。

## 测试和验证

- 自动测试：`cd packages/live_core && dart test test/sites/bilibili_api_test.dart test/sites/bilibili_site_test.dart …`（五个平台十个文件，共约 400 个 `test(` 写法）；样本逐键对照 3.x 冻结输出，有意差异用 `changed:` 列出。
- 真实接口：各平台 record.md 的“真实环境检查”（2026-09-30～10-01）；以后按 E01.6 每轮记录。
- 真机：[S02 的 CHECKLIST.md](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 1 条（五个平台各进一个直播间）、第 2 节第 1 条（弹幕）、第 4 节第 2、4、6～8 条（搜索、分区、哔哩哔哩登录和原画）。

## 路线

1. [E01.6](E01.6-国内五大平台巡检和修复/README.md)（第一档，持续）：先等或配合 [E07.1](../E07-平台巡检/E07.1-平台巡检工具/README.md) 的工具，跑第一轮、修失效，之后每两周一轮。
2. 哔哩哔哩轮播在直播间里能播：[E06.2](../E06-平台层升级/E06.2-平台层新数据接到界面/README.md) 第 1 阶段。
3. 以后：C-3、C-5、C-11 录到样本后在 D01 做；C-17 维护者决定后再开任务；新想法写进 V01 提议，不直接加任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [E 直播平台](../README.md)。

- 代码：`packages/live_core/lib/src/sites/`
- 进度：`█████████████████░░░` 83%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| E01.1 | 哔哩哔哩 | 平台 | 完成 | 2026-09-28 | d5ed42a5d | [设计或说明](E01.1-哔哩哔哩/README.md)、[记录](E01.1-哔哩哔哩/record.md) |
| E01.2 | 斗鱼 | 平台 | 完成 | 2026-09-28 | dc09e6d8e | [设计或说明](E01.2-斗鱼/README.md)、[记录](E01.2-斗鱼/record.md) |
| E01.3 | 虎牙 | 平台 | 完成 | 2026-09-28 | c1a82891f | [设计或说明](E01.3-虎牙/README.md)、[记录](E01.3-虎牙/record.md) |
| E01.4 | 抖音 | 平台 | 完成 | 2026-09-28 | 6b4a3d35b | [设计或说明](E01.4-抖音/README.md)、[记录](E01.4-抖音/record.md) |
| E01.5 | 快手 | 平台 | 完成 | 2026-09-28 | 944c67f40 | [设计或说明](E01.5-快手/README.md)、[记录](E01.5-快手/record.md) |
| E01.6 | 国内五大平台巡检和修复（持续） | 平台 | 未开始 | — | — | [设计或说明](E01.6-国内五大平台巡检和修复/README.md)、[任务书](E01.6-国内五大平台巡检和修复/brief.md) |

## 还没完成的

- **E01.6 国内五大平台巡检和修复（持续）**（未开始，第一档，规模 中）
  - 阶段：写巡检清单 → 逐个平台跑一遍 → 修复失效的

<!-- docs:生成结束 -->
