# A08.7 小窗弹幕的颜色选择改成面板：记录

- 日期：2026-10-08
- 执行者：Claude（本机工作区，没有推送）
- 分支和提交：本机工作区分支，提交 `[A08.7] …`（在 A08.6 之后）
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)（H1 A、H2 A，见 README“结论”）

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 | 做了 | 新组件 `DanmakuColorPickerRow`（`shared/danmaku/danmaku_color_palette.dart`）：点“统一弹幕颜色”行在行下面展开 `DanmakuColorPalette`，再点收起，行尾 ⌄ / ⌃（`AppIcons.dropDown` / `foldUp`）；10 个色圈（当前色主色 3 像素描边加勾 `AppIcons.selected`，勾的颜色按色圈深浅取）、“#”色值框（回车或失焦生效；出错写在框下“请输入 6 位十六进制颜色，例如 2196F3”，不清空、不收起）；点色圈立即生效；不弹对话框 |
| c2 | 做了 | 色圈看起来 36、点击区 48×48，`Wrap` 按宽度换行（360 宽的面板里一行 7 个）；展开后 `Scrollable.ensureVisible`（`keepVisibleAtEnd`）让色板完整可见，系统“减少动态效果”时不做动画；色圈有悬停提示（色值）、能用 Tab 走到、回车选 |
| c3 | 做了 | H1 A：设置的“小窗弹幕”页在 A08.6 之后就是同一个组件，自然是同一个色板；设置搜索结果里的“统一弹幕颜色”行（`PipColorTile`）也改成在行下面展开同一个 `DanmakuColorPalette`，不再用带透明度的 `LiveColorPicker` 对话框 |
| c4 | 保留 | 保留平台颜色开着时行变灰、不能点、不展开（开着时如果已展开会收起）；`pipDanmakuColor` 的键和值的格式不变 |

## 根因

- A08.1 给小窗弹幕颜色另做了一个居中小对话框（`showDanmakuColorDialog`，偏差 1），没有面板式的选色组件；A08.1 E1 又把小窗弹幕放进了画面上的面板，横屏全屏时对话框压在画面中间。设置页的同一项用的是另一个对话框（`showColorDialog` → `LiveColorPicker`，带透明度）。

## 改了哪些文件

- `apps/pure_live/lib/shared/danmaku/danmaku_color_palette.dart`（新：`danmakuColorSwatches`、`danmakuColorText`、`DanmakuColorChip` 从旧文件挪来；新加 `parseDanmakuColor`、`DanmakuColorPickerRow`、`DanmakuColorPalette`）
- 删掉 `apps/pure_live/lib/shared/danmaku/danmaku_color_dialog.dart`（`showDanmakuColorDialog` 和它的对话框不再用）
- `apps/pure_live/lib/shared/danmaku/pip_danmaku_settings.dart`（颜色行换成 `DanmakuColorPickerRow`）
- `apps/pure_live/lib/features/settings/playback_tiles.dart`（`PipColorTile` 展开色板）
- 测试：`test/shared/danmaku_color_palette_test.dart`（新）、`test/features/live_play/room_popups_test.dart`、`test/features/settings/settings_playback_test.dart`

## 新设置、翻译键、门禁基线

- 新设置：无。新翻译键：无（`settings_color_hex`、`settings_color_invalid` 是已有的；对话框的“保存”键不删，D-024）。门禁基线不变。
- `showColorDialog`（设置）仍给主题色、加载样式颜色用，没动；`LiveColorPicker` 没动。

## 测试

- 新增 9 个：`danmaku_color_palette_test.dart` 5 个（点行展开 / 收起、没有对话框、10 个色圈和色值框；点色圈立即生效、勾和描边移过去、点击区 ≥48；色值 `00A2FF` 回车生效、`XYZ` 和 `12345` 框下出说明、不清空、不收起、只生效一次；变灰时点不开；色值解析）；`room_popups_test.dart` 3 个（横屏全屏 852×393、竖屏 393×852、宽屏 1280×800：打开弹幕设置面板、关保留平台颜色、点统一弹幕颜色 → 没有对话框、色板在面板里且完整可见，点红色写进设置）；`settings_playback_test.dart` 1 个（设置的小窗弹幕页和搜索结果里的行都展开同一个色板）。
- 已有的 `live_play_tabs_test.dart` 颜色行可点 / 不可点的用例没改，照样通过。
- 改之前失败：`room_popups_test.dart` 3 个（找到 `Dialog`）、`settings_playback_test.dart` 1 个；色板组件的测试和组件一起写的。
- 全部通过：`apps/pure_live` 全部 `flutter test`；`dart analyze --fatal-infos`、格式、`check_ui_structure.py`、`docs.py --check`。

## 真机上要看的

1. 进直播间，横屏全屏，下栏“弹幕设置”，滑到“小窗弹幕”，关掉“保留平台弹幕颜色”，点“统一弹幕颜色”：色板在这一行下面展开，面板滚到能看全；画面中间没有对话框。
2. 点红色色圈：勾移到红色；进应用内小窗或画中画时弹幕是红色。
3. 色值框输入 `00A2FF` 回车：生效（勾移到蓝色）；再输入 `XYZ`（键盘上只能打进 0-9、A-F）或 5 位数回车：框下写“请输入 6 位十六进制颜色，例如 2196F3”，色板不收起。
4. 竖屏打开同一处：在画面下方的面板里展开，键盘弹出时面板内容能滚动，同样的操作。
5. 设置 → 小窗弹幕 → 统一弹幕颜色：同样的展开色板，没有透明度；设置里搜“小窗 颜色”，结果里那一行点开也是同样的色板。

## 可能和别的任务冲突的文件

- `shared/danmaku/pip_danmaku_settings.dart`（A08.6 新建）；`features/settings/playback_tiles.dart`（A04.1）。

## K90 复查（2026-10-08，master 660b488b7）

- 横屏全屏 → 弹幕设置 → 小窗弹幕 → 关掉“保留平台弹幕颜色”后点“统一弹幕颜色”：面板里就地展开 10 个色圈和“颜色代码”输入框，当前色描边加勾，没有对话框 ✓。
- 小毛病：行尾写 `#FFFFFFFF`（带透明度的 8 位），输入框提示是 `RRGGBB`（6 位），写法不一致，没改。
