# Z03.3 界面清点脚本改用新编号：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区 `ai/Z03.3`（从 master `7abf9562c` 开始）
- 任务书：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 对照表 | 做了，按 A | `new_ids()` 读 `docs/tasks.toml` 的 `old`，55 个 U 编号一一对上；同一个旧编号对两个任务、或规则里的旧编号没有任务时报错。规则表不动 |
| c2 排序 | 做了 | 按组字母、子分类、序号排（A07.6 在 A08.1 前，R02.1 在 A 组之后） |
| c3 版本 | 做了 | 两份清单开头写“扫描的提交”；`--tv-ref <提交>` 用 `git archive` 取那个提交的 `lib/` 和翻译，解到电视版仓库旁边的临时目录，不动它的工作区 |
| c4 重新生成 | 做了 | 用 `b9d2f739` 重新生成：两份清单除了任务的顺序和开头一行，排序后逐行相同。电视版最新（`37660afc`）多出 8 个视频模块的文件，见下 |
| c5 测试 | 做了 | `tools/gate/tests/test_inventory.py` 5 个：对照表、一对二报错、没有对照报错、按新编号排序、真实规则表全部有对照 |

## 发现的问题

- 条目编号（A11.3-11 这种，文档里约 495 处引用）跟着 `os.walk` 返回目录的顺序，也就是文件系统的顺序。试过把目录排序，编号会整体变，所以保留原来的顺序；`--tv-ref` 解压到电视版仓库旁边（同一个 ext4 盘，同名目录顺序相同）才和原来一致，解到 `/tmp`（tmpfs）就不一致。换机器重新生成前要先对比编号，已写进 `docs/inventory/README.md`。

## 电视版最新多出的界面文件（给 A17.6）

- `tv:modules/video/pages/archive/video_detail_dialogs.dart`
- `tv:modules/video/pages/discover/video_tag_search_page.dart`
- `tv:modules/video/pages/discover/widgets/video_live_results.dart`
- `tv:modules/video/pages/discover/widgets/video_search_filter_dialog.dart`
- `tv:modules/video/pages/playback/widgets/video_info_panel.dart`
- `tv:modules/video/pages/playback/widgets/video_speed_menu.dart`
- `tv:modules/video/pages/playback/widgets/video_subtitle_menu.dart`
- `tv:modules/vod/pages/widgets/comment_pictures.dart`

清单现在仍按 `b9d2f739`，要不要换成最新由 [A17.6](../../../A-界面设计/A17-电视界面/A17.6-电视点播/README.md) 定。

## 测试

- `python3 -m unittest discover -s tools/gate/tests`：36 个全过（新增 5 个）。
- 不需要真机。
