# A16.2 直播间菜单的“在新窗口打开”接上 A16.1 的新窗口，补回误删的翻译键：任务书

## 背景

- 来源：[A16.1](../A16.1-桌面窗口/README.md) 的确认改动 c12：“两个入口都跟设置‘新建独立播放窗口’走；直播间菜单的叫‘在新窗口打开’，图标换成 `add_to_photos`，放在‘在哔哩哔哩打开’后面；Linux 也有”。A16.1 只做了首页菜单，直播间菜单交给 A07（[A16.1 记录](../A16.1-桌面窗口/record.md)“给其他任务的接口”），之后没人接；给它准备的 `open_in_new_window` 又被 `00f5edf18`（清理不用的键）删掉。2026-10-07 docs v2 A 组核对时登记。
- 现象（Windows）：设置 → 通用 → 关掉“新建独立播放窗口”，首页菜单里的“新建独立播放窗口”没了，但进任意直播间点右上角四宫格，第二组最后仍有“在新窗口播放此直播间”，图标是外链箭头（和上面“在哔哩哔哩打开”几乎一样）。设置行的说明却写着“首页菜单和直播间菜单里显示‘在新窗口打开’”。
- 为什么现在做：第三档（现在只做 Android，D-004；Windows 开工前做完即可）；规模小，约 1 小时。设计已确认，不用出图。
- 已经做过的：A16.1（`a44167dc2`、合并 `86ffd56f2`）：`DesktopWindow.offersNewWindow` / `openNewWindow`、首页菜单；A07.6（菜单分组 c6）。

## 目标和验收

1. 直播间菜单“在新窗口打开”只在 `DesktopWindow.offersNewWindow(settings)` 为真时出现（有桌面外壳且设置“新建独立播放窗口”开），不再看 `TargetPlatform.windows`；设置关掉后，下次打开菜单就没有这一项。
2. 文字“在新窗口打开”（`open_in_new_window`，中英文都加回），图标 `AppIcons.newPlayerWindow`（和首页菜单同一个）；位置不变：第二组最后、“在<平台>打开”后面；网络电视频道也有。
3. 点了调 `DesktopWindow.openNewWindow(room: controller.room)`，新窗口直接进这个直播间；启动失败时提示条“新窗口启动失败，请重试”（由 `openNewWindow` 给，只提示一次）。
4. `launchNewWindow`（`app/launch_args.dart:115`）删掉，没有别的调用；`startWindowProcess` 不变。
5. Android、电视上菜单里没有这一项（现在也没有，不能变）；菜单其他项、分组、顺序、键（`room-menu-<名字>`）不变。
6. 测试和门禁通过；`tools/gate/ui_baseline.json` 不增加。

## 现状（读代码得出，写文件:行）

- 菜单：`apps/pure_live/lib/features/live_play/buttons/room_menu_button.dart`：
  - `RoomMenuEntry.newWindow`（`:138`）；`roomMenuGroups({required bool iptv, required bool windows, required bool cast, …})`（`:158-180`），第二组 `if (windows) RoomMenuEntry.newWindow`（`:173`）。
  - `RoomMenuButton`（`:199` 起）的参数 `windows`（`:203`、`:214`），`build` 里把它传给 `roomMenuGroups`（`:330`）。
  - `run` 的 `case RoomMenuEntry.newWindow`（`:254-261`）：`launchNewWindow(services.store, services.cipher, room: room)`，失败时自己 `developer.log` + `AppNavigator.toast(i18n('open_new_window_failed'))`。
  - 文字和图标：`:300` `RoomMenuEntry.newWindow => (AppIcons.newWindow, i18n('open_room_in_new_window'), null)`。
- `windows` 从哪来：`layout/room_header.dart:108` `RoomMenuButton(controller: controller, windows: widget.windows)`（`live_play_page.dart:1108` 传 `_platform.windows`）；`player/player_controls.dart:374-377` `windows: actions.platform.windows`（`:73` `platform == TargetPlatform.windows`）。
- 接口（A16.1 备好的）：`apps/pure_live/lib/app/desktop/desktop_window.dart`：`newWindowLauncher`（`:80`）、`canOpenNewWindow`（`:85`）、`offersNewWindow(SettingsStore)`（`:89`）、`openNewWindow({LiveRoom? room})`（`:94-105`，失败时自己提示并返回 false）；Windows 外壳启动时 `:321` 设 `newWindowLauncher = startWindowProcess`，关窗口时 `:558` 清掉。首页的用法：`features/home/menu_button.dart:56`（`DesktopWindow.canOpenNewWindow && watchSetting(ref, Settings.enableNewWindowPlay)`）、`:84`。
- 旧接口：`app/launch_args.dart:108` `startWindowProcess`，`:115` `launchNewWindow(LiveStore store, SecretCipher cipher, {LiveRoom? room}) => startWindowProcess(room: room)`，全仓库只有 `room_menu_button.dart:257` 调它。
- 翻译：`open_room_in_new_window`“在新窗口播放此直播间”（`apps/pure_live/assets/translations/zh.json:1145`）在用；`open_in_new_window` 没有（`git show 00f5edf18 -- apps/pure_live/assets/translations/zh.json` 能看到删掉的那行“在新窗口打开”）；`open_new_window_failed`（`:1142`）在用；设置说明 `settings_new_window_desc`（`:1979`）已经是新说法。
- 图标：`packages/live_ui/lib/src/icons/app_icons.dart:68` `newPlayerWindow = Icons.add_to_photos_outlined`、`:289` `newWindow = Icons.open_in_new_rounded`。
- 测试：`apps/pure_live/test/features/live_play/live_play_popups_test.dart:860` 起“room menu: three groups in order …”（键列表里有 `room-menu-newWindow`，`:914` 断言 `roomMenuGroups(iptv: false, windows: true, cast: false)[1].last == RoomMenuEntry.newWindow`）；`apps/pure_live/test/desktop_window_test.dart:622` 起“new windows: offered with a launcher and the setting …”（接口本身）、`:692` 起首页菜单用例；`room_switch_test.dart:337`、`:348` 也调了 `roomMenuGroups`（改参数时一起改）。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/widgets/button/live_play_menu_button.dart`：`_buildItems`（`:186-208`）最后一项 `if (Platform.isWindows) … open_room_in_new_window`（`:206`），图标 `Icons.open_in_new_rounded`，和第一项“打开直播间”（`:188`）同一个；点了起新进程（`common/utils/windows_multi_instance_launcher.dart`），失败提示 `open_new_window_failed`。
- 要保留：Windows 上能从直播间菜单在新窗口打开这个直播间（[specs/UI.md](../../../specs/UI.md) 附录 A 第 15 条）；失败提示文字；`enableNewWindowPlay` 键名和默认值（开，D-018）。改动（跟设置走、改名、换图标）是 A16.1 c12 确认过的。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`（第 7 节代码规则）；`docs/specs/UI.md` 附录 A 第 15 条。
3. 本文件夹的 `README.md`；`docs/A-界面设计/A16-桌面界面/A16.1-桌面窗口/README.md`（c12、c14 和“实现和验证”）、`record.md`（“给其他任务的接口”）；`docs/A-界面设计/A07-直播间界面/A07.6-直播间弹窗/README.md`（c6 菜单分组）。

## 范围

- 可以改：`apps/pure_live/lib/features/live_play/buttons/room_menu_button.dart`；`layout/room_header.dart`、`player/player_controls.dart`、`live_play_page.dart`（只为去掉或改 `windows` 参数）；`apps/pure_live/lib/app/launch_args.dart`（删 `launchNewWindow`）；两个翻译文件（只加 `open_in_new_window`）；上面列的测试；本文件夹。
- 不能改：`DesktopWindow` 的接口和行为、首页菜单、新窗口的启动参数和共用数据（A16.1）；菜单其他项；`enableNewWindowPlay` 的键名和默认值（D-018）；不删 `open_room_in_new_window`（D-024）；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1：`roomMenuGroups` 的 `windows` 参数改名为 `newWindow`（意思是“提供新窗口”），`RoomMenuButton` 不再收 `windows`，在 `build` 里用 `DesktopWindow.offersNewWindow(ref.read(storeProvider).settings)` 算（或 `DesktopWindow.canOpenNewWindow && watchSetting(ref, Settings.enableNewWindowPlay)`，和首页一样能跟着设置重建）；两个调用处去掉 `windows:`。c2：`:300` 换成 `(AppIcons.newPlayerWindow, i18n('open_in_new_window'), null)`，两个翻译文件按键名排序加回 `open_in_new_window`（“在新窗口打开” / “Open in a new window”）。c3：`run` 里改成 `await DesktopWindow.openNewWindow(room: room)`，删掉自己的 try/catch 和提示；删 `launchNewWindow` | 见“可以改” | 验收 1～6；下面的测试 |

只有一个阶段（规模小）。

## 测试

- 改之前会失败：`live_play_popups_test.dart` 加用例“room menu: the new window follows the desktop shell and the setting (A16.1 c12)”：`DesktopWindow.newWindowLauncher = ({room}) async => opened.add(room)`（`addTearDown` 清掉），pump 直播间，打开菜单 → 有 `room-menu-newWindow`，文字“在新窗口打开”，图标 `AppIcons.newPlayerWindow`；点它 → `opened.single` 是这个直播间；关掉 `Settings.enableNewWindowPlay` 再打开菜单 → 没有这一项；`newWindowLauncher = null` 时也没有。现在的代码按 `windows` 参数（测试里是 false），所以第一步就失败。
- 改：`:914` 的 `roomMenuGroups(…, windows: true, …)` 换成新参数名；`:860` 起的用例里键列表的期望不变（测试环境没有启动器时那一项本来就不在）。
- 失败提示：启动器抛 `ProcessException` 时只出现一次“新窗口启动失败，请重试”（`desktop_window_test.dart:644` 已测接口，这里测菜单不再重复提示）。
- 界面：菜单在 393×852 竖屏和 1280×800 宽屏各打开一次，没有溢出（`live_play_layouts_test.dart` 的现有布局用例改完照样通过）。
- `apps/pure_live` 的 `i18n_test.dart`（代码里用到的键都存在、中英文键一致）通过。

## 真机验证（维护者做）

Windows 要等 X01（D-004），归 [X01.1](../../../X-多端客户端/X01-Windows/X01.1-键盘鼠标操作核对/README.md) 一起看；K90 上只看第 1 步。

| 步骤 | 期望 |
|---|---|
| 1. K90：进一个直播间，点右上角四宫格（竖屏应用栏和横屏全屏控制层各一次） | 没有“在新窗口打开”；其他项和分组不变 |
| 2. Windows：设置 → 通用“新建独立播放窗口”开；进哔哩哔哩直播间，点四宫格 | 第二组最后是“在新窗口打开”，图标和首页菜单的“新建独立播放窗口”一样，在“在哔哩哔哩打开”后面 |
| 3. 点它 | 出现第二个窗口，直接播这个直播间；原窗口接着播；第二个窗口里关注一个主播，主窗口关注页马上有（A16.1 c14） |
| 4. 关掉“新建独立播放窗口”，回直播间再打开菜单 | 没有这一项；首页菜单也没有“新建独立播放窗口” |

## 风险和注意

- `RoomMenuButton` 是 `ConsumerWidget`，用 `watchSetting` 会在设置变化时重建菜单按钮；菜单是打开时才算条目的，用 `ref.read` 也行，但测试要先改设置再打开菜单。
- `features/live_play` 引 `app/desktop/desktop_window.dart`：`features/home/menu_button.dart` 已经这样引（功能目录引 `app/` 不受“功能之间不互相引用”的门禁限制），跑一次 `python3 tools/gate/check_ui_structure.py` 确认。
- 去掉 `windows` 参数时，`RoomHeader`（`room_header.dart:26`、`:35`）的 `windows` 字段可能只剩这一个用处，一起删，别留不用的参数。
- 可能冲突的文件：`room_menu_button.dart`、`player_controls.dart`（A07.11、A07.14 在直播间控制层上的任务）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A16.2` 或本机工作区；提交信息以 `[A16.2]` 开头（英文）；不推 master。
- 提交前：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。不需要 Windows 构建（运行器没改）。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `next`、`branch`。

## 报告（中文，简洁）

c1～c3 做到没有；测试数量（改之前失败几个）；改了哪些文件；新翻译键；删掉的 `launchNewWindow` 有没有别的调用；要在 Windows 上看的；可能冲突的文件。
