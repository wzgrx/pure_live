# T18d.1 电视网络电视和链接放映：设计（第 1 版）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 范围：电视的 IPTV 设置（订阅源、导入、自动同步、请求头、节目单源）、订阅源管理、导入和请求头对话框、删除确认、网络电视直播间的节目单、“链接放映”页（INVENTORY 的 `MoviePlaybackPage`，导航名“链接放映”）。下面的界面清点表是这一批出图的清单
- 对应：[TASKS.md](../../../TASKS.md)、[inventory/UI.md](../../../inventory/UI.md#t18d1)、[inventory/UI_FILES.md](../../../inventory/UI_FILES.md#t18d1)；计划书 [specs/UI.md](../../../specs/UI.md) 第 5.5 节
- 基线：pure_live_TV（`~/ref/pure_live_TV/lib/modules/live/iptv/`、`modules/live/movie_playback/`）。手机上同样的功能：v3 的 IPTV 设置页和订阅源管理（`modules/iptv/iptv_page.dart`、`iptv_manage.dart`；手机版 [T11a.4](../../../T11/T11a/T11a.4/README.md) 未开始）、工具箱的链接解析（`modules/toolbox/toolbox_page.dart`；[T07i.3](../../../T07/T07i/T07i.3/README.md) 未开始）、节目单（[T05i.1](../../../T05/T05i/T05i.1/README.md)）。电视直播间的其余部分见 [T18c.1](../../T18c/T18c.1/README.md)
- 评审页：`page.json` 生成（`tools/ui/mock/page.py`），待发布；效果图源文件 [src/gen.py](src/gen.py)（电视公共样式在 [../U.15d/src/tvkit.py](../../T18c/T18c.1/src/tvkit.py)）
- 图片：pure_live_TV 按代码还原（1920×1080 设计像素折半画在 960×540 上）；文字取自 pure_live_TV 和 v3 的 `zh.json`；画面、二维码是示意

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| T18d.1-03 | IPTV 设置（`IptvManageSectionPage` → 新设计合成一页） | 设置 → IPTV 设置 | 电视 | 默认；没选节目单源（橙色提示）；自动同步关时没有“检查间隔”一行 |
| T18d.1-04 | 订阅源管理（`IptvResourcesSectionPage`，pure_live_TV 叫“资源列表”） | IPTV 设置第一行 | 电视 | 有网络和本地源；加载中“加载中...”；加载失败“订阅源加载失败 / 已有订阅数据已保留，请重试。”+ 重试；空“暂无订阅源 / 请返回 IPTV 设置导入播放列表或电子节目单。”；同步中 |
| T18d.1-02 | 导入（`IptvImportSectionPage` → 新设计用手机的两个对话框） | IPTV 设置“导入播放源”“导入节目单源” | 电视 | 选方式；网络导入填写中；导入中；成功“导入成功”或失败“导入失败或文件不存在”（提示条）；“参数错误”（地址为空） |
| T18d.1-05 | 自动同步（`IptvSyncSectionPage` → 合进 IPTV 设置） | — | 电视 | 开 / 关；同步中；“请设置需要同步的资源” |
| T18d.1-01 | 请求头（`IptvHeadersSectionPage` → 合进 IPTV 设置 + 输入对话框） | IPTV 设置三行 | 电视 | 未设置 / 已设置；“同步配置已保存” |
| T18d.1-06 | 确认对话框（`confirmReplaceIptvSource`、删除确认） | 导入同名源、删除源 | 电视 | 替换（“是否确认删除旧的 {} 数据并替换为当前文件？”）；删除 |
| 新 | 节目单（T05i.1 组件） | 网络电视频道的播放设置 → 节目单 | 电视 | 直播中；回看中；加载、失败、空、没配置节目单源同 T05i.1 |
| T18d.1-07 | 链接放映（`MoviePlaybackPage`） | 首页导航“链接放映” | 电视 | 服务启动中；已启动；未启动；正在解析；解析失败 |
| — | 二维码（`RemoteSyncQrCard`、`TvQrCodeCard`） | 上面各页 | 电视 | 服务启动中“正在启动局域网同步服务…”；出错写原因 |

## pure_live_TV 的样子

文件在 `lib/` 下。尺寸写设计像素，电视上的逻辑像素是一半。

**设置页外壳**（`features/settings/tv_settings_page.dart:345-362` → `core/widgets/tv_page_scaffold.dart`）：顶栏高 66，左边“返回”按钮（`arrow_back_ios_new` + “返回”），后面标题（t24 粗体）；内容整页滚动，内边距 16。打开时焦点在“返回”（`core/widgets/tv_page_shell.dart:163-172`）。行（`core/widgets/tv_settings_row.dart`）：图标 30、标题 t22 粗、说明 t16，焦点时浅色底 + 蓝色 2 像素边 + 光晕；进入下一页的行右边 `chevron_right`，只有一个选项的“动作行”也是箭头（`tv_settings_option_tile.dart:14-18,42-57`）。分组标题 t16 蓝色（`TvSettingsGroupTitle`），卡片几乎透明（`tv_settings_card.dart:27-41`）。

**IPTV 设置**（`modules/live/iptv/pages/iptv_manage_section.dart`）：顶部居中二维码卡片（宽 280，`RemoteSyncQrCard`，指向手机网页 `#/sync`），下面一组“IPTV 设置”四个入口：资源列表（查看已导入的直播源，支持同步与删除）、导入直播源（网络导入，或扫码在手机网页上传播放列表）、自动化周期同步设置（自动同步开关、周期与一键同步）、直播源请求头（User-Agent / Referer / Cookie）。

**资源列表**（`iptv_resources_section.dart`）：同样的二维码；“热门资源地址”一组（自定义“热门”频道的订阅地址，留空使用内置默认源 + 当前地址，行尾“编辑”，`:162-193`）；“资源列表”一组：网络资源（多于一个时有“同步”行）、每个源一行（名字、类型，行尾三个小按钮“同步”“自动同步”“删除”，`:263-317`）、本地资源（只有“删除”）；页底一行状态字（`:153-157`）。删除前确认（`:105-122`），确认框焦点默认在“确认”（`core/dialog/tv_dialog.dart:113`）。

**导入直播源**（`iptv_import_section.dart:80-127`）：二维码；“从 URL 导入播放列表”一组：两个输入框“播放列表地址（http/https）”“名称（留空则用地址命名）”、一行“从 URL 导入播放列表 / 下载网络播放列表并导入，请求头会写入该源的每个频道”；“手机网页导入”一组：一行说明“扫码打开远程页面，填写地址或上传 m3u/txt 文件推送到电视”。没有本地文件导入（`:8-11`）。没有节目单导入。

**自动化周期同步设置**（`iptv_sync_section.dart`）：二维码；“启动时全自动同步”开关；开着时“自动同步检查间隔 / 当前每隔 6 小时进行一次同步”（选项 2、6、12、24、48、72 小时，`:17`）；“同步 / 同步所有开启了自动同步的网络资源”。

**直播源请求头**（`iptv_headers_section.dart`）：二维码；三行：自定义直播源请求头、Referer 请求头、Cookie 请求头，说明是当前值或“未设置”；点开是输入对话框（最长 2000 字），保存后页底“同步配置已保存”。

**替换确认**（`services/iptv_confirm_dialog.dart`）：`TvDialog`，标题、说明（t24）、取消 / 确认。

**链接放映**（`modules/live/movie_playback/movie_playback_page.dart`）：首页导航里的一页（导航名“链接放映”，`features/settings/pages/navigation_menu_meta.dart:18,28`）。顶部左“在此粘贴或输入链接地址”（t18），右边状态胶囊“局域网服务已启动 / 服务未启动”；中间二维码（手机网页 `#/movie`）和地址；下面“支持的平台”一组小标签（全部 35 个平台，含“网络”，`:184-216`）。手机发来链接后解析并打开直播间（`:47-77`），失败弹提示条“解析失败，请检查链接格式”；页面上没有输入框（`:17-18`）。

**电视直播间的网络电视**：pure_live_TV 的直播间对网络电视频道没有节目单和回看（`modules/live/playback/` 里没有节目单界面）。

**v4 现在**：电视外壳只有网络电视频道列表（`apps/pure_live/lib/tv/pages/tv_iptv_pane.dart`），没有 IPTV 设置和链接放映页；手机的 IPTV 设置（`features/iptv/`）有节目单源，没有 Referer、Cookie。

## pure_live_TV 的问题

| 编号 | 问题 | 位置 |
|---|---|---|
| E1 | 五个页面各放一次同样的大二维码，占上半屏 | `iptv_manage_section.dart:22`、`iptv_resources_section.dart:146`、`iptv_import_section.dart:83`、`iptv_sync_section.dart:62`、`iptv_headers_section.dart:51` |
| E2 | 打开设置页焦点在“返回”，按两下确认就退出了 | `core/widgets/tv_page_shell.dart:163-172` |
| E3 | 同一页三个名字（资源列表、播放列表管理、订阅源管理） | `iptv_manage_section.dart:28`、`iptv_resources_section.dart:221`；v3 `iptv_page.dart:147`、`iptv_manage.dart:227` |
| E4 | 没有节目单导入和选择，直播间也没有节目单和回看 | `iptv_manage_section.dart:25-51`；v3 `iptv_page.dart:201-225` |
| E5 | 导入的输入框和按钮分成三行，导入中没有进度，结果在页底小字 | `iptv_import_section.dart:85-124` |
| E6 | 删除确认默认焦点在“确认” | `core/dialog/tv_dialog.dart:113`、`iptv_resources_section.dart:108-115` |
| E7 | 三个小按钮挤在行尾；“自动同步”看不出是开关 | `iptv_resources_section.dart:282-316` |
| E8 | “手机网页导入”是说明，样子却和能点的行一样 | `iptv_import_section.dart:107-118` |
| E9 | 结果只在页底写一行字，成功失败一个颜色 | `iptv_resources_section.dart:153-157`、`iptv_sync_section.dart:93-97` |
| E10 | 链接放映标题叫人“粘贴或输入”，却没有输入框 | `movie_playback_page.dart:17-18,133-139` |
| E11 | 解析中没有显示，失败只弹提示条 | `movie_playback_page.dart:47-77` |
| E12 | “支持的平台”是全部平台，和手机工具箱的“支持解析列表”不是一份 | `movie_playback_page.dart:189-213`；v3 `toolbox_page.dart:140-147` |
| E13 | 字太小（行标题逻辑 11、说明 8、行内按钮 7） | `core/widgets/tv_settings_row.dart:114-125` |

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | IPTV 设置一页、订阅源管理、导入和请求头对话框、删除确认、节目单、链接放映及其状态；四处选择 | 待评审 |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [对比：IPTV 设置](page/02-对比-IPTV-设置.jpg)
- [对比：订阅源](page/03-对比-订阅源.jpg)
- [对比：导入](page/04-对比-导入.jpg)
- [网络电视直播间：节目单（新）](page/05-网络电视直播间-节目单-新.jpg)
- [对比：链接放映](page/06-对比-链接放映.jpg)
- [链接放映的状态](page/07-链接放映的状态.jpg)
- [pure_live_TV 的问题](page/08-pure_live_TV-的问题.jpg)
- [改了什么](page/09-改了什么.jpg)
- [按钮用法：IPTV 设置和订阅源](page/10-每个按钮是干什么的-怎么用-IPTV-设置和订阅源.jpg)、[导入、请求头、节目单、链接放映](page/11-每个按钮是干什么的-怎么用-导入-请求头-节目单-链接放映.jpg)
- [遥控器按键和焦点路线](page/12-遥控器按键和焦点路线.jpg)
- [各客户端](page/13-各客户端.jpg)
- [需要你选的](page/14-需要你选的.jpg)
- [性能要点](page/15-性能要点.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-iptv.jpg](v3-iptv.jpg)、[v3-sync.jpg](v3-sync.jpg)、[v3-headers.jpg](v3-headers.jpg) | pure_live_TV：IPTV 设置入口、自动同步、请求头 |
| [v4-iptv.jpg](v4-iptv.jpg)、[v4-iptv-n.jpg](v4-iptv-n.jpg)、[v4-iptv-full.jpg](v4-iptv-full.jpg)、[v4-iptv-full-n.jpg](v4-iptv-full-n.jpg) | 新设计 IPTV 设置一页（第一屏、完整内容） |
| [v4-ua.jpg](v4-ua.jpg)、[v4-ua-n.jpg](v4-ua-n.jpg) | 修改请求头对话框 |
| [v3-resources.jpg](v3-resources.jpg)、[v3-resources-full.jpg](v3-resources-full.jpg)、[v3-confirm.jpg](v3-confirm.jpg) | pure_live_TV 资源列表、删除确认 |
| [v4-sources.jpg](v4-sources.jpg)、[v4-sources-n.jpg](v4-sources-n.jpg)、[v4-confirm.jpg](v4-confirm.jpg) | 新设计订阅源管理、删除确认 |
| [v3-import.jpg](v3-import.jpg)、[v4-import.jpg](v4-import.jpg)、[v4-import-n.jpg](v4-import-n.jpg)、[v4-import-url.jpg](v4-import-url.jpg)、[v4-import-url-n.jpg](v4-import-url-n.jpg) | 导入 |
| [v4-guide.jpg](v4-guide.jpg)、[v4-guide-n.jpg](v4-guide-n.jpg) | 网络电视直播间的节目单（回看中） |
| [v3-link.jpg](v3-link.jpg)、[v4-link.jpg](v4-link.jpg)、[v4-link-n.jpg](v4-link-n.jpg)、[v4-link-states.jpg](v4-link-states.jpg) | 链接放映和它的状态 |

## 改动（待确认）

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 保留 | 全部功能（订阅源同步 / 自动同步 / 删除、热门资源地址、网络导入、手机扫码、启动时同步、间隔、一键同步、三个请求头、链接放映入口） | — |
| c2 | 修改 | 五个子页合成一页，分组顺序照手机 v3；订阅源管理单独一页 | E1（N1） |
| c3 | 修改 | 二维码只一个，固定右栏，写清用途和服务状态 | E1（N2） |
| c4 | 修改 | 默认焦点在第一行 | E2 |
| c5 | 修改 | 统一叫“订阅源管理” | E3 |
| c6 | 增强 | 节目单源导入和选择；网络电视直播间播放设置加“节目单”（T05i.1 组件） | E4（N3） |
| c7 | 修改 | 导入用手机的两个对话框；“本地导入”换成“用手机导入” | E5、E8 |
| c8 | 修改 | 删除确认默认焦点在“取消”，“确认”红字 | E6 |
| c9 | 修改 | 订阅源一张卡片一个，三个按钮在卡片下面，开关写“开 / 关”；上面一行个数 | E7、E13 |
| c10 | 修改 | 结果用提示条，失败写原因 | E9 |
| c11 | 修改 | 请求头单独一组三项；用手机的“修改请求头 (User-Agent)”对话框 | — |
| c12 | 修改 | 链接放映加遥控器输入框；解析中、失败写在输入框下 | E10、E11（N4） |
| c13 | 修改 | “支持解析列表”用手机工具箱的同一份 | E12 |
| c14 | 修改 | 字号大一级 | E13 |

## 按钮的作用和用法

见对比页“每个按钮是干什么的”两节：IPTV 设置 1–11、订阅源管理 1–4、导入 1–3、网络导入 1–4、请求头 1–4、节目单 1–3、链接放映 1–2。

## 焦点路线

| 页面 | 默认焦点 | 上下 | 左右 | 确认 | 返回 |
|---|---|---|---|---|---|
| IPTV 设置 | 第一行“订阅源管理” | 行（第一行再上到“返回”） | —（二维码不能聚焦） | 进入、开关、对话框、小菜单 | 回到设置 |
| 订阅源管理 | 第一个源的“同步” | 源之间（同一列按钮）；最上到“全部同步” | 同一源的三个按钮 | 执行 | 回到 IPTV 设置 |
| 对话框 | 导入：第一项；输入：输入框；删除：取消 | 项和输入框 | 按钮 | 执行 | 关闭 |
| 节目单 | 正在播或正在回看的一行 | 节目 | 左：回到播放设置 | 回看、返回直播 | 回到播放设置 |
| 链接放映 | 输入框 | 输入框 | 左：导航轨 | 打开输入法 / 解析 | 回到导航轨 |

遥控器菜单键（长按确认）在这些页面没有用法。

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 不适用（电视界面）；同功能在 T11a.4、T07i.3、T05i.1 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 不适用 |
| 电视 | 本任务 |
| 苹果平台差异 | 不适用 |

## 待选（A 是建议）

- N1 IPTV 设置结构：A 一页（同手机分组）+ 订阅源管理；B 照 pure_live_TV 入口页 + 四个子页。
- N2 二维码：A 一个，固定右栏；B 每页顶部一个。
- N3 电视上的节目单：A 提供（同手机）；B 不提供。
- N4 链接放映输入：A 加遥控器输入框；B 只能用手机发，标题改成“用手机发送链接”。

## 跨任务待同步（不改别的任务文件，记在这里）

| 要改的任务 | 内容 |
|---|---|
| T11a.4（手机 IPTV 管理） | v3 把“自定义直播源请求头”放在“自动化周期同步设置”一组里；建议手机也分出“直播源请求头”一组。电视多 Referer、Cookie 两项，手机要不要加随 T11a.4 定；“播放列表管理 / 订阅源管理”两个名字统一成“订阅源管理” |
| T18c.1 | 网络电视频道的播放设置第一组多一行“节目单”（打开本任务的节目单面板） |
| T18a.2、T18e.2 | 电视设置页打开时焦点在第一行而不是“返回”（E2 是所有设置页的共同做法） |
| T07i.3 | 链接放映用的“支持解析列表”和工具箱是同一份 |

## 拿不准的地方

1. **焦点样式和配色**：以 T18a.2 为准（同 T18c.1）。
2. **“手机网页导入”那一行能不能聚焦**：`TvSettingsOptionTile` 的选项为空时 `onSelect` 是空的（`tv_settings_option_tile.dart:53`），行本身是否还是焦点停靠点没有在真机上确认。
3. **pure_live_TV 的链接解析能认哪些平台**：页面列了全部平台（含“网络”），手机工具箱列了 15 个；电视解析器（`urlParseEngineProvider`）实际支持的范围没逐个核对，新设计先用手机工具箱的列表。
4. **订阅源卡片上的信息**：手机 v3 是名字、地址、网络 / 本地、格式；电视原来写类型（`provider.type`）。频道数、上次同步时间两边都没有，新设计没加。
5. **电视的输入法**：Android TV 的系统输入法样子各家不同，图里只画输入框获得焦点；长字段（请求头、Cookie）建议用手机填。
6. **链接放映的名字**：pure_live_TV 导航叫“链接放映”，页面里没有标题；手机工具箱叫“链接解析”。新设计保留“链接放映”（电视独有入口），列表和提示文字用手机工具箱的。
7. **节目单的其他状态**（加载、失败、空、没配置节目单源）同 T05i.1，没再出电视图。
8. **服务未启动的原因**：pure_live_TV 把错误原文写在二维码位置（`movie_playback_page.dart:97-100`）；新设计写“服务未启动”+ 重试，原文放在下面一行。

## 文件对照

| pure_live_TV | v4 |
|---|---|
| `modules/live/iptv/pages/iptv_*_section.dart` | 电视版还没有；手机 `features/iptv/iptv_page.dart`、`iptv_settings.dart`、`iptv_import.dart`（同一组逻辑） |
| `modules/live/iptv/services/iptv_confirm_dialog.dart` | `live_ui` 的对话框组件（T01d.1）电视样式 |
| `core/widgets/remote_sync_qr_card.dart`、`tv_qr_card.dart` | 局域网接收（`features/remote_receiver/` 是设备同步，IPTV 和链接的手机网页随 T18 定） |
| `modules/live/movie_playback/movie_playback_page.dart` | 电视版还没有；解析逻辑同手机工具箱 `features/toolbox/` |
| —（没有节目单） | `features/live_play/dialogs/iptv_guide.dart`（T05i.1 组件） |
