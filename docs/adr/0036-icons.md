# 0036 图标：Material Symbols Rounded 的语义目录、轴的落实和发布包裁剪的验证

- 状态：已接受
- 日期：2026-09-28

## 背景

principles §2.6 定了全部图标用 Material Symbols Rounded 可变字体，并写了四个轴、尺寸和自绘图标的规则。2026-09-28 设计复核（R4）时应用和 `live_ui` 仍有约 350 处 Material Icons（`Icons.*`），没有用任何可变轴；搜索页签选中时换成另一个图形（`saved_search`）；展开宽度和全屏的控制层图标仍是 24dp。实现时还要决定几件长期影响代码的事：图标怎么命名和传递、光学尺寸怎么跟着显示尺寸走、Symbols 没有的图标怎么画、Material 自带控件里的默认图标怎么办、发布包的图标裁剪（#183381）怎么验证。

## 决定

1. **一个语义目录 `LiveIcons`（枚举），一个显示组件 `LiveIcon`，都在 `live_ui`。** 每个值按含义命名（`follow`、`danmaku`、`mute`），对应一个 `Symbols.*_rounded` 字形或一个自绘字形；应用只写 `LiveIcon(LiveIcons.x)`，不再出现 `Icons.*`、`Symbols.*`、`IconData` 或普通 `Icon`。`live_ui` 的 README 有完整对照表，测试保证表和枚举一致、每个值都被用到。
2. **轴的来源**：
   - 主题的 `IconThemeData` 给默认值：FILL 0、wght 400、GRAD 浅色 0 / 深色和纯黑 -25、opsz 24（TV 32）。颜色沿用 Material 的默认对象，图标按钮仍把它当“未设置”。
   - `LiveIcon` 把 opsz 设为实际显示尺寸（20–48 之间取值）；`filled` 决定 FILL。部分 Material 组件（导航轨）会整个替换图标主题，这时 wght 和 GRAD 回退到主题值，深色下不会丢掉 -25。
   - 开关只改 FILL，不换字形：导航当前项、弹幕开、已关注、静音中、仅听声音、聊天栏、剧场、锁定、提醒、默认平台、预约录制、显示密码。静音按钮的字形是 `volume_off`，静音时实心。播放 / 暂停、进入 / 退出全屏这类“动作”图标仍按动作换字形。
   - 画面上的控制层用 `VideoControlIcons`：wght 500；GRAD 在所有主题下都是 0，因为画面上的控件在所有主题里外观相同（§2.2 的白字加 60% 黑），而 -25 会抵消 500 带来的加粗；尺寸在全屏和展开宽度以上 32、以下 24。直播间的上下栏、锁定键、画面提示、仅听声音和未开播的封面、多画面的格子和大格控制条、TV 直播间的信息栏、应用内小窗和桌面画中画窗口都在这一层里。
3. **尺寸**：列表和工具栏 24；密集信息 20；按钮和标签旁的图标由主题统一为 20（Material 默认 18 低于 Symbols 最小的光学尺寸 20），TV 上 24；TV 独立图标 32（含导航轨）；画面中间的状态图标 40 或 48；嵌在文字徽标里的图标（封面上的人数、全屏时钟旁的电量、多画面名字前的声音）跟随文字大小。
4. **自绘图标用路径画，按 Symbols 的笔画模型取线宽。** Symbols 没有弹幕图标（`subtitles` 表示字幕），`danmaku` 是 24dp 网格上的屏幕外框加三行错开的文字线，外框外角半径 2、内角直角、线帽圆头，实心时文字线从实心屏幕里挖出。线宽由 `symbolStroke` 按 wght、GRAD、opsz 计算：模型取自字体本身（`remove` 字形在 wght 400/500、GRAD 0/-25、opsz 20–48 下的实测，误差小于 0.01），所以自绘图标和同一行的字体图标一样粗细。放弃把它做成字体：要同时做出四个轴的母版，工作量和维护成本都高。
5. **Material 自带控件的默认图标**：主题的 `ActionIconThemeData` 接管返回、关闭、抽屉按钮；分段按钮的对勾由主题给 `LiveIcons.check`；`CheckedPopupMenuItem` 的对勾写死为 Material Icons，换成 `live_ui` 的 `CheckedMenuItem`；弹出菜单按钮都显式给 `LiveIcons.more`；展开列表项自带箭头；三个可排序列表关掉默认拖动柄（桌面上它会多画一个 Material 的拖动柄），用自己的拖动柄，触屏上长按整行拖动。截图测试不再加载 Material Icons 字体，画面上出现 Material Icons 字形就失败。
6. **发布包的图标裁剪按工具链逐版验证，而不是关掉。** #183381 的修复 PR #183857（保留可变字体的全部字形）因为包体增大被 #184147 撤回，真正的修复是 Flutter 升级 HarfBuzz。`live_ui/test/icon_subset_test.dart` 用当前 SDK 自带的 `font-subset`（`flutter build` 做裁剪用的同一个工具）按目录里全部字形裁剪 Rounded 字体，逐个比较裁剪前后在 FILL 0/1、GRAD 0/-25、wght 400/500 下的像素：Flutter 3.47.5 上完全一致，所以不关闭裁剪。以后升级 SDK 时这个测试先报出回归。`material_symbols_icons` 自己引用了一次 Outlined 和 Sharp 字体，发布构建会把它们也裁到几 KB，不需要额外处理。

## 备选方案与放弃理由

- **`IconData` 常量表加普通 `Icon`**：光学尺寸要在每个调用处手写，容易漏；自绘图标也放不进 `IconData`（它是 final 类）。枚举加组件让漏写在编译期就发现。
- **`VariedIcon.varied` 和按字体族设置的全局默认值（包里自带）**：全局可变状态，和主题、局部覆盖是两套机制。
- **控制层 GRAD 跟随主题**：同一个控制层在浅色和深色主题下粗细不同，而 wght 500 的目的（复杂画面上更清楚）会被 -25 抵消。
- **`--no-tree-shake-icons`**：四个图标字体全部原样进包，Rounded 15.1 MB、Outlined 10.6 MB、Sharp 8.8 MB、Material Icons 1.6 MB，共 36.2 MB（APK 内压缩后约 16.2 MB），而裁剪后只有几十 KB。只在 SDK 回归、且无法等修复时作为临时开关。
- **按钮图标保持 Material 的 18dp**：低于最小光学尺寸，Symbols 在 18 上只能把 20 的设计缩小；和 M3 Expressive 小按钮的 20dp 一致。

## 影响

- 依赖：`live_ui` 加 `material_symbols_icons` 4.2960.0（Apache-2.0）。调试包含完整的三个字体（约 34.5 MB 资源），发布包只含用到的字形。
- 规格：principles §2.6 加实现细则，风险一条改为实际情况（修复在 HarfBuzz 升级里，3.47.5 已验证裁剪工具）。
- 测试：`apps/pure_live/test/icons_lint_test.dart` 扫描应用和 `live_ui` 的 `lib/`；截图测试检查 Material Icons 字形；`live_ui` 有轴、目录、笔画模型、裁剪的测试和两张图标 golden（`icon_axes.png`、`icon_catalog.png`）。
- 待统一构建验证：release 包里图标字体确实被裁剪（构建日志的 “Font asset … was tree-shaken”），真机上开关图标的实心和空心、深色主题的 GRAD、控制层 32dp 都显示正确；见 STATUS。
