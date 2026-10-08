# D05.2 同屏最大弹幕条数可以设置（接 V01.4）：记录

- 日期：2026-10-08
- 执行者：Claude（本机工作区，没有推送、没有合并）
- 分支和提交：工作区分支 `worktree-agent-aa1803a92d92a655e`，提交 `[D05.2] …`
- 任务书：[brief.md](brief.md)；说明：[README.md](README.md)；设计：[V01.4 README](../../../V-需求和反馈/V01-新功能提议/V01.4-同屏最大弹幕条数可以设置/README.md)“评估结论和设计”

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 1 设置 | 做了 | `Settings.danmakuMaxVisibleCount`：默认 48，`min: 10`、`max: 120`、`resetOutOfRange: true`（0、9、121 都读成 48）；放在 `danmakuAutoFps` 后面 |
| 2 三处弹幕层 | 做了 | `player_view.dart` 的 `build` 读设置传给 `_danmaku(maxVisible:)`；多画面在弹幕 `Consumer` 里读；电视的 `_Picture` 读。弹幕层的规则一行没改，只改了注释 |
| 3 小窗不变 | 做了 | `compact_danmaku.dart`、`playback_tiles.dart` 没动 |
| 4 设置行和搜索 | 做了 | `DanmakuSettingsContent`“流畅度”最后一行（弹幕帧率下面），滑条 10～120、56 档、显示“N 条”；`settings_catalog.dart` 的 `danmaku_max_visible`（步长 2） |
| 5 翻译 | 做了 | 3 个键，zh、en 都加，按键名排序 |

## 根因

- 不是 bug：3.x 和 4.x 的直播间都把 48 写死（3.x `video_controller_panel.dart:801`；4.x `DanmakuOverlay` 的默认参数，`player_view.dart` 不传）。

## 改了哪些文件

- `packages/live_store/lib/src/settings/settings.dart`
- `apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart`（只改注释）、`shared/danmaku/danmaku_settings_content.dart`
- `apps/pure_live/lib/features/live_play/player/player_view.dart`、`features/multiview/multiview_page.dart`、`tv/room/tv_live_play_page.dart`
- `apps/pure_live/lib/features/settings/settings_catalog.dart`
- `apps/pure_live/assets/translations/zh.json`、`en.json`
- `tools/docs/settings_audit_notes.py`；重新生成了 J01.2 的 `settings.md`（220 个设置）
- 测试：见下

## 新设置、翻译键、门禁基线

- 新设置：`danmakuMaxVisibleCount`（`danmaku` 一节，跟备份和设备同步；默认 48；3.x 没有这个键，D-018 只加不改）。归属照 `docs/inventory/OWNERS.toml` 的分节默认（D05），不用加行。
- 翻译键：`danmaku_max_visible`（同屏最大弹幕条数）、`danmaku_max_visible_desc`（画面上同时飞的弹幕最多几条，默认 48；少一些更清楚、更省电）、`danmaku_max_visible_value`（{count} 条）。
- 门禁基线不变。

## 测试

- 新增 6 个用例，改了 4 个：
  - `apps/pure_live/test/shared/danmaku_overlay_test.dart` 新增“D05.2：上限 10 只飞 10 条、20 条等；调到 24 等着的进来（24 飞、6 等）；调到 12 屏上的 24 条不拿掉、新来的等”；测试工具 `_Layer.pump` 加了 `maxVisible` 参数（默认 48，和弹幕层一样）。
  - `apps/pure_live/test/features/live_play/live_play_page_test.dart` 新增“直播间改成 10、120 立即传给弹幕层”；F.2a 的用例加了“默认 48”。
  - `apps/pure_live/test/features/multiview/multiview_page_test.dart` 新增“多画面格子默认 48，改成 20 跟着变”。
  - `apps/pure_live/test/tv/tv_test.dart` 的电视直播间用例加了“默认 48，改成 30 跟着变”。
  - `apps/pure_live/test/features/live_play/live_play_popups_test.dart` 的弹幕设置面板用例：逐项标题表加了这一行；在“弹幕帧率”下面；滑条 10～120、55 段、值 48，显示“48 条”；改成 20 存进设置、显示“20 条”。
  - `apps/pure_live/test/features/settings/settings_danmaku_test.dart` 新增“设置 → 弹幕有这一行、改了是设置；搜索‘同屏’在‘弹幕 › 流畅度’下”。
  - `packages/live_store/test/danmaku_on_screen_test.dart`（新文件，2 个）：默认 48、10 和 120 能存、0/9/121/-1 读成 48、`danmaku` 一节、跟备份；备份往返、3.x 的备份没有它时保持 48 且没存值、电视版备份的 0 读成 48。
  - `packages/live_store/test/settings_defaults_test.dart`：`newInV4`、`ranges` 各加一行。
- 默认值下行为不变的证据：弹幕层的 48 条用例（D03.3 c4）没改照样通过；直播间、多画面、电视在没设过时都是 48。
- 全部通过的范围：`packages/live_store` 全部；`apps/pure_live` 改到的 7 个测试文件和 `settings_page_test.dart`（说明不超过 40 个字）；最后跑 `tools/gate/gate.sh --all`（结果写在 V01.3 的实现任务 D03.4 的记录里，两个任务同一次门禁）。

## 真机上要看的

K90（`com.mystyle.purelive.v4dev`，每次点按前确认前台是测试包）：

1. 覆盖安装后先不改设置，进哔哩哔哩或斗鱼一个弹幕多的热门直播间，横屏全屏看 30 秒：弹幕多少和装这个版本之前一样。
2. 全屏里点画面调出控制层 → 点“弹幕设置”按钮 → 面板拉到最下面的“流畅度”：“弹幕帧率”下面有“同屏最大弹幕条数”，右边写“48 条”。
3. 把滑条拉到最左（10 条）：右边写“10 条”；关掉面板看 30 秒：画面上同时飞的弹幕明显少（数一下，不超过 10 条），已经在飞的那些先照常飞完。
4. 再打开面板拉到最右（120 条）：关掉面板看 30 秒，弹幕明显比第 3 步多，画面不卡（不卡顿、不掉帧）。
5. 竖屏（退出全屏）下打开直播间下方的“弹幕设置”标签：同一行显示刚才的“120 条”。
6. 返回首页 → 设置 → 弹幕：“流畅度”里同一行也是“120 条”；设置页顶上的搜索框输入“同屏”：搜到“同屏最大弹幕条数”，路径是“弹幕 › 流畅度”，下面写着说明。
7. 多画面：首页进多画面，加一个热门直播间，开这一格的弹幕：弹幕多少跟着设置变（拉到 10 时明显少）。
8. 小窗不受影响：设置 → 弹幕 →“小窗弹幕”的“最大同时显示数量”还是原来的值（默认 6）；开“离开直播间时小窗播放”后回首页，小窗里的弹幕条数和以前一样。
9. 把同屏条数拉回 48；设置 → 备份与恢复 → 导出一份备份，再导入：同屏条数还是 48（中间改成 30 再导入，回到导出时的 48）。
