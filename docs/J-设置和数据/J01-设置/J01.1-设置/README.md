# J01.1 设置

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（模块重构：设置页）
- 来源：模块重构计划 M13.7（3.x 的设置页按 4.x 的结构重写）；用户 2026-10-01 授权“设置页可以重新设计，分类、层级、选项归属、搜索、说明都可以改，前提是 3.x 的设置完整迁移”
- 旧编号：M13.7、T09a.1
- 相关：依赖 J02.1（`Settings` 注册表和 `SettingsStore`）；之后的界面重做 A11.1～A11.5；逐条核对 J01.2；决定 D-018；记录 [record.md](record.md)

## 目标

把 3.x 的 23 个设置页（`lib/modules/settings/`，约 7600 行，11 组入口）换成一个**目录驱动**的设置页：每个设置是一条登记（所在页、分组、标题、一句说明、搜索词、它改哪些存储项、在哪些平台和宽度出现、怎么画），页面、分区、搜索、“恢复默认”都从这张表生成；3.x 的每一个设置都有入口，键名和含义不变（D-018）。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 做完时（2026-10-01） | 现在（A11 重做之后） |
|---|---|---|---|
| 结构 | `lib/modules/settings/settings_page.dart`（184 行）11 组入口，每组再进二三级页 | 10 个分区 + 搜索，宽于 840 两栏（`settings_page.dart`） | 五组 17 个入口（`settings_model.dart:10`、`:35`），目录 `settings_catalog.dart:321`，129 行 |
| 存储 | 23 个 GetX 控制器各自 `hive*('键', 默认值)`，`ever` 自动落盘 | `live_store` 的 `Settings` + `SettingsStore`（J02.1） | 同左 |
| 滑块 | 每动一帧写一次 Hive（`widget_extensions.dart` + `hive_rx`） | 拖动时只改显示，停 200 毫秒写一次 | `settings_tiles.dart:250` |
| 同一设置的多个入口 | 播放代理在内核页和代理页各一份（`player_kernel_settings_page.dart:63`）；小窗弹幕两个入口（`settings_page.dart:97`、`video_settings_page.dart:274`） | 每个设置只在一处，靠搜索找 | 同左 |
| 播放器选项 | 所有平台的驱动都列出（Android 上能选 WASAPI，`mpv_option_page.dart`、`player_consts.dart:51-88`） | 只列当前平台可用的 | `settings_editors.dart:91` 的 `mpvOptionsFor` |
| 代理地址 | 逐字保存，空主机也能开（`network_proxy_settings_page.dart`） | 对话框里校验后保存，没地址先要求填 | 同左（A11.4） |
| 弹幕样式 | 只能在直播间里改（`live_play/pages/danmaku_settings_page.dart`） | 设置页也能改（同一组存储项） | 设置 → 弹幕（A08.5，直播间同一个组件） |
| 语言 | 显示“简体中文”，实际跟随系统（`theme_settings_page.dart:232`） | 加“跟随系统” | 同左 |

## 结果

- 提交：`9a90cbf6c`（2026-10-01 合并）。
- 做了什么（详见 [record.md](record.md)“做法”和“与 v3 的功能对照”）：
  - c1 目录驱动：`SettingsEntry`、`settingsCatalog`，页面、分区、搜索、“已修改”计数、“恢复本页默认”都从目录生成。
  - c2 3.x 的 23 个页面逐个对到分区：主题、字体、加载动画（85 种）、卡片外观、分页、视频、竖屏 9 项、观看数据口径、小窗弹幕、播放内核、MPV 选项、代理、刷新、平台、导航、通用、缓存、配置预览全部有入口；本地互动设置页当时没有（直播间本地互动做好后由 A08.2 加上）。
  - c3 新增入口：已批准升级的 5 个新设置（`showUnplayableInDiscover`、`preferH264`、`douyuForceRenew`、`twitchLanguages`、`youtubeShowAllChat`），以及 3.x 有存储项但没有入口的弹幕点按/长按操作、斗鱼机器人过滤、相似过滤参数、关闭窗口时（`exitChoose`）。
  - c4 `live_store` 注册表的修正（只改范围，不改键名和默认值）：弹幕上下留白 0～300 像素（原来夹到 0～1，3.x 用户的 40 像素会变成 1）；文字缩放 0.5～2 和五种字号加上 3.x 的范围，越界读出时夹紧。
  - c5 修了 record 列的 10 个 3.x 问题（滑块每帧写盘、多入口、跨平台驱动、代理空地址、语言显示、弹幕样式只能在直播间改等）。
- 偏差：后台播放、睡眠、小窗置顶、开机启动、窗口大小当时只存设置、不调系统接口；之后由 I01.3、O03.1、I04.1、C02.1、O05.1、D05.1、A08.4 逐个接上（清点第 15 节“读取”现在只剩 4 个没人读的设置，见子分类页）。字体下载、刷新率当前/最高 Hz、下载目录当时留给后续，I01.3 做完。
- 测试：当时 `settings_page_test.dart` 13 个、`live_store` 30 个、`i18n_test` 通过；翻译 zh、en 各加 186 个 `settings_` 键。之后 A11 重做时测试拆成 `test/features/settings/` 下 7 个文件（共 72 个用例，见子分类页）。

## 验证

- 自动测试：`cd apps/pure_live && flutter test test/features/settings/`；注册表的范围和夹紧在 `packages/live_store/test/stores_test.dart`。
- 真机：当时没装到手机；之后 S02.2、S02.3 在 K90 上用过设置页（改画质、弹幕、刷新率），没有逐页走。设置页的逐页真机由 A11 的各任务和 [S03.1](../../../S-质量和验证/S03-统一验证/README.md) 统一验证覆盖。登记表按当时“构建通过 + 单元测试”记成“完成”。

## 留下的问题

- 默认值、范围、生效位置没逐条对照 3.x → [J01.2](../J01.2-设置项逐条核对/README.md)。
- 小窗弹幕的实时预览当时没做 → A11.3 做了（`PipDanmakuPreviewBinding`）。
- 3.x 偏技术的说明文字（`audience_*_detail` 等）和本页没用到的旧翻译键没删 → 不清理（D-024）。
