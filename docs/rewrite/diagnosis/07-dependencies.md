# v4 第 0 阶段诊断：依赖

依据 master（v3.2.11）的 `pubspec.yaml` / `pubspec.lock`、`build/` 中 2026-09-27 的 arm64 Release APK、Windows Release 目录；pub.dev、GitHub 数据于 2026-09-27 实时查询。直接依赖共 143 个非 SDK 条目（dependencies 120、dev 10、overrides 13），另有 4 个 SDK 包。hosted 包全部是 pub.dev 最新版；落后的只有 path/git 形式引入的包。本次只读，未改动仓库；临时文件在 scratchpad。

## ① 依赖总表

图例：⚠ 表示最后一次发版早于 2025-09-27；“导出≈N” 表示该包经 `lib/common/index.dart` 转出口，按符号估算的使用文件数；〔PLAN〕表示与第 04 节一致。另外，`media_kit`、`fvp`、`xml`、`wakelock_plus`、`screen_retriever` 同时出现在 dependency_overrides 中。

| 名称 | 锁定 | pub 最新（发布） | lib 文件 | 用途 | 许可证 | v4 处置 |
|---|---|---|---|---|---|---|
| flutter / flutter_localizations / flutter_test / integration_test | SDK | 3.47.5 | — | 框架/测试 | BSD-3 | 保留 |
| **通用/编解码** | | | | | | |
| archive | 4.3.0 | 4.3.0（2026-09-13） | 2 | EPG gz/zip | MIT | 保留 |
| brotli | 0.6.0 | 0.6.0（2023-05-13） ⚠ | 1 | B站弹幕解压 | MIT | 评估：改 zlib 协议后删 [待确认] |
| charset_converter | 2.5.1 | 2.5.1（2026-07-18） | 2 | GBK 解码（M3U/HTTP） | BSD-3 | 评估→纯 Dart |
| crypto | 3.0.7 | 3.0.7（2025-11-04） | 14 | MD5/SHA 签名 | BSD-3 | 保留 |
| crypto_simple | 3.0.2 | 3.0.2（2024-09-20） ⚠ | 0 | 未使用 | MIT | 删除 |
| dart_sm | 0.1.5 | 0.1.5（2024-04-12） ⚠ | 1 | 抖音 a_bogus SM3 | Apache-2.0 | 评估→适配器内自写 |
| date_format | 2.0.9 | 2.0.9（2024-08-21） ⚠ | 2 | 备份文件名日期 | BSD-3 | 删除→intl |
| equatable | 3.0.0 | 3.0.0（2026-09-15） | 4 | IPTV 模型相等 | MIT | 删除→freezed〔PLAN〕 |
| ffi | 2.2.0 | 2.2.0（2026-02-11） | 1 | Win 自启 | BSD-3 | 保留 |
| file | 7.0.1 | 7.0.1（2024-10-08） ⚠ | 0 | 未使用 | BSD-3 | 删除 |
| fixnum | 1.1.1 | 1.1.1（2024-10-16） ⚠ | 1 | protobuf 整数 | BSD-3 | 保留 |
| fuzzywuzzy | 1.2.0 | 1.2.0（2024-08-15） ⚠ | 1 | 弹幕相似过滤 | GPL-2.0 | 删除（GPL-2.0）〔PLAN 合并〕 |
| hashlib | 2.4.2 | 2.4.2（2026-07-08） | 0 | 未使用 | BSD-3 | 删除 |
| html | 0.15.7 | 0.15.7（2026-08-28） | 7 | 页面解析 | MIT | 保留 |
| html_unescape | 2.0.0 | 2.0.0（2021-03-22） ⚠ | 1 | 斗鱼标题实体解码 | BSD-3 | 删除→html 包 |
| logger | 2.8.0 | 2.8.0（2026-09-05） | 4 | 日志 | MIT | 替换→talker〔PLAN〕 |
| meta | 1.19.0 | 1.19.0（2026-07-09） | 4 | 注解 | BSD-3 | 保留 |
| path | 1.9.1 | 1.9.1（2024-10-17） ⚠ | 22 | 路径 | BSD-3 | 保留 |
| pinyindart | 0.0.1 | 0.0.1（2026-03-16） | 1 | 录制文件名拼音 | MIT | 删除 |
| pointycastle | 4.0.0 | 4.0.0（2025-02-19） ⚠ | 3 | AES/RSA（克拉克拉/Bigo/LookLive） | MIT | 保留（评估 cryptography） |
| pro_mpack | 3.2.0 | 3.2.0（2026-07-25） | 1 | 分享口令 msgpack | MIT | 评估（兼容旧口令） |
| protobuf | 6.1.0 | 6.1.0（2026-09-11） | 2 | 抖音弹幕 | BSD-3 | 保留〔PLAN〕 |
| qr | 4.0.0 | 4.0.0（2026-05-16） | 2 | B站登录二维码 | BSD-3 | 保留 |
| quiver | 3.2.2 | 3.2.2（2024-08-28） ⚠ | 0 | 未使用 | Apache-2.0 | 删除 |
| rxdart | 0.28.0 | 0.28.0（2024-06-14） ⚠ | 6 | 流合并 | Apache-2.0 | 删除〔PLAN〕 |
| stop_watch_timer | 3.2.2 | 3.2.2（2025-04-16） ⚠ | 3 | 定时关闭 | MIT | 删除→Timer |
| string_similarity | 2.2.0 | 2.2.0（2026-04-04） | 3 | IPTV/分区图匹配 | MIT | 合并：留一个或自写〔PLAN〕 |
| synchronized | 3.4.2 | 3.4.2（2026-09-10） | 8 | 异步锁 | MIT | 保留 |
| timezone | 0.11.1 | 0.11.1（2026-06-29） | 0 | 未使用 | BSD-2 | 删除 |
| uuid | 4.6.0 | 4.6.0（2026-07-15） | 7 | 备份/IPTV 主键 | MIT | 保留 |
| xml | 7.0.1 | 7.0.1（2026-04-25） | 1 | XMLTV/WebDAV | MIT | 保留 |
| **网络/系统集成** | | | | | | |
| android_intent_plus | 6.1.0 | 6.1.0（2026-07-23） | 1 | 打开文件/Intent | BSD-3 | 保留 |
| app_links | 7.2.1 | 7.2.1（2026-07-09） | 0 | 未使用（仅注册） | Apache-2.0 | 删除 |
| bonsoir | 7.1.5 | 7.1.5（2026-08-11） | 1 | 局域网发现 | MIT | 保留（局域网同步） |
| connectivity_plus | 7.3.1 | 7.3.1（2026-07-23） | 2 | 网络状态 | BSD-3 | 保留 |
| cookie_jar | 4.0.9 | 4.0.9（2026-02-27） | 1 | Cookie 存储 | MIT | 保留，持久层改加密 |
| device_info_plus | 13.2.0 | 13.2.0（2026-06-26） | 3 | 设备信息 | BSD-3 | 保留 |
| dio | 5.11.1 | 5.11.1（2026-09-04） | 79 | HTTP | MIT | 保留（重写）〔PLAN〕 |
| dio_cookie_manager | 3.5.0 | 3.5.0（2026-07-25） | 1 | Cookie 拦截 | MIT | 保留 |
| dlna_dart | 0.1.1 | 0.1.1（2026-06-26） | 1 | DLNA 投屏 | BSD-3 | 保留 |
| flutter_inappwebview | 6.2.0-beta.3（git） | 6.1.5（2024-10-08） ⚠ | 7 | 网页登录/搜索 | Apache-2.0 | 隔离〔PLAN〕；现为 beta 分支 |
| http | 1.6.0 | 1.6.0（2025-11-10） | 2 | race_http/缓存 | BSD-3 | 删除直接依赖（统一 dio） |
| permission_handler | 13.0.2 | 13.0.2（2026-09-04） | 1+导出≈5 | 权限 | MIT | 保留 |
| share_handler | 0.0.25 | 0.0.25（2025-07-29） ⚠ | 2+导出≈4 | 接收分享 | MIT | 评估→自写 ACTION_SEND |
| share_plus | 13.3.0 | 13.3.0（2026-07-23） | 1 | 系统分享 | BSD-3 | 保留 |
| stream_channel | 2.1.4 | 2.1.4（2025-01-07） ⚠ | 1 | YY 大小写敏感 WS | BSD-3 | 保留 |
| url_launcher | 6.3.2 | 6.3.2（2025-07-10） ⚠ | 14 | 外链 | BSD-3 | 保留 |
| web_socket_channel | 3.0.3 | 3.0.3（2025-04-17） ⚠ | 4 | 弹幕 WS | BSD-3 | 保留〔PLAN〕 |
| **数据/文件** | | | | | | |
| cloud_firestore | 6.10.0 | 6.10.0（2026-09-14） | 6 | 云同步 | BSD-3（含 GMS 专有） | 删除 |
| drift | 2.35.0 | 2.35.0（2026-09-09） | 5 | IPTV 库 | MIT | 保留（扩大）〔PLAN〕 |
| file_picker | 13.1.0 | 13.1.0（2026-09-15） | 5 | 选文件/目录 | MIT | 保留 |
| firebase_auth | 6.7.0 | 6.7.0（2026-09-14） | 4 | Firebase 登录 | BSD-3（含 GMS 专有） | 删除 |
| firebase_core | 4.15.0 | 4.15.0（2026-09-14） | 2 | Firebase | BSD-3（含 GMS 专有） | 删除（宪法；PLAN §04 仍写待定） |
| flutter_cache_manager | 3.4.5 | 3.4.5（2026-09-19） | 1 | 图片/文件缓存（带 sqflite） | MIT | 随图片方案，建议删除 |
| hive_ce | 2.20.0 | 2.20.0（2026-09-12） | 2 | 设置/关注存储 | Apache-2.0 | 仅迁移〔PLAN〕 |
| hive_ce_flutter | 2.3.4 | 2.3.4（2026-01-09） | 1 | Hive 初始化 | Apache-2.0 | 仅迁移〔PLAN〕 |
| mime | 2.1.0 | 2.1.0（2026-08-28） | 1 | MIME | BSD-3 | 保留 |
| open_filex | 4.7.0 | 4.7.0（2025-03-06） ⚠ | 2 | 打开 APK/文件 | BSD-3 | 评估→自写 Intent |
| path_provider | 2.1.6 | 2.1.6（2026-06-15） | 4+导出≈8 | 目录 | BSD-3 | 保留 |
| path_provider_platform_interface | 2.1.3 | 2.1.3（2026-06-15） | 2 | Windows 数据目录重定向 | BSD-3 | 保留 |
| path_provider_windows | 2.3.0 | 2.3.0（2024-07-09） ⚠ | 1 | 同上 | BSD-3 | 保留 |
| shared_preferences_platform_interface | 2.4.2 | 2.4.2（2026-03-25） | 1 | Windows 便携目录重定向（easy_localization 存语言） | BSD-3 | 删除（v4 无 SharedPreferences 使用者时） |
| shared_preferences_windows | 2.4.1 | 2.4.1（2024-08-09） ⚠ | 1 | 同上 | BSD-3 | 同上 |
| uri_to_file | 1.0.0 | 1.0.0（2023-10-27） ⚠ | 1+导出≈0 | 未使用 | MIT | 删除 |
| webdav_client | 1.2.2 | 1.2.2（2024-05-12） ⚠ | 3 | WebDAV 备份 | BSD-3 | 替换→dio 自写（PLAN 未列） |
| **播放/媒体** | | | | | | |
| audio_service | 0.18.19 | 0.18.19（2026-06-29） | 2 | 后台播放/通知 | MIT | 保留〔PLAN〕 |
| audio_service_win | 0.0.3 | 0.0.3（2026-03-29） | 0 | Windows SMTC | MIT | 保留（PLAN 未列） |
| audio_session | 0.2.4 | 0.2.4（2026-06-29） | 1 | 音频焦点 | MIT | 保留（PLAN 未列） |
| battery_plus | 7.1.1 | 7.1.1（2026-07-15） | 1 | 播放器电量 | BSD-3 | 评估 |
| better_player_plus | 1.3.5（path） | 1.4.1（2026-09-04） | 2 | Exo 内核 | Apache-2.0 | 删除〔PLAN〕 |
| ffmpeg_kit_extended_flutter | 0.6.2 | 0.6.2（2026-08-31） | 1 | 录制 FFmpeg | LGPL-3.0 | 删除〔PLAN〕 |
| flame_barrage | 0.0.4（path） | 0.0.7（2026-09-27） | 8 | 弹幕渲染（引入 flame） | MIT | 替换→canvas_danmaku/自研〔PLAN〕 |
| floating | 6.0.0（path） | 6.0.0（2025-02-14） ⚠ | 1 | 系统画中画 | MIT | 合并→自写〔PLAN〕 |
| flutter_floating | 2.0.2 | 2.0.2（2026-01-22） | 2 | 应用内小窗 | MIT | 合并→自写〔PLAN〕 |
| flv_lzc | 1.0.4+purelive.2（path） | 1.0.1（2025-11-15） | 2+导出≈5 | IJK 内核 | MIT（IJK LGPL-2.1） | 删除〔PLAN〕 |
| fvp | 0.38.1（path） | 0.38.1（2026-08-17） | 1 | 备用内核 | BSD-3（libmdk 专有） | PLAN 保留；建议评估（见④⑥） |
| media_kit | 1.1.11（path） | 1.2.6（2025-12-13） | 3 | mpv 播放 | MIT | 保留（Predidit 分支）〔PLAN〕 |
| media_kit_video | 1.2.5（path） | 2.0.1（2025-12-02） | 5 | mpv 视频输出 | MIT | 保留（本地补丁）〔PLAN〕 |
| screen_brightness_android | 2.1.6 | 2.1.6（2026-06-14） | 0 | 亮度手势 | MIT | 保留 |
| screen_brightness_ios | 2.1.4 | 2.1.4（2026-06-14） | 0 | 亮度手势 | MIT | 保留 |
| screen_brightness_platform_interface | 2.1.2 | 2.1.2（2026-06-14） | 1 | 亮度手势 | MIT | 保留 |
| volume_controller | 3.7.1 | 3.7.1（2026-09-18） | 1 | 音量手势 | MIT | 保留 |
| wakelock_plus | 1.8.0 | 1.8.0（2026-09-01） | 2 | 常亮 | BSD-3 | 保留 |
| **界面** | | | | | | |
| animated_splash_plus | 1.0.3 | 1.0.3（2025-04-24） ⚠ | 0 | 未使用 | MIT | 删除〔PLAN〕 |
| best_form_validator | 1.4.0 | 1.4.0（2026-07-21） | 1 | Firebase 邮箱表单 | MIT | 删除 |
| bordered_text | 3.0.2 | 3.0.2（2026-04-13） | 0 | 未使用 | MIT | 删除 |
| cached_network_image | 4.0.2 | 4.0.2（2026-09-23） | 7 | 网络图片 | MIT | 二选一〔PLAN〕，建议 extended_image |
| dynamic_color | 2.1.0 | 2.1.0（2026-08-20） | 2+导出≈1 | 系统取色 | Apache-2.0 | 按设计定〔PLAN〕 |
| easy_localization | 3.0.8 | 3.0.8（2025-07-24） ⚠ | 9 | 多语言 | MIT | 替换→slang〔PLAN〕 |
| easy_refresh | 3.5.1 | 3.5.1（2026-06-14） | 1+导出≈13 | 下拉刷新/加载 | MIT | 评估→官方 Sliver〔PLAN〕 |
| flex_color_picker | 4.0.0 | 4.0.0（2026-08-30） | 6 | 主题色选择 | BSD-3 | 评估（按设计） |
| flutter_color | 2.1.1 | 2.1.1（2026-08-20） | 1+导出≈1 | 仅 HexColor | MIT | 删除 |
| flutter_json | 0.2.0 | 0.2.0（2026-08-14） | 2 | 调试页 JSON 树 | MIT | 删除 |
| flutter_reorderable_grid_view | 5.7.0 | 5.7.0（2026-05-31） | 1 | 标签拖动排序 | BSD-3 | 评估→SliverReorderableList |
| flutter_smart_dialog | 5.3.0 | 5.3.0（2026-08-23） | 2+导出≈6 | 全局弹窗/Toast | MIT | 删除（PLAN 未列） |
| flutter_spinkit | 5.2.2 | 5.2.2（2025-08-11） ⚠ | 2 | 加载动画 | MIT | 删除〔PLAN〕 |
| flutter_svg | 2.3.0 | 2.3.0（2026-05-08） | 1 | SVG 图标 | MIT | 保留 |
| font_awesome_flutter | 11.0.0 | 11.0.0（2026-03-09） | 0 | 未使用 | MIT | 删除〔PLAN〕 |
| loading_animation_widget | 1.3.0 | 1.3.0（2024-10-02） ⚠ | 2 | 加载动画 | BSD-3 | 删除〔PLAN〕 |
| loading_indicator | 4.0.2 | 4.0.2（2026-08-30） | 2 | 加载动画 | Apache-2.0 | 删除〔PLAN〕 |
| lottie | 3.6.1 | 3.6.1（2026-09-18） | 0 | 未使用（assets 仍打包） | MIT | 删除 |
| markdown_widget | 2.3.2+8 | 2.3.2+8（2025-04-26） ⚠ | 3 | 更新日志渲染 | MIT | 评估→flutter_markdown_plus |
| material_ui | 1.4.0 | 1.4.0（2026-09-22） | 3 | 解耦 Material 桥接 | BSD-3 | 评估（随 Flutter 解耦） |
| mobile_scanner | 7.4.0（path） | 7.4.2（2026-09-14） | 2 | 扫码导入 | BSD-3（ML Kit 专有） | 评估→flutter_zxing〔PLAN 评估〕 |
| photo_view | 0.15.0 | 0.15.0（2024-04-17） ⚠ | 1 | WebDAV 帮助图缩放 | MIT | 删除→InteractiveViewer |
| remixicon | 4.9.3 | 4.9.3（2026-04-04） | 61 | 图标 | MIT | 删除→Material Symbols〔PLAN〕 |
| scroll_animator | 0.3.0 | 0.3.0（2024-10-31） ⚠ | 1 | 桌面平滑滚动 | BSD-3 | 评估 |
| scrollview_observer | 1.27.3 | 1.27.3（2026-09-14） | 0 | 未使用 | MIT | 删除〔PLAN 评估〕 |
| syncfusion_flutter_sliders | 34.2.9 | 34.2.9（2026-09-22） | 4 | 滑块 | Syncfusion 专有 | 删除→Material Slider〔PLAN〕 |
| waterfall_flow | 3.1.1 | 3.1.1（2025-01-24） ⚠ | 3 | 瀑布流 | MIT | 删除→SliverGrid〔PLAN 评估〕 |
| **桌面/系统** | | | | | | |
| flutter_acrylic | 1.1.4 | 1.1.4（2024-06-11） ⚠ | 1 | 窗口特效 | MIT | 删除/按设计 |
| flutter_exit_app | 2.1.2（path） | 2.1.2（2026-06-03） | 1 | 退出应用 | MIT | 删除→自写 |
| move_to_desktop | 0.0.2 | 0.0.2（2023-11-03） ⚠ | 1 | 返回桌面 | BSD-3 | 删除→自写 |
| package_info_plus | 10.2.1 | 10.2.1（2026-07-15） | 3 | 版本号 | BSD-3 | 保留 |
| screen_retriever | 0.2.0（git） | 0.2.2（2026-07-04） | 1 | 多显示器 | MIT | 改回 pub 0.2.2 |
| tray_manager | 0.7.0 | 0.7.0（2026-09-19） | 1 | 托盘 | MIT | 保留，Android 排除 .so |
| win32 | 6.4.0 | 6.4.0（2026-08-05） | 1 | Win API | BSD-3 | 保留 |
| win32_registry | 3.0.3 | 3.0.3（2026-04-11） | 2 | 自启/安装目录 | BSD-3 | 保留 |
| window_manager | 0.5.2 | 0.5.2（2026-07-04） | 3+导出≈8 | 桌面窗口 | MIT | 保留〔PLAN〕 |
| windows_single_instance | 1.2.0 | 1.2.0（2026-06-16） | 1 | 单实例 | MIT | 保留 |
| **dev_dependencies** | | | | | | |
| build_runner | 2.16.1 | 2.16.1（2026-09-02） | 0 | 代码生成 | BSD-3 | 保留 |
| change_app_package_name | 1.5.0 | 1.5.0（2025-02-23） ⚠ | 0 | 改包名 | MIT | 删除 |
| dmg | 0.1.10 | 0.1.10（2026-05-04） | 0 | macOS 打包 | MIT | 评估（后续平台） |
| drift_dev | 2.35.0 | 2.35.0（2026-09-09） | 0 | drift 生成 | MIT | 保留 |
| enven | 1.3.0 | 1.3.0（2026-04-02） | 0 | 环境变量生成 | MIT | 删除→--dart-define-from-file |
| flutter_launcher_icons | 0.14.4 | 0.14.4（2025-06-10） ⚠ | 0 | 图标生成 | MIT | 保留 |
| flutter_lints | 6.0.0 | 6.0.0（2025-05-27） ⚠ | 0 | 静态检查 | BSD-3 | 替换→very_good_analysis〔PLAN〕 |
| intl_utils | 2.8.16 | 2.8.16（2026-06-11） | 0 | 未使用 | BSD-3 | 删除 |
| msix | 3.18.0 | 3.18.0（2026-06-27） | 0 | MSIX 打包 | MIT | 保留 |
| shared_preferences | 2.5.5 | 2.5.5（2026-03-25） | 0 | 测试替身 | BSD-3 | 删除 |
| **dependency_overrides** | | | | | | |
| _fe_analyzer_shared | 108.0.0 | 108.0.0（2026-09-11） | 0 | 越过 SDK 锁定 | BSD-3 | 删除覆盖 |
| analyzer | 14.4.0 | 14.4.0（2026-09-11） | 0 | 越过 SDK/上游锁定 | BSD-3 | 删除覆盖 |
| cli_util | 0.6.0 | 0.6.0（2026-08-21） | 0 | 越过 SDK/上游锁定 | BSD-3 | 删除覆盖 |
| code_assets | 2.1.0 | 2.1.0（2026-09-16） | 0 | Native Assets | BSD-3 | 评估（media_kit 钩子需要） |
| dbus | 0.8.0 | 0.8.0（2026-09-16） | 0 | 越过 SDK/上游锁定 | MPL-2.0 | 删除覆盖 |
| file_picker_linux | 2.0.1 | 2.0.1（2026-09-22） | 0 | 越过 SDK/上游锁定 | MIT | 删除覆盖 |
| flutter_inappwebview_android | 1.2.0-beta.3（path） | 1.1.3（2024-10-02） ⚠ | 0 | AGP9/ProGuard 补丁 | Apache-2.0 | 随网页方案 |
| hooks | 2.2.0 | 2.2.0（2026-08-18） | 0 | Native Assets | BSD-3 | 评估（media_kit 钩子需要） |
| material_color_utilities | 0.13.1 | 0.13.1（2026-08-10） | 0 | 越过 SDK/上游锁定 | Apache-2.0 | 删除覆盖 |
| nm | 0.6.0 | 0.6.0（2026-09-23） | 0 | 越过 SDK/上游锁定 | MPL-2.0 | 删除覆盖 |
| share_handler_android | 0.0.11（path） | 0.0.11（2025-07-29） ⚠ | 0 | 分享接收补丁 | MIT | 随 share_handler |
| source_gen | 4.3.0 | 4.3.0（2026-08-19） | 0 | 越过 SDK/上游锁定 | BSD-3 | 删除覆盖 |
| test_api | 0.7.14 | 0.7.14（2026-09-02） | 0 | 越过 SDK/上游锁定 | BSD-3 | 删除覆盖 |

**13 个直接依赖在 lib/ 中没有使用**：hashlib、crypto_simple、quiver、file、timezone、lottie、bordered_text、font_awesome_flutter、animated_splash_plus、app_links、scrollview_observer、uri_to_file、intl_utils。

**与 PLAN 第 04 节不一致的地方**
1. firebase_*：第 04 节写“待定”，宪法已决定移除，本表按删除处理。
2. fvp：第 04 节写“保留”。但它带来闭源的 libmdk（见④），还带来第 4 份 FFmpeg（libffmpeg.so 7.9 MB，另加 libass 1.3 MB），并通过 video_player 间接引入 video_player_android（Exo/Media3）。这与“去掉 Exo、共用一份 FFmpeg”冲突，建议写 ADR 重新评估。
3. native_dio_adapter 是 Flutter 插件，放不进纯 Dart 的 live_net（宪法第 7 条），只能在应用层注入。它只覆盖 Android（cronet_http 默认依赖 GMS 的 play-services-cronet，国内没有 GMS 的机型无法使用）和 Apple；Windows 仍回退到 dart:io，第 02 节“Windows 不跟随系统代理”的问题没有解决。
4. flutter_inappwebview：第 04 节写的是 6.1.5，实际使用 guide-inc-org 分支的 6.2.0-beta.3 加本地 Android 补丁，违反“不用 beta”。回到 6.1.5 能否在 AGP 9.4 上编译 [待确认]。
5. 图片库“二选一”：建议选 extended_image，或自写走 dio 的 ImageProvider。cached_network_image 依赖 flutter_cache_manager，后者会带入 sqflite，与 drift/sqlite3 形成第二套 SQLite。
6. 第 04 节没有覆盖、但需要处置的：上面 13 个未使用依赖；webdav_client、flutter_smart_dialog、audio_service_win、audio_session；tray_manager 在 Android 上的副作用（见⑥）；Cookie 加密存储需要的 flutter_secure_storage（11.2.0）。

## ② 冗余组

| 功能 | 现有 | v4 |
|---|---|---|
| 加载动画 | flutter_spinkit、loading_animation_widget、loading_indicator、lottie（未用，但 3 个 json 仍打包） | 设计系统自绘 1 个 |
| 模糊匹配 | string_similarity（3）、fuzzywuzzy（1，GPL） | 自写 Dice/编辑距离，或只留 string_similarity |
| 图标 | remixicon（61 个文件）、font_awesome_flutter（0）、CustomIcons.ttf、Material Icons、flutter_svg | material_symbols_icons 4.2960.0（或子集字体）+ 少量 SVG |
| 悬浮窗 | floating（系统画中画，含本地补丁）、flutter_floating（应用内小窗） | 自写一个 PiP/小窗模块 |
| 播放器 | media_kit（libmpv）、fvp（libmdk，另带 video_player_android）、better_player_plus（Exo）、flv_lzc（IJK） | mpv（fvp 待定） |
| FFmpeg 副本 | Android：libmpv 静态链接一份、libffmpegkit、libijkffmpeg、fvp 的 libffmpeg；Windows：libmpv-2.dll、libffmpegkit.dll | 每个平台一份共享库 |
| 日志 | logger、自写 core_log | talker |
| 国际化 | easy_localization、intl_utils（未用）、shared_preferences 重定向 | slang |
| 刷新/滚动 | easy_refresh、scrollview_observer（未用）、scroll_animator | 官方 RefreshIndicator + Sliver |
| 瀑布流/网格 | waterfall_flow、flutter_reorderable_grid_view | SliverGrid + SliverReorderableList |
| HTTP | dio、http、dart:io HttpClient（race_http）、charset_converter | dio + 原生适配器 |
| 加密/哈希 | crypto、hashlib（未用）、crypto_simple（未用）、pointycastle、dart_sm | crypto + pointycastle + 适配器内自写 SM3 |
| HTML | html、html_unescape | html |
| 存储 | hive_ce、drift/sqlite3、sqflite（间接）、shared_preferences（间接） | drift |
| 状态/模型 | 内置 GetX、rxdart、equatable、stop_watch_timer | Riverpod + freezed |
| 弹窗/控件 | flutter_smart_dialog、GetX 对话框、syncfusion 滑块、best_form_validator | 设计系统组件 |
| 颜色 | dynamic_color、material_ui、flex_color_picker、flutter_color | 按设计定 |
| 系统小功能 | flutter_exit_app、move_to_desktop、app_links（未用）、share_handler、open_filex | 自写一个 Android 平台通道 |

## ③ 陈旧依赖与维护问题

dart.dev、flutter.dev 的官方包（path、fixnum、stream_channel、web_socket_channel、url_launcher、path_provider_windows、shared_preferences_windows、file）只是功能稳定、不需要发版，不算风险。

| 依赖 | 最后发版 | 问题 |
|---|---|---|
| flutter_inappwebview | 6.1.5（2024-10） | 214 个未关闭 issue；项目实际用第三方 beta 分支 |
| media_kit / media_kit_video | 1.2.6 / 2.0.1（2025-12） | 官方仓库有提交但不发版；我们依赖单人维护的 Predidit 分支 |
| ffmpeg_kit_extended_flutter | 0.6.2（2026-08） | 上游 arthenica/ffmpeg-kit 已归档；接手者规模小（34 赞） |
| flv_lzc / ijkplayer | fplayer-core 1.0.4 | 内置 FFmpeg 是 4.0 时代（Lavc58.18）；Maven 上的包不满足 16 KB 对齐，只能本地重编 |
| webdav_client | 2024-05 | 28 个 issue；需要覆盖 xml 版本才能解析 |
| easy_localization | 2025-07 | 221 个 issue |
| photo_view | 2024-04 | 119 个 issue |
| pointycastle | 2025-02 | 66 个 issue |
| share_handler | 2025-07 | 62 个 issue；GitHub 仓库没有许可证元数据 |
| markdown_widget | 2025-04 | 46 个 issue |
| flutter_acrylic | 2024-06 | 27 个 issue |
| html_unescape、brotli、move_to_desktop、uri_to_file | 2021–2023 | 长期无人维护 |
| dart_sm、crypto_simple、date_format、fuzzywuzzy、loading_animation_widget、scroll_animator、rxdart、quiver | 2024 | 超过 12 个月没有发版 |
| floating、animated_splash_plus、stop_watch_timer、open_filex、waterfall_flow、flutter_spinkit | 2025-01 至 2025-08 | 超过 12 个月没有发版 |
| firebase_auth / firebase_core | 2026-09 | 仍应用 KGP，与 AGP 9 内置 Kotlin 冲突（见 5537e272 的提交说明） |
| 采用率极低 | — | pinyindart（0 赞）、move_to_desktop（1）、flame_barrage（1）、audio_service_win（3）、flutter_json（5）、pro_mpack（5）、crypto_simple（9）、dart_sm（11，115/160 分） |

## ④ 许可证风险

| 依赖 | 许可 | 风险 | 处置 |
|---|---|---|---|
| syncfusion_flutter_sliders（及 syncfusion_flutter_core） | Syncfusion 专有；社区许可要求年收入低于 100 万美元、开发者少于 5 人，并需同意其条款 | 附加限制与 AGPL 第 7、10 条冲突；每个下游分发者也需要自己的许可 | 删除（v3 也应尽快删除） |
| fvp 的 libmdk | 闭源；“Flutter 用户免费，已内置密钥” | 不是系统库的专有组件，无法提供对应源码，与 AGPL 不兼容，除非全部版权人给出链接例外 [待确认] | 删除 fvp，或写 ADR 并附例外条款 |
| mobile_scanner 的 ML Kit（libbarhopper_v3） | Google ML Kit 条款（专有） | 同上；另外依赖 GMS | 换 zxing-cpp 系（flutter_zxing，MIT/Apache-2.0） |
| firebase_*（Android 端依赖 play-services） | 插件 BSD-3，GMS 为专有 | 同上 | 删除（已决定） |
| cronet_http（PLAN 计划新增） | 默认依赖 play-services-cronet | 同上，且国内机型不可用 | 使用 `cronetHttpNoPlay=true` 内嵌 Cronet（增加体积 [待确认]） |
| fuzzywuzzy | GPL-2.0，源码中没有写“或更高版本” | 如果是 GPL-2.0-only，与 AGPL-3.0 不兼容 [待确认] | 删除 |
| pinyindart | pub.dev 标 MIT，GitHub 显示 NOASSERTION | 来源不清 | 删除 |

**FFmpeg 与 `--enable-version3` 的影响**（从 .so/.dll 的字符串实测）：Android 的 libmpv（Predidit 的 default 配置：`--disable-gpl --disable-nonfree --enable-version3 --enable-mbedtls`，mpv 用 `-Dgpl=false`）和 libffmpegkit（ffmpeg-kit-builders 固定加 `--enable-version3`）都显示 “LGPL version 3 or later”；Windows 的 libmpv-2.dll（`--enable-version3 --enable-openssl`）与之相同。IJK 和 fvp 自带的 FFmpeg 是 LGPL 2.1+。结论：
- LGPLv3 与 AGPL-3.0 兼容，这个开关也是必要的：FFmpeg 9.0.2 的 configure 把 mbedTLS 列为必须使用 version3 的库；OpenSSL 3 是 Apache-2.0，按 FSF 的观点也只与 (L)GPLv3 兼容。
- 代价一：整个发行物不能再混入只允许 GPLv2 的代码，fuzzywuzzy 的风险因此放大。
- 代价二：按 GPLv3 第 6 条，发布 APK、EXE 以及 `native-*` Release 资产时，必须提供对应源码，包括 FFmpeg、mpv、libplacebo、dav1d、mbedtls 的确切提交、configure 参数和补丁。目前仓库只有构建脚本和上游链接，建议在同一个 Release 附上源码包。
- LGPLv3 的“安装信息”条款：Android 用户可以替换 .so 后重新签名安装，已满足。
- 绝不能使用 `--enable-nonfree`。Linux 的 mpv-build 在检测不到 gnutls 时会自动加 `--enable-nonfree --enable-openssl`，必须显式指定 TLS 库 [待确认当前 Linux 包的实际选择]。
- Linux 的 libmpv 没有设置 `-Dgpl=false`，因此是 GPLv2+，仍兼容 AGPL，但与其它平台不一致。
- 如果将来需要 x264 等 GPL 组件，可以加 `--enable-gpl`（得到 GPLv3，仍兼容 AGPL）。

## ⑤ 本地补丁包

| 包 | 上游基线 | 相对上游的改动 | 原因 | v4 |
|---|---|---|---|---|
| third_party/media_kit | Predidit@803c4a27（包版本 1.1.11） | `native_bundles.json` 指向自编的 libmpv（Android 三个架构、Linux x64）；去掉 hls_ad_filter | 用 FFmpeg 9 读取 codec-12 HEVC；满足 16 KB 对齐 | 保留（ADR 0002），改为共享 FFmpeg |
| third_party/media_kit_video | 同上（1.2.5） | `setVideoOutputEnabled`（Android Surface 由单一对象管理）、Windows `frameRevision`、`setSize(force)`、退出时的释放顺序 | 纯音频模式不重开流；多画面卡顿检测 | 保留，争取合入上游 |
| third_party/fvp | 0.38.1 | pubspec 只保留 android/ios 平台 | 避免 Windows 上 libmdk 释放时卡死（fvp#402） | 随 fvp 去留 |
| plugins/flame_barrage | 0.0.4 | 15 个文件、约 600 行差异：阴影、字距、逐条速度、待显示队列上限（120 条 / 5 秒）、emoji 正则只编译一次、键盘焦点 | 直播弹幕堆积和性能 | 删除；把这些需求写进弹幕规格 |
| plugins/flv_lzc | liuchuancong@030d611 | 去掉注册阶段的 SurfaceTexture 探测；修复纹理 id 为 0 时黑屏；按 16 KB 对齐重编 fplayer-core 的三个 arm64 .so | Flutter 3.47 断言；16 KB 页 | 删除 |
| built_in_kotlin/better_player_plus | 1.3.5 | Gradle 去掉 KGP、Java 17、Media3 1.11.1；修复视频尺寸 | AGP 9 | 删除（上游 1.4.1 已支持内置 Kotlin） |
| built_in_kotlin/mobile_scanner | 7.4.0 | 只改了 build.gradle | AGP 9 | 删除（上游 7.4.1 已修复） |
| built_in_kotlin/flutter_exit_app | 2.1.2 | 只改了 build.gradle | AGP 9 | 删除 |
| built_in_kotlin/floating | 6.0.0 | 去掉 KGP；另有运行时改动：100 ms 状态探测、画中画几何更新、同一时间只有一个状态观察 | 画中画状态准确 | 自写 PiP 时吸收 |
| built_in_kotlin/share_handler_android | 0.0.11 | Kotlin 约 176 行：先复制共享内容、保留文件名、清理暂存目录 | 分享导入的可靠性 | 自写接收分享时吸收 |
| built_in_kotlin/flutter_inappwebview_android | guide-inc-org@3e6c4c4a（1.2.0-beta.3） | 只改 Gradle：去掉模块私有的 AGP classpath、Java 17、换 ProGuard 文件 | AGP 9.3 | 随网页登录方案 |
| built_in_kotlin/flutter_js | 0.8.7 | 孤儿目录（2.3 MB），f9ad9a16 已从 pubspec 移除 | — | 删除 |
| screen_retriever（git） | liuchuancong@b246b39 | 空值检查修复 | 已合入上游 0.2.1 | 改用 pub 0.2.2 |

另外，`docs/DEPENDENCY_AUDIT.md` 说 flame_barrage“仅修补逐条速度”、flutter_js“仅保留许可证”，都与实际不符。

## ⑥ 原生库来源（arm64 APK，144 MB）

| 库 | 大小 | 来源 |
|---|---|---|
| libffmpegkit.so | 29.1 MB | ffmpeg_kit_extended_flutter（Native Assets，自编 FFmpeg 9.0.2，LGPLv3） |
| libmpv.so | 21.6 MB | media_kit 的构建钩子（自编 mpv 0.41.0，静态链接 FFmpeg 9.0.2） |
| libijkffmpeg / libijkplayer / libijksdl | 11.8 / 0.5 / 0.4 MB | flv_lzc → fplayer-core 1.0.4-purelive16k |
| libffmpeg.so | 7.9 MB | fvp（mdk-sdk 自带，FFmpeg master，Lavc63.13） |
| libbarhopper_v3.so | 4.7 MB | mobile_scanner → com.google.mlkit:barcode-scanning 17.3.0 |
| libmdk.so / libfvp.so | 2.2 / 0.1 MB | fvp |
| libsqlite3.so | 1.7 MB | sqlite3 3.6.0（drift 的依赖，Native Assets） |
| libcnativeapi.so | 1.6 MB | tray_manager 0.7.0 → nativeapi → cnativeapi（FFI 插件，在 Android 上没有用处） |
| libass.so | 1.3 MB | fvp（mdk-sdk 自带；libfvp 的 NEEDED 依赖；mpv 的 libass 是静态链接） |
| libc++_shared.so | 1.2 MB | NDK 运行库（归属于 ffmpeg_kit_extended_flutter；libmdk、libfvp 也需要） |
| libmediakitandroidhelper.so、libmedia_kit_event_loop.so | 0.4 MB 等 | media_kit |
| libdartjni.so | 0.1 MB | jni（path_provider_android 2.3.1 引入；v4 的 cronet_http 同样需要） |
| libsurface_util_jni、libimage_processing_util_jni | 很小 | CameraX 1.6.1（mobile_scanner） |
| libdatastore_shared_counter.so | 很小 | androidx.datastore（shared_preferences_android） |
| libffmpeg_kit_extended_dummy.so | 很小 | ffmpeg_kit_extended_flutter |

Windows 的 Release 目录：
- libffmpegkit.dll 54.6 MB，来自 ffmpegkit。
- libmpv-2.dll 38.7 MB，来自 Predidit 的预编译包，版本是 `mpv v0.41.0-1049-g0b7ed670f-dirty`，FFmpeg 是 master 分支（Lavc63.13）。它既不是自编，也不是正式版，第 04 节工具链表“当前”一栏的写法对 Windows 不成立。
- sqlite3.dll 来自 sqlite3。
- cnativeapi.dll 来自 tray_manager。
- dartjni.dll 来自 jni，在 Windows 上没有用处。
- WebView2Loader.dll 来自 inappwebview。
- Firebase C++ 静态库被链接进 pure_live.exe（15.9 MB），在其中的占比 [待确认]。

## ⑦ v4 依赖清单建议

1. **运行时保留约 60 个直接依赖**（现为 120 个），dev 14 个：
   - live_core / live_danmaku（纯 Dart）：crypto、pointycastle、protobuf、fixnum、html、xml、archive、uuid、synchronized、meta、freezed_annotation、json_annotation
   - live_net（纯 Dart）：dio、cookie_jar、dio_cookie_manager、web_socket_channel、stream_channel；原生网络适配器由应用层注入
   - 应用层：
     - 框架与数据：flutter_riverpod、riverpod_annotation、go_router、drift、slang、slang_flutter
     - 播放：media_kit 和 media_kit_video（分支）、audio_service、audio_session、audio_service_win
     - 桌面：window_manager、tray_manager、windows_single_instance、win32、win32_registry、ffi
     - 界面：extended_image、flutter_svg、material_symbols_icons
     - 系统能力：url_launcher、share_plus、file_picker、path_provider（含 Windows 重定向）、package_info_plus、device_info_plus、permission_handler、connectivity_plus、wakelock_plus、volume_controller、screen_brightness（3 个包）、flutter_secure_storage
     - 局域网与投屏：bonsoir、dlna_dart
     - 其它：qr、talker_flutter、native_dio_adapter
     - 需隔离、迁移或可选：flutter_inappwebview（隔离）、hive_ce（仅迁移）、sentry_flutter（可选）、fvp（由 ADR 决定）
   - dev：build_runner、riverpod_generator、riverpod_lint、freezed、json_serializable、slang_build_runner、drift_dev、very_good_analysis、mocktail、alchemist、patrol、widgetbook、msix、flutter_launcher_icons
2. **dependency_overrides 清零**：只保留 workspace 里指向分支的路径依赖；以后每增加一个覆盖，都要写 ADR 并注明复查日期。9 个“越过 SDK 锁定”的覆盖直接删除；hooks、code_assets 在 media_kit 钩子验证后再决定。
3. **plugins/ 整个删除**，只保留 `third_party/media_kit*`；本地补丁中确有价值的行为（画中画状态、分享导入、弹幕队列）先写进规格。
4. **原生层**：
   - 每个平台只编一份 FFmpeg 共享库（`--disable-gpl --enable-version3 --disable-nonfree` + mbedTLS/OpenSSL），libmpv 动态链接它，录制转封装也调用同一份。
   - Windows 的 libmpv 改为按正式版标签自编。
   - Android 打包时排除 libcnativeapi.so。
   - 去掉 Jetifier 和 google-services 插件，开启 Gradle 依赖校验。
   - 发布时附上原生库的源码包。
5. **预计体积**：arm64 至少减少约 48 MB（ffmpegkit 29.1 + IJK 12.7 + barhopper 4.7 + cnativeapi 1.6）；如果去掉 fvp，再减 11.5 MB [估算]。
6. **`tool/check_latest`**：除 pub.dev 外，还要比对 Predidit/media-kit、libmpv 构建仓库、mdk-sdk 的提交，以及 FFmpeg、mpv 的正式版标签。
