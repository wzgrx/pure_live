# A08.7 小窗弹幕的颜色选择改成面板（全屏里最后一个居中对话框）：任务书

## 背景

- 来源：[A07.11 记录](../../A07-直播间界面/A07.11-直播间小问题合集/record.md)“需要维护者决定的”第 6 条（登记表 T06e.4）：全屏里还剩一个居中对话框——弹幕设置面板“小窗弹幕”一组的“统一弹幕颜色”（`showDanmakuColorDialog`）。
- 现象：横屏全屏 → 下栏“弹幕设置” → 右侧面板滑到“小窗弹幕” → 关掉“保留平台弹幕颜色” → 点“统一弹幕颜色”：屏幕中间弹出一个对话框（10 个色圈、色值输入、取消 / 保存），压在画面上，挡住正在调的弹幕；竖屏同样是居中对话框。
- 为什么现在做：第二档；规范第 7 节（直播间里的设置用面板）和 A07.11 c8（全屏里不再有居中对话框）只剩这一处。规模小。
- 已经做过的：A08.1（c10 变灰不消失、偏差 1 另做的小对话框）、A07.11 c8（全屏的其他居中对话框）。

## 目标和验收

1. 定稿 README 的待选 H1、H2（可按 D-003 用建议 A）；登记表改“已确认”。
2. 直播间里点“统一弹幕颜色”在行下面展开色板（10 个色圈 + 色值输入），再点收起；点色圈立即生效；全屏、竖屏、宽屏都在面板里，不弹对话框。
3. 当前色主色描边加勾；色圈点击区至少 48；色值输入出错写在框下，不清空。
4. “保留平台弹幕颜色”开着时行变灰、不能展开（A08.1 c10 不变）；存储键 `pipDanmakuColor` 和值的格式不变。
5. （H1 A）设置的“小窗弹幕”页用同一个展开色板，不再用 `LiveColorPicker` 对话框。
6. 测试和门禁通过；`shared/danmaku/danmaku_color_dialog.dart` 里不再用的对话框删掉（`danmakuColorSwatches`、`danmakuColorText`、`DanmakuColorChip` 留着或挪进新组件）。

## 现状（读代码得出，写文件:行）

- 直播间的行：`apps/pure_live/lib/features/live_play/danmaku/danmaku_settings_panel.dart:192-209`：`InkWell(onTap: keepColors ? null : () async { showDanmakuColorDialog(...); set(Settings.pipDanmakuColor, picked.toARGB32()) })`，子组件 `SettingRow(settingKey: 'pipColor', enabled: !keepColors, trailing: DanmakuColorChip(...))`。
- 对话框：`apps/pure_live/lib/shared/danmaku/danmaku_color_dialog.dart`：`danmakuColorSwatches`（`:8-19`，10 色）、`danmakuColorText`（`:22`）、`DanmakuColorChip`（`:26`）、`showDanmakuColorDialog`（`:66`，`showAppDialog`）、`_ColorDialogState._apply`（`:94-103`：去 `#`、6 位补 `FF`、8 位解析，失败显示 `settings_color_invalid`）、色圈 44（`:122-133`）、色值框（`:142-158`）、按钮（`:162-165`）。
- 设置的“小窗弹幕”页：`apps/pure_live/lib/features/settings/playback_tiles.dart:510-540` 的 `PipColorTile`（`needsOn` 变灰说明、`SettingsSwatch`，点开 `showColorDialog`）；`features/settings/settings_dialogs.dart:317` 的 `showColorDialog`（`LiveColorPicker`，`packages/live_ui/lib/src/widgets/color_picker.dart:73`）。
- 面板外壳：直播间里是 `RoomSidePanel`（`apps/pure_live/lib/shared/panels/side_panel.dart:24`），标签里是 `TabBarView` 的一页；两处都在滚动视图里，展开后要能滚到色板完整可见（`Scrollable.ensureVisible`）。
- 相关测试：`apps/pure_live/test/features/live_play/live_play_tabs_test.dart:300` 起的用例检查“保留平台颜色”开时颜色行 `InkWell.onTap` 为空、关掉后可点（键 `danmaku-setting-pipColor`）。

## 3.x 基线

- `git show v3.2.11:lib/modules/settings/pages/pip_danmaku_settings_page.dart`：`_colorPickerRow`（`:445`，名字 + 28 的色圈 + “#FFFFFFFF”），只在关掉保留平台颜色时出现（`:199-200`）；点开 `_showColorPicker`（`:485-499`）→ `showAppColorPickerDialog`（`lib/modules/settings/widgets/app_color_picker_dialog.dart:85`，居中对话框，`enableOpacity: false`，色板 `AppConsts.colorsNameMap`，选了就写设置）。
- 3.x 画面上的弹幕面板不带小窗弹幕（`lib/modules/live_play/widgets/video_player/video_controller_panel.dart:2206`，`includePipSettings: false`），全屏时不会出现这个对话框；4.x 按 A08.1 E1 把小窗弹幕放进了画面上的面板，才有了这个问题。
- 要保留：颜色不带透明度；选了立即生效；`pipDanmakuColor` 的键名和含义（D-018）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 4.1 节、第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 3 节第 6、7 条，第 5.4 节（点击区 48），第 7 节（面板、当前项主色加勾）。
3. 本文件夹的 `README.md`；`docs/A-界面设计/A08-弹幕界面/A08.1-弹幕列表和弹幕设置页/README.md`（c10、偏差 1）；`docs/A-界面设计/A07-直播间界面/A07.11-直播间小问题合集/record.md`（c8、第 6 条）；`docs/A-界面设计/A08-弹幕界面/A08.6-设置的弹幕页补两组/brief.md`（同一个组件会被挪到 `shared/danmaku/`）。

## 范围

- 可以改：`apps/pure_live/lib/shared/danmaku/danmaku_color_dialog.dart`（改成展开色板组件，或新文件）；“小窗弹幕”组所在的文件（A08.6 之前是 `features/live_play/danmaku/danmaku_settings_panel.dart`，之后是 `shared/danmaku/` 的新文件）；（H1 A）`features/settings/playback_tiles.dart` 的 `PipColorTile`；对应测试；本文件夹。
- 不能改：别处的颜色选择（主题色、加载样式颜色仍用 `LiveColorPicker`）；`packages/live_ui` 的 `LiveColorPicker`；3.x 的设置键名和含义；其他组的界面和逻辑；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 定稿 H1、H2（出一张横屏全屏面板展开的图，或按 D-003 用建议） | README、（出图时）`src/` | README 写清结论；登记表“已确认” |
| 2 | c1、c2、c4：直播间的“统一弹幕颜色”行展开色板 | `shared/danmaku/` 的色板组件、小窗弹幕组所在文件、测试 | 新测试通过；横屏全屏打开面板操作颜色时没有 `Dialog` |
| 3 | c3（H1 A）：设置的小窗弹幕页用同一个色板 | `features/settings/playback_tiles.dart`、`settings_catalog.dart`（需要时）、测试 | 设置页的颜色行展开同样的色板；`settings_playback_test.dart` 相关断言更新 |

每个阶段都要能单独合并（门禁通过、不留半截功能）。

## 测试

- 改之前会失败：`apps/pure_live/test/features/live_play/room_popups_test.dart`（或 `live_play_tabs_test.dart`）加“横屏全屏 852×393 打开弹幕设置面板、关掉保留平台颜色、点统一弹幕颜色：没有 `Dialog`，面板里出现 `danmaku-color-` 开头的色圈”。
- 加：点色圈后 `Settings.pipDanmakuColor` 变了、勾移到这个色圈；色值输入 `FE0302` 回车生效，输入 `XYZ` 框下出现说明且不收起；保留平台颜色开时点行不展开；色圈的点击区 ≥48（`tester.getSize`）；竖屏 393×852、宽屏 1280×800 各一个布局测试。
- 已有的 `live_play_tabs_test.dart:300` 起的用例（颜色行可点 / 不可点）照旧通过。
- 测试里的定时器至少 1 秒；不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 进直播间，横屏全屏，下栏“弹幕设置”，滑到“小窗弹幕”，关掉“保留平台弹幕颜色”，点“统一弹幕颜色” | 色板在这一行下面展开，面板滚到能看全；画面中间没有对话框 |
| 2. 点红色色圈 | 勾移到红色；进应用内小窗或画中画时弹幕是红色 |
| 3. 色值框输入 `00A2FF` 回车；再输入 `XYZ` 回车 | 前者生效（勾移到蓝色）；后者框下写“请输入 6 位十六进制颜色，例如 2196F3”，色板不收起 |
| 4. 竖屏打开同一处 | 在画面下方的面板里展开，同样的操作 |
| 5. （H1 A）设置 → 小窗弹幕 → 统一弹幕颜色 | 同样的展开色板，没有透明度 |

## 风险和注意

- 和 A08.6 改同一组设置：A08.6 会把“小窗弹幕”组挪到 `shared/danmaku/`。**先做 A08.6 再做这个**，或者两个一起做，否则会改两遍、合并时冲突。
- 展开区在 `RoomSidePanel`（可下拉关闭）里：展开时不要抢走面板的拖动手势；色值输入框弹键盘时面板内容要能滚动（竖屏面板在画面下方，空间小）。
- 不要把透明度带进来（3.x 没有；`pipDanmakuColor` 在弹幕层里按不透明色用，透明度另有“透明度”滑块）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A08.7` 或本机工作区；提交信息以 `[A08.7]` 开头（英文）；不推 master。
- 提交前：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`（登记表现在没有写阶段，开工时按上表补上）。

## 报告（中文，简洁）

H1、H2 的结论；每条做到没有；测试数量（改之前失败几个）；改了哪些文件；删掉了什么；要在真机上看的；可能冲突的文件（尤其和 A08.6）。
