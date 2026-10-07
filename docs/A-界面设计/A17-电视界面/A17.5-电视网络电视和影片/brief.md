# A17.5 电视网络电视和链接放映：任务书

## 背景

- 来源：界面重做的电视部分（旧编号 U.15e、T18d.1）。设计第 1 版 2026-10-01 评审确认（“后续全部通过”，确认记录 `62391fdd2`），待选 N1～N4 按建议 A（D-003）：IPTV 设置合成一页加订阅源管理（N1）、二维码只一个固定右栏（N2）、电视上提供节目单（N3）、链接放映加遥控器输入框（N4）。设计正文在本文件夹 [README.md](README.md)（c1～c14、E1～E13、焦点路线、跨任务待同步），评审页导出在 `page/`。
- 名字：登记表标题是“电视网络电视和影片”，设计 README 标题是“电视网络电视和链接放映”（pure_live_TV 的导航名“链接放映”，就是登记表说的“影片”）。下面一律叫“链接放映”。
- 设计写的时候手机的 A13.1（网络电视管理）、A15.1（工具箱）还没开始，现在都已完成：IPTV 设置、导入对话框、订阅源卡片、链接解析在手机上都有了，电视用它们的电视样式。
- 现象：电视上只有网络电视频道列表（`apps/pure_live/lib/tv/pages/tv_iptv_pane.dart`），“IPTV管理”打开手机的网络电视页（手机样子、字小、没有电视焦点描边）；没有链接放映；电视直播间里网络电视频道没有节目单和回看。
- 为什么现在做：第三档（D-004）。电视阶段里排在 A17.4（播放设置面板，节目单一行放在那里）和 A17.9（扫码到手机组件）之后。
- 已经做过的：X03.1（网络电视频道浏览和播放）；手机 A13.1（`7c6d685cb`）、A15.1（`b164796dc`）、A07.7 的节目单（`features/live_play/dialogs/iptv_guide.dart`，C01.2）。
- 半成品：旧分支 M14.2（工作区 `/home/wzgrx/projects/pure_live/.claude/worktrees/agent-af79805552a6c7d0e`，提交 `69f12f418`）的 `tv/room/tv_iptv_room.dart`（575 行）：`TvChannelPanel`（播放列表和分组在左、频道和正在播的节目在右）、`loadOnAirProgrammes`（按节目单源取每个频道正在播的节目）、电视节目单（按天，左右换天，OK 回看）。界面是重做前的样子，建在旧目录；只参考取数和按键，界面照新设计和 A07.7 组件重写。旧分支 M14.5（工作区 `/home/wzgrx/projects/pure_live/.claude/worktrees/agent-af3e4f5945df78e33`，提交 `37ef8cbf0`）的 `tv/remote/web_remote_server.dart`（348 行）、`tv_remote_actions.dart`（137 行）是手机网页遥控（扫码打开网页、推送链接或文字到电视）的半成品，链接放映和“用手机导入”要的就是它。

## 目标和验收

1. （c2、c4、c5）设置里“网络电视”是一页（分组顺序照手机 v3 / A13.1）：订阅源管理、导入播放源、导入节目单源、自动同步（开关、间隔、立即同步）、直播源请求头（一组三项）、节目单源；打开时焦点在第一行；全部叫“订阅源管理”，不再有“资源列表”“播放列表管理”。
2. （c3）二维码只有一个，固定在右栏，写清用途（用手机导入播放列表 / 填写请求头）和服务状态（启动中、已启动、出错写原因加“重试”）。
3. （c9、c8）订阅源管理单独一页：上面一行个数和“全部同步”；每个源一张卡片（名字、地址、网络 / 本地、格式），三个按钮在卡片下面：同步、自动同步（写“开 / 关”）、删除；删除先确认，焦点在“取消”、“删除”红字。
4. （c7、c10）导入用手机 A13.1 的两个对话框（选方式 → 网络地址），电视上没有“本地文件”，换成“用手机导入”（扫码）；结果用提示条，失败写原因；同名先问替换（`confirmReplace`）。
5. （c11）请求头一组三项：自定义 User-Agent（手机已有）、Referer、Cookie；对话框用手机的“修改请求头 (User-Agent)”对话框的电视样式。Referer、Cookie 是否加到手机由 A13.1 的结论定（见“需要维护者决定的”）。
6. （c6）节目单源可以导入和选择；电视直播间播放网络电视频道时，播放设置第一组多一行“节目单”，打开 A07.7 的节目单组件（`IptvGuideView`）的电视样式：正在播的一行有默认焦点，OK 回看已播的节目、“返回直播”。
7. （c12、c13）导航轨“链接放映”一页：一个遥控器输入框（OK 弹输入）、解析中和失败写在输入框下面；右边二维码（手机发送链接）和服务状态；“支持解析列表”用手机工具箱的同一份。解析成功直接进电视直播间。
8. （c14）字号大一级；页面留 48 / 28 安全边距。
9. （c1）保留全部功能：订阅源同步 / 自动同步 / 删除、热门资源地址、网络导入、手机扫码、启动时同步、间隔、一键同步、三个请求头、链接放映入口。
10. 手机界面一点不变；`flutter test` 全部通过；`tv` 直接写的颜色和图标保持 0。

## 现状（读代码得出，写文件:行）

- 电视：`apps/pure_live/lib/tv/pages/tv_iptv_pane.dart`（177 行）：`loadTvPlaylists`（`:36`，内置热门 + 导入的播放列表）、`TvIptvPane`（`:56`）；没有播放列表时“IPTV管理”按钮打开手机页（`:108-113`），右上角也有（`:165-169`，`RoutePath.kIptv`）。
- 手机网络电视（A13.1 完成）：`apps/pure_live/lib/features/iptv/iptv_page.dart`（`IptvPage` `:29`，默认节目单只加载一次 `defaultGuideMetaKey` `:42`）、`iptv_settings.dart`（同步间隔 `syncIntervalOptions` `:7` 是 2 / 6 / 12 / 24 / 48 / 72、`chooseSyncInterval` `:12`、UA 最长 500 `:29`、`editUserAgent` `:35`）、`iptv_import.dart`（`chooseImportOrigin` `:84`、`askForFilePath` `:159`、`confirmReplace` `:240`、`IptvNetworkImportDialog` `:273`、`IptvTextImportDialog` `:430`）、`iptv_cards.dart`（`IptvSourceCard` `:24`、自动同步行 `_AutoSyncRow` `:372`）、`iptv_data.dart`（`iptvOverviewProvider` `:19`、`playlistName` `:102`）。
- 设置键（`packages/live_store/lib/src/settings/settings.dart:773-797`）：`selectedSourceName`、`selectedSourceId`、`isAutoSyncEnabled`、`autoSyncHoursInterval`（默认 24）、`customIptvUserAgent`、`m3uDirectory`。**没有** Referer、Cookie 两项，也没有“热门资源地址”设置（内置地址写死在 `packages/live_iptv/lib/src/importer.dart:106` 的 `hotPlaylistUrl`）。
- 节目单：`apps/pure_live/lib/features/live_play/dialogs/iptv_guide.dart`：`loadChannelGuide`（`:19`）、`showIptvGuide`（`:57`）、`IptvGuideView`（`:78`）；手机直播间从菜单打开。电视直播间（`tv/room/tv_live_play_page.dart`）没有入口。
- 链接解析（A15.1 完成）：`apps/pure_live/lib/features/toolbox/toolbox_actions.dart`：`toolboxLinksProvider`（`:23`，`LinkParser`）、`ToolboxController`（`:45`）；页面 `toolbox_page.dart:35`。
- 局域网服务：设备同步有 `features/remote_receiver/remote_sync_service.dart`（`HttpServer` 绑定 `:192`）；**没有**给 IPTV、链接、屏蔽词用的手机网页（pure_live_TV 的网页遥控，`#/sync`、`#/movie`），旧分支 M14.5 的 `web_remote_server.dart` 是半成品。
- 电视组件：设置行 `tv/widgets/tv_settings_rows.dart`、对话框 `tv/widgets/tv_dialogs.dart`、输入 `TvTextInput`（`:386`，Android 走原生输入对话框）、`TvInputField`（`:604`）。扫码到手机的统一组件是 A17.9 c15 要做的。

## 3.x 基线

- 手机 3.x：`git show v3.2.11:lib/modules/iptv/iptv_page.dart`（`:147` 订阅源管理入口、`:201-225` 节目单源）、`iptv_manage.dart`（`:227`）；工具箱 `lib/modules/toolbox/toolbox_page.dart:140-147`（支持解析列表）。设置键名和含义照 3.x（D-018）。
- 电视基线 pure_live_TV（设计用 `b9d2f739`，本机 `37660afc`）：`lib/modules/live/iptv/pages/iptv_manage_section.dart`、`iptv_resources_section.dart`（`:105-122` 删除确认、`:162-193` 热门资源地址、`:263-317` 源的三个按钮）、`iptv_import_section.dart`（`:80-127`）、`iptv_sync_section.dart`（`:17` 间隔选项）、`iptv_headers_section.dart`（最长 2000 字）、`services/iptv_confirm_dialog.dart`；`lib/modules/live/movie_playback/movie_playback_page.dart`（`:47-77` 解析、`:184-216` 支持的平台）；二维码 `core/widgets/remote_sync_qr_card.dart`、`tv_qr_card.dart`。开工前看 `git log b9d2f739..HEAD -- lib/modules/live/iptv lib/modules/live/movie_playback`。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5、8、14 节）。
2. `docs/specs/ENGINEERING.md`（第 5 节）；`docs/specs/UI.md` 第 5.5 节。
3. 本文件夹 `README.md`（“改动”“焦点路线”“跨任务待同步”“拿不准的地方”）和 `page/`。
4. 手机：`docs/A-界面设计/A13-网络电视和多画面界面/A13.1-网络电视管理/README.md` 和 `record.md`；`docs/A-界面设计/A15-小页面/A15.1-工具箱/README.md`；`docs/A-界面设计/A07-直播间界面/A07.7-直播间的状态/README.md`（节目单）；L 组 `docs/L-网络电视和点播/L01-网络电视/README.md`、`L02-节目单和回看/README.md`。
5. 电视：`A17.4-电视直播间/brief.md`（播放设置面板）、`A17.9-电视设置/README.md`（c15 扫码到手机组件、设置目录）、`A17.1` 的 README。
6. 代码：上面“现状”列的文件；旧分支 `tv/room/tv_iptv_room.dart`、`tv/remote/` 两个文件（只读）。

## 范围

- 可以改：`apps/pure_live/lib/tv/`（新页 `tv/pages/tv_iptv_settings_page.dart`、`tv_iptv_sources_page.dart`、`tv_link_play_pane.dart` 之类）；手机 `features/iptv/` 的对话框拆出内容给电视用（手机样子不变）；局域网网页遥控如果要做，放在 `apps/pure_live/lib/shared/` 或 `app/`（和设备同步的服务分开），只加；`packages/live_store`（只加 Referer、Cookie、热门资源地址三个设置，默认空，D-018）；`packages/live_iptv`（只为让请求头带上新的两项，只加）；翻译文件（只加键）；`test/tv/`；本文件夹。
- 不能改：手机网络电视和工具箱的样子、行为和设置含义；节目单和回看的逻辑（L02）；直播间逻辑；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 设置里的“网络电视”一页和订阅源管理（c2、c4、c5、c8、c9、c14）：分组、默认焦点第一行、卡片和三个按钮、删除确认；电视首页“IPTV管理”改到这一页 | 新 `tv/pages/` 两个文件、`tv_iptv_pane.dart`、`features/iptv/` 拆分 | 新用例：分组顺序、默认焦点、卡片按钮左右走、删除确认焦点在“取消”；手机 `test/features/iptv/` 不改断言照样通过 |
| 2 | 导入和请求头（c7、c10、c11）：手机两个对话框的电视样式、“用手机导入”（服务没有时这一项先不显示）、请求头三项 | 同上、`live_store`、`live_iptv` | 新用例：网络导入成功和失败的提示条、同名替换确认、三项请求头的保存和说明 |
| 3 | 节目单（c6）：A17.4 的播放设置面板加“节目单”行（网络电视频道才有），打开 `IptvGuideView` 的电视样式；节目单源导入和选择 | `tv/room/`、`iptv_guide.dart` 的拆分 | 新用例：网络电视频道有这一行、普通直播没有；默认焦点在正在播的节目；OK 回看、“返回直播” |
| 4 | 链接放映（c12、c13）和二维码（c3）：输入框、解析中和失败、支持解析列表；局域网网页（扫码发链接、上传播放列表）——按“需要维护者决定的”第 2 条 | 新 `tv/pages/tv_link_play_pane.dart`、局域网服务 | 新用例：输入链接 → 解析 → 进电视直播间；解析失败写在输入框下；二维码区的三种状态 |

每个阶段都要能单独合并。登记表的阶段（设计 ✓ → 开发 → 真机）开工时按上表拆开。

## 测试

- 改之前会失败：`test/tv/` 加“设置 → 网络电视打开电视样式的页面，焦点在第一行‘订阅源管理’”（现在打开的是手机 `IptvPage`）。
- 每个阶段的用例见上表。导入用 `iptvImporterProvider`、`iptvFilePickerProvider` 的测试替身（照 `test/features/iptv/` 的写法），节目单用 `fixtures/` 的 XMLTV 样本；不访问网络（热门地址、链接解析都用假的）；定时器至少 1 秒。
- 1080p@2x 和 720p 各一个布局测试：右栏二维码不压内容、卡片按钮不出屏。

## 真机验证（维护者在电视或盒子上做）

| 步骤 | 期望 |
|---|---|
| 1. 设置 → 网络电视 | 一页，焦点在“订阅源管理”；右栏一个二维码和服务状态 |
| 2. 进订阅源管理，在一个网络源上按右 | 焦点在“同步 → 自动同步 → 删除”之间走；“删除”弹确认、焦点在“取消” |
| 3. 导入播放源 → 网络地址，用遥控器输入一个 m3u 地址 | 导入中有进度；成功提示条；失败写原因 |
| 4. 用手机扫二维码上传一个 m3u | 电视上出现新源（服务做了的话） |
| 5. 进一个网络电视频道，右键 → 播放设置 → 节目单 | 节目单面板，焦点在正在播的节目；OK 已播的节目开始回看，“返回直播”能回来 |
| 6. 导航轨“链接放映”，输入一个哔哩哔哩直播间链接 | 解析中写在输入框下，成功进电视直播间；输入乱写的文字写“解析失败”和原因 |

## 风险和注意

- 局域网网页遥控是一个新服务（端口、网页、防火墙、和设备同步的服务共存），规模可能比界面大；如果维护者决定不在本任务做，第 2、4 阶段里的扫码部分先不显示，写进 record.md 并建议在 X03 开任务。
- Referer、Cookie 是新设置：只加，默认空；加到播放请求里要经 `live_iptv` 的请求头规则，别影响没设置的用户。Cookie 是敏感信息，不进日志、不进备份明文（看 J 组的加密存储规则）。
- 长字段（请求头、Cookie）用遥控器很难输入，设计建议用手机填（README“拿不准的地方”第 5 条）；服务没做时只能遥控器输入。
- 可能冲突的文件：`tv/room/`（A17.4）、`features/iptv/`（L01 的任务）、`features/live_play/dialogs/iptv_guide.dart`（L02、C01 的任务）、`live_store` 的 `settings.dart`。

## 需要维护者决定的（开工时问，或按建议）

1. Referer、Cookie 两项手机要不要也加（A13.1 当时没加）。建议：电视加，手机不加（手机输入方便的话以后再加），设置键共用。
2. 手机网页遥控在不在本任务做。建议：在本任务做最小的一版（扫码打开网页、发送链接、上传 m3u），参考旧分支 M14.5 的 `web_remote_server.dart`，A17.3 的搜索、A17.4 的屏蔽、A17.9 的扫码到手机以后都用它。
3. “热门资源地址”要不要做成设置（现在写死在 `importer.dart:106`）。建议：做，默认空 = 内置地址。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A17.5` 或本机工作区；提交信息以 `[A17.5]` 开头（英文）；不推 master。
- 提交前：改过的包（`apps/pure_live`、`live_store`、`live_iptv`）跑 `dart format --output=none --set-exit-if-changed .`、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；三个决定的结论；局域网服务做到哪（端口、页面、和设备同步怎么共存）；测试数量（改之前失败几个）；新设置（键名、默认值）和翻译键；要在电视上看的；可能冲突的文件。
