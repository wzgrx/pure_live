# T02g.2 模型扩展

- 日期：2026-09-28
- 目标包：`packages/live_core`（`live_room.dart`、`sites.dart`）
- 依据：[升级决定](../../../specs/UPGRADES.md) 的“统一原则”和模块列含 T02g.2 的 28 条；3.x 模型 `legacy/lib/common/models/live_room.dart`

## 做了什么

| 内容 | 接口 |
|---|---|
| 开播时间 | `LiveRoom.startedAt`（UTC `DateTime?`，构造时转成 UTC） |
| 受限类型 | 新枚举 `LiveRestriction`；`LiveRoom.restriction`（可空）、`effectiveRestriction`、`isRestricted`；`LiveRestriction.fromName` |
| 轮播状态 | `LiveStatus.carousel`（下标 5，追加在末尾） |
| 关注分组 | 新枚举 `FollowGroup`（live、replay、offline）；`LiveRoom.followGroup` |
| 房间身份 | `SiteIds.caseInsensitiveRoomIds`、`SiteIds.ignoresRoomIdCase`；`LiveRoom.identityKeyFor`；`identityKey`、`hasSameIdentity`、`hasIdentity`、`==`、`hashCode` 在这些平台上不分大小写 |
| 占位值规则 | 写进 `LiveRoom` 和 `mergeFrom` 的文档注释；`LiveRoom.hasNick`、`LiveRoom.displayNick(平台名)` |

`copyWith`、`mergeFrom`、`fromJson`、`toJson` 都带上了两个新字段。平台适配器的行为没有改（见“适配器的机械更新”）。

## JSON 兼容

| 键 | 写法 | 读法 |
|---|---|---|
| `startedAt` | ISO 8601 UTC 字符串，如 `2026-09-28T12:34:56.789Z` | ISO 字符串（带时区的换成 UTC，不带时区的按 UTC 理解）或毫秒时间戳（数字或纯数字字符串）；其他值、不晚于 1970 年的时间都当作没有 |
| `restriction` | `LiveRestriction` 的名字，如 `paid` | 认识的名字照读；不认识的名字（以后的版本新加的种类）读成 `none`；没有这个键或值为 null 读成 null（未提供） |
| `liveStatus` | 仍按下标写，新增 5 = `carousel` | 0～5 照读；越界时照旧由 `isRecord`、`status` 推出 |

- **只在有值时写新键**：没有开播时间、没有受限信息的房间，`toJson` 的键和 T02g.1 完全相同（3.x 的键加 `link`）。所以现有的平台输出、样本对照都不受影响。
- **旧数据读进来不变**：3.x 的记录没有这两个键，读进来 `startedAt`、`restriction` 都是 null，其余字段和状态的读法没有改。
- **3.x 读 v4 的数据**（备份导回 3.x）：
  - 3.x 只读自己认识的键，`startedAt`、`restriction` 被忽略；
  - 轮播房间写的是 `liveStatus: 5`、`status: false`、`isRecord: false`。3.x 的 `_liveStatusFromJson` 遇到越界的下标退回 `status`，读成“未开播”，不会出错。
- 测试证据：`live_room_upgrades_test.dart` 读取 `fixtures/*/*/expected.json` 里 3.x 解析器输出的全部房间 JSON（6139 个，覆盖 33 个平台），逐个检查：
  - 新字段为 null；
  - `toJson` 的键集合与 T02g.1 相同；
  - `liveStatus`、`status` 与 3.x 写的一致；
  - `followGroup` 与 3.x 关注页的分组规则一致；
  - 再读一遍结果不变。
- 存储层（T09b.1）如果不用 JSON 存房间，也按同样的语义存：`startedAt` 存 UTC 时间，`restriction` 存名字，null 和 `none` 分开存。

## 状态对照

| 下标 | `LiveStatus` | 直播中 `isLiveNow` | 可播放 `isPlayableNow` | 平台明确不在播 `isExplicitlyOfflineNow` | 关注分组 `followGroup` | JSON 的 `status` / `isRecord` | 3.x 读到的状态 |
|---|---|---|---|---|---|---|---|
| 0 | `live` | 是 | 是 | 否 | 直播中 | true / false | 直播 |
| 1 | `offline` | 否 | 否 | 是 | 未开播 | false / false | 未开播 |
| 2 | `replay` | 否 | 是 | 否 | 回放；带 `unplayable` 时归入未开播 | false / true | 回放 |
| 3 | `unknown` | 否 | 否 | 否 | 未开播（3.x 同样放在这里，卡片显示“待定”） | false / false | 未知 |
| 4 | `banned` | 否 | 否 | 是 | 未开播 | false / false | 封禁 |
| 5 | `carousel` | 否 | 否 | 是 | 未开播 | false / false | 未开播 |

- **轮播**：不算可播放，分组归入未开播；录制（T08a.1）按“平台明确不在播”处理，不录轮播内容。
- **回放算可播放的规则不变**。拿不到回放地址的，用受限类型 `unplayable` 表达：`isPlayableNow` 仍为真（进房后由取流报错说明原因），`followGroup` 归入未开播（统一原则“拿不到的标‘不可播放’，关注分组归入未开播”）。
- **受限的直播仍是直播**：`isLiveNow`、`isPlayableNow` 都为真，分组在直播中，只是卡片标出受限类型、播放时说明原因。直播中但本客户端拿不到流的（YouTube 23-5）用 `live` + `unplayable`，同样留在直播中。
- 检查过的地方（`grep -rn "LiveStatus\." packages/`）：
  - `live_core` 里没有按状态分组或排序的代码：分组在 v3 的关注页，现在由 `followGroup` 给出；排序（`compareAudienceRanking`）不看状态；
  - 判断能否播放的是 `isPlayableNow`、`isExplicitlyOfflineNow` 和各适配器的取流检查；
  - 对 `LiveStatus` 做穷尽 `switch` 的只有 YouTube、TikTok 两处，见下一节；
  - 斗鱼、Steam、六间房、17LIVE 等的 `switch` 带默认分支，轮播落进“状态不明”一支，这些平台不会产生轮播。

## 适配器的机械更新

新增枚举值后，两处穷尽 `switch` 编译不过，只做了最小的改动。这两个平台不会产生轮播，行为不变，未开播时的错误文字也不变：

- `youtube_site.dart` 的 `_checkPlayable`：`offline` 分支加上 `carousel`，报 `StreamUnavailable`；
- `tiktok_site.dart` 的 `_playable`：同上。

没有平台测试因为新字段需要修改（新键只在有值时写出）。`live_room_test.dart` 里“枚举顺序就是存储格式”的用例加上了 `carousel`。

## 受限类型

`LiveRestriction` 按名字存，以后可以在任何位置追加新种类。

| 名字 | 含义 | 播放时的错误（T02.U 照此报） | 相关条目 |
|---|---|---|---|
| `none` | 平台说没有限制 | — | — |
| `needsLogin` | 登录后可看 | `NeedsLogin` | 26-9 |
| `paid` | 付费直播、门票 | `StreamUnavailable`（带原因） | 19-5、21-1、21-5、22-1、30-5 |
| `subscribersOnly` | 仅订阅者、会员 | `StreamUnavailable`（带原因） | 22-1 |
| `private` | 私密、仅好友 | `StreamUnavailable`（带原因） | 11-9、12-5、18-4、21-5、22-1 |
| `appOnly` | 仅限平台 App | `StreamUnavailable`（带原因） | 32-4 |
| `regionBlocked` | 地区受限 | `RegionBlocked` | 20-8 |
| `password` | 密码房、加锁 | `StreamUnavailable`（带原因） | 7-8、24-2 |
| `adult` | 成人内容，需要平台的年龄验证 | `NeedsLogin` | 7-5 |
| `unplayable` | 平台说在播或有回放，但不给本客户端播放地址 | `StreamUnavailable` | 3-1、18-5、23-5、30-4、32-2 |

平台用“受限”笼统表示、分不清种类的（如 LOOK 的 -10、小红书的 `joinLimitTypes`），按平台的说明选最接近的一种；实在分不清就用 `unplayable`。

### “未提供”和“没有限制”

- `restriction == null`：这次回答没说。例如只查开播状态的轻量刷新、3.x 或 T02g.2 之前存下的记录。
- `restriction == LiveRestriction.none`：平台回答里能看出受限情况，而且没有限制。
- 界面显示时两者一样（`effectiveRestriction` 都是 `none`，`isRestricted` 都为假）；区别只在合并。
- JSON 里也分开：null 不写键，`none` 写 `"none"`。

### 合并规则

`startedAt` 和 `restriction` 都属于“这一场直播”：

1. 新数据给了值就用新值。受限状态会变，`none` 会清掉存下的限制。
2. 新数据没给时，只要状态没有变，就保留旧值。“没变”指以下任一情况：
   - 新数据没给状态，或状态是 `unknown`；
   - 存下的状态是空或 `unknown`，例如请求失败后的 `pendingAfterError`；
   - 新旧状态相同。
3. 状态变了（直播 → 未开播、回放 → 直播、直播 → 轮播……）而新数据没给值，就变成 null（不知道）。

规则 3 是对“新值为空时保留旧值”的补充：

- 如果不清掉，主播下播后再开播时，只带状态的轻量刷新会把上一场的开播时间显示成这一场的（“已开播 26 小时”）；
- 同样，“回放不可播放”的标记会跟到下一场直播上。

`copyWith` 仍然只能设值、不能清空（T02g.1 问题 4 的约定）。`pendingAfterError`、`fillFromDetail`、`withAudienceFallbackFrom` 保留这两个字段。

## 房间身份

`identityKey` 是 `平台:房间号`。在下表的平台上，房间号先转小写再比较：`==`、`hashCode`、`hasSameIdentity`、`hasIdentity`、`mergeFrom`、`withAudienceFallbackFrom` 都用它。`roomId` 本身保留创建时的写法，请求、链接、显示都用原写法；平台 id 本来就规范成小写。

忽略大小写的平台（`SiteIds.caseInsensitiveRoomIds`），只选“房间号是用户名、平台本身不分大小写”的：

| 平台 | 房间号 | 依据 |
|---|---|---|
| Twitch | 登录名 | 登录名本来就是小写，适配器对任何写法都请求小写形式（T02c.2 差异 13） |
| SOOP | 主播 id（BJ id） | 平台回答的 `BJID` 都是小写，链接里的 id 统一转小写（T02c.1 问题 4） |
| Picarto | 频道名 | 平台查找频道不分大小写，返回自己的写法（`kaiyote`、`KAIYOTE` → `Kaiyote`，T02c.3 样本 S04、升级候选 8） |
| TwitCasting | 频道名（screen id） | 适配器请求时用小写频道名（T02c.4 问题 8） |
| TikTok | 用户名 `uniqueId` | 回答按用户名比对不分大小写，适配器已把房间号转小写（T02c.9） |
| PandaTV | 登录 id | v3 的 `_snapshot` 比对房间数据时不分大小写（T02c.12） |

不忽略的平台：

- **数字房间号**：大小写无关。包括哔哩哔哩、抖音、网易 CC、YY、AcFun、猫耳、映客、克拉克拉、小红书、微博、SHOWROOM（数字 `room_id`）、LiveMe、FC2、Steam、京东、酷狗、百度、六间房、LOOK、17LIVE。
- **YouTube**：视频 id、频道 id 区分大小写。
- **niconico**：节目号 `lv…` 不是用户名。
- **CHZZK**：32 位十六进制频道号，适配器已统一成小写。
- **没有证据表明平台不分大小写的**：虎牙的别名房间号，Bigo 的 id。以后在 T02.U 核实后，可以加进集合。斗鱼的别名已在 T02a.2 实测不分大小写（`lpl`、`LPL`、`Lpl` 都跳到 288016），已加入集合。快手的用户 id 已在 T02a.5 实测不分大小写（`kpl704668133` 打开 `KPL704668133`），已加入集合。Bigo 的 id 已在 T02c.11 实测不分大小写（`chrispcritter78`、`CHRISPCRITTER78` 都打开 `ChrisPCritter78`，`QASHIA305` 打开 `qashia305`），已加入集合。

这些平台上，3.x 存下的关注身份不变（原写法照存）。大小写不同的重复关注在 T09b.1 迁移时按 `identityKey` 合并。

## 占位值规则（X-2）

- **适配器**：拿不到真实的主播名、标题、封面时留空，不填占位文字（如“JD Live”“Steam Broadcast”“Baidu Live”）。
- **合并**：`mergeFrom` 遇到空值保留存下的值，所以留空就不会覆盖关注里的真实名字。占位文字会覆盖，这正是要避免的。
- **界面**：名字为空时显示平台名。`live_core` 里只有适配器的默认名 `LiveSite.name`，界面上的平台名要随界面语言变（T02d.1 问题 5，v3 的 `site_<id>` 文案）。所以模型提供：
  - `hasNick`：名字是否为空；
  - `displayNick(平台名)`：名字为空时返回传入的平台名。

  平台名由 M13 从多语言文案里取。

## 给后续模块的说明

### T02.U（各平台）

- **`startedAt`**：
  - 所有能取到的平台都填 UTC 时间，包括 TwitCasting、niconico、SHOWROOM、LOOK、SOOP（7-9）、AcFun（10-3）、映客 App 热门（14-1）、17LIVE（33-7）；
  - PandaTV 的时间是韩国时间（UTC+9），要先换算（25-12）；
  - 秒级时间戳乘 1000 后再构造 `DateTime`；
  - 未开播时不填，平台的 0 或空值不填。
- **`restriction`**：
  - 平台回答里能判断受限情况时，一律填上，没有限制就填 `none`；
  - 只查状态、看不出受限情况的轻量刷新留 null，合并时会保留旧值；
  - 受限的直播状态填 `live`，不要再用 `banned` 或 `unknown` 表示受限。T02.U 按统一原则改掉现在的做法：
    - 用 `banned` 的：YouTube、TikTok、LiveMe；
    - 用 `unknown` 的：微博、百度、LOOK、FC2、六间房、Steam；
    - SOOP 的 19 禁在进房时直接报 `NeedsLogin`（7-5）；
  - 取流时按上面“受限类型”表报对应的错误。
- **回放**：
  - 有回放地址就是 `replay`；
  - 拿不到地址的是 `replay` + `unplayable`（虎牙 3-1、微博 18-5、百度 30-4）。
- **哔哩哔哩轮播**（1-1）：
  - `live_status=2` 改为 `carousel`；
  - 登录后能取到地址时，取流照常给地址。房间页是否提供“播放轮播”的入口由 M13 决定，`isPlayableNow` 对轮播为假；
  - 哔哩哔哩的取流检查不要用 `isExplicitlyOfflineNow` 挡住轮播。
- **Twitch 重播**（8-9）：`rerun` 有可播放的流，标 `replay`（显示为回放，与直播分开），不需要新状态。
- **占位值**：去掉适配器里的占位名字、标题（京东 28-2、百度 30-10 的“Baidu Live”、Steam 的“Steam Broadcast”等），留空即可。
- **身份**：上表以外的平台，如果核实平台不分大小写，把它加进 `SiteIds.caseInsensitiveRoomIds`，并写明依据。

### T09b.1（存储和迁移）

- 按上面的 JSON 规则存新字段，null 和 `none` 分开存。
- 迁移 3.x 数据时，关注按 `identityKey` 合并大小写不同的重复项（11-8）：保留先关注的那条的写法和标签，合并标签。

### M13（界面）

- 关注页的三个分组直接用 `followGroup`。
- 卡片在 `isRestricted` 时标出受限类型。
- 发现页默认隐藏不能播放的直播（设置里可以打开），关注和搜索照常显示。哪些种类算“不能播放”由 M13 定，`needsLogin`、`adult` 登录后可能可以播放。
- 名字用 `displayNick(本地化的平台名)`。
- 开播时间只在直播中（`isLiveNow`）显示。
- 轮播显示为单独的状态，但放在未开播分组里。

## 测试

`live_core` 共 2882 个用例（本模块新增 28 个），全部通过：

- `live_room_upgrades_test.dart`（28 个）：
  - 开播时间：ISO 往返、本地时间转 UTC、毫秒时间戳和各种 ISO 写法的读取、坏值；
  - 受限类型：名字是存储格式、每种往返、不认识的名字、“未提供”和 `none` 的区别、受限的直播仍是直播；
  - 轮播：下标 5 和 3.x 的下标不变、分组和可播放、3.x 读成未开播、各状态的分组表、不可播放的回放；
  - 身份：所有平台逐个比较大小写（只有 6 个平台忽略）、YouTube 区分大小写、键的规范化、大小写不同的刷新能合并；
  - 合并：同一场保留、状态变化后清掉、请求失败后保留、`none` 清掉限制、`copyWith`；
  - 占位值：空值不覆盖、`displayNick`；
  - 3.x 样本：6139 个房间 JSON 读进来与之前一致。
- `live_room_test.dart`：枚举顺序的用例加上 `carousel`。
