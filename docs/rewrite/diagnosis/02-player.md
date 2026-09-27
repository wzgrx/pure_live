# 第 0 阶段诊断：播放层（master，只读，没有改动任何文件）

## ① 规模与结构

| 范围 | 规模 | 备注 |
|---|---|---|
| lib/player | 51 个文件，13,525 行 | player_manager 5,028；media_kit_adapter 1,266；portrait_stream_support 830 |
| PlayerManager 的状态 | 98 个可变字段、13 个 Timer、13 个 revision/generation 计数、13 个 Rx、42 个公开方法 | player_manager.dart:202-470 |
| 改动频率 | player_manager 被 140 次提交改过；lib/player 共 366 次提交，其中 221 次是 fix | git log |
| 被播放复用的录制侧代码 | ffmpeg_hls_input_relay 990 行，另有 hls_* 约 3.7k 行；FlvInputFramer | lib/recorder/services |
| 多画面 | 自带一套播放和恢复：controller 1,424 行、cell_player 471 行、watchdog 110 行 | lib/modules/multiview |
| 主要测试 | player_error_recovery 3,841、audio_mode_transition 1,543、video_source_commit_listener 1,317、playback_source_transport 334、flv_splice_relay 207、flv_legacy_hevc_relay 176 | test/ |

### 1.1 PlayerManager 职责地图（player_manager.dart）

| 行号 | 职责 | 主要状态 |
|---|---|---|
| 1-200、4932-5028 | 值类型：刷新请求/结果、画质选择、提交快照、RoomSessionSnapshot | 纯数据 |
| 483-548 | 生命周期挂起、音频打断挂起（令牌 = session + intent） | _playbackSuspensions |
| 550-636 | 默认引擎；小窗回到房间页时复用会话；挂接 VideoController | currentFloatRoom、_appFloatingSession |
| 638-749 | 发布源提交快照，以及“画质 × 线路”同一批源的元数据 | _currentSourceCommit、_sourceCohort* |
| 750-810、2970-3217 | 应用内小窗（flutter_floating 覆盖层，UI 也写在这里） | _appFloatingPrepared |
| 812-1085 | 画面几何、竖屏检测、截图探测、Android 画中画比例更新 | videoGeometry、3 个 Timer |
| 1087-1187 | 创建播放器、串行生命周期队列、initialize | _playerLifecycleQueue |
| 1189-1562 | 会话打开：play、playSource、_playInternal、replay | _sessionId、_currentSource |
| 1564-1808 | 音频模式：保温、省电提交、回前台预热、同步 AudioService | 3 个 audioOnly 标志 |
| 1810-1992 | 切换引擎（事务式：候选成功才提交，失败回滚） | _currentPlayer、_runtimeEngine |
| 1994-2251 | Windows 热切换，外加一个备用播放器 | _windowsWarmStandbyPlayer |
| 2253-2370 | 经 Transport 打开源；FLV 续期回调 | _sourceTransports、_splicedLeasePlayers |
| 2372-2712 | 看门狗：首帧截止、帧进度、缓冲停滞、意外暂停、恢复次数清零 | 5 个 Timer |
| 2780-2968 | 画中画：Android 用 floating 插件，Windows 改窗口大小 | isInPip、_pipTransition* |
| 3219-3580 | UI：画中画覆盖层、纯音频卡片、getVideoWidget | Rx、SettingsService |
| 3582-3741 | 关闭、软停、空闲 45 秒后释放、硬释放 | _isClosing |
| 3743-4089 | 错误恢复状态机、去重、退避重试 | 3 个计数器、lineManager、fallbackManager |
| 4091-4309、4567-4673 | 签名续期：出错后刷新、预取、Windows 虎牙提前交接 | _prefetchedSourceRefresh、_credentialPrefetch |
| 4389-4565 | 把内核事件归一成统一状态（playing/loading/complete/error/尺寸） | 所有 Subject |
| 4735-4930 | 纯函数：小窗尺寸、视频可见区域 | 无状态 |

### 1.2 各职责之间共享的可变状态

| 状态 | 谁写 | 谁读 |
|---|---|---|
| _sessionId | 会话打开 1378、热切换 2106/2155、关闭 3596、硬释放 3722、dispose 4694 | 几乎所有异步守卫（_isSessionValid 348） |
| _playbackRequested、_playbackIntentRevision、_playbackSuspensions | 公共命令、挂起令牌、终态错误 4313 | 恢复、续期、热切换、画中画 2813、源提交 693-701 |
| _currentSource、_currentPlayUrls、currentFloatRoom | 会话、热切换、换线路 | 小窗快照、续期、恢复 |
| 3 个 audioOnly 标志 | 音频模式、引擎切换、热切换 | 看门狗、UI、截图探测 |
| 恢复计数、线路/引擎失败名单 | 恢复链、换房、连续播放 30 秒清零、退避、作废退还 3992-3995 | 恢复链 |
| loading/playing/state Subject、hasError | 事件归一、恢复、热切换 | 看门狗是否生效、UI |
| isInPip、isFloating | 画中画、小窗 | 空闲释放 3672-3684；后台是否继续播放（global_player_service.dart:79-80） |

### 1.3 各播放内核的差异

| 项目 | media_kit (mpv) | fvp (mdk) | IJK (flv_lzc) | Exo (better_player_plus) |
|---|---|---|---|---|
| 平台 | 全平台；桌面只用它 | 只 Android/iOS（pubspec.yaml:193-196） | 移动端；iOS 默认用它（player_settings_controller.dart:11） | Android |
| 实现的可选能力 | 填充方式、换源隔离、本地输入绕过代理、软解回退、帧进度（只 Windows）、截图访问 | 填充方式、换源隔离、静音起播、本地输入绕过代理 | 同 fvp | 没有代理支持 |
| 纯音频 | Android 用补丁接口 setVideoOutputEnabled（1040-1060）；桌面 setVideoTrack | setActiveTracks 并释放纹理（315-326） | disable-vid 选项（361）[待确认：不重开是否生效] | 只改标志，视频仍在解码（276-279） |
| 旧式 codec 12 HEVC | 走本地转写中继（PM 2290） | Android 强制软解（77-80） | 自带 FFmpeg | — |
| 独有的补丁或绕行 | 直播属性集（76-127）；按日志前缀过滤诊断，非致命错误等 1.2 秒（792-866）；同一源代次内同文本 2 秒去重（761-765、913-923）；同一 URL 只软解重试一次（505-529）；Android 打开后不再重发 vid=auto（587-596）；恢复视频时等关键帧，最多 2.8 秒（1085-1117） | 音频 OpenSL 优先（67-72）；解码器打开失败的负事件不算致命（160-162）；纹理尺寸为 null 时重新 prepare 一次（235-257） | 单独跟踪 freeze 缓冲事件（88-104）；开流期间的错误先暂存（152） | 开流期间的同步错误先暂存（120） |

选用条件：
- 用户设置经 `normalizeVideoPlayerKeyForPlatform` 归一（player_settings_controller.dart:13-25）；桌面强制 mpv（main.dart:86-90）。
- 自动降级只在移动端，顺序是“默认引擎 + 枚举顺序”：mpv → IJK → Exo → fvp（engine_fallback_manager.dart:17-19；global_player_service.dart:53）。

### 1.4 本地中继和 PlaybackSourceTransport

| 组件 | 什么时候用 | 做法 | 位置 |
|---|---|---|---|
| Transport | 每个播放器实例一个（PM 286） | 按事务打开：递增代次 → 取消未完成的 → 带取消令牌获取输入 → 内核打开本地 URI（绕过代理）→ 成功后才替换，旧输入随后关闭 | playback_source_transport.dart:59-303 |
| 选择顺序 | FLV 续流 > HEVC 转写 > HLS 查询策略 > 直连，四者互斥 | — | 129-181 |
| FlvSpliceRelay | 普通 URL、没有查询策略、有续期回调、.flv 且带 expire 参数（344-352） | 到期前 45 秒续期（douyu_site.dart:34）。新连接找到旧连接还没送出的关键帧后切过去；时间轴差超过 60 秒就平移时间戳；等旧流最多 10 秒，找关键帧最多 15 秒；切换后不再转发 script tag，编解码配置变了就补发 | flv_splice_relay.dart:94-320 |
| FlvLegacyHevcRelay | 只对 MediaKitAdapter，且域名以 .17app.co 结尾 | codec 12 改写成 Enhanced FLV（hvc1） | flv_legacy_hevc_relay.dart:76-99 |
| FFmpegHlsInputRelay | 播放侧只在带查询策略时用；Bigo/FC2/Niconico 的自有输入也用它 | 本地回环 HTTP；用伪 FFmpeg 参数 `-headers -i` 启动 | transport 74-99；ffmpeg_hls_input_relay.dart:199 |
| 自有源配方 | Bigo、FC2、Niconico | 走 openOwned | playback_source.dart:31-41 |

- HLS 查询策略：唯一产出它的 TTing 已在 1495f56b 下线，站点层现在搜不到调用者，这条播放路径可能已经没有真实流量 [待确认]。
- HEVC 转写：Android/Linux 的 libmpv 已是 FFmpeg 9.0.2（pubspec.yaml:65-66），代码注释仍写 7.1（flv_legacy_hevc_relay.dart:12）；Windows 版 libmpv 的 FFmpeg 版本 [待确认]。

### 1.5 恢复策略清单

| 检测 | 阈值 | 动作 | 次数/窗口 | 位置 |
|---|---|---|---|---|
| 内核 open 不返回 | 18 秒 | 按初始化错误进入恢复链 | — | 296、2297-2313 |
| 开流后没有首帧 | 默认 0，即关闭 | source_ready_timeout | — | 298、2372-2391；测试 986 |
| 意外 playing=false | 等 350 毫秒 → 调 play() 限时 5 秒 → 再确认 5 秒 | 先重新播放当前源，不行再升级 | 每次暂停一轮 | 299-300、2641-2712 |
| 缓冲停滞 | 每段连续缓冲 12 秒，中途通知不续期 | buffering_stall_timeout | — | 301、2610-2639 |
| 画面不再出新帧 | 10 秒；只 Windows，且可见、非纯音频、非缓冲 | video_frame_stall_timeout | — | 302、2495-2551 |
| 直播中意外 completed | 仍有播放意图 | live_source_completed | — | 4498-4517 |
| 恢复链顺序 | ①签名刷新（出错后最多 2 次，第 2 次换线）②换线路 ③画面停滞时同引擎重建 ④视频解码错误用软解重试一次 ⑤换引擎（每个 1 次）⑥停滞类错误同引擎重建（最多 1 次）⑦退避 750 毫秒、2 秒 ⑧报终态错误 | — | — | 3826-4007、4096、4338 |
| 次数清零 | 连续正常播放 30 秒 | 清空计数和线路/引擎失败名单 | 实际等于时间窗口 | 303、2553-2574 |
| 事务作废 | 恢复途中用户暂停、换源或已恢复 | 退还本次计数 | — | 3977-4006 |
| 到达续期时间 | refreshAt | 一般只预取凭据，不占播放队列；Windows 虎牙网页/HLS 源在 40 秒时热交接，失败 10 秒后重试；已走续流的跳过 | — | 226、4172-4234、4616-4673 |
| 刷新解析、热切换就绪、音频模式切换 | 12 秒 / 8 秒 / 5 秒 | 超时进入恢复，或保留旧状态 | — | 297、2078、295 |
| 多画面 | 帧看门狗 10 秒 | 恢复 | 每格 3 分钟内最多 2 次 | multiview_controller.dart:338-366 |
| mpv 内置 | network-timeout 15；hwdec-software-fallback 1 | — | — | media_kit_adapter.dart:98-105 |
| 应用切后台 | 隐藏 1.5 秒后才暂停 | 用令牌恢复 | — | playback_lifecycle_coordinator.dart:44-48 |

### 1.6 平台相关代码分布

| 能力 | 位置 |
|---|---|
| Windows 纹理 | media_kit_video/windows（帧进度 frameRevision、setSize(force)、释放顺序）；video_output_viewport_sizer.dart；被页面遮挡时拆掉 Texture（video_player.dart:37-42）并暂停看门狗（PM 2465-2488） |
| Windows 画中画 | 改窗口大小实现：fullscreen.dart:106-240、window_helper.dart |
| Android Surface | media_kit_video 补丁（VideoOutput.java、android_video_controller/real.dart）；StableVideoLayer（video_player.dart:69-104）；兼容模式 mediacodec_embed（media_kit_adapter.dart:289） |
| Android 画中画 | plugins/built_in_kotlin/floating（带状态探测补丁）；PM 2780-2868、1055-1085 |
| 后台播放与通知 | live_audio_service.dart、live_audio_handler.dart；MainActivity.kt:145、233-256（Wake/Wifi 锁） |
| 亮度、音量、屏幕常亮 | video_controller.dart:426-429、494、542、857、1527；live_play_controller.dart:255-257 |
| Linux | linux_mpv_runtime.dart |

## ② 依赖与耦合

| 耦合 | 证据 |
|---|---|
| 播放层反向依赖界面层 | PM 导入 live_play 的 VideoController、GlobalPlayerState、CompactDanmakuOverlay（player_manager.dart:50-52、337） |
| 播放层里写 UI | 小窗、画中画覆盖层、纯音频卡片，约 600 行（2970-3580） |
| 播放层里有站点知识 | HuyaTransportPolicy（4172、4571、4630）；PlaybackHeaderResolver 导入 20 个站点；几何提示解析抖音数据；HEVC 域名表；续流靠 URL 里的 `expire` 判断 |
| 播放依赖录制目录 | Transport 调 recorder 的 HLS 中继；两个 FLV 中继依赖 FlvInputFramer |
| 全局单例 | SettingsService.to（PM 1006、1416、2769，适配器里也读）、LiveAudioService 静态类、floatingManager、Get.overlayContext |
| 能力判断靠 `is` | 7 个可选接口（unified_player_interface.dart:78-140），PM 里到处是 `is XxxAware` |
| 多画面只复用了一部分 | 复用 Transport 和 applyNativeLiveProperties，恢复规则却自己写了一套 |

## ③ 技术债（按风险×收益排序）

| # | 问题 | 风险 | 收益 |
|---|---|---|---|
| 1 | PM 一个类担 20 多个职责，靠 13 套 revision 计数手工防竞态；新增一个定时器要在 pause 2723、close 3582、hardDispose 3704、dispose 4675 等多处一起取消 | 高 | 高 |
| 2 | 两套恢复逻辑规则不同：单房间是“连续播放 30 秒清零”，多画面是“3 分钟内最多 2 次” | 高 | 高 |
| 3 | 帧进度只有 Windows 有；Android 没有画面栅栏，看门狗和热切换都用不上，黑屏只能从缓冲/暂停间接发现 | 高 | 中高 |
| 4 | 播放层依赖界面和站点，无法做纯 Dart 测试；租期语义靠猜 URL | 中 | 高 |
| 5 | 自动降级链里有 IJK 和 Exo；Exo 不支持代理，纯音频也不省电 | 中 | 高 |
| 6 | 每个中继各起一个 HttpServer，并用 dart:io HttpClient（Windows 不跟系统代理，TLS 指纹问题）；续流读取没有空闲超时 | 中 | 中 |
| 7 | 疑似死代码：HLS 查询策略路径、HEVC 转写（FFmpeg 9 下）、fvp 的 isReusable=true、虎牙 40 秒交接（只剩网页回退源会走） | 低 | 中 |
| 8 | 测试替身绑定内部结构，还拿 PlayerEngine.fijk 当降级目标（测试 3362、1951） | 中 | 中 |

## ④ 处置建议

| 子模块 | 处置 | 理由 | 目标包 |
|---|---|---|---|
| PlayerManager | 重写并拆分 | 见 ⑥ | live_media 和 apps |
| PlaybackSourceTransport | 重写，保留事务契约和测试样本 | 代次、取消、成功才替换，这套契约清楚 | live_media |
| FlvSpliceSession/Relay | 重写，保留算法和探针 | 逻辑纯，录制可以直接写它的输出 | live_media（live_record 复用） |
| FFmpegHlsInputRelay 及 hls_* | 从 recorder 移出，接口不再用 FFmpeg 参数形式 | 播放、录制、自有源三方共用 | live_media |
| FlvLegacyHevcRelay | 确认 Windows libmpv 的 FFmpeg ≥ 8 后删除 | FFmpeg 9 已认识 codec 12 | 暂留 live_media |
| media_kit 适配器 | 重写为 MpvEngine，保留属性集、诊断分类、源代次隔离 | 主力内核 | live_media |
| fvp 适配器 | 重写为 FvpEngine，保留 OpenSL、解码器顺序、纹理重试 | Android 备用内核 | live_media |
| IJK、Exo | 删除 | 宪法已定 | — |
| 引擎/线路降级管理、错误分类 | 重写为 RecoveryPolicy，映射到 sealed 错误类型 | 统一恢复规则 | live_media |
| 竖屏检测和几何提示 | 检测器重写为纯函数单元；站点提示改由 StreamLine 带宽高 | 去掉站点依赖 | live_media / live_core |
| 生命周期协调、后台播放、音频服务 | 重写，保留令牌语义 | 属于应用层 | apps/pure_live |
| 画中画、小窗 | 重写 | UI 不该在播放层 | apps/pure_live |
| media_kit_video 补丁、floating 补丁 | 原样保留 | 原生行为已验证 | third_party |
| PlaybackHeaderResolver | 改由站点适配器产出请求头 | 去掉 20 个站点导入 | live_core |

删除 IJK/Exo 时一并移除：
- 代码：`fijk_adapter.dart`、`video_player_adapter.dart`、`fijk_helper.dart`、两个 accessor 文件；`player_engine.dart:1` 的 fijk/exo；`player_consts.dart:9-10,16-17`；`player_adapter_factory.dart:14-18`。
- 配置和引用：`common/index.dart:16`（全局导出 fijkplayer）；`player_settings_controller.dart:11`（iOS 默认 ijk）；`player_kernel_settings_page.dart:57`（Exo 隐藏代理）；`android/build.gradle.kts:5`；`analysis_options.yaml:25`；`pubspec.yaml:71-72、83-84`。
- 插件与资源：`plugins/flv_lzc`（15 MB）、`plugins/built_in_kotlin/better_player_plus`、翻译键 player_ijk/player_exo、`test/fijk_buffering_event_test.dart`、`docs/FIJK_BUFFER_EVENT_AUDIT_2026_09_05.md`。
- 连带改动：设置里的 'ijk'/'exo' 迁移成 mpv；降级链只剩 mpv → fvp；静音起播接口（AudioOutputSuppressionAwarePlayer）要留给 fvp。

## ⑤ 必须继承的行为与坑

| 现象 | 根因 | 正确做法 | 提交/测试 |
|---|---|---|---|
| 多画面斗鱼 300 秒后画面冻结 | mpv 在流结束时先发 playing=false 再发 completed=true，被当成用户暂停 | 按用户意图判断是否恢复；测试替身按真实顺序发事件 | 42cbded2；multiview_test.dart:89-93；PM 2432-2439；测试 3362 |
| 图标闪成“暂停”，像随机暂停 | media_kit 在 loading 之后会报 paused | 还有播放意图时视为网络状态 | 4521-4540；测试 1212 |
| Windows 黑屏不恢复 | 数据断供时 libmpv 仍报 playing=true；每次通知都重置计时器 | 以缓冲状态为准，每段缓冲只设一个截止时间 | 3377ce30、6a8c007d；测试 1317、1434 |
| Windows 退出或多格长播时进程 abort（0xc0000409） | mpv 核心先于渲染上下文被释放 | 停回调 → 排空任务 → 注销纹理 → 同步释放渲染上下文 → 释放 D3D；Dispose 等原生完成后才返回 | 6973c57f、21a0c1ec；docs/WINDOWS_MULTIVIEW_NATIVE_ABORT_2026_09_24.md |
| Windows 被页面遮挡时崩溃，或被误判停滞 | 纹理和合成器竞态；被遮挡时本来就不出帧 | 拆掉 Texture、暂停帧看门狗；重新挂上时 setSize(force) | video_player.dart:37-42；2465-2488；测试 1582 |
| Android 首帧黑屏 / 返回后黑屏 | 替换视频子树时和 Surface 回调竞态 | 遮挡时 Offstage 保留（StableVideoLayer）；Surface 只由补丁控制器管理 | 403772f1；stable_video_layer_test、android_surface_contract_test |
| 第一次点耳机一直等 | 打开后重发 vid=auto 可能永远不返回 | Android 不重发；恢复视频时等关键帧再露出 | media_kit_adapter.dart:587-596、1085-1117 |
| 恢复后永久黑屏（0×0） | open 成功不代表有画面 | 候选出第一帧才替换 | 2045-2080、4353-4376；测试 1514 |
| 虎牙无谓重开 | 凭据过期不会断开已建立的连接 | 原生 FLV 只预取；真正断开才用；同一 URL 也要重开 | 8a6fdce1、d6d4123c；测试 2322、2364、2867 |
| 斗鱼每 5 分钟卡一次 | expire=300，CDN 到点断开 | 提前 45 秒续期，在关键帧处拼接 | 31982153；flv_splice_relay_test |
| Shopee/17LIVE 只有声音 | FFmpeg 8 以前不认 codec 12；高通硬解静默丢帧 | mpv 改写 tag；fvp 在 Android 软解 | 79f78e06、719f902f、5b7cb9c9 |
| fvp 崩溃或没有画面 | AAudio 释放时崩溃；尺寸 null 时永远不建纹理 | OpenSL 优先；重新 prepare 一次 | 5b7cb9c9、cabd2c83 |
| 换到第二条线路后一直加载 | 整条流做 distinct，同样的报错文本被吞掉 | 按源代次去重 | media_kit_adapter.dart:761；测试 3232 |
| 降级后一直等待 | 错误在 open 返回前就发出，监听挂得太晚 | 开流期间的错误先暂存 | PM 2026-2031；测试 2045 |
| 竖屏识别一直停在 unknown | Timer 截断毫秒提前触发；防抖被连续事件饿死 | 向上取整；改为固定窗口合并 | 5fe31c86；测试 1011 |
| ColorOS 随机暂停或重载 | 截图探测会临时拆掉硬解 Surface | 默认关闭截图探测 | 311-316；测试 806 |
| 小窗吞掉菜单点击 | 拖动手势层 opaque | 有弹出菜单时整个小窗 Offstage | c766d319 |
| 关闭后被旧任务重新打开 | 关闭要排到队列里才生效 | 关闭时同步撤销意图 | b231449e；测试 2579-2720 |
| 自动降级时短暂出声 | 用户关了音频输出，新引擎默认有声 | 初始化前先静音 | 1924-1929；测试 846 |
| 浏览首页也占内存 | 暂停后仍持有解码器和连接 | 软停卸载媒体，45 秒后硬释放 | c5072259 |

## ⑥ 对 v4 live_media 的具体建议

| 单元 | 输入 | 输出 | 依赖 | 来源 |
|---|---|---|---|---|
| PlayerEngine（mpv、fvp） | 配置；源输入（uri、headers、是否本地） | 带代次的 sealed 事件流；能力声明 | 内核、third_party 补丁 | 两个适配器 |
| SourcePipeline | StreamLine（url、headers、租期）和引擎能力 | 输入租约（本地 URI、close） | live_net | Transport 和三个中继 |
| PlaybackSession | 打开、暂停、继续、关闭、纯音频等命令 | 状态流、源提交流 | Engine、Pipeline | 1087-1562、3582-3741 |
| HealthMonitor | 引擎事件、可见性、意图、时钟 | 停滞证据 | 纯 Dart | 2372-2712 |
| RecoveryPolicy | 失败类型、按时间窗口的历史、可用线路和引擎 | 恢复动作 | 纯函数 | 3769-4089 |
| LeaseCoordinator | 租期（refreshAt、到期是否断连）、续期回调 | 预取、续流或交接 | Pipeline | 4091-4309 |
| EngineHandoff | 候选引擎、画面栅栏 | 提交或回滚 | Engine | 1810-2251 |
| AudioModeController、GeometryTracker | 模式请求 / 尺寸事件 | 引擎调用 / 几何快照 | Engine / 纯 Dart | 1564-1808、812-1053 |

- **契约测试**：用真实内核录下事件轨迹（结束时的顺序、loading 后的 paused、fvp 的负事件），测试替身只回放这些轨迹。
- **一个事务对象替代多套计数**：用“会话 + 意图 + 取消令牌”替代 13 个 revision 计数；所有原生命令走同一个 actor。
- **统一恢复规则**：单房间和多画面共用 RecoveryPolicy；保留现有恢复链顺序和手动选的线路；次数按时间窗口算。
- **租期来自数据**：到期会断连的 → 拼接续流（同时供录制使用）；不断连的 → 只预取；未知的 → 首帧栅栏交接。
- **Android 也补帧进度**：在 Android 补丁里加 frameRevision，让看门狗和热切换两个主力平台都能用 [需要验证可行性]。
- **中继统一**：一个回环服务器，每个会话一个带随机路径的地址；上游走 live_net，续流读取加空闲超时。
- **删代码前两项确认**：Windows libmpv 的 FFmpeg 版本（决定 HEVC 转写去留）；HLS 查询策略是否还有站点产出。
- **测试迁移**：player_error_recovery_test 约 100 个场景转成 spec/modules/playback 的行为样本。
