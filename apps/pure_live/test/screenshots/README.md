# 截图测试（golden）

整个应用在假数据上逐页渲染，与 `goldens/` 里的 PNG 逐像素比较，用于设计复核和防止界面走样（PLAN 第 6 阶段“截图测试、五个宽度等级”）。

## 运行与更新

在 `apps/pure_live` 里（WSL，`source ~/tools/purelive-env.sh` 之后）：

```bash
flutter test test/screenshots                   # 比较
flutter test --update-goldens test/screenshots  # 界面有意改动后重新生成，提交前逐张看过
flutter test --exclude-tags screenshots         # 只跑其余测试
```

- 这组测试带 `@Tags(['screenshots'])`，标签在 `apps/pure_live/dart_test.yaml` 声明，**默认包含在 `flutter test` 和门禁里**：68 张在 WSL 上约 23 秒（连编译约 31 秒），低于 60 秒的门槛；整个应用的 `flutter test` 因此从约 49 秒变为约 85 秒（2026-09-28 实测）。
- 比较失败时，差异图写在 `test/screenshots/failures/`（`*_masterImage`、`*_testImage`、`*_isolatedDiff`、`*_maskedDiff`，已忽略，不提交）。
- 更新后用图片查看器或 `git diff --stat` 检查哪些图变了；只改了一处界面却有很多图变化，通常说明改动波及了共用组件。
- 找不到字体文件的机器（例如 Windows 主机）上整组跳过，不算失败，控制台打印 `screenshots skipped: …`。

## 字体

测试引擎默认把所有字形画成方块，所以 `shot_fonts.dart` 在每个测试文件开始时加载真实字体：

| 用途 | 来源 | 注册名 |
|---|---|---|
| 中文（简体） | 系统的 Noto Sans CJK：`/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc`、`-Bold.ttc`（`fonts-noto-cjk`），取集合里的 SC 字面 | `Microsoft YaHei UI`（主题简体回退链的第一项，也是 Windows 的显式字体族）、`Segoe UI` |
| 中文（繁体） | 同上，取 TC 字面 | `Microsoft JhengHei UI` |
| 拉丁字母和数字（Android、TV） | Flutter SDK 的 Roboto：`$FLUTTER_ROOT/bin/cache/artifacts/material_fonts/Roboto-*.ttf` | `Roboto`，以及界面字体 `PureLive-screenshot-roboto` |
| 图标 | 同目录的 `MaterialIcons-Regular.otf` | `MaterialIcons` |
| 画面上的弹幕 | Noto Sans CJK SC | 弹幕字体 `PureLive-screenshot-noto` |

两处与真机不同，看图时注意：

- Android 主题不指定字体族，交给系统默认字体；测试引擎把“未指定”解析成方块字体，而且这一步排在所有回退之前。所以 Android 和 TV 截图把设置里的“界面字体”选成一个注册为 Roboto 的字体族，每个文字样式（包括组件主题里不带字体族的样式）都用 Roboto 显示拉丁字母，中文落到 Noto Sans CJK。Windows 截图不动，仍是主题给的 `Microsoft YaHei UI`，由 Noto Sans CJK SC 代替雅黑（拉丁字母也来自它）。
- 画面上的弹幕没有回退链，所以把弹幕字体选成 Noto Sans CJK SC。设置里“弹幕 › 字体”会显示这个值，因此没有截“弹幕”分组。

## 尺寸与平台

宽度等级按 `spec/design/principles.md` §5.1 各取一个代表尺寸，另加高度紧凑的手机横屏和 TV 画布（逻辑尺寸 × 设备像素比 = 图片像素）：

| 名称 | 逻辑尺寸 | 像素比 | 等级 | 平台 |
|---|---|---|---|---|
| `phone` | 393×852 | 1.5 | 紧凑 | Android |
| `phoneland` | 852×393 | 1.5 | 展开宽度 + 紧凑高度（横屏手机规则） | Android |
| `medium` | 768×1024 | 1 | 中等 | Android |
| `expanded` | 1024×768 | 1 | 展开 | Android |
| `large` | 1440×900 | 1 | 大 | Windows（桌面密度、指针控件、雅黑族） |
| `xlarge` | 1920×1080 | 1 | 超大 | Windows |
| `tv` | 960×540 | 1.5 | TV 模式（§5.3） | Android，`TvDevice(television: true)` |

文件名是 `<页面>_<尺寸>_<主题>_<语言>[_text<倍数>].png`。`text2.0` 是系统 1.5 倍乘以应用内 1.3 倍（§2.3 的上限）。

## 画面里是什么

- 数据全部是虚构的（`shot_world.dart`）：12 个开播直播间、4 个未开播的关注、搜索只有 B 站、斗鱼、虎牙有结果；标题故意有长有短，人数覆盖“523”到“128万”。
- 封面不加载网络图片，显示无封面时的占位；播放器用 `FakeEngine`，画面是黑的，控制层处于显示状态；聊天是一批固定的弹幕。
- 名字带 `-white` 的截图把画面换成纯白（`debugPictureBackground`，假引擎没有画面）：控制层的遮罩必须让白字在最亮的画面上也读得清（principles §2.2）。
- 录制中心只有“已完成”“失败”“已停止”三种任务：正在录制需要真的直播流。
- 时间：时长和“3 小时前”相对测试开始时刻计算；全屏时钟读 `clockProvider`，固定为 20:30。
- 已过首次启动：一次性提示不出现。阴影按真实方式绘制（测试框架默认把阴影画成黑边，这里关掉了）。
- “出错”截图用应用的重试策略 `networkRetry`（网络错误重试两次，1 s、2 s），推进 4 秒假时间后截：错误必须在 4 秒内出现。

## 页面清单（77 张）

| 文件 | 页面 | 尺寸 | 主题 | 语言 |
|---|---|---|---|---|
| `discover-areas_phone_light_zh-Hans.png` | 发现（分区） | 手机竖屏 | 浅色 | 简体 |
| `discover-error_expanded_dark_zh-Hans.png` | 发现（出错） | 展开 | 深色 | 简体 |
| `discover-error_phone_light_zh-Hans.png` | 发现（出错） | 手机竖屏 | 浅色 | 简体 |
| `discover-loading_large_dark_zh-Hans.png` | 发现（加载中） | 大（Windows） | 深色 | 简体 |
| `discover-loading_phone_light_zh-Hans.png` | 发现（加载中） | 手机竖屏 | 浅色 | 简体 |
| `discover_expanded_light_zh-Hans.png` | 发现 | 展开 | 浅色 | 简体 |
| `discover_large_dark_en.png` | 发现 | 大（Windows） | 深色 | 英文 |
| `discover_medium_dark_zh-Hans.png` | 发现 | 中等 | 深色 | 简体 |
| `discover_phone_dark_zh-Hans.png` | 发现 | 手机竖屏 | 深色 | 简体 |
| `discover_phone_light_en.png` | 发现 | 手机竖屏 | 浅色 | 英文 |
| `discover_phone_light_zh-Hans.png` | 发现 | 手机竖屏 | 浅色 | 简体 |
| `discover_phone_light_zh-Hant.png` | 发现 | 手机竖屏 | 浅色 | 繁体 |
| `discover_phoneland_dark_zh-Hans.png` | 发现 | 手机横屏 | 深色 | 简体 |
| `discover_xlarge_light_zh-Hans.png` | 发现 | 超大（Windows） | 浅色 | 简体 |
| `follows-banner_medium_light_zh-Hans.png` | 关注（平台异常横幅） | 中等 | 浅色 | 简体 |
| `follows-empty_phone_light_zh-Hans.png` | 关注（空） | 手机竖屏 | 浅色 | 简体 |
| `follows_expanded_dark_zh-Hans.png` | 关注 | 展开 | 深色 | 简体 |
| `follows_large_light_zh-Hans.png` | 关注 | 大（Windows） | 浅色 | 简体 |
| `follows_phone_dark_zh-Hans.png` | 关注 | 手机竖屏 | 深色 | 简体 |
| `follows_phone_light_zh-Hans.png` | 关注 | 手机竖屏 | 浅色 | 简体 |
| `follows_phone_light_zh-Hans_text2.0.png` | 关注 | 手机竖屏 | 浅色 | 简体 · 文字 ×2.0 |
| `follows_phoneland_light_zh-Hans.png` | 关注 | 手机横屏 | 浅色 | 简体 |
| `follows_xlarge_dark_zh-Hans.png` | 关注 | 超大（Windows） | 深色 | 简体 |
| `iptv_large_light_zh-Hans.png` | IPTV | 大（Windows） | 浅色 | 简体 |
| `iptv_phone_dark_zh-Hans.png` | IPTV | 手机竖屏 | 深色 | 简体 |
| `iptv_phone_light_zh-Hans.png` | IPTV | 手机竖屏 | 浅色 | 简体 |
| `me_large_dark_zh-Hans.png` | 我的 | 大（Windows） | 深色 | 简体 |
| `me_phone_light_zh-Hans.png` | 我的 | 手机竖屏 | 浅色 | 简体 |
| `multiview_expanded_light_zh-Hans.png` | 多画面 | 展开 | 浅色 | 简体 |
| `multiview_large_dark_zh-Hans.png` | 多画面 | 大（Windows） | 深色 | 简体 |
| `multiview_phone_dark_zh-Hans.png` | 多画面 | 手机竖屏 | 深色 | 简体 |
| `multiview_xlarge_light_zh-Hans.png` | 多画面 | 超大（Windows） | 浅色 | 简体 |
| `recording-empty_phone_light_zh-Hans.png` | 录制中心（空） | 手机竖屏 | 浅色 | 简体 |
| `recording_large_light_en.png` | 录制中心 | 大（Windows） | 浅色 | 英文 |
| `recording_phone_dark_zh-Hans.png` | 录制中心 | 手机竖屏 | 深色 | 简体 |
| `recording_phone_light_zh-Hans.png` | 录制中心 | 手机竖屏 | 浅色 | 简体 |
| `room_expanded_dark_zh-Hans.png` | 直播间 | 展开 | 深色 | 简体 |
| `room_large_light_zh-Hans.png` | 直播间 | 大（Windows） | 浅色 | 简体 |
| `room_medium_light_zh-Hans.png` | 直播间 | 中等 | 浅色 | 简体 |
| `room_phone_dark_zh-Hans.png` | 直播间 | 手机竖屏 | 深色 | 简体 |
| `room_phone_light_en.png` | 直播间 | 手机竖屏 | 浅色 | 英文 |
| `room_phone_light_zh-Hans.png` | 直播间 | 手机竖屏 | 浅色 | 简体 |
| `room_phoneland_light_zh-Hans.png` | 直播间（直接全屏） | 手机横屏 | 浅色 | 简体 |
| `room_xlarge_dark_zh-Hans.png` | 直播间 | 超大（Windows） | 深色 | 简体 |
| `room-chat_phoneland_dark_zh-Hans.png` | 直播间（全屏，聊天浮层） | 手机横屏 | 深色 | 简体 |
| `room-failed_phone_dark_zh-Hans.png` | 直播间（播放失败：重试、换线路） | 手机竖屏 | 深色 | 简体 |
| `room-loading_phone_light_zh-Hans.png` | 直播间（正在连接） | 手机竖屏 | 浅色 | 简体 |
| `room-tip_large_dark_zh-Hans.png` | 直播间（一次性提示） | 大（Windows） | 深色 | 简体 |
| `room-white_phone_light_zh-Hans.png` | 直播间（白色画面） | 手机竖屏 | 浅色 | 简体 |
| `room-white_phoneland_light_zh-Hans.png` | 直播间（白色画面，全屏和锁定键） | 手机横屏 | 浅色 | 简体 |
| `search-empty_large_dark_zh-Hans.png` | 搜索（无结果） | 大（Windows） | 深色 | 简体 |
| `search-empty_phone_light_zh-Hans.png` | 搜索（无结果） | 手机竖屏 | 浅色 | 简体 |
| `search_expanded_light_zh-Hans.png` | 搜索（有结果） | 展开 | 浅色 | 简体 |
| `search_large_dark_zh-Hans.png` | 搜索（有结果） | 大（Windows） | 深色 | 简体 |
| `search_phone_dark_en.png` | 搜索（有结果） | 手机竖屏 | 深色 | 英文 |
| `search_phone_light_zh-Hans.png` | 搜索（有结果） | 手机竖屏 | 浅色 | 简体 |
| `search_xlarge_light_zh-Hans.png` | 搜索（有结果） | 超大（Windows） | 浅色 | 简体 |
| `settings-general_medium_black_zh-Hans.png` | 设置 › 通用 | 中等 | 纯黑 | 简体 |
| `settings-playback_phone_dark_zh-Hans.png` | 设置 › 播放 | 手机竖屏 | 深色 | 简体 |
| `settings-playback_phone_light_en.png` | 设置 › 播放 | 手机竖屏 | 浅色 | 英文 |
| `settings-playback_phone_light_zh-Hans.png` | 设置 › 播放 | 手机竖屏 | 浅色 | 简体 |
| `settings-playback_phone_light_zh-Hant_text2.0.png` | 设置 › 播放 | 手机竖屏 | 浅色 | 繁体 · 文字 ×2.0 |
| `settings-playback_xlarge_light_zh-Hans.png` | 设置（两栏，选中播放） | 超大（Windows） | 浅色 | 简体 |
| `settings_expanded_light_zh-Hans.png` | 设置首页（两栏） | 展开 | 浅色 | 简体 |
| `settings_large_dark_en.png` | 设置首页（两栏） | 大（Windows） | 深色 | 英文 |
| `settings_phone_dark_zh-Hans.png` | 设置首页 | 手机竖屏 | 深色 | 简体 |
| `settings_phone_light_en.png` | 设置首页 | 手机竖屏 | 浅色 | 英文 |
| `settings_phone_light_zh-Hans.png` | 设置首页 | 手机竖屏 | 浅色 | 简体 |
| `settings_phone_light_zh-Hant.png` | 设置首页 | 手机竖屏 | 浅色 | 繁体 |
| `tv-discover_tv_dark_zh-Hans.png` | TV 发现（焦点在卡片） | TV | 深色 | 简体 |
| `tv-follows-card_tv_black_zh-Hans.png` | TV 首页（焦点在卡片） | TV | 纯黑 | 简体 |
| `tv-follows_tv_dark_zh-Hans.png` | TV 首页（焦点在导航轨，轨道展开） | TV | 深色 | 简体 |
| `tv-room_tv_dark_zh-Hans.png` | TV 直播间（按 OK 后的信息栏和控制行） | TV | 深色 | 简体 |
| `tv-room-list_tv_dark_zh-Hans.png` | TV 直播间（左侧直播间列表） | TV | 深色 | 简体 |
| `tv-room-settings_tv_dark_zh-Hans.png` | TV 直播间（右侧播放设置） | TV | 深色 | 简体 |
| `tv-room-white_tv_dark_zh-Hans.png` | TV 直播间（白色画面上的信息栏） | TV | 深色 | 简体 |
| `tv-settings_tv_dark_zh-Hans.png` | TV 设置（焦点在分组列表） | TV | 深色 | 简体 |

## 加一张截图

1. 在对应的 `*_screens_test.dart` 里写 `screenshot('<页面>', ShotScreen.<尺寸>, (app) => app.go('<路由>'), theme: …, locale: …)`；全屏路由用 `app.push`，需要等待的状态用 `app.frames()`。
2. 页面要的数据放进 `ShotWorld`；需要的 provider 替换放进 `ShotApp.pump`。
3. `flutter test --update-goldens test/screenshots --plain-name <文件名>` 生成，看过再提交，并把它加进上表。
4. 总量控制在 8 MB 以内（现在约 7.0 MB）。
