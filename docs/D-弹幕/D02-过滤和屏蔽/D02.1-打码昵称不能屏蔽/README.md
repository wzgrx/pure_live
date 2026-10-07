# D02.1 哔哩哔哩打码昵称不能“屏蔽此用户”，清理已存的打码屏蔽

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为待真机，2026-10-02，提交 `40dc22279`，和 D01.32 一起合并 `944bab5fc`）；当时定的规模小（热修）
- 类型：功能
- 来源：审查报告 B-1（严重）、A-04（[V03.1 全面审查](../../../V-需求和反馈/V03-审查和调研/V03.1-全面审查/README.md)）：访客能“屏蔽”打码昵称“观***”，结果是所有昵称以“观”开头的观众在所有哔哩哔哩直播间被永久屏蔽
- 旧编号：B01、T06b.2
- 相关：决定 D-013（打码昵称不能“屏蔽此用户”）；同一分支后做的 [D01.32](../../D01-平台弹幕协议/D01.32-哔哩哔哩访客昵称和粉丝牌/README.md)（访客提示和登录引导）；过滤框架 [D01.1](../../D01-平台弹幕协议/D01.1-弹幕框架和过滤/README.md)；长按弹幕面板 [A07.6](../../../A-界面设计/A07-直播间界面/A07.6-直播间弹窗/README.md)（后来 A07.12 改成 `RoomMessagePanel`）；屏蔽管理组件 [A08.3](../../../A-界面设计/A08-弹幕界面/A08.3-弹幕屏蔽页/README.md)；画面弹幕点按 [A08.4](../../../A-界面设计/A08-弹幕界面/A08.4-画面弹幕点按和长按/README.md)
- 任务书 [brief.md](brief.md)；记录 [record.md](record.md)；真机验证 [verify.md](verify.md)

## 目标

未登录时哔哩哔哩服务器把每条弹幕的昵称打码成“观***”这样（uid 也是 0，见 D01.32 的根因）。屏蔽按名字全等（不分大小写）、全局、永久生效，所以“屏蔽”一个打码昵称，等于屏蔽所有被打码成同一个样子的观众，在所有直播间，还会删掉列表里所有同名行。做完以后：

1. 打码昵称在长按弹幕面板、画面弹幕点按面板里**没有**“屏蔽此用户”（复制、屏蔽关键词照旧）；
2. 以前已经存进屏蔽表的打码昵称，在升级后第一次启动时清掉一次，屏蔽管理页顶上说一次清了几个；
3. 过滤层兜底：屏蔽表里就算有打码昵称（备份恢复、3.x 导入带进来），也不屏蔽任何人。

## 3.x 和现状

| 方面 | 3.x（`git show v3.2.11:lib/...`，文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 长按面板的“屏蔽此用户” | `modules/live_play/widgets/danmaku/danmaku_message_actions.dart`：除本地弹幕外都有，打码昵称也有 | `apps/pure_live/lib/features/live_play/danmaku/message_panel.dart:169`：`name.isNotEmpty && !message.isLocal && !isMaskedViewerName(name)` 时才显示；列表长按和画面弹幕点按都走 `showRoomMessageActions`（`:20`） | 打码昵称不显示（做到） |
| 打码判断 | 直播间控制器里的正则 `\*{2,}|＊{2,}`（`modules/live_play/controllers/danmaku_controller.dart:211`），只用来插提示 | `isMaskedViewerName`（`apps/pure_live/lib/shared/danmaku/masked_blocks.dart:7`）= 去两端空白后 `BilibiliDanmakuProtocol.isMaskedName`（`packages/live_danmaku/lib/src/sites/bilibili.dart:344`，同一正则 `:341`）；对所有平台生效（LOOK 直播的匿名模式也是“观***”） | 做到 |
| 屏蔽表的匹配 | `_isBlocked`（`danmaku_controller.dart:252`）：整名相同（去空白、小写）就屏蔽 | `DanmakuBlockList`（`packages/live_danmaku/lib/src/filters/block_list.dart:13`）：打码昵称不进屏蔽集合（`:20-22`），其余同 3.x | 打码昵称不屏蔽任何人（做到） |
| 已存的打码屏蔽 | 不清理 | `MaskedNameBlocks.cleanOnce`（`masked_blocks.dart:24`）：每次安装只跑一次，meta 键 `danmaku.maskedUserBlocksCleaned`（`:16`，值是清掉的个数）；清掉了才写 `danmaku.maskedUserBlocksNotice`（`:19`）；启动时调用（`apps/pure_live/lib/app/startup.dart:79`，出错只写日志） | 做到 |
| 清理后的说明 | 没有 | 屏蔽管理组件打开时 `_takeMaskedNotice`（`apps/pure_live/lib/shared/danmaku/block_manager.dart:79`）取走提示，顶上一条“已清理 N 个打码昵称的屏蔽（它们会误伤其他观众）”带 ×（`_maskedNotice` `:90`）；取走即删，只出现一次；直播间“屏蔽管理”标签和设置的“弹幕屏蔽”页是同一个组件 | 做到 |
| 手动添加打码昵称 | 3.x 设置里只有关键词页（`modules/shield/danmu_shield_page.dart`），没有添加用户的输入框 | 屏蔽管理同样没有添加用户的输入框（A08.1、A08.3：用户只能从长按弹幕屏蔽） | 任务书 c3 没有可拒绝的输入，改由过滤层兜底（见“结果”偏差 1） |

## 结果

- 改动清单（任务书 c1～c3，详见 [record.md](record.md)“逐条对照”）：
  - c1 打码昵称不显示“屏蔽此用户”：当时改在 `chat_list.dart` 的 `showChatMessageActions`，A07.12 把面板挪到 `message_panel.dart` 后条件照搬（`:169`）。
  - c2 一次性清理和一次性说明：新文件 `shared/danmaku/masked_blocks.dart`、`block_manager.dart` 顶上的说明、`startup.dart` 的一处调用。
  - c3（偏差）：页面没有添加用户的输入框，没有为这一条新加（那是新设计）；改为 `DanmakuBlockList` 忽略打码昵称，备份恢复、3.x 导入带进来的也不起作用。
- 其他偏差：改了任务书范围外的 `app/startup.dart`（启动流程只在这里）；打码判断对所有平台生效；meta 键定义在应用里（和 `LegacyReloginNotice` 一样），`live_store` 没改。
- 没有新设置；翻译键 1 个：`danmaku_masked_blocks_cleaned`（zh、en）。
- 提交：代码 `40dc22279`（`fix(danmaku): masked Bilibili guest names cannot be blocked`），合并 `944bab5fc`（2026-10-02）。

## 验证

- 自动测试（新增 8 个，record“测试”）：
  - `packages/live_danmaku/test/message_filter_test.dart:31`：打码昵称不屏蔽任何人（连同名的打码昵称也不屏蔽），全名照旧屏蔽。
  - `apps/pure_live/test/shared/masked_blocks_test.dart`（3 个）：打码判断（`**`、`＊＊`、两端空白）；清掉打码昵称、保留其他名字和顺序、关键词不动、只跑一次、提示只欠一次；没有打码昵称时不提示、不再跑。
  - `apps/pure_live/test/features/shield/shield_page_test.dart:158`、`:184`：清理后的说明在最上面、个数对、× 能关、再打开不出现；没有清理时不提示。
  - `apps/pure_live/test/features/live_play/live_play_popups_test.dart:980`：长按“观***”“ab＊＊”的弹幕没有“屏蔽此用户”，复制和屏蔽关键词还在，之后全名照旧能屏蔽并存进屏蔽表。
  - `apps/pure_live/test/features/live_play/live_play_page_test.dart:327`：画面弹幕点按“观***”的面板没有“屏蔽此用户”。
- 真机：**待真机**，步骤在 [verify.md](verify.md)（record“要在 K90 上看的”5 条）。

## 留下的问题

- `LiveRoomController.blockUser`（`apps/pure_live/lib/features/live_play/logic/room_controller.dart:997`）本身不检查打码昵称，只靠面板不给入口；以后有别的入口（例如多画面的长按）调用它时要一起判断。没有任务，记在 [D02 的已知问题](../README.md)。
- “按发送者哈希只在本场屏蔽”（审查 B-1 的另一个建议）：没做；访客收到的 `info[0][7]` 发送者摘要可以做到本场屏蔽一个打码观众，但要新的屏蔽种类和界面。没有任务，有需要时在 V01 提议。
