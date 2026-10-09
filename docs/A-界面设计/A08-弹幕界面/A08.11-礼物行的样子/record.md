# A08.11 礼物行的样子：全平台统一：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区 `worktree-agent-ad5eb20bf7f8f3c62`，从 master `f28cee592` 开始，含 E05.5、A08.10、A08.13）
- 分支和提交：`worktree-agent-ad5eb20bf7f8f3c62`，提交见文末
- 任务书：[brief.md](brief.md)；设计：[README.md](README.md)（第 1 版，G1～G14 按 D-003 由维护者定）；真机步骤：[verify.md](verify.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 阶段 1 效果图和评审页 | 没出（G13） | 维护者授权按 D-003 直接定，和 A08.10 一样；设计和选择写在 README，样子由测试断言，真机截图进 verify.md |
| c1 和聊天行分开 | 做了：`GiftLine`（新文件 `danmaku/gift_line.dart`）：礼物图或图标、标签和名字、动词、礼物名、×N、价值 | 名字后面没有冒号（A08.10 G11 就是这样）；价值用等宽数字 |
| c2 卡片 | 做了：聊天卡片的样子，圆点换成礼物图 | 没有 |
| c3 档位 | 做了：值钱 2 宽第三色竖条，很值钱 4 宽竖条 + 礼物名平台色（过 4.5:1），读屏文字 | 多了宽度差（G4），任务要求不只靠颜色 |
| c4 连击 | 做了：显示的数变了只有“×N”跳到 1.2 倍再回来（200 毫秒），减少动态时不动；行缓存认消息对象，D07.1 换行或换消息都会重建这一行 | 合并本身没做（D07.1）；`chat_feed.dart`、`room_controller.dart` 一行没改 |
| c5 “显示用户名”关 | 做了：名字、徽章、粉丝牌不显示，“对方”留着 | 没有 |
| c6 横屏 280、大字 | 做了：整段换行、价值整块换行、礼物图对第一行；测试 280 宽 × 1.3、2 倍 × 三套主题 × 两种样式 | 顺带修了大字号下行内小块放大两次（G14） |
| c7 长按、双击 | 做了：`chatLineActionable` 认平台礼物；面板卡片写礼物的话和价值；复制“名字: 送出 礼物名 ×N”；关键词先填礼物名 | 礼物还不过屏蔽（D07.1 c1），见 README“留下的问题” |
| c8 翻译 | 做了：21 个键（zh、en） | 没加“上舰”键：会员一律“开通”（G8） |
| 恢复 niconico 名次、Kick 和 niconico 的价值 | 做了：`giftNotes`（“贡献第 N 名”）、Kicks 和点数作为价值 | 没有 |
| G1 门槛和折算表 | 定稿：表和 10、100 元不变（README 有表和理由）；`live_gift.dart` 只改注释 | 没有 |

## 根因

- 礼物行没有自己的样子：`ChatLineView` 的礼物分支（master `f28cee592` `chat_list.dart` `case ChatLineKind.gift`）只画一个图标、名字和 `line.text`，E05.5 给的 `LiveGift`（图、价值、档位、种类、收礼人）界面一项没读；长按、双击没有，因为 `chatLineActionable` 只认聊天和本地礼物。
- 大字号下内容放大两次（G14）：`ChatLineView._words` 把 `EmoteText` 放在 `WidgetSpan` 里。Flutter 的 `WidgetSpan.extractFromInlineSpan` 按整行的 `textScaler` 把里面的组件放大（`_AutoScaleInlineWidget`），里面的 `Text` 又从 `MediaQuery` 读到同一个 `textScaler` 再放大一次，系统 2 倍字时内容是 4 倍、名字（普通 `TextSpan`）是 2 倍；“对方”“本地”、粉丝牌、本地徽章（`ChatChip`）同样。实测：14 号字 1.3 倍时内容一行高 35.1（应为 27.3）。

## 改了哪些文件

- 新：`apps/pure_live/lib/features/live_play/danmaku/gift_line.dart`。
- `apps/pure_live/lib/features/live_play/danmaku/chat_list.dart`：礼物分支用 `giftLineOf`；`chatLineActionable`、`chatCopyText`、`chatMessageWords`；行缓存 `(ChatLineView, LiveMessage?)`；`ChatLineView.giftRoom`；`ChatList` 传 `GiftLineRoom`；行内小块用 `chatInline`。
- `apps/pure_live/lib/features/live_play/danmaku/chat_text.dart`：`chatInline`、`ChatInline`。
- `apps/pure_live/lib/features/live_play/danmaku/message_panel.dart`：卡片的话（`_words`）、关键词的初始值。
- `apps/pure_live/lib/features/live_play/local_interaction/local_chat_line.dart`：两个小块用 `chatInline`（样子不变）。
- `packages/live_core/lib/src/live_gift.dart`：注释（表定稿）。
- 翻译：`apps/pure_live/assets/translations/zh.json`、`en.json`。
- 测试：新 `apps/pure_live/test/features/live_play/gift_line_test.dart`；`chat_line_roles_test.dart` 加一个、两个辅助函数认 `ChatInline`。
- 文档：本文件夹 README、record、verify；A08 子分类 README 的现状和代码地图；`docs/tasks.toml`；生成的 STATUS、TASKS 等。

## 新设置、翻译键、门禁基线

- 新设置：没有。新图标：没有（兜底用已有的 `AppIcons.chatGift`）。
- 新翻译键（21 个，zh / en）：`gift_line_bought`（开通 / bought）、`gift_line_count`（×{count}）、`gift_line_gifted`（赠送 / gifted）、`gift_line_months`（×{count} 个月 / ×{count} mo）、`gift_line_rank`（贡献第 {rank} 名 / top giver #{rank}）、`gift_line_sent`（送出 / sent）、`gift_line_sent_to`（送给 {name} / sent {name}）、`gift_line_tipped`（打赏 / tipped）、`gift_line_unnamed`（礼物 / a gift）、`gift_tier_precious`（很值钱的礼物）、`gift_tier_valuable`（值钱的礼物）、`gift_value_bits`、`gift_value_cheese`（奶酪）、`gift_value_diamond`（钻石）、`gift_value_douyin_coin`（抖币）、`gift_value_gold_seed`（金瓜子）、`gift_value_kicks`、`gift_value_point`（点 / pt）、`gift_value_red_bean`（红豆）、`gift_value_star_balloon`（星气球）、`gift_value_yuan`（{value} 元 / ¥{value}）。没有删键，`keptUnusedKeys` 不用改（旧礼物行没有专用的键）。
- 门禁基线：没改。

## 测试

- 新 `gift_line_test.dart`（22 个）：
  - 各平台经真实解析器：哔哩哔哩 `SEND_GIFT`（金瓜子）、`COMBO_SEND`（×20、2万 金瓜子）、`GUARD_BUY`（开通 舰长 ×1 个月、19.8万 金瓜子）、银瓜子（不写价值）；斗鱼录制样本 `S15-gifts`（连击数、主播不写“送给”、别的房间写）；猫耳录制样本 `S09-events`（28 钻石、礼物图、免费）；Kick 的帧（100 Kicks）；niconico、克拉克拉、虎牙、YouTube、百度的类（名次、收礼人、单位不明不写、图）；英文；没有 `LiveGift` 的旧消息。
  - 礼物图：16×16、按 3 倍屏解码 48、加载中和失败画图标；没有图时字的位置不变。
  - 三套主题 × 两种样式：名字 600、动词 400 次要色、礼物名 600 第三色、×N 等宽、价值小一号，全部 ≥4.5:1；紧凑没有底色、卡片有。
  - 档位：普通没有竖条、值钱 2 宽第三色、很值钱 4 宽平台色且 ≥4.5:1（三套主题 × 两种样式）；没有平台色时第三色；读屏文字。
  - 表和门槛的值；连击按显示的数升档（30 个 5 元 = 150 元很值钱，120 个 1 毛 = 12 元值钱）。
  - 连击：数变了只有 ×N 在 100 毫秒时 1.2 倍、250 毫秒时回到 1；减少动态时没有动画。
  - “显示用户名”关：两种样式没有名字和粉丝牌，剩“送出 小心心 ×33000 金瓜子”。
  - 280 宽 × 1.3、2 倍 × 三套主题 × 两种样式：不溢出、礼物名完整、不截断、价值在后面的行；×N 和图在 1、2 倍下只放大一次、图不变大、对着第一行。
  - 直播间竖屏：适配器的礼物进列表、很值钱用哔哩哔哩色、长按开面板（卡片“送出 小心心 ×3 · 3000 金瓜子”、关键词“小心心”）、双击复制“舰长大人: 开通 舰长 ×1 个月”、关掉“在聊天列表显示礼物”行都没了；手机横着拿 869×400、宽屏 1280×800（卡片和紧凑）不溢出；50 条礼物每行只构建一次。
  - 改之前的代码上：除了“没有 LiveGift 的旧消息”和开关那一步，都会失败（没有图、价值、档位、动词，礼物行不能长按）。
- `chat_line_roles_test.dart` 加“内容和小块随系统字号只放大一次”（1、1.3、2 倍，聊天行和本地行）：修之前 1.3 倍时失败（35.1 对 27.3）。
- `apps/pure_live/test/features/live_play/` 全部 422 个、`test/i18n_test.dart` 通过。
- 基准 `chat_benchmark_test.dart`（每秒 200 条聊天、3 秒、120 赫兹，没改测试；加礼物的场景是 D07.1 的）：改之前 `ChatLineView` 602 次构建、每帧 45.2 个组件构建；改之后 602 次、每帧 48.6 个（每行多 `ChatInline` 和它的 `MediaQuery` 两个组件，内容那一块）；帧时间这台机器上前后都在 17～33 毫秒之间跳（同时有别的任务在跑），看不出差别。

## 真机上要看的

- 按 [verify.md](verify.md) 的 14 步。重点：
  - 礼物行和聊天行、醒目留言、通知一眼分得开；免费礼物没有价值。
  - 值钱和很值钱的竖线粗细看得出差别，很值钱的平台色在深色、纯黑主题下看得清。
  - 有图的平台（猫耳、克拉克拉、YouTube、百度）图和字对齐，图慢的时候字不跳。
  - 手机横着拿的 280 宽列表、系统最大字号：礼物名完整，价值整块换行；聊天行的内容和名字一样大（G14 修了以前内容大一圈）。
  - 长按开面板、双击复制的文字。
  - D07.1 合并后看“×N”跳一下。

## 提交

- `e14ca4efc` [A08.11] One gift line for every platform: picture, name, gift, count, value, tier mark
- `e18fcffde` [A08.11] Scale the chat line's inline pieces once with the system text
- `94b05f540` [A08.11] Record the gift line design (G1-G14, tier table) and mark it 待真机
- `32045cd1e` [A08.11] Format ChatInline
- 本节的更新是最后一个提交。没有推送、没有合并；合并后在登记表补 `commit`。

## 门禁

- 第一次在 `94b05f540` 上跑：只有 `apps/pure_live format` 不过（`chat_text.dart` 的 `ChatInline.build` 最后改的一行没格式化），其余全过，测试全过。
- 格式化后在 `32045cd1e` 上：`bash tools/gate/gate.sh --all` 通过（`gate: passed (all, 14 members)`）。

## 和 D07.1 合并（2026-10-09，维护者）

- D07.1 合并连击时换成新的一行（新 id，所以是新组件），只靠 `didUpdateWidget` 的跳动不会发生。`GiftLine` 加了 `merged`（`ChatLine.revision > 0`），第一次建出来时 ×N 跳一次；系统要求少动画时照旧不动。测试：`gift_line_test.dart` 的“D07.1's merged line … pulses ×N when first built”。
- D07.1 的 `CombinedGift` 的 `count` 已经是总数、`totalValue` 已按总数换算，`giftShownCount` 取 `max(count, comboTotal)` 等于总数，价值不会乘两次。
- `chat_list_follow_test.dart` 里 D07.1 的测试改成按 `GiftLine` 显示的数字找行（礼物行分成几段画，不再是一整段文字）。
