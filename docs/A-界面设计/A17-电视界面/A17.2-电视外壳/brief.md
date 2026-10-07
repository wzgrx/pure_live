# A17.2 电视外壳：任务书

## 背景

- 来源：界面重做的电视部分（旧编号 U.15b、T18a.3）。设计第 1 版 2026-10-01 出图评审，用户同意全部电视设计（“后续全部通过”，确认记录 `422b69576`），待选 B1～B4 按建议 A（D-003）。设计正文在本文件夹 [README.md](README.md)（c1～c11、按钮编号 1～61、焦点路线），评审页导出在 `page/`。
- 现象（现在的电视首页，`apps/pure_live/lib/tv/home/tv_home_page.dart`，X03.1 做的）：导航栏一直展开、固定 200 宽，名字是“推荐、历史”等，和手机不同；没有模式按钮，视频、音乐、壁纸三项写成“建设中”占位不显示；按返回键是提示“再按一次返回键退出”，没有退出确认；第一次启动没有使用须知；新版本用的是手机的对话框（手机样子，没有电视焦点样式）；没有启动解锁。
- 为什么现在做：第三档。客户端顺序 Android → Windows → 电视（D-004），电视阶段开工时第一个做：A17.6、A17.7 要从这里的模式按钮进，A17.3 的页面要放进这里的导航轨，A17.9 的“导航栏显示控制”编辑的就是这里的入口。
- 已经做过的：X03.1（电视外壳、焦点导航、路由，`781586ff7`，合并 `d28963a5c`）；A17.1（电视组件，合并 `727e184ad`）：`TvNavItem`、`TvDialog`、`showTvConfirm`、`showTvChoice`、`TvStatusView` 都可以直接用。
- 半成品：没有。登记表 `note` 说旧分支 M14.2～M14.5 有电视各界面的半成品，那些是直播间、点播、音乐、网页遥控的，**不含外壳**（外壳只有 `TvPane` 里的三个占位，在 master 上）。

## 目标和验收

1. （c2）导航栏平时收起，只显示图标，选中项主色容器底；焦点移进导航栏时展开显示名字，**盖在页面上**（页面不动、压暗）；焦点回到页面时收起。新设置“导航栏始终展开”打开时一直展开、页面右移。
2. （c3、c4）每个入口只有一个名字，和手机一致：关注、热门、分区、关注分区、链接放映、搜索、观看记录、设置；图标和手机一致（README c4 列出的 `Remix.*`、`CustomIcons.search`，选中用实心），用户在 A17.9 换过的图标照样生效。
3. （c5）导航栏有自己的底色（表面容器低）和右边一条分隔线（现在已有，收起和展开时都保持）。
4. （c6）导航项上按 OK 切换并进入页面（回到上次那一项），按右也进；页面最左一列按左回到导航栏当前项；启动时焦点在页面第一项，页面还没加载出来时在导航栏当前项。
5. （c1、c7）导航栏最上面是模式按钮（直播 / 视频 / 音乐），OK 打开通用选择框“选择模式”：当前模式主色字加勾、焦点在当前项、标题下写“切换后，正在播放的音乐会停止”；切换后导航栏换成那个模式的入口。只有直播一种模式可用时（A17.6、A17.7 还没合并）不显示模式按钮。
6. （c8，B1 A）首页按返回键（焦点在导航栏时）弹退出确认：左右排，左边感谢和捐赠说明、右边二维码；按钮“取消 / 退出”，默认焦点在“退出”，返回键 = 取消；“退出”结束应用。
7. （c9，B4 A）启动检查发现新版本时，弹手机 A06.3 同一个新版本对话框的电视样式：标题写新版本号、下一行当前版本、“更新内容”、“不再提醒这个版本”、“取消 / 下载并安装”（默认焦点）、“其他下载方式”；“下载并安装”在应用里下载安装包，进度用 A06.3 下载对话框的电视样式；每次运行只弹一次。
8. （c10）第一次启动先进协议页：标题“使用须知”，正文放在浅底框里、最宽 720，正文超出一屏时上下键滚动正文（焦点留在按钮上）、底部渐隐提示还有内容；按钮“已阅读并同意”（默认焦点，以后不再出现）和“退出”。
9. （c11）启动解锁（有哔哩哔哩账号设了密码锁时）：账号卡片用统一焦点；只有一个账号时直接到输入页；输入页写清“用方向键 ↑ ↓ ← → 输入密码，按 OK 确认；返回键删一位，删完回到选择账号”；密码用圆点显示；错误用错误色加图标。**前提**：4.x 有哔哩哔哩多账号和账号密码锁（现在没有，见“现状”），前提不满足时这一条记为“不适用”，写进 record.md。
10. 手机界面一点不变；`flutter test` 全部通过；`tools/gate/ui_baseline.json` 不增加（`tv` 直接写的颜色和图标保持 0）。

## 现状（读代码得出，写文件:行）

- 首页：`apps/pure_live/lib/tv/home/tv_home_page.dart`（462 行）。
  - `TvPane`（`:28-77`）：十个目的地，`video`、`music`、`wallpaper` 是 `available: false`（`:48`、`:51`、`:54`），`menu`（`:71`）去掉不可用的和设置。目的地名字的键 `tv_menu_*`。
  - 导航栏（`build` `:320` 起）：`Container` 宽 `scale.pxText(200)`（`:338`），底色 `palette.low` 加右边 `palette.divider`（`:340-341`），时钟 `_Clock`（`:411`）、入口列表（`:354`）、最下面设置（`:358`）；入口是 `TvNavItem`（`apps/pure_live/lib/tv/widgets/tv_nav_item.dart:9`，图标加名字、选中主色容器底），`_menuItem`（`:395`）。没有收起状态。
  - 焦点：启动时 `_menuNode(_pane).requestFocus()`（`:158`），焦点在导航栏（设计要在页面第一项）；`_select`（`:260`）切换后下一帧 `_enter`（`:248`），已经是“切换并进入”；`_menuKey`（`:301`）右键进入；`_remember`（`:214`）让页面最左一列按左回到选中的入口。
  - 返回：`_back`（`:276`）：页面自己的一层 → 导航栏 → 提示 `tv_press_back_again`，2 秒内再按 `moveToBack`（`:293`，退到后台，不结束）。
  - 新版本：启动 2 秒后 `checkForUpdateOnStartup`（`:176`，`apps/pure_live/lib/features/version/update_prompt.dart:34`），弹的是手机的 `NewVersionDialog`（`update_prompt.dart:108`）和下载对话框 `UpdateDownloadDialog`（`features/version/update_download.dart:191`），样子是手机的，没有电视焦点描边；“不再提醒这个版本”已有设置 `skippedUpdateVersion`（`packages/live_store/lib/src/settings/settings.dart:49`）。
  - 恢复后刷新（`didChangeAppLifecycleState` `:188`）、命令行房间（`:160`）要保留。
- 路由：`apps/pure_live/lib/routes/tv_router.dart` 根路径是 `TvHomePage`；没有协议页路由。手机启动页 `features/splash/` 不在电视路由的起点（`app/app.dart:118-120` 的 `splashInitialLocation`）。
- 手机的入口顺序：`savedMenuIds`（`settings.dart:95`）、`HomeMenu`（`features/home/home_menu.dart:6`）、编辑界面 `HomeMenusList`（`features/settings/appearance_pages.dart:1176`）。电视没有自己的入口设置。
- 4.x **没有**：协议页、捐赠文字和二维码（翻译文件和 `assets/` 里都没有）、哔哩哔哩多账号（只有一份 Cookie；多账号是提议 [V01.2](../../../V-需求和反馈/V01-新功能提议/README.md)，来自 pure_live_TV `6ba16c55`）、账号密码锁。
- 测试：`apps/pure_live/test/tv/tv_test.dart` 的“首页焦点”用例断言启动焦点在“关注”入口、左两次回到选中的入口、返回两次提示退出——这几条照设计要改。

## 3.x 基线

- 3.x 没有电视界面（只在清单声明了 `LEANBACK_LAUNCHER`，`git show v3.2.11:android/app/src/main/AndroidManifest.xml` 第 63 行）。基线是 pure_live_TV（`~/ref/pure_live_TV`，设计用提交 `b9d2f739`，本机副本现在是 `37660afc`）：
  - 首页 `lib/features/home/home_page.dart`（导航栏 `:352-513`、宽 160/228 `:321`、模式按钮 `:48-67`、直播目的地 `:141-211`、OK 只切换 `:156`、返回弹退出 `:343-348`）、`home_provider.dart:119-186`（入口、短名、图标、导航栏显示控制）、`core/widgets/tv_icon_button.dart:226-231`。
  - 退出确认 `lib/features/home/exit_confirm_dialog.dart`（`:15-57`）；新版本 `home_update_dialog.dart`（`:10-135`）；协议页 `lib/features/agreement/agreement_page.dart`（`:26`、`:61-76`）；启动解锁 `lib/features/settings/pages/widgets/account_lock.dart:338-639`。
  - 要保留（c1）：首页结构（时钟、模式按钮、目的地、最下面设置）；目的地和顺序由“导航栏显示控制”决定、至少留一个、可换图标；访问过的页面保留状态；切走音乐模式时停音乐；新版本每次运行只弹一次；第一次启动的协议页；启动解锁的流程和按键（↑↓←→ 组成密码、OK 确认、返回删一位）。
- 开工前先看 `b9d2f739..37660afc` 之间这些文件有没有改（本机 `~/ref/pure_live_TV` 里 `git log b9d2f739..HEAD -- lib/features/home lib/features/agreement lib/features/settings/pages/widgets/account_lock.dart`）；改了的照新代码理解行为，设计不改。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 8 节合并审查、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`（第 5 节：pure_live_TV 是 AGPL-3.0，借鉴代码注明来源仓库和提交）；`docs/specs/UI.md` 第 5.5 节（导航轨收起、焦点进入时展开）、第 7 节（弹窗）。
3. 本文件夹的 `README.md`（c1～c11、按钮作用、焦点路线、拿不准的地方）和 `page/` 的导出图。
4. `docs/A-界面设计/A17-电视界面/A17.1-电视设计系统和通用组件/README.md` 和 `record.md`（组件、偏差 5：导航项放大由本任务定）；`docs/X-多端客户端/X03-电视/X03.1-电视外壳和焦点导航/record.md`（焦点方案、返回逐级退出）。
5. `docs/A-界面设计/A06-首页和全局/A06.3-全局弹窗/README.md`（新版本和下载对话框）；`docs/A-界面设计/A06-首页和全局/A06.1-手机首页/README.md` 的 X3（分区图标）。
6. 代码：`apps/pure_live/lib/tv/home/tv_home_page.dart`、`tv/widgets/tv_nav_item.dart`、`tv/widgets/tv_dialogs.dart`、`routes/tv_router.dart`、`features/version/update_prompt.dart`、`update_download.dart`、`test/tv/tv_test.dart`。

## 范围

- 可以改：`apps/pure_live/lib/tv/home/`、`tv/widgets/`（加导航轨、模式选择、退出确认、协议页需要的组件）、新文件 `tv/home/tv_agreement_page.dart` 等、`routes/tv_router.dart`（协议页路由）；`features/version/` 里新版本和下载对话框（只为了能换电视样式，例如把内容和外框拆开，手机样子不变）；`packages/live_store`（只加设置：电视入口和顺序、导航栏始终展开、已同意使用须知）；`packages/live_ui` 的 `TvIcons`（只加）；翻译文件（只加键，中英都有，按键名排序）；`test/tv/`；本文件夹。
- 不能改：手机首页和手机设置的样子和行为；手机的 `savedMenuIds` 的含义（D-018）；A17.3 的页面内容（这里只管把它们放进导航轨）；版本号、`assets/version.json`、`assets/releases.json`；签名配置；原生代码（`moveToBack`、`isTelevision` 已有，结束应用用 `SystemNavigator.pop()` 或已有通道，不要新加原生方法，确实需要时先问维护者）。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 准备：核对 pure_live_TV 设计基线之后的变化；定下面“需要维护者决定的”第 1、2 条（可按 D-003 用建议） | record.md | record.md 写清结论 |
| 2 | 导航轨（c2～c6）：收起 / 展开（焦点进入时展开、盖在页面上、页面压暗）、名字和图标照手机、启动焦点在页面第一项；新设置“导航栏始终展开”（默认关）和电视入口列表（默认全部、至少一个）；`TvPane` 改名（推荐 → 热门、历史 → 观看记录），“关注分区”“链接放映”两个入口先接到 A17.3、A17.5 做好前的现有页面或不显示（写清） | `tv/home/tv_home_page.dart`、`tv/widgets/tv_nav_item.dart`、`live_store` 设置、`TvIcons`、翻译、`test/tv/tv_test.dart` | 首页焦点用例照新规则改完并通过；新加：收起时只有图标、焦点进入展开且页面不重新布局、“始终展开”打开时页面右移、启动焦点在页面第一项、页面没加载出来时在导航栏 |
| 3 | 模式按钮和选择模式（c7）：组件和测试做好，只有直播模式可用时不显示按钮；退出确认（c8）：首页返回键弹退出确认，“退出”结束应用 | `tv/home/`、`tv/widgets/tv_dialogs.dart`（或新文件） | 新加：两个模式时显示按钮、选择框焦点在当前项、切换后入口换掉；退出确认默认焦点“退出”、返回键 = 取消、“退出”调用结束 |
| 4 | 新版本和下载（c9）：电视界面里新版本、下载对话框用电视外框和焦点（内容同 A06.3）；协议页（c10）：第一次启动进协议页 | `features/version/update_prompt.dart`、`update_download.dart`（拆内容和外框）、`tv/home/`、`routes/tv_router.dart`、`live_store`（已同意） | 新加：电视上新版本对话框按钮顺序和默认焦点、“其他下载方式”打开版本页；协议页第一次出现、同意后不再出现、正文超长时上下键滚动、“退出”结束；手机 `features/version` 的测试不改断言照样通过 |
| 5 | 启动解锁（c11）：前提满足时做；不满足时写进 record.md 并在登记表 `note` 建议拆成新任务等 V01.2 | `tv/home/` 或新文件 | 前提满足：选择账号、输入、错误、只有一个账号跳过选择的用例；不满足：record.md 写明 |

每个阶段都要能单独合并（门禁通过、不留半截功能）。登记表现在的阶段是“设计 ✓ → 开发 → 真机”，开工时把“开发”按上表拆开写进 `stages`。

## 测试

- 改之前会失败：`apps/pure_live/test/tv/tv_test.dart` 加“启动后焦点在页面第一项，导航栏收起只显示图标”（现在焦点在导航栏、导航栏展开）。
- 要加或改的测试（都在 `test/tv/`，可以新开 `tv_shell_test.dart`）：
  - 导航轨：收起宽度、只有图标；焦点移进去展开、页面的 `RenderBox` 位置不变（盖在上面）；“始终展开”时页面左边界右移；OK 切换并进入、回到上次那一项；最左一列按左回到当前项。
  - 模式：两个以上模式时有按钮；选择框焦点在当前项；切换后入口列表变化；只有直播时没有按钮。
  - 退出：首页焦点在导航栏时按返回弹确认；默认焦点“退出”；返回键关掉确认、留在首页。
  - 新版本：注入一个假的 `UpdateFeed`（照 `test/features/version/` 已有的写法），电视界面里弹出的对话框有“不再提醒这个版本”“其他下载方式”，默认焦点在“下载并安装”；同一次运行不再弹第二次。
  - 协议页：第一次启动进协议页，同意后到首页，重启（重建应用）后不再出现；正文超长（文字放大 160%）时下键滚动正文、焦点不离开按钮。
- 1080p@2x（960×540 逻辑）和 720p（`devicePixelRatio = 1`，1280×720）各一个布局测试：导航栏收起、展开都不出屏，文字不小于 14。
- 测试里的定时器至少 1 秒（D-017）；不访问真实平台、不访问 GitHub（假的 feed）。

## 真机验证（维护者在电视或盒子上做）

需要一台 Android 电视或电视盒子（遥控器有 OK、返回、方向键，最好有菜单键）；没有时在 K90 上把“界面模式”改成“电视”、接蓝牙键盘粗看，结论写明“不是电视”。

| 步骤 | 期望 |
|---|---|
| 1. 第一次装好后打开 | 先是“使用须知”，焦点在“已阅读并同意”；按下键正文往下滚 |
| 2. 点“已阅读并同意”，退出再打开 | 直接到首页，不再出现须知 |
| 3. 首页不动 | 导航栏收起只有图标，焦点在页面第一张卡片 |
| 4. 在第一列按左 | 导航栏展开显示名字，盖在页面上、页面变暗不移动；焦点在当前入口 |
| 5. 上下走到“热门”按 OK | 切到热门并进入页面；再按左回到“热门” |
| 6. 设置里打开“导航栏始终展开” | 导航栏一直展开，页面往右让出位置 |
| 7. 焦点在导航栏时按返回 | 退出确认，左边感谢、右边二维码；返回键关掉；点“退出”应用结束（最近任务里也没有） |
| 8. 有新版本时（或维护者在测试包里指向测试 feed） | 电视样式的新版本对话框，焦点在“下载并安装”；下载进度对话框能取消 |
| 9. （有视频或音乐模式后）导航栏最上面的模式按钮 | 选择框焦点在当前模式；切到视频后入口换成视频的 |

## 风险和注意

- 导航轨展开时“盖在页面上”：用 `Stack` 叠在页面上面，页面宽度不能变（否则 4 列网格每次展开都重排、丢焦点）；压暗层不能拦截焦点。
- 焦点进入导航栏的判断目前在 `_remember`（`FocusManager` 监听），展开 / 收起要跟它走，避免和几何导航互相抢（X03.1 记录“焦点方案”）。
- 结束应用：Android 上 `SystemNavigator.pop()` 只关 Activity；pure_live_TV 是结束进程（`exit_confirm_dialog.dart:19`）。如果后台播放、录制还在跑要先停（看 `RoomBackgroundPolicy`、录制器）——这是风险点，开工时确认，写进 record.md。
- 新版本对话框改的是手机也用的 `features/version/`：手机样子和测试必须不变；电视样式只换外框和焦点。
- 可能冲突的文件：`tv/home/tv_home_page.dart`（A17.3、A17.6～A17.9 都会加入口）、`features/version/`（Y02 更新通道的任务）、`live_store` 的 `settings.dart`。同一组同时只开一个开发（PROCESS 第 5.1 节）。

## 需要维护者决定的（开工时问，或按建议）

1. 现在电视首页有“网络电视”入口，设计的入口表（c3）里没有，pure_live_TV 的网络电视在分区里、管理在设置里。建议：保留“网络电视”一项，放在“链接放映”后面（不删现有功能）。
2. 退出确认的捐赠说明和二维码：4.x 没有这些。建议：只写感谢和项目主页（文字，不放二维码）；要放上游作者的捐赠码需维护者确认来源和授权。
3. 启动解锁的前提（多账号、账号锁）不满足时，是否从本任务拆出。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A17.2` 或本机工作区；提交信息以 `[A17.2]` 开头（英文）；不推 master。
- 提交前：改过的包（`apps/pure_live`、加设置时 `packages/live_store`、加图标时 `packages/live_ui`）跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`（或 `dart analyze`）、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`（`tv` 不能出现直接写的颜色和图标）；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；三个决定的结论；测试数量（改之前失败几个）；改了哪些文件；新设置（键名、默认值、作用域）和新翻译键；结束应用时后台播放和录制怎么处理；要在电视上看的；可能冲突的文件。
