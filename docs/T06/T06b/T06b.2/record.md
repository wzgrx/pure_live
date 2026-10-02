# T06b.2 记录：哔哩哔哩打码昵称的“屏蔽此用户”（热修）

- 任务单：[`docs/T06/T06b/T06b.2/brief.md`](brief.md)；审查报告 B-1、A-04。
- 本地 worktree 任务（不推送、不开 PR），提交在当前分支。

## 根因

- 访客连接哔哩哔哩弹幕时，服务器在每条 `DANMU_MSG` 里只给打码昵称（`info[2][1]`、`info[0][15].user.base.name`、`origin_info.name` 全是“观***”这种），uid 都是 0（结论和样本核对见 [T06d.2 记录](../../T06d/T06d.2/record.md)“昵称从哪里来”）。
- 长按弹幕面板和画面弹幕点按面板是同一个函数 `showChatMessageActions`（`features/live_play/danmaku/chat_list.dart`），原来只排除了空名字和本地弹幕，打码名照样有“屏蔽此用户”。
- 屏蔽按名字全等（小写）匹配，屏蔽表全局、持久（`live_store` 的 `block_rules`，所有平台共用）：屏蔽一个“观***”等于屏蔽所有以“观”开头、被打码成同一个样子的观众，在所有哔哩哔哩直播间永久生效，还会删掉列表里所有同名行。

## 逐条对照

| 条 | 做到没有 | 怎么做的 |
|---|---|---|
| c1 打码名不显示“屏蔽此用户”，屏蔽关键词照旧 | 做了 | `showChatMessageActions` 多一个条件 `!isMaskedViewerName(name)`；长按聊天行和点按画面弹幕都走它，所以两处一起生效。复制、屏蔽关键词不变 |
| c2 启动时一次性清理已存的打码名，屏蔽管理页顶部提示一次 | 做了 | 新文件 `shared/danmaku/masked_blocks.dart` 的 `MaskedNameBlocks.cleanOnce`：`AppStartup.start()` 里调用；meta 键 `danmaku.maskedUserBlocksCleaned` 记下已经跑过（值是清掉的个数），清掉了才写 `danmaku.maskedUserBlocksNotice`。屏蔽管理组件（直播间“屏蔽管理”标签和设置里的“弹幕屏蔽”页是同一个组件）打开时取走这个提示，顶部显示“已清理 N 个打码昵称的屏蔽（它们会误伤其他观众）”，带 × 可关；取走即删除，只出现一次 |
| c3 屏蔽管理页添加用户屏蔽时拒绝打码名 | 偏差，见下 | 屏蔽管理页没有“添加用户”的输入框（已确认的 T06d.1 / T06b.1 设计：用户只能从长按弹幕屏蔽，空列表写“长按弹幕可屏蔽发送者”），所以没有可拒绝的输入。改为在过滤层兜底：`packages/live_danmaku` 的 `DanmakuBlockList` 忽略打码名（只加了一个判断），备份恢复、3.x 导入带进来的打码名也不会屏蔽任何人 |

### 偏差

- c3：页面没有用户输入框，没有为了这一条新加输入框（那是新设计）。兜底放在过滤层，见上表。
- 改了 `apps/pure_live/lib/app/startup.dart`（不在任务单的可改目录里）：只加了一处调用，c2 要求“启动时”，启动流程只在这里。
- 打码判断对所有平台生效，不只哔哩哔哩：打码名（两个以上连续 `*` 或 `＊`）在任何平台都代表一群人，按全名屏蔽都没有意义（LookLive 的匿名模式也是“观***”）。判断直接用 `BilibiliDanmakuProtocol.isMaskedName`，`isMaskedViewerName` 只是先去掉两端空白。
- meta 键定义在应用里（`MaskedNameBlocks.doneKey`、`noticeKey`），和 `LegacyReloginNotice` 一样，`live_store` 没有改。

## 改了哪些文件

- `packages/live_danmaku/lib/src/filters/block_list.dart`：打码名不进屏蔽集合。
- `apps/pure_live/lib/shared/danmaku/masked_blocks.dart`（新）：`isMaskedViewerName`、`MaskedNameBlocks`。
- `apps/pure_live/lib/features/live_play/danmaku/chat_list.dart`：打码名不显示“屏蔽此用户”。
- `apps/pure_live/lib/shared/danmaku/block_manager.dart`：顶部一次性提示。
- `apps/pure_live/lib/app/startup.dart`：启动时调用清理。
- `apps/pure_live/assets/translations/zh.json`、`en.json`：`danmaku_masked_blocks_cleaned`。
- 测试：`packages/live_danmaku/test/message_filter_test.dart`、`apps/pure_live/test/shared/masked_blocks_test.dart`（新）、`test/features/shield/shield_page_test.dart`、`test/features/live_play/live_play_popups_test.dart`、`test/features/live_play/live_play_page_test.dart`。

## 新设置和翻译

- 没有新设置。meta 键：`danmaku.maskedUserBlocksCleaned`（跑过的标记，值为清掉的个数）、`danmaku.maskedUserBlocksNotice`（待显示的个数，显示后删除）。
- 翻译键：`danmaku_masked_blocks_cleaned`（“已清理 {count} 个打码昵称的屏蔽（它们会误伤其他观众）”）。

## 测试

新增 8 个：

- `live_danmaku`：打码名不屏蔽任何人（连同名的打码名也不屏蔽），全名照旧屏蔽。`live_danmaku` 全部 1590 个通过。
- 应用：打码判断；清理只跑一次（清掉打码名、保留其他名字和顺序、关键词不动、之后再加进来的不再清）；没有打码名时不提示、也不再跑；屏蔽管理页顶部提示在最上面、个数对、× 能关、再打开不再出现；没有清理时不提示；长按“观***”“ab＊＊”的弹幕没有“屏蔽此用户”，复制和屏蔽关键词还在，之后全名“路人”照旧能屏蔽并存进屏蔽表；画面弹幕点按“观***”的面板没有“屏蔽此用户”。`apps/pure_live` 全部 748 个通过，`flutter analyze` 无问题。
- `dart format` 两个包都无改动；`python3 tools/gate/check_ui_structure.py` 通过。没有跑完整门禁（本地任务约定）。

## 要在 K90 上看的

1. 退出哔哩哔哩登录（或用没登录过的安装），进一个热闹的哔哩哔哩直播间。
2. 长按聊天列表里一条“观***”这样的弹幕：面板里有“复制”“屏蔽关键词…”，没有“屏蔽此用户”。
3. 画面上点按一条飞过的打码弹幕：同样没有“屏蔽此用户”。
4. 升级前屏蔽过打码名的话：升级后第一次打开“屏蔽管理”（直播间标签或 设置 → 弹幕屏蔽），顶部有“已清理 N 个打码昵称的屏蔽（它们会误伤其他观众）”，已屏蔽用户里没有打码名；关掉再进，不再提示。
5. 其他平台（如斗鱼）长按一条正常昵称的弹幕，“屏蔽此用户”还在，屏蔽后生效。

## 可能和别的任务冲突的文件

- `features/live_play/danmaku/chat_list.dart`（T06d.2、T02f.2 也改聊天行）。
- `shared/danmaku/block_manager.dart`、`app/startup.dart`。
