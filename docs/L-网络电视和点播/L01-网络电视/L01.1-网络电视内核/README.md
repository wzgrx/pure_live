# L01.1 网络电视内核

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（模块重构：`packages/live_iptv`）
- 来源：模块重构计划 M6（3.x 的 `lib/core/iptv/` 和 `lib/core/site/iptv/` 搬成纯 Dart 包）
- 旧编号：M6、T11a.1
- 相关：之后的 L01.2（`IptvLibrary` 的持久化）、L01.3（网络电视页面）、I01.1（注册 `IptvSite`、注入 GBK 解码、启动 3 秒后自动同步）、C01.2（直播间的节目单和回看用 `catchup.dart`）；参考归档 v4 的 `packages/live_iptv`（只借了拉取式 XMLTV 解析和“存储由应用实现”的分层）；记录 [record.md](record.md)

## 目标

把 3.x 的网络电视内核（约 4700 行，直接用 GetX 拿全局 drift 数据库、在内核里弹 Toast）换成纯 Dart 的 `packages/live_iptv`：存储是接口、设置和网络和时钟都注入、结果用状态表示、所有导入排队执行；行为照 3.x，并修掉审查出的 15 个问题。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在（`packages/live_iptv/lib/src/`） | 要做到 |
|---|---|---|---|
| 坏数据 | 任何一行有问题整个列表导入失败（`services/iptv_import_manager.dart:227-229`）；坏的百分号编码抛未捕获的 `ArgumentError`（`m3u_parser.dart` 的 `_parseHeaderOptions`） | 坏段落跳过并记行号，只有停在半个段落才算截断（`playlist/m3u_parser.dart`、`importer.dart:193`） | 完成 |
| 热门列表 | 用户把列表命名为 `hot` 就变成内置热门（`iptv_import_manager.dart:238`） | 只认 `isHot` 导入（`importer.dart:113` 的 `hotName` 只用于内置） | 完成 |
| GBK | 导入用 GBK 回退，同步用 UTF-8 容错，同步后乱码还显示成功（`iptv_sync_engine.dart:31`） | 同步和导入同一个解码（`text.dart:13`） | 完成 |
| 节目单 | XMLTV 只认 `+0800`；只有 `.gz` 结尾才解压；整份建 DOM；JSON 的字符串 Unix 秒读成公元 179000 年 | 时区写法补全、按 gzip 魔数解压、拉取式解析、10/13 位数字先当 Unix 时间（L02） | 完成 |
| 房间 | 找不到的房间号返回“直播中”的空房间；头像是外链的商业图库图片（`site/iptv/iptv_site.dart:25`） | 抛 `NotFound`（房间号本身是地址时照旧播）；头像留空，界面用平台图标 | 完成 |
| 频道顺序 | 查询没有 `ORDER BY`，同步后新频道排到最后（`local/database.dart:229`） | `IptvLibrary` 约定按文件顺序 | 完成 |
| 存储 | 全局 drift 数据库（schema 9） | 接口 `IptvLibrary`（`library.dart:22`），持久化在 L01.2 | 完成 |

## 结果

- 提交：`414fe49a6`（2026-10-01 合并）。
- 做了什么（详见 [record.md](record.md)“做法”“与 v3 的对照”）：
  - c1 解析：`M3uParser`、`TxtParser`、`XmltvParser`（拉取式）、`JsonGuideParser`，行为照 3.x。
  - c2 导入和同步：`IptvImporter`（导入、同步、自动同步 `syncExpired`、热门列表、默认节目单、删除），同名确认改为回调，所有操作排队。
  - c3 频道身份：`reconcileChannels`（8 步唯一匹配、模糊时整体放弃）；节目单匹配 `GuideIndex`、`rebuildMappings`、`resolveGuideChannel`（L02）。
  - c4 平台：`IptvSite`（分类 = 播放列表、分区 = 频道、推荐 = 热门列表、单一“默认”画质、回看四项和请求头）。
  - c5 回看：`classifyIptvProgramme`、`evaluateIptvCatchupAvailability`、`buildIptvCatchupUrl`（L02）。
  - c6 修了 15 个 3.x 问题（record“审查发现的 v3 问题”），去掉了死代码（Trakt 剧集、`ChannelDetailController`、`EpgAutoMapper`、四组没有界面的表）。
- 有意差异：坏行跳过（UPGRADES 统一原则“容错”）；未知房间号报 `NotFound`；房间头像留空；列表接口第 2 页起返回空；非 UTF-8 要注入解码器；下载走 `live_net`（平台键 `iptv`、整次 2 分钟超时）；节目单格式按内容判断。
- 依赖：新增 `xml` 7.1.0。
- 测试：42 个（`playlist_test.dart` 15、`guide_test.dart` 8、`catchup_test.dart` 9、`reconcile_test.dart` 3、`import_test.dart` 7），移植了 3.x 的 `m3u_parser_test`、`iptv_programme_policy_test`、`iptv_import_manager_test` 的主要用例。

## 验证

- 自动测试：`cd packages/live_iptv && dart test`。
- 真机：内核本身不靠原生；整条路径（导入、播放、节目单、回看）的 K90 验证在 [S02.6](../../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 第 2 阶段，还没做。登记表按当时“单元测试通过”记成“完成”。

## 留下的问题

- 当时留给其他模块的都已接走：`IptvLibrary` 的持久化和 3.x 库的迁移（L01.2）；注册 `IptvSite`、GBK 解码、启动自动同步（I01.1）；网络电视页面（L01.3、A13.1）；直播间的节目单和回看（C01.2、A07.7）；播放请求头加自定义 UA（C01.2，`room_controller.dart:521-536`）；录制（H01.1）；分享导入（O03.2）。
- 切换节目单后重建频道映射：L01.1 记为可选，没有做（直播间按 tvg-id 和名字兜底）→ L02 的已知问题。
