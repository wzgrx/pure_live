# T07i.2 启动页

- 日期：2026-10-01
- 设计：[docs/T07/T07i/T07i.2/README.md](README.md)（第 1 版，用户已确认；K1、K2 按建议 A）
- 范围：启动页，和启动后自动弹出的提示的先后（两个对话框本身在 [T07a.6](../../T07a/T07a.6/record.md)）。系统启动画面（原生）属于 T13a.1，没做。
- 改动的目录：`apps/pure_live/lib/features/splash/`、`apps/pure_live/lib/shared/app_prompts.dart`（新）、文档。没有改原生部分。

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 设置“启动动画”（默认开）；图标、“欢迎使用”、进度条三样居中；停 1 秒、最多再等 0.35 秒关注核验；关掉时直接进首页 | ✅ | 去掉了 v4 原来多加的一行“纯粹直播”（v3 没有）；图标 150（v4 原来 132） |
| c2 | 动画 0.4 秒做完（淡入加 0.9→1 放大，减速、不回弹） | ✅ | `Curves.decelerate`；离开时图标和文字完整显示 |
| c3 | 背景跟主题：表面色，右下角带一点主色容器色；深色用深色表面 | ✅ | 渐变 表面色 → 表面色（45%）→ 主色容器（浅色 70%、深色 45%，叠在表面色上），方向照效果图的 160° |
| c4 | 进度条主色，底轨主色 15%，圆头 | ✅ | 宽 200、高 4 |
| c5 | 图标和“欢迎使用”之间留 16 | ✅ | 文字 20 号 600 字重；进度条在文字下 32 |
| c6 | 点一下直接进首页 | ✅ | 另外电脑上按任意键也直接进（“各客户端”一节） |
| c7 | 启动后的提示排队：同一时间只开一个；口令导入先，新版本后；新版本只在首页弹，进了直播间就等回到首页 | ✅（口令导入的触发在 M12.5） | 见下 |
| c8 | Android 系统启动画面同底色 | — | 交给 T13a.1（任务书要求不做） |
| 各客户端 | 状态栏透明，图标颜色跟深浅色 | ✅ | `AnnotatedRegion` |

**提示的先后**（`shared/app_prompts.dart` 的 `AppPrompts`）：应用自己弹的提示（`AppPromptKind.share` 口令导入、`AppPromptKind.update` 新版本）排一个队：同一时间只开一个；几个同时等时口令导入先；一个提示可以带“时机”（新版本的时机是首页在最上面）。页面或对话框每变一次（`liveRouteObserver`）、一个提示关掉一帧以后，重新看等着的提示能不能弹——所以口令导入点“进入房间”后，新版本会等直播间盖上去再判断，回到首页才弹。

偏差：口令导入的识别（读剪贴板、解码分享口令）不在 v4 主线上，在暂停的 M12.5 分支（`ClipboardRoomWatcher`）。这次做了对话框和排队（`showRoomPrompt` 自动排在新版本前面），合并 M12.5 时它的 `prompt` 回调改用这里的 `showRoomPrompt` 即可，见 [T07a.6](../../T07a/T07a.6/record.md)“需要决定的”。

## v3 文件 → v4 文件

| v3 | v4 |
|---|---|
| `modules/splash/splash_screen.dart`、`routes/app_pages.dart:188-235` | `features/splash/splash_page.dart` |
| `common/global/platform/desktop_manager.dart:595-650`（口令导入的时机）、`modules/home/home_page.dart:99-104`、`:198-216`（新版本的时机） | `shared/app_prompts.dart`；`features/version/update_prompt.dart`（`checkForUpdateOnStartup` 走队列） |

## 新设置

无。

## 门禁

`splash` 没有直接写的颜色和图标（前后都是 0）。

## 测试

- `test/features/splash/splash_page_test.dart`：3 → 8 个：0.4 秒内透明度只增、放大不超过 1、0.4 秒时完整；图标 150、文字在图标下 16、进度条 200 宽在文字下 32、主色和 15% 底轨、没有“纯粹直播”；浅色和深色的背景都取主题颜色（没有 3.x 的青色）；电脑按任意键进首页。原有三个照旧。
- `test/shared/app_prompts_test.dart` 的排队部分 2 个：第二个提示等第一个关掉、口令导入插到新版本前面、返回顺序；没到时机的提示在页面变化后才弹。
- `update_dialogs_test.dart` 里“另一个页面在上面时新版本不弹，回到首页才弹”1 个（总数见 T07a.6）。
