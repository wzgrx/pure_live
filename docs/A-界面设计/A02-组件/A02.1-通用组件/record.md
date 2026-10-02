# A02.1 通用组件（开发记录）

- 日期：2026-10-02（云端任务 A02.1，本地 worktree；记录见 [docs/A-界面设计/A02-组件/A02.1-通用组件/record-2.md](record-2.md)）
- 设计：[docs/A-界面设计/A02-组件/A02.1-通用组件/README.md](README.md)（已确认，C1～C4 按 A）
- 组件都在 `packages/live_ui`；各页面只替换成统一组件。直播间（`features/live_play/`）按协调人的要求没动。

## 组件和设计的对应

| 设计编号 | 组件（`live_ui`） | 说明 |
|---|---|---|
| c2～c7 状态页 | `AppStatusView`（`status_view.dart`） | 五种类型：加载、空、出错、受限（`restricted`，锁 + “前往登录”）、离线（`offline`，“没有网络连接”）；三种场合：整页、区块（`compact`：32 图标、不带圆圈、次要色）、卡片封面（`isMini`）；画面上沿用 A07.7 的 `VideoStateView`。圆圈 80 实色（表面容器）、图标 40 主色不透明，没有弹跳入场。加载：转圈下一句话（默认“加载中...”，可换）。出错：`details` 放原始报错，第二个按钮“详情”打开整段可选中的文字和“复制”（C4）。第一个按钮浅色实心、图标跟动作，第二个文字按钮（C1）；`busy` 时第一个按钮转圈不可点。横屏手机（窗口高 <480 且宽大于高）左图右文。骨架：`StatusSkeleton`（列表行、设置行，静态）；卡片用 A09.1 的 `RoomCardSkeleton` |
| c8 页顶横幅 | `StatusBanner`（`status_banner.dart`） | 说明（浅色条 + ⓘ，最多两行、点开看全文）、提醒（暖色，移动流量）、出错（错误容器色，“重试”“详情”和 ✕）；按钮在文字下面，✕ 点击区域 48 |
| c9 头像 | `CommonAvatar` | 加载中表面容器色；没头像次色容器底 + 首字（字号 0.42、600）；没名字人形图标；加载失败同没头像；给了 `onTap` 时悬停变暗 10%、按下 18%、键盘焦点框、可带 `tooltip` |
| c10 计数 | `CounterControl`、`CountButton`（`count_button.dart`） | A07.6 的描边样式：框 36 高、圆角 12、`outlineVariant`，每半边点击区域 48；数字主色 600 等宽；到上下限那一半变灰；不可用整体变灰不消失；长按半秒后每 100 毫秒一次，松手不多加一次；有焦点时 ← → 加减。`SettingsCounterRow` 和弹幕面板的计数行都用它 |
| c11 二维码 | `QrCodeWidget`（圆角 12、白底黑码）、`QrCodeCard` | 卡片（表面容器低、圆角 16）里放码；加载、已扫描、已失效（按钮“刷新”）、出错（按钮“重试”）、处理中、完成都盖在码上，码的位置不动；深色主题也是白底 |
| c12 标签 | `TabLabel`、`SecondaryTabBar`（`tab_label.dart`）；主题 `tabBarTheme` | 标签可带数量（等宽 13）和角标；悬停、按下只亮标签自己那一块（圆角 8）；键盘焦点框；二级标签 14 号、选中深色 600、指示条铺满、下面一条线、从左排 |
| c13 芯片 | `AppChip`（`app_chip.dart`，就是一个 `ChoiceChip`）；主题 `chipTheme` | 36 高（点击 48）、圆角 8、14 号；选中次色容器 + 勾（勾占平台图标的位置），未选 `outlineVariant` 描边；所有 Material 芯片通过主题同样子 |
| c14 开关 | （Material 3 默认） | 没有页面再写 `activeThumbColor`；测试锁住主题不覆盖滑块颜色 |
| c15～c17 行 | `SettingsRow` 一族（A11.1）、`ListTile` 主题 | 组标题 13/600 主色；卡片表面容器低、圆角 16；行标题 15 号 **400**（C3）；说明 12 号次要色（≥4.5:1）；选择行值 + ⌄（`SettingsLinkRow(choice: true)`，C2），跳转行 › 次要色 24；开关处理中：转圈在开关左边、开关变灰。列表行主题：标题 15/400、说明 12 次要色、图标次要色、最少 56 高、选中次色容器 |
| c18 | `readableContentMaxWidth`（720） | 960 的 `settingsContentMaxWidth` 和 3.x 的设置构建函数一起删掉 |
| c19 | （A03.1 的 `AppRefreshView`） | 只检查：没有 `RefreshIndicator`，能下拉刷新的列表都用它 |
| c20 回到顶部 / 底部 | `ScrollJumpButtons`（`jump_buttons.dart`） | 看起来 40 圆形、点击 48；表面容器最高色 + 浮层阴影；悬停、键盘焦点框 |
| c21 状态 | `FocusRing`（`focus_ring.dart`）、`FocusFrame`（主题） | 键盘焦点框 2 像素主色，只在用键盘时显示：主题里的实心、描边、文字、图标按钮，芯片，标签，头像、计数、回到顶部 |
| 第 7 节 | `EscapeBack`（`escape_back.dart`）；`centredPageTitle`（`live_theme.dart`） | 页面 Esc = 返回（可先做页面自己的一步）；标题照 3.x 实际运行的样子：主题不设居中，3.x 自己居中的 6 页（录制中心、关注、分区、热门、观看记录、工具箱）用 `centredPageTitle` |

## 和设计不同的地方

- 转圈大小和“横屏左图右文”按窗口（窗口宽 ≥600 用 32，否则 28；区块、卡片 24。窗口高 <480 且宽大于高时横排），不是按所在区域的约束：状态页也放在 `SliverFillRemaining` 里（搜索），那里要先量子组件的高度，`LayoutBuilder` 不能回答。页面里的区块用 `compact` 表示。
- “离线”说“连上网络后会自动刷新”：列表（热门、分区房间、分区）的离线状态接了网络变化（`networkChangesProvider`），连上后自动重试；其他页面没有离线状态。
- 页顶横幅：账号页的说明（`AccountTipBanner`，带链接和多段文字）和搜索的链接横幅保持各自的样子。
- 录制清晰度芯片在直播间里（`features/live_play/`），这次没动；观看模板芯片已统一成圆角 8。
- 设置行标题从 A11.1 的 600 改成 400（A02.1 的 C3 按 A，和 A07.6 一致），所有设置页跟着变。
