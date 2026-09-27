# NNNN 界面多语言：slang 按功能分命名空间，全局 t 加整树重建，live_ui 文案注入

- 状态：提议
- 日期：2026-09-28

## 背景

- 产品规格 F-APP-06 和 PLAN §12 要求界面有简体中文、繁体中文、英文三种语言，缺失的翻译在 CI 报错，语言只存一份。PLAN §04 选定 slang + slang_flutter（类型安全）。
- ADR 0015 决定 4 让预览版只有中文，说“加第二种语言时再引入 slang”。实际情况是：界面文字散在约 93 个文件里（约 1200 条不重复的中文），`lib/l10n/strings.dart` 只收了 42 个常量。
- 很多文字不在 `build` 方法里：错误说明（`describeError`）、通知、枚举的标签、录制和同步的结果提示、托盘菜单，拿不到 `BuildContext`。
- `live_ui` 自己也显示文字（“直播”“录制中”徽标、卡片的读屏文字、错误视图的默认按钮、“1.2万”“3 小时前”），但它不能依赖应用。
- 设置注册表已经有 `Settings.locale`（`theme.locale`，取值 `system`、`zh-Hans`、`zh-Hant`、`en`，并换算 3.x 的 `language` / `languageName`）。

## 调研（2026-09-28）

| 包 | 最新稳定版 | 发布日期 | 许可证 | 说明 |
|---|---|---|---|---|
| slang | 4.19.2 | 2026-09-12 | MIT | 生成器和运行时；依赖 intl、yaml、watcher 等 |
| slang_flutter | 4.19.0 | 2026-08-06 | MIT | `flutterLocale`、`TranslationProvider`、按系统语言解析 |
| slang_build_runner | — | — | MIT | 不用：`dart run slang` 生成，生成代码提交进仓库 |

- `fallback_strategy: none`（默认）时，某个语言少了键，生成出来的类缺实现，`dart analyze` 直接报错（本机验证过）。
- slang 没有内置中文的复数规则（中文只有 other），不注册会在每次取复数时打印警告。

## 决定

1. **文件和生成**：`apps/pure_live/slang.yaml`；源文件 `lib/i18n/<语言>/<命名空间>.i18n.json`，基础语言 `zh-Hans`，另有 `zh-Hant`、`en`；占位符用 `{name}`；不回退；生成 `lib/i18n/strings*.g.dart`（格式化到 120 列，与 `dart format` 一致）并提交。改了 JSON 要在 `apps/pure_live` 里运行 `dart run slang`。
2. **命名空间按功能区**（32 个）：`app`、`common`、`ui`、`errors`、`sites`、`audience`、`quality`、`follows`、`discover`、`search`、`room`、`rooms`、`danmaku`、`recording`、`settings`、`iptv`、`accounts`、`backup`、`sync`、`system`、`tv`、`web`、`cast`、`alerts`、`multiview`、`me`、`about`、`fonts`、`health`、`diagnostics`、`onboarding`、`share`。几个页面共用的词（取消、删除、撤销、重试……）放 `common`；键用驼峰，需要时用点分层（`settings.general.language`）。平台名和各平台人数说明用 slang 的 `(map)`，保持 `platformNames[id]` 的写法。
3. **访问方式：全局 `t`，切换语言时整树重建一次**。
   - 所有代码都用 `t.xxx`，包括没有 `BuildContext` 的函数。
   - `PureLiveApp.build` 监听语言（设置加系统语言），变化时 `LocaleSettings.setLocaleSync`，并把根下所有元素标记为需要重建一次：当前页面原地换成新语言，路由、播放器、滚动位置都保留。
   - 已经生成并存下来的文字（正在显示的 SnackBar、网页登录流程里存的提示、托盘菜单）等下次生成时才换语言。
4. **语言选择**：设置 › 通用 最上面的“语言”：跟随系统、简体中文、繁體中文、English；语言名总用各自的文字写。只存 `theme.locale`。
   - 跟随系统：系统语言列表里第一个中文或英文决定；中文里文字系统为 Hant，或地区为台湾、香港、澳门的是繁体，其它中文是简体；列表里没有中文和英文时用英文。系统语言改变时立即生效。
   - `MaterialApp`：`locale` 取所选语言，`supportedLocales` 是三种语言，`localizationsDelegates` 是 `GlobalMaterialLocalizations.delegates`（Material、Cupertino、Widgets）。繁体给 Material 的是 `zh_Hant_TW`，和译文一样用台湾习惯。
   - 启动时 `main()` 在第一帧前就设好语言，第一帧不会闪中文。
   - 中文的复数规则注册为“只有 other”。
5. **字体（principles §2.3）**：`PureTheme.of` / `PureTheme.tv` 加 `locale` 参数，文字样式都带上界面语言的 locale，字体回退按它选简繁字形；繁体时 Windows 的字体族和前两个回退换成 `Microsoft JhengHei UI` → `Microsoft JhengHei`，其它平台的回退换成 TC 系列。用户下载的字体仍排在最前。直播间、多画面的深色覆盖主题也带同样的 locale。
6. **live_ui 文案注入**：`LiveUiText` 放着 live_ui 自己显示的词和两种格式（相对时间、人数），`LiveUiText.current` 默认简体中文；应用每次设语言时用 `ui` 命名空间的译文替换它。人数格式由数据决定：中文以 10000 为一级（万/亿、萬/億），英文以 1000 为一级（K/M/B），一位小数、去掉“.0”，进位到下一级时换单位（`9999.99万` 写成 `1亿`）。
7. **翻译原则**
   - 简体：就是原来的中文，不改意思（测试仍按原文断言）。
   - 繁体：台湾用语和字形，不逐字转换，例如 视频→影片、屏幕→螢幕、网络→網路、设置→設定、默认→預設、文件→檔案、登录→登入、账号→帳號、关注→追蹤、分组→群組、屏蔽→封鎖、画中画→子母畫面、全屏→全螢幕、横屏/竖屏→橫向/直向、投屏→投放、节目单→節目表、播放列表→播放清單、缓存→快取、代理→Proxy、剪贴板→剪貼簿、二维码→QR 碼。引号用「」。
   - 英文：自然的界面英文，句首大写；平台用官方英文名（Douyu、Huya、Bilibili、Douyin、Kuaishou、NetEase CC、MissEvan、REDnote……）；弹幕译作 danmaku，聊天面板叫 Chat；数量随复数变化。
8. **缺失翻译报错**：少键不能编译（第 1 条）；`test/i18n_test.dart` 在门禁里检查三种语言的命名空间和键完全一致、没有空文案、复数都有 other、同一个键的占位符一致、繁体里没有常见的简体字、英文里没有汉字、生成代码和源文件一致（在临时目录里重新生成比对）、三种语言 Flutter 都支持。
9. **测试语言**：`test/flutter_test_config.dart` 让用到 widget 测试绑定的测试文件把系统语言报成 zh-Hans-CN，跟随系统的应用在测试里就是简体；纯 `test` 的文件不初始化绑定（绑定会把所有 HTTP 请求模拟成 400）。
10. **保持中文的数据**：与平台画质名比对的 `qualityPreferenceNames`（原画、蓝光8M……），许可证页上的双语应用名“纯粹直播 Pure Live”，`live_ui` 内置的简体默认文案。`live_core` 等包里平台返回或按平台规则拼出的文字（画质名、分区名）是数据，不翻译。

## 备选方案与放弃理由

- **`context.t` 加 `TranslationProvider`**：只有依赖了它的组件会重建，但大量文字在没有 context 的函数里，只能混用全局 `t`，切换语言后会留下旧语言的文字。
- **切换语言时给整个应用换 key**：实现最简单，但会丢掉导航栈、正在播放的直播间和多画面。
- **Flutter 自带的 gen_l10n（ARB）**：也类型安全，但取文字要 `AppLocalizations.of(context)`，同样解决不了没有 context 的代码；没有命名空间，一个大 ARB 文件难以分工维护。PLAN 已选 slang。
- **YAML 源文件**：少写引号，但 YAML 会把 `on`、`no`、带冒号的句子解析错；选 JSON。
- **`fallback_strategy: base_locale`**：少了的译文会悄悄显示成中文，违背 PLAN §12。
- **live_ui 依赖 slang 或自带三种语言**：多一套翻译流程，或者让界面库依赖应用的文案；改成注入一个小的文案对象。
- **翻译画质名**：这些名称要和平台返回的画质名比对，翻译后匹配会失败。

## 影响

- 取代 ADR 0015 决定 4：`lib/l10n/strings.dart` 删除，界面文字都在 `lib/i18n/`。
- 新增或修改界面文字：三种语言的 JSON 一起改，再 `dart run slang`；测试会拦下漏改。
- 托盘菜单在启动时设置，Android 通知渠道名在启动时创建，切换语言后下次启动才换。
- principles §8 的“Windows 简繁字体回退”“Android 繁体字形”仍待统一构建后三语截图验证。
