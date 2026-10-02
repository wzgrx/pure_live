# T06d.2 记录：哔哩哔哩访客昵称说明和登录引导、粉丝牌和头像

- 任务单：[`docs/T06/T06d/T06d.2/brief.md`](brief.md)；审查报告 A-04。T06b.2 之后做（同一分支）。
- 本地 worktree 任务（不推送、不开 PR），提交在当前分支。

## 根因：“哔哩哔哩的弹幕没有用户名字”

结论：**不是我们漏了字段，是服务器按连接身份打码**。未登录（uid 0、访客 key）的连接收到的每条 `DANMU_MSG` 里，所有能放昵称的字段都是打码的；没有哪个字段带着全名而我们没取。所以修不了解析，只能引导登录（c1）。

### 怎么核对的

解码仓库里两份真实录制（都是未登录）：`fixtures/bilibili/danmaku/S13-live`（2026-09-27，房间 5050，44 条弹幕）和 `S13-protover2-paired`（2026-09-30，房间 1700301235，66 条弹幕；`S13-protover3` 是同一时刻的 brotli 连接，通知逐条相同）。脱敏说明（`docs/T06/T06a/T06a.2/record.md`“样本”）写明：打码昵称是**按原样换成另一个打码名**（如 `离***` 换成 `观***`），完整昵称才换成合成名，所以样本里“打码 / 不打码”的状态和服务器发来的一致。

### 每种消息结构取昵称的路径

| 消息 | 字段 | 访客收到的 | 我们读不读 |
|---|---|---|---|
| `DANMU_MSG` 旧结构 | `info[2]` = `[uid, 昵称, …]` | `[0, "观***"]`，110 条全部打码，uid 全是 0 | 读，最后一个候选 |
| `DANMU_MSG` 新结构 | `info[0][15].user.base.name` | 全部打码 | 读，第一个候选 |
| | `info[0][15].user.base.origin_info.name` | 全部打码 | 读，第二个候选 |
| | `info[0][15].user.uid` | 全部 0 | — |
| | 消息顶层 `uinfo`、`data.uinfo` | 真实 `DANMU_MSG` 里没有这两个键（只有 `cmd`、`info`、`dm_v2`）；合成向量里有，按旧格式保留 | 读，第三、四个候选 |
| | `dm_v2`（protobuf） | 空字符串（paired 样本没有脱敏这个字段，原样就是空） | — |
| | `info[0][15].extra` 里的 `reply_uname` | 空 | — |
| | `info[0][15].user.base.face` | **不打码**（头像地址） | T06d.2 起读：头像 |
| | `info[0][15].user.medal{name, level}`、`info[3]` | **不打码**（粉丝牌，两处 102 条全部一致） | T06d.2 起读：粉丝牌 |
| | `info[0][7]`、`extra.user_hash` | 发送者摘要（不是名字） | 不读 |
| `SUPER_CHAT_MESSAGE` | `data.user_info.uname`、`data.uinfo.base.name` | 完整昵称（不打码） | 读 `user_info.uname`，醒目留言本来就有名字 |
| `ENTRY_EFFECT`（进场）、`LIKE_INFO_V3_CLICK`（点赞） | `data.uinfo.base.name`、`data.uname` | 完整昵称（录制工具当作完整昵称替换掉了） | 不解码这两种通知 |
| `LOG_IN_NOTICE` | `data.notice_msg` | “为保护用户隐私，未登录无法查看他人昵称”——服务器在访客连接开头明说了 | 不解码 |

现在的取名顺序（`packages/live_danmaku/lib/src/sites/bilibili.dart` 的 `_userName`）：rich `user.base.name` → `origin_info.name` → 顶层 `uinfo` → `data.uinfo` → `info[2][1]`，取第一个不打码的；全打码时取第一个 rich 候选。和 3.2.11 的 `_preferredBilibiliUserName` 一样，不是退化。登录后服务器在 `user.base.name` 给全名，按这个顺序直接取到（c3 的测试）。

### 没有做的“绕过”

访客帧里不打码的头像地址，可以和同一场里进场、点赞消息的“头像 + 全名”对上，或者从发送者摘要反推 uid 再查名字，从而还原部分昵称。**没有做**：哔哩哔哩在 `LOG_IN_NOTICE` 里明说了这是为保护隐私而隐藏；而且只能对上本场进过场、点过赞的人，默认头像会撞。建议不做，见“需要维护者决定的”。

## 逐条对照

| 条 | 做到没有 | 怎么做的 |
|---|---|---|
| c1 访客常驻提示“访客模式下哔哩哔哩会隐藏昵称 · 去登录”，替换系统消息；点去登录打开哔哩哔哩登录，回来自动重连；Cookie 失效提示“登录已失效 · 重新登录” | 做了 | `LiveRoomController.nameHint`（新枚举 `ChatNameHint`）：哔哩哔哩直播间、弹幕开着（连接中、已连上、超时、失败都算），没有哔哩哔哩 Cookie → `guest`；有 Cookie 但这次连接已经收到 3 条打码昵称、一条全名都没有 → `loginExpired`。聊天列表（`ChatList`）在最上面放一条 `ChatNameHintBar`（信息图标 + 文字 + 按钮），在空状态上面也显示；列表始终放在同一个 `Column` 里，提示出现或消失时列表不重建、滚动位置不丢。按钮调 `AppNavigator.toBiliBiliLogin()`。原来每次连接插入的“哔哩哔哩访客连接会隐藏弹幕昵称…”系统消息去掉了。**自动重连**：控制器订阅 `store.secrets.cookieChanges`，哔哩哔哩 Cookie 一变（扫码登录成功、退出登录、换 Cookie）就重新取一次房间详情拿新的弹幕凭据（`danmakuData`），再强制重连；所以扫码成功时就重连了，不必等回到直播间 |
| c2 粉丝牌填进 `fansName`、`fansLevel`；卡片样式加头像 | 做了 | 解析：粉丝牌先读 `info[0][15].user.medal{name, level}`，没有再读 `info[3]`（`[等级, 牌子名, …]`），等级 0 不写；头像读 `user.base.face`（没有再读 `origin_info.face`），转 https，`hdslb.com` 的地址加 `@96w_96h.jpg`。头像放在 `LiveMessage.data` 里的新类型 `DanmakuSender`（`packages/live_danmaku/lib/src/sender.dart`，见偏差）。界面：紧凑样式和卡片样式原来的 `_fans` 小标签现在有内容了；卡片样式有头像时，24dp 圆形头像代替左边的小圆点，名字改用弹幕颜色（原来颜色在圆点上）；没头像照旧圆点。紧凑样式不加头像（任务单只要卡片） |
| c3 登录后昵称完整 | 做了（测试） | 照 `S13-protover2-paired` 第一条真实 `DANMU_MSG` 原样复制，只把 uid 和三处昵称换成登录后的样子（合成），解析出全名和 uid；另外验证 rich 名优先、打码的 rich 名被跳过而用 `info[2][1]`。仓库没有真正的登录态录制，在线未验证 |

### 偏差

- 头像没有加到 `LiveMessage`（在 `live_core`，不在可改目录里）。放在 `LiveMessage.data`：哔哩哔哩的聊天消息原来 `data` 为空，其他代码（过滤、录制、多画面）不读聊天消息的 `data`。以后要给更多平台加头像，建议在 `LiveMessage` 上加正式字段。
- “登录已失效”的判断是推断：Cookie 还在但同一次连接里 3 条打码、0 条全名。正常登录时服务器给全名，所以不会误报；启动时的登录核验（`verifyBilibiliLogin`）发现失效会直接退出登录，那之后显示的是访客提示。文字写成“登录已失效，哔哩哔哩隐藏了昵称 · 重新登录”，比任务单多半句原因。
- 重连凭据用 `site.getRoomDetail` 重新取（哔哩哔哩的实现里带 `getDanmuInfo`），多一次房间详情请求；没有直接调 `BilibiliDanmakuArgs.refresh`，房间控制器不依赖哔哩哔哩的类型。只对哔哩哔哩直播间、只对哔哩哔哩的 Cookie 变化生效。
- 没解析 `LOG_IN_NOTICE`：没有 Cookie 就已经知道是访客；解析出来会和顶部提示重复。

## 改了哪些文件

- `packages/live_danmaku/lib/src/sites/bilibili.dart`：`_chat` 读粉丝牌（`_medal`）和头像（`_avatar`），`_userName` 改为接收解好的 rich 对象（顺序不变）。
- `packages/live_danmaku/lib/src/sender.dart`（新）、`lib/live_danmaku.dart`（导出）：`DanmakuSender`。
- `apps/pure_live/lib/features/live_play/logic/room_controller.dart`：`ChatNameHint`、`nameHint`、Cookie 变化后重取凭据并重连；去掉打码系统消息。
- `apps/pure_live/lib/features/live_play/danmaku/chat_list.dart`：`ChatNameHintBar`，列表上方的提示；卡片头像。
- `apps/pure_live/assets/translations/zh.json`、`en.json`：3 个键。
- 测试：`packages/live_danmaku/test/sites/bilibili_test.dart`、`apps/pure_live/test/features/live_play/chat_names_test.dart`（新）、`test/features/live_play/live_play_controller_test.dart`。

## 新设置和翻译

- 没有新设置。
- 翻译键：`bilibili_guest_names_hidden`（“访客模式下哔哩哔哩会隐藏昵称”）、`bilibili_login_expired_short`（“登录已失效，哔哩哔哩隐藏了昵称”）、`bilibili_login_again`（“重新登录”）。“去登录”用已有的 `live_play_go_login`。3.x 的 `bilibili_guest_name_masked` 不再用，按“3.x 翻译文件保留”的约定没有删。

## 测试

新增 10 个，改了 4 个：

- `live_danmaku`（+4）：两份访客录制里每条弹幕的昵称在每个字段都打码、uid 0、`dm_v2` 空、没有顶层 `uinfo`，粉丝牌和头像照样解析出来（有牌子的 61 / 41 条，和 `info[3]` 一致）；登录态合成样本取全名和 uid；粉丝牌的来源和边界（`info[3]` 兜底、等级 0、名字不是文字、旧结构）；头像的来源和地址处理（https、尺寸、已有尺寸不再加、非 http 不要）。
- 改的冻结对照（4 个）：S13-live、S13-vectors、S13-protover3、S13-brotli-vectors 和 3.x 对比时去掉 T06d.2 新加的粉丝牌和头像（3.x 不读这些）；S13-protover3 第一条弹幕的逐字段断言改为带上真实的粉丝牌“小路泥 22”和头像。`live_danmaku` 全部 1594 个通过。
- 应用（+6）：控制器——访客时有提示、不再插系统消息、弹幕关掉后没有提示；登录后 2 条打码不提示、3 条提示失效、来一条全名就消失，退出登录后用访客凭据重连；其他平台没有提示、别的平台 Cookie 变化不重连。页面——访客提示在聊天行上面，点“去登录”打开扫码登录页，登录（写入 Cookie）后重取详情并用新凭据重连，返回后提示消失；失效提示和“重新登录”；粉丝牌小标签，卡片样式头像 24dp 代替圆点、没头像的照旧。
- `dart format` 两个包都无改动；`flutter analyze`、`dart analyze` 无问题；`python3 tools/gate/check_ui_structure.py` 通过；`apps/pure_live` 全部 754 个通过（T06b.2 之后是 748 个）。没有跑完整门禁（本地任务约定）。

## 要在 K90 上看的

1. 设置 → 账号里退出哔哩哔哩登录，进一个热闹的哔哩哔哩直播间：聊天列表最上面有一条“ⓘ 访客模式下哔哩哔哩会隐藏昵称　去登录”，弹幕昵称是“观***”；聊天里不再有“哔哩哔哩访客连接会隐藏弹幕昵称…”那条系统消息。
2. 戴粉丝牌的观众：名字前面有“牌子名 等级”的小标签。
3. 点“去登录” → 扫码登录 → 成功后返回直播间：顶部提示消失，聊天里出现“开始连接弹幕服务器”“弹幕服务器连接正常”（自动重连），之后的新弹幕昵称完整。
4. 弹幕设置里把聊天列表样式改成“卡片”：每条前面是圆形头像（加载失败时是名字首字），名字是弹幕的颜色；横屏、平板的聊天栏同样。
5. 横屏全屏打开聊天侧栏、竖屏全屏：提示条同样在最上面，文字长时两行，按钮不被挤掉。
6. （能复现时）Cookie 失效但 App 还没退出登录：进房间几条打码弹幕后，顶部变成“登录已失效，哔哩哔哩隐藏了昵称　重新登录”。

## 需要维护者决定的

- 是否在 `live_core` 的 `LiveMessage` 上加正式的头像字段（现在借用 `data`）。
- 未点亮的粉丝牌（`is_light` 0，S13-live 里 10 条）现在和点亮的画法一样；网页上是灰的。要不要区分。
- 是否要做“用进场 / 点赞消息里的头像和全名对上访客弹幕”的还原：建议不做（平台明说为保护隐私而隐藏，覆盖也不全）。

## 可能和别的任务冲突的文件

- `features/live_play/danmaku/chat_list.dart`（T02f.2 也改聊天行；T06b.2 也改了这个文件）。
- `features/live_play/logic/room_controller.dart`（很多任务都会动）。
- `packages/live_danmaku/lib/src/sites/bilibili.dart`、两份翻译文件。
