# U.10b 登录和 Cookie

- 日期：2026-10-01
- 设计：[docs/ui/compare/U.10b/README.md](../compare/U.10b/README.md)（第 1 版，用户已确认；待选 L1～L3 按建议 A）
- 范围：七个平台和网易 CC 的 Cookie 页（同一个页面）、斗鱼页、哔哩哔哩扫码页和网页登录页、舍弃确认、页内退出确认、提示条。电视的账号设置在 U.15i，没有动。
- 改动的目录：`apps/pure_live/lib/features/account/`、`packages/live_ui`（只做添加：`QrColors`、图标，随 U.9 提交）、翻译文件、文档。
- 依赖：没有新增。网页登录要的内置浏览器 `flutter_inappwebview`（6.2.0-beta.3，M12.3 已加入并写明理由：稳定版 6.1.5 的 Android 部分用了 AGP 9 不接受的写法）已经在 `pubspec.yaml`；`InAppWeb.detect()` 在 Android、iOS 上可用，Windows 有 WebView2 运行时才可用，Linux 没有。设计“拿不准的地方”里说的“v4 现在没有，先不显示”已经过时：手机上扫码页下面显示“网页登录”。没有改原生部分，没有构建 APK。
- 敏感内容：测试和截图只用明显的假值（`SESSDATA=ok`、`yyuid=1234`、`xxxxxxxx`），没有真实 Cookie 写进任何文件。

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 标题写平台：“虎牙账号”等 | ✅ | `account_editor_title`“{name}账号”（v3 都是“设置cookie”） |
| c2 | 顶部状态卡：平台图标、名字、现在的状态（文字和列表一致）；哔哩哔哩、抖音有“重新核验” | ✅ | `AccountStatusCard`（图标 32）；没存时“未设置：粘贴登录后的 Cookie”；“重新核验”是卡片右边的文字按钮，核验中不显示 |
| c3 | 说明和输入提示统一，虎牙、抖音、快手换掉旧说明 | ✅ | 通用说明“登录{name}网页并进入任意直播间，在浏览器开发者工具的网络请求中复制完整 Cookie。”（“仅保存在本机”挪到页底的说明，不重复）；提示一律“粘贴 {name} Cookie”；哔哩哔哩、Twitch、SOOP 用各自的说明 |
| c4 | 说明里加“打开 xx 网页” | ✅ | 系统浏览器打开；斗鱼是“打开 passport.douyu.com” |
| c5 | 框下“粘贴”“清空”；不是 Cookie 的内容框下说明、不能保存；去掉“Cookie:”前缀 | ✅ | 两个描边小按钮（圆角 8、高 36）；格式错误时框变红并说明 |
| c6 | 没改动时保存变灰；哔哩哔哩、抖音先核验再存；保存中转圈；一次一条提示 | ✅ | 要核验的平台保存中显示“正在核验并保存…”；斗鱼保存后只提示“Cookie 已保存在本机”（或“已从粘贴内容填入 LTP0 / dy_did……”），会话说明在状态卡上 |
| c7 | 页面里加“退出登录”，和列表上的退出一样先确认；清空后保存也按退出处理 | ✅ | 页内确认用设计图的文字“退出虎牙？ / 将删除本机保存的虎牙 Cookie。确定退出“虎牙”账号吗？”（L3 按 A）；列表上仍是 v3 的文字（U.10a c8） |
| c8 | 保留说明横幅、“Cookie”分组、多行输入（3～7 行）、48 高的保存按钮、舍弃确认（文字照 v3，“舍弃”红底） | ✅ | 舍弃确认“继续编辑 / 舍弃”；L1 按 A，已存的 Cookie 在框里照原文显示 |
| c9 | 斗鱼：会话说明常驻状态卡；LTP0、dy_did 放进“续期”一组，标签在框上方，“立即续期”旁一句说明；粘 passport Cookie 只取走 LTP0 / dy_did，保存后框里是实际存下的登录 Cookie | ✅ | 说明两段 + 链接（7 天时效那段由状态卡代替） |
| c10 | 斗鱼“登录后强制续期”开关（默认关）带说明 | ✅ | 放在续期组下面的单独一张卡（设计图） |
| c11 | 扫码页：去掉重复的顶部说明；二维码 200（宽屏 220）；状态盖在二维码上，位置不动；失效和失败的按钮在二维码中间 | ✅ | 加载、已扫描、失效、失败、核验中、核验成功六种覆盖层；二维码下面一行说明（已扫描时主色浅底） |
| c12 | 扫码页下面“扫不了？”：网页登录（手机才有）、填写 Cookie | ✅ | L2 按 A；网页登录只在 Android、iOS 且有内置浏览器时显示；“填写 Cookie”进哔哩哔哩的 Cookie 页，返回回到扫码页 |
| c13 | 扫码确认后先核验，平台说没登录就不存；核验请求本身失败时照存，提示“暂时无法核验” | ✅ | 提示“已保存，暂时无法核验账号” |
| c14 | 网页登录页照 v3：标题栏“二维码登录”（窄时只有图标），核验中盖一层，出错底部红条 | ✅ | 宽 <520 时只有图标（悬停显示“二维码登录”）；v4 原来用标题栏下的进度条和提示条，改回 v3 的盖层和红条 |
| c15 | 网易 CC 的 Cookie 页（C-22），状态“已保存，暂未用于请求” | ✅ | |

### 各客户端

| 客户端 | 做到 | 说明 |
|---|---|---|
| 手机竖屏、横屏 | ✅ | 同一列；输入框 `scrollPadding` 照 v3，键盘弹出时滚到可见 |
| 宽屏（平板、Windows、Linux） | ✅ | 一栏最宽 720 居中；扫码二维码 220；没有网页登录；Ctrl+V 粘贴（输入框自带）、Ctrl+S 保存（新，macOS 的 Cmd+S 也接上了） |
| 电视、苹果平台 | — | 电视在 U.15i；iOS 同 Android（有网页登录），macOS 同电脑 |

### 偏差和原因

1. **页内退出确认的文字**：设计图的说明写“和列表上的退出同一个确认”，图里画的却是“退出虎牙？”这一版；照图做，列表保留 v3 的文字（U.10a c8 明确要求）。如果要两处完全一样，改 `confirmPageSignOut` 一处即可。
2. **网页登录**：设计写“v4 现在没有内置浏览器、先不显示”，实际 M12.3 已经接入，所以手机上显示；Windows 即使装了 WebView2 也不在扫码页给网页登录（照 v3 和设计）。没有内置浏览器时打开旧的网页登录地址，显示哔哩哔哩的 Cookie 页和黄色提醒（文字改为“这台设备没有可用的内置浏览器……”）。
3. **斗鱼到期时间的格式**沿用 v4 的 `yyyy-MM-dd HH:mm`（设计图是示意的“10-08 21:30”）。
4. 哔哩哔哩 Cookie 页去掉了 v4 原来标题栏上的“二维码登录”（设计图的 Cookie 页没有标题栏按钮；从扫码页进来时返回即回到扫码页）。

## v3 文件 → v4 文件

| v3（`modules/account/`） | v4（`features/account/`） |
|---|---|
| `widgets/account_cookie_editor.dart` | `cookie_editor.dart`（`CookieEditorScaffold`、`AccountField`）、`account_widgets.dart`（状态卡、说明横幅、确认框） |
| `huya/`、`douyin/`、`kuaishou/`、`twitch/`、`soop/`、`yy/` 的 `*_cookie_page.dart` 和 controller | `platform_cookie_view.dart`（一个页面）、`account_platforms.dart`（提示、说明、网址） |
| `douyu/douyu_cookie_page.dart`、`douyu_cookie_controller.dart` | `douyu_cookie_view.dart` |
| `bilibili/qr_login_page.dart`、`bilibili_login_qr_code.dart`、`qr_login_controller.dart` | `bilibili_qr_login.dart`；二维码绘制在 `live_ui` 的 `QrCodeWidget` |
| `bilibili/web_login_page.dart` | `bilibili_web_login.dart`、`shared/in_app_web.dart` |

## 设置、文字、门禁

- 没有新设置（`douyuForceRenew` 是 M13.8 已有的）；存储键不变。
- 文字：新加 `account_status_none_hint`、`account_sign_out_title`、`account_sign_out_message`、`account_saving_verifying`、`account_qr_cannot_scan`、`account_qr_stopped`、`account_web_login_option`、`qr_scanned`、`qr_expired_hint`、`douyu_open_passport`；改 `account_editor_title`、`account_saved_signed_in`（“已保存，已登录：{name}”）、`account_cookie_privacy`、`account_clear_input`（“清空”）、`account_douyu_renew_now_desc`、`account_bilibili_web_unavailable`、`qr_waiting_scan`（去掉多余空格）、`cookie_tip`、`douyu_cookie_tip_step2`、`douyu_cookie_credentials_absorbed`、三条 `douyu_cookie_valid_*`（“登录态有效”→“登录有效”，照状态卡的图）。
- 门禁：见 U.10a（`account` 25 → 0）。

## 测试

`account_page_test.dart` 中本任务 13 个：Cookie 页的上下顺序、标题、未设置状态、说明和链接、保存变灰、格式错误、去前缀、保存后状态、原文显示、粘贴和清空的位置、保存按钮高度、舍弃确认（“继续编辑”）；页内退出确认文字、清空后保存等于退出；剪贴板粘贴、Ctrl+S 保存；哔哩哔哩和抖音先核验再存、“已保存，已登录”、重新核验按钮、核验失败照存；网易 CC 页；斗鱼的状态卡、续期组顺序、passport Cookie、立即续期、强制续期、页内退出；扫码的已扫描和失效覆盖层、二维码位置不动、200 大小、刷新后确认并存；平台拒绝时不存；“扫不了？”只有“填写 Cookie”（没有内置浏览器）并能返回扫码页；手机有内置浏览器时网页登录在前；宽屏二维码 220、Cookie 页一栏 ≤720；没有内置浏览器时网页登录地址的提醒；斗鱼会话说明的逻辑。原测试按新文字改：“虎牙 账号”→“虎牙账号”，“已登录：Alice”提示 →“已保存，已登录：Alice”，网页登录地址的提醒文字。
