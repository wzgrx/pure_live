# 回归清单（v4）

> 状态：第 1 阶段初稿（2026-09-27）。依据 `master@49ceccb0`，代码与 v3.2.11 相同。
>
> 来源：
> - 第 0 阶段 8 份诊断报告（`docs/rewrite/diagnosis/`）。01–05 各有一张“必须继承的行为与坑”表；06（测试）、07（依赖）、08（原生与工程）没有这张表，其中的坑从正文提取。
> - [DIAGNOSIS.md](../docs/rewrite/DIAGNOSIS.md) 的“旧版缺陷”表，PLAN §02“必须继承的经验”。
> - 从 `test/` 导出的 3557 个测试名（导出方法和归并结果见附录 A）。
>
> 本文件是 v4 的验收依据之一。新代码的测试必须能对上这里的编号。

## 怎么用

**编号**：`REG-<领域>-NNN`。编号一经发布就不再复用；条目作废时保留编号，标“作废”并写原因。

**每条的字段**

| 字段 | 含义 |
|---|---|
| 现象 | 用户看到的问题。旧版逐步补上、没有对应事故的防御写“潜在” |
| 根因 | 为什么会发生 |
| 正确做法 | v4 必须保证的行为，只写行为，不写类名 |
| 证据 | 提交、旧测试、旧代码位置、文档 |
| 验收 | v4 用什么证明（见下表） |

**验收方式**

| 写法 | 含义 |
|---|---|
| 单元 | 纯 Dart 单元测试，时间用 `package:clock` 和 fake_async |
| 样本 | 录制的真实接口、媒体或弹幕样本，加上冻结的 `expected.json` |
| 轨迹 | 契约轨迹回放：用真实 libmpv 录下事件序列，替身按原顺序异步回放 |
| 探针 | `live_cli probe` 真实网络巡检 |
| 截图 | 组件或截图测试（alchemist） |
| 真机 | patrol 集成测试或人工真机记录（K90、Windows 等），先拿设备租约 |
| 门禁 | CI 或发布流水线里的脚本检查 |

**平台条目**：B 站、斗鱼、虎牙、抖音、快手的平台坑由 `spec/sites/<平台>.md` 负责，编号为 `REG-BILIBILI-*`、`REG-DOUYU-*`、`REG-HUYA-*`、`REG-DOUYIN-*`、`REG-KUAISHOU-*`。本文只写跨平台和模块级的要求。平台坑影响模块时，本文写模块侧要求，并写成“平台侧：REG-DOUYU-*（主题）”。编号已按各平台规格第 10 节回填（2026-09-27）；平台规格里没有单独编号的，写明所在章节。平台坑与本文条目的对照见附录 B。

**证据写法**

- 提交哈希取自诊断报告。本次按要求没有运行 git 重新核对。
- `test/<文件>:<行>` 指该测试声明所在的行。
- 旧代码位置沿用诊断报告的短写（文件名:行）；`PM` 指 `player_manager.dart`。完整路径见附录 C。
- 标“仅 Windows”的旧测试带 `skip: !Platform.isWindows`，在 CI（ubuntu）上从未运行。
- 标“源码断言”的旧测试只检查源文件里有没有某段字符串，不能证明行为。

**标注**：[待确认] 表示需要在第 1 阶段查证，查清后改写本条。

## 条目统计

| 领域 | 前缀 | 条数 |
|---|---|---|
| 平台通用 | REG-COMMON | 19 |
| 播放 | REG-PLAY | 25 |
| 中继与租期 | REG-LEASE | 18 |
| 直播间交互 | REG-ROOM | 19 |
| 多画面 | REG-MULTI | 14 |
| 弹幕 | REG-DANMAKU | 17 |
| 录制 | REG-RECORD | 24 |
| 存储与迁移 | REG-STORE | 26 |
| 网络与代理 | REG-NET | 10 |
| Android | REG-ANDROID | 13 |
| Windows | REG-WINDOWS | 13 |
| Linux | REG-LINUX | 3 |
| 构建与发布 | REG-BUILD | 10 |
| **合计** | | **211** |

另有 23 项没有自动化测试的缺口（G-01 至 G-23）和 9 项明确不继承的旧行为（N-01 至 N-09）。

---

## 1 平台通用（REG-COMMON）

### REG-COMMON-001 详情请求失败不等于下播

- 现象：录制被误停；关注列表把请求失败的房间显示成“未开播”。
- 根因：7 个老站在详情请求失败时返回“状态未知”的房间（`live_room.dart:874`），调用方把它当成离线；B 站 -352 风控靠 `toString().contains` 判断。
- 正确做法：详情只有一个入口，永不吞错。只有平台明确给出下播、封禁、回放，才改变房间状态；网络、风控、解析失败一律作为类型化错误上抛，状态保持“未知 / 待刷新”。录制、多画面、关注刷新、“立即录制”都用这个入口。
- 证据：233d858d；`live_site.dart:314-331`；`douyu_site.dart:510-512`；`recorder_controller.dart:701-704`；`test/recorder_stream_resolver_test.dart:218`；`test/live_room_error_fallback_test.dart:13`；`test/sites_test.dart:55`；`test/multiview_test.dart:719`。平台侧：REG-BILIBILI-003、REG-BILIBILI-006（-352 风控），REG-HUYA-015（只有明确的非直播状态才算离线）。
- 验收：样本（各主力平台的失败、风控响应）＋单元。

### REG-COMMON-002 错误有类型，界面不解析文案

- 现象：风控提示要靠匹配错误字符串；弹幕“正在重连”的中文句子被当成状态；错误对象的 `toString` 会本地化，判定结果随语言变化。
- 根因：`throw Exception(e.toString())` 共 8 处；`HttpError` 继承 `Error`；弹幕错误回调传中文句子（`douyu_danmaku.dart:81,86`）；录制按日志字符串分类。
- 正确做法：平台层返回 sealed `SiteFailure`（Network、RateLimited、RiskControl、NeedLogin、RegionRestricted、AgeOrPaid、NotFound、ApiChanged、StreamUnavailable、Cancelled）；下播、封禁、回放属于房间状态，不算失败。弹幕、播放、录制同样输出类型化事件。界面按类型取文案，日志记录类型和脱敏上下文。
- 证据：01 ③-1、⑥；DIAGNOSIS 跨模块结论 3；`bilibili_site.dart:104`；`test/danmaku_controller_lifecycle_test.dart:141`（类型化重连通知不受文案影响）；04 ③-5（两份致命错误清单不一致）。
- 验收：单元（每个失败样本映射到唯一类型）＋样本。

### REG-COMMON-003 房间状态五态

- 现象：旧数据只有布尔 `isLive`，布尔与枚举冲突时显示错误；回放房间被当成直播参与排序。
- 根因：模型里布尔和枚举并存，老记录只有布尔。
- 正确做法：直播中、未开播、回放、未知、封禁五态。显式枚举优先于旧布尔；“未知”和“封禁”不被旧布尔覆盖；回放可以播放，但不按直播排序；没有平台证据时保持未知。
- 证据：05 ③（`liveStatus` 下标 0–4）；`test/live_room_status_test.dart:40,50`；`test/multiview_room_picker_test.dart:6`；`test/windows_multi_instance_launcher_test.dart`（房间参数携带规范状态）。
- 验收：单元＋迁移样本。

### REG-COMMON-004 观众数：热度、在线、累计分开

- 现象：虎牙 8006、抖音 `total_user`、B 站人气被标成“在线人数”；未知时显示 0；在线排序被热度值压过。
- 根因：模型只有一个“人数”字段。
- 正确做法：每个数值带类型：在线、热度、累计、未知、待刷新。显式的 0 保留；未知不显示 0；平台已支持但值还没到时显示“待刷新”，不拿热度顶替。在线排序中，有真实在线值的平台排在只有热度的平台前面；值相同时按“平台＋房间号”稳定排序；一次刷新缺值不丢掉列表里已有的人气。
- 证据：`test/live_room_audience_metric_test.dart:49,57,206`（共 17 个用例）；`test/popular_audience_ranking_test.dart`；`test/search_ranking_test.dart`；`test/huya_danmaku_protocol_test.dart:63`；`test/douyin_audience_metric_test.dart`；`docs/PLATFORM_COMPATIBILITY.md:100`。平台侧：REG-HUYA-014（8006 是热度），REG-DOUYIN-008（`total_user` 是累计），REG-BILIBILI-014、REG-BILIBILI-015（人气与累计观看）。
- 验收：样本＋单元。

### REG-COMMON-005 画质以服务端确认为准

- 现象：B 站选了高画质但没生效，界面仍显示高画质；斗鱼被降档后仍显示原画；缺少确认时冒充原画。
- 根因：游客请求会被服务端降档；界面显示的是用户点击的标签。
- 正确做法：取流结果带“请求画质、实际画质、是否已确认”。只有源提交成功后才更新显示；确认缺失或畸形时显示“未确认”，不冒充请求的画质。画质顺序保留接口给出的顺序，不对不透明的请求码排序；重复的显示标签加编号，但稳定 id 不变。
- 证据：03234c7d；`test/bilibili_play_quality_test.dart:13`；`test/douyu_quality_ack_test.dart:114`（共 14 个用例）；`test/douyu_playback_parser_test.dart:130`；`test/stream_selection_controller_test.dart:284,379,601`。平台侧：REG-BILIBILI-001、REG-BILIBILI-002（`current_qn` / `accept_qn`），REG-DOUYU-005、REG-DOUYU-006、REG-DOUYU-007（rate 确认）。
- 验收：样本＋单元。

### REG-COMMON-006 线路按身份识别，不按下标

- 现象：虎牙刷新后跳到别的线路；HLS 变体重排后选错。
- 根因：按列表下标选线。
- 正确做法：线路身份由 CDN 主机、格式、凭据类型（或平台给的稳定 id）组成。刷新、续期、恢复都按身份匹配；下标越界时钳制，但保留身份。
- 证据：4df2f98d；`huya_transport_policy.dart:3-48`；`test/huya_transport_policy_test.dart`（表驱动）；`test/hls_master_selection_test.dart:33`；`test/stream_selection_controller_test.dart`（钳制过期的画质和线路下标）。平台侧：REG-HUYA-010、REG-HUYA-011（线路回退表）。
- 验收：单元（表驱动用例直接转成 YAML）。

### REG-COMMON-007 画质列表只含视频档

- 现象：抖音多画面小格黑屏。
- 根因：纯音频档 `ao` 被当成最低画质。
- 正确做法：画质列表过滤 `only_audio` / `ao`，“最低画质”永远是视频档。纯音频由播放层的纯音频模式提供（REG-PLAY-016）。
- 证据：56cd4d97；`test/douyin_playback_parser_test.dart:144`；`test/multiview_test.dart:349`。平台侧：REG-DOUYIN-001（纯音频档）。
- 验收：样本。

### REG-COMMON-008 请求头随取流结果走，播放与录制一致

- 现象：同一个流播放能开、录制 403；IPTV 频道自带的请求头只在播放时生效。
- 根因：请求头由播放层按平台分支拼接（`playback_header_resolver.dart:52-140` 导入了 20 个站点），录制另有一份。
- 正确做法：每条线路自带请求头（UA、Origin、Referer、Cookie）。播放、录制、中继、多画面使用同一份；IPTV 频道级请求头覆盖全局配置，并且两边一致；未知平台不附加请求头。
- 证据：`test/playback_header_resolver_test.dart:14,27,82`；`test/account_cookie_editor_test.dart:118`（斗鱼会话同时到达签名、播放、录制请求头）；`test/multiview_test.dart`（默认解析转发 IPTV 频道请求头）；`test/recorder_stream_resolver_test.dart`（录制携带 IPTV 频道请求头）。
- 验收：单元＋样本。

### REG-COMMON-009 平台 id 规范化

- 现象：导入的平台 id 带空格或大小写不同就打不开；站点 id `17live` 与目录 `seventeenlive` 不一致。
- 正确做法：平台 id 去空格、转小写后匹配；新代码的站点 id 与目录名一致，旧 id 通过别名表读入；校验路由里的平台 id 时不构造适配器；每个注册平台在所有语言里都有显示名。
- 证据：`sites.dart:74`；01 ⑥；`test/sites_test.dart:12,50`。
- 验收：单元。

### REG-COMMON-010 短链解析有界

- 现象（潜在）：短链自重定向形成死循环；`Location` 指向无关域名时被跟随；解析一直卡住。
- 正确做法：一次解析的所有重定向共享一个有限预算；自重定向、只改片段的重定向不重置循环检测；相对 `Location` 按当前地址解析；多个互相冲突的 `Location` 头一律忽略；非重定向状态码不读 `Location`；只跟随平台自己的域名；连接、发送、接收都有超时；调用方取消时立即关闭客户端，迟到的重定向不再发请求；直接房间链接不发网络请求；一个短链失败不影响后面的直接链接。
- 证据：`test/live_short_link_test.dart:29,36,53,64,111,127,205`（共 19 个用例）；`test/live_short_link_io_test.dart`。
- 验收：单元（本地 HTTP 服务器）。

### REG-COMMON-011 链接识别与已下线平台

- 正确做法：只识别房间链接；搜索页、分类页、作者页和仿冒域名一律忽略；只有平台名、没有 URL 的文本不自动填入；已下线平台的链接明确回答“该平台已下线”，不当作无法识别；支持的海外链接离线识别，不发请求。
- 证据：`test/web_search_room_parser_test.dart:33`；`test/toolbox_link_detection_test.dart:53`；`test/retired_site_links_test.dart:7`；`test/live_url_tool_parser_test.dart`；`test/toolbox_clipboard_test.dart`。
- 验收：样本（链接表）＋单元。

### REG-COMMON-012 分享口令与剪贴板导入

- 现象：老版本分享的口令新版读不了；刚分享出去的口令回到前台又被导入；读剪贴板失败后口令丢失。
- 正确做法：口令格式 `base64url(msgpack{m:'pure_live',p,r,ti,n,l,c,a})` 必须兼容；没有可用房间身份的口令忽略；并发检查共用一次读取；消费失败的口令保留、可重试；自己分享的口令在有限的历史内不回导；读剪贴板在 v4 可以关闭。
- 证据：`share_command_handler.dart:4-47`；`desktop_manager.dart:611-625`；`test/share_command_handler_test.dart:31,91,221`（共 14 个用例）。
- 验收：样本（旧版口令）＋单元。

### REG-COMMON-013 目录分页由游标驱动

- 现象：空页被当成最后一页；刷新失败把已显示的卡片清空；桌面端页码与卡片错位。
- 正确做法：分页返回不透明游标，不按条数判断是否结束；空页不是终点，按显式的请求预算停止；刷新失败保留已提交的页和结束标记，刷新成功原子替换；连续两页没有新结果时停止“卡住”的分页接口；页面关闭后迟到的响应不回填。
- 证据：`live_directory.dart:5-6`；`test/live_directory_controller_test.dart:322,911`（共 38 个用例）；`test/transactional_page_refresh_test.dart`；`test/search_request_cancellation_test.dart:433`。
- 验收：单元。

### REG-COMMON-014 聚合搜索

- 正确做法：“全部”搜索按各平台完成顺序渐进显示；单个平台超过 12 秒标为本轮部分失败，不阻塞其它平台；同时进行的平台数有上限；新关键词作废旧关键词的第二页；重复提交共用一次搜索；直播中排在离线前，各排序模式（平台顺序、观众、粉丝、在线）只用各自的值。
- 证据：`docs/PLATFORM_COMPATIBILITY.md:95`；`test/search_request_cancellation_test.dart:179,222`（共 17 个用例）；`test/search_ranking_test.dart`。
- 验收：单元。

### REG-COMMON-015 账号身份与登出

- 现象（潜在）：旧的“登录无效”响应清掉了刚登录的新账号；浏览器 Cookie 清理失败导致登出回滚。
- 正确做法：身份查询按代次，旧响应不能覆盖新账号。登出立即作废进行中的查询，本地账号以清空为准，即使 WebView 的 Cookie 清理失败。二维码刷新后旧的轮询结果作废，轮询不重叠，连续失败停在可见的重试状态。
- 证据：`test/account_identity_lifecycle_test.dart:43,138`；`test/bilibili_login_lifecycle_test.dart`。
- 验收：单元。

### REG-COMMON-016 诊断与日志脱敏

- 现象：签名 URL、Cookie、AntiCode 出现在日志和录制诊断里。
- 正确做法：日志、诊断包、错误提示、持久化的诊断记录都不含签名 URL、查询 token、Cookie、凭据和响应体；诊断只报告结论和不透明 id；诊断输出失败不能替换原始错误。
- 证据：cf35dcf9；`ffmpeg_service.dart:809-820`；`test/http_error_diagnostic_test.dart:6`；`test/huya_play_url_test.dart:487`；`test/live_record_task_persistence_test.dart:124`；`test/ffmpeg_terminal_evidence_test.dart`（兜底诊断只披露结论）；`test/douyin_danmaku_protocol_test.dart`（握手诊断隐去 Cookie）；`test/hls_relay_diagnostics_test.dart`。
- 验收：单元（对日志和诊断输出做敏感字段扫描）。

### REG-COMMON-017 异步结果与界面生命周期

- 现象：页面关闭后，迟到的结果弹出对话框或覆盖新页面；重复点击启动两次下载或删除；确认框确认了已被替换的对象。
- 正确做法：每个异步操作都有所有者（页面、会话或任务）。所有者关闭后，迟到的结果不产生任何可见副作用；同一动作重复触发只执行一次；确认对话框捕获目标身份，目标被替换后确认无效；系统返回键取消对话框并释放占用。
- 证据：旧测试中约 250 个用例名涉及迟到、过期、合并、单次执行，例如 `test/known_room_link_action_test.dart:219`、`test/webdav_directory_state_test.dart`、`test/history_page_test.dart`、`test/iptv_settings_page_test.dart`、`test/about_update_prompt_layout_test.dart`（迟到的更新结果不会重新打开已销毁的首页）。
- 验收：单元（provider 生命周期测试）＋截图。

### REG-COMMON-018 应用骨架（原 GetX 本地补丁的行为）

- 现象：旧版内置 GetX 有 4 处本地补丁，各对应一个曾经出现的问题。
- 根因：GetX 原实现的缺陷。
- 正确做法：v4 用 go_router 和 Riverpod 实现同样的行为：页面转场动画使用应用主题（1343f3e6）；画中画之后，广播流在最后一个监听者取消后能重新挂接（ee85ed8d）；浮层按导航器的 overlay 取上下文，嵌套导航器不捕获根 overlay（b24fa1d2）；小窗关闭流程串行化（6a02975b）。
- 证据：05 ②；`test/get_overlay_context_test.dart:9,42`；`test/rx_stream_resubscribe_test.dart:5`；`test/get_native_predictive_back_test.dart:131`。
- 验收：单元＋截图。

### REG-COMMON-019 小屏大字号下操作可达（登记，由 spec/design 负责）

- 现象：旧版多次出现大字号下按钮被挤出屏幕、对话框无法确认。
- 正确做法：在 320×480、3 倍字号、窄窗口下，所有操作都可达、不溢出，触控目标不小于 48 dp。作为设计不变量写入 `spec/design`，本条只登记来源。
- 证据：旧测试中约 139 个用例名涉及该项（`*_layout_test`、`*_page_test`）；06 ⑥-7。
- 验收：截图（五个宽度等级 × 大字号）。

---

## 2 播放（REG-PLAY）

### REG-PLAY-001 流结束的事件顺序

- 现象：多画面斗鱼 300 秒后画面冻结；源结束被当成用户暂停。
- 根因：mpv 在流结束时依次发出 `playing=false` → `completed=true` → `buffering=false` → 清空音视频轨道。旧代码把 `playing=false` 当成暂停；测试替身只发前两个事件，驱动真实适配器的测试里 `completed` 是空流，所以适配器的“流结束”映射没有被测到。
- 正确做法：用户播放意图单独记录，不由内核事件推断。直播中收到 `completed` 且仍有播放意图时，按“直播源结束”进入恢复（REG-PLAY-010）。测试替身只回放真实内核录下的轨迹，并保持异步广播（旧替身有 10 个文件用了 `broadcast(sync: true)`）。
- 证据：42cbded2；`test/multiview_test.dart:89`；PM 2432-2439、4498-4517；`test/player_error_recovery_test.dart:3362`；`third_party/media_kit/lib/src/player/native/player/real.dart:1779-1806`；`test/media_kit_buffering_state_test.dart:294`；06 ⑤-1、⑤-2。关联 REG-MULTI-002。
- 验收：轨迹（真实 libmpv 的“流结束”轨迹）＋单元。

### REG-PLAY-002 loading 之后的 paused 不是用户暂停

- 现象：播放图标闪成“暂停”，看起来像随机暂停。
- 根因：media_kit 在 loading 之后会报 paused。
- 正确做法：仍有播放意图时，内核的 paused 视为网络或缓冲状态，由传输层处理；只有用户显式暂停才发布“已暂停”。
- 证据：PM 4521-4540；`test/player_error_recovery_test.dart:1212`；同文件“explicit user pause is still published as paused”。
- 验收：轨迹＋单元。

### REG-PLAY-003 缓冲停滞以缓冲状态为准

- 现象：Windows 上数据断供后一直黑屏，不会恢复。
- 根因：断供时 libmpv 仍报 `playing=true`；每收到一次缓冲通知就重置计时器，永远不到期。
- 正确做法：每一段连续缓冲只设一个截止时间（旧值 12 秒），中途的通知不续期；`playing=true` 期间也要监督缓冲；到期后进入有界的源恢复。
- 证据：3377ce30、6a8c007d；PM 2610-2639；`test/player_error_recovery_test.dart:1317,1434`。
- 验收：轨迹（断流轨迹）＋单元。

### REG-PLAY-004 意外暂停：有界地重新播放，用户暂停不可反转

- 现象：网络抖动或音频焦点变化后播放停住，需要手动点播放。
- 根因：内核会在没有用户操作时进入暂停。
- 正确做法：非用户意图的 `playing=false`：等 350 毫秒 → 调用 play（限时 5 秒）→ 再确认 5 秒，仍不行才升级恢复；每次暂停只做一轮；卡住的 play 命令有上限。用户显式暂停永远不会被自动恢复反转。恢复进行中用户暂停、换源或已恢复，本次恢复作废并退还计数。
- 证据：PM 2641-2712、3977-4006；`test/player_error_recovery_test.dart:1191,1261,1282`；`MAINTENANCE_POLICY.md` §8（没有用户意图就不 pause/stop）。
- 验收：轨迹＋单元。

### REG-PLAY-005 不凭可选事件缺席判定失败

- 现象（潜在）：因为没收到首帧或路径事件就重开源，造成无谓断流。
- 正确做法：首帧超时默认关闭（0）；不能因为没收到某个可选事件（首帧元数据、path 事件、帧属性）就判定失败或重开；内核报告的 playing 是权威信号；paused 不因合成的“就绪”而被提升为播放中。
- 证据：PM 298、2372-2391；`test/player_error_recovery_test.dart:986`；`test/media_kit_buffering_state_test.dart:142`；`test/media_kit_video_geometry_test.dart:15`；`test/player_error_classifier_test.dart`（没有 path 事件时已完成的 open 仍可用）；`MAINTENANCE_POLICY.md` §8。
- 验收：轨迹＋单元。

### REG-PLAY-006 候选源出首帧才替换

- 现象：恢复之后永久黑屏（画面 0×0）。
- 根因：open 成功不代表有画面。
- 正确做法：恢复、热交接等场景下的候选播放器必须出第一帧（或有等价的画面栅栏）才提交；候选在首帧之后又报错，仍然不安装；候选尺寸一直为 0 时保留当前纹理；源提交快照只在原生 open 成功之后发布。
- 证据：PM 2045-2080、4353-4376；`test/player_error_recovery_test.dart:562`、`1514`、`2093`（后两个仅 Windows）。
- 验收：轨迹＋单元。Android 需要先补画面进度信号（REG-ANDROID-010）。

### REG-PLAY-007 所有内核调用都有时限

- 现象（潜在）：内核 open 或原生切换不返回时，界面永远停在加载。
- 正确做法：open 18 秒不返回，按初始化错误进入恢复；刷新解析 12 秒、热交接就绪 8 秒、纯音频切换 5 秒，超时后进入恢复或回到原状态；超时的输入先关闭，再打开下一个。
- 证据：PM 295-297、2078、2297-2313；`test/player_error_recovery_test.dart:1114`；`test/player_audio_mode_transition_test.dart:758`。
- 验收：单元（fake_async）。

### REG-PLAY-008 错误按源代次去重

- 现象：换到第二条线路后一直加载。
- 根因：对整条错误流做去重，新线路上同样文本的错误被吞掉。
- 正确做法：同一源代次内，同文本错误 2 秒去重；新代次重新计算；重复的原生失败不取消已排定的有界重试；新的源代次让之前所有回调失效，同一 URL 重开也算新代次。
- 证据：`media_kit_adapter.dart:761-765,913-923`；`test/player_error_recovery_test.dart:3232`（仅 Windows）；`test/player_error_classifier_test.dart:118`。
- 验收：轨迹＋单元。

### REG-PLAY-009 开流期间的错误先暂存

- 现象：自动降级后一直等待。
- 根因：错误在 open 返回之前就发出，监听挂得太晚，错误丢了。
- 正确做法：打开事务期间产生的错误先存在事务里，open 结束后统一处理；候选的错误留在恢复事务内，不进入公共错误流。
- 证据：PM 2026-2031；`test/player_error_recovery_test.dart:2045`（仅 Windows）。
- 验收：轨迹＋单元。

### REG-PLAY-010 恢复链的顺序与预算（单房间和多画面共用）

- 现象：单房间和多画面的恢复规则不同；多画面恢复次数一辈子只有 2 次，斗鱼格永久冻结（REG-MULTI-002）。
- 根因：两套恢复逻辑各自实现。
- 正确做法：保持旧顺序：① 签名刷新（出错后最多 2 次，第 2 次换线）② 换线路 ③ 画面停滞时同引擎重建 ④ 视频解码错误用软解重试一次（音频解码错误跳过此步）⑤ 停滞类错误同引擎重建（最多 1 次）⑥ 退避 750 毫秒、2 秒 ⑦ 报终态错误。只有最终耗尽才进入公共错误流。次数按时间窗口计算：连续正常播放 30 秒清零（多画面旧规则是“3 分钟内 2 次”，v4 统一一种）；紧密的失败循环必须停下；恢复保留用户手动选的线路。v4 只有 mpv，旧链里的“换引擎”由 mpv 软解回退和兼容模式代替 [待确认：Android mediacodec 兼容模式是否作为独立一步]。
- 证据：PM 3826-4007、4096、4338；`test/player_error_recovery_test.dart:929,1138,1167,2900`；`multiview_controller.dart:338-366`；02 ③-2、⑥。
- 验收：单元（恢复策略写成纯函数，约 80 个旧场景转为表驱动样本）＋轨迹。

### REG-PLAY-011 错误分类到恢复通道

- 现象（潜在）：`video`、`audio` 里的字母 `io` 被当成网络错误，走错恢复通道。
- 正确做法：按具体的传输和源标记分类，不做子串匹配；平台 DNS 诊断是终态传输错误；HTTP 5xx 是传输恢复信号；硬件解码初始化失败可以恢复，不支持的编码直接失败；音频、视频解码错误走不同通道。
- 证据：`test/player_error_classifier_test.dart:8,35,66`（共 13 个用例）。
- 验收：单元（真实 mpv 日志行作为样本）。

### REG-PLAY-012 画面停滞看门狗

- 现象：Windows 画面不再出新帧，但状态显示正常；被其它页面遮挡时误判为停滞。
- 正确做法：以帧进度为准。可见、非纯音频、非缓冲时 10 秒没有新帧，同引擎重建渲染；显式暂停取消看门狗；不为每一帧分配新计时器；故意隐藏（被遮挡、页面覆盖）时暂停看门狗，也不重开传输；重新可见时给完整宽限。
- 证据：PM 2465-2488、2495-2551；`test/player_error_recovery_test.dart:1469,1556,3273`、`1582`（仅 Windows）；`test/multiview_frame_watchdog_test.dart:6,60`。旧版只有 Windows 有帧进度信号（`frameRevision`）。
- 验收：单元＋真机。Android 缺口见 REG-ANDROID-010。

### REG-PLAY-013 播放意图串行，以最后一次请求为准

- 现象：关闭后又被旧任务重新打开；快速切换时打开了中间的源。
- 根因：关闭要排到队列里才生效。
- 正确做法：关闭同步撤销播放意图；关闭后立刻播放，保留较新的意图；已被关闭取代的播放不再打开源；原生分配期间收到关闭，迟到的播放器不再开源；快速连续选择只打开最后一个；play 等待进行中的 close 完成，而不是静默返回；重新进房的请求取代进行中的纯音频切换；房间加载失效后，迟到的画质响应不能改动房间。
- 证据：b231449e；`test/player_error_recovery_test.dart:2621,2644,2720`、`2579`（仅 Windows）；`test/player_audio_mode_transition_test.dart:1048,1075`；`test/player_load_fence_test.dart:19`。
- 验收：单元（会话按单一 actor 串行执行原生命令）。

### REG-PLAY-014 重建播放器时保持静音状态

- 现象：自动降级时短暂出声。
- 根因：用户关了音频输出，新创建的引擎默认有声。
- 正确做法：任何重建（恢复、热交接、多画面换流）都在初始化之前应用静音和音量状态；用户主动切换时保留其音频设置。
- 证据：PM 1924-1929；`test/player_error_recovery_test.dart:846`。
- 验收：单元＋轨迹。

### REG-PLAY-015 软停与空闲释放

- 现象：浏览首页时，播放器仍然占着内存和连接。
- 根因：暂停后仍持有解码器和连接。
- 正确做法：离开直播间先软停（卸载媒体），空闲 45 秒后硬释放；宽限期内重进直播间复用当前播放器；画中画和小窗期间不释放。
- 证据：c5072259；PM 3582-3741、3672-3684；`test/player_audio_mode_transition_test.dart:1105,1120`；`test/media_kit_video_geometry_test.dart:9`（旧版只在 Windows 声明软停复用）。
- 验收：单元＋真机（内存）。

### REG-PLAY-016 纯音频模式原地切换

- 现象：第一次点耳机按钮一直等待；切回视频时黑屏。
- 根因：Android 打开后重发 `vid=auto` 可能永远不返回；恢复视频时没有等关键帧。
- 正确做法：纯音频在当前播放器上切换，不重开流（Android 用补丁接口 `setVideoOutputEnabled`，桌面用 `setVideoTrack`）；Android 不重发 `vid=auto`；恢复视频时等关键帧（上限 2.8 秒）再露出画面；纯音频界面期间保留原生视频元素；短时间来回切换时保留视频解码；原生切换卡住 5 秒后超时回滚；进入纯音频先显示稳定的界面，不等原生回复；播放器初始化不等待 Android 媒体服务。
- 证据：`media_kit_adapter.dart:587-596,1040-1060,1085-1117`；`test/player_audio_mode_transition_test.dart:438,683,758,795,893`。
- 验收：单元＋真机（K90）。

### REG-PLAY-017 竖屏判定

- 现象：竖屏识别一直停在“未知”；换画质时的瞬时尺寸把方向翻转。
- 根因：Timer 把毫秒截断，提前触发；防抖被连续事件饿死（在 Linux 上出现过）。
- 正确做法：计时向上取整，改为固定窗口合并；连续 3 次一致的采样才确认；接近正方形保持中性；换画质的瞬时尺寸不翻转已稳定的方向；新的源代次作废旧的裁剪；缓存和平台元数据只是临时提示，不能控制自动布局；手动房间设置优先于自动检测；横屏画布中嵌入的竖屏内容由两次画面分析确认，均匀暗场不算黑边证据。
- 证据：5fe31c86；`test/player_error_recovery_test.dart:1011`；`test/portrait_stream_support_test.dart:8,39,50,334`（共 28 个用例）；`test/active_video_content_analyzer_test.dart`。
- 验收：单元（纯函数，旧用例转成样本）。

### REG-PLAY-018 画面几何与显示比例

- 现象（潜在）：画面被拉伸；竖屏源在旋转元数据缺失时显示成横屏。
- 正确做法：几何取一次经过显示校正的解码快照；旋转只应用一次；缺少旋转元数据时，已经是竖屏的源保持竖屏；只有完整的原始宽高对才能作为回退；移动端只有一个可信的 contain 比例，平台方向提示不能拉伸尚未测量的横屏画布；裁剪去掉编码进去的黑边，但不拉伸节目；平台几何提示只取所选 URL 对应的那一项，方向互相冲突时不猜；画中画比例钳制到 Android 允许的范围。
- 证据：`test/media_kit_video_geometry_test.dart:51`；`test/mobile_video_frame_test.dart:24,151`；`test/live_stream_geometry_hint_test.dart`；`test/portrait_stream_support_test.dart:371`；02 ④（几何提示改由取流结果带宽高）。
- 验收：单元。

### REG-PLAY-019 输出纹理按显示尺寸

- 现象（潜在）：小窗口里按原分辨率解码和渲染，内存偏高。
- 正确做法：纹理尺寸取可见区域的物理像素，不超过源分辨率，保持比例且宽高为偶数；源元数据到达前用有上限的临时尺寸；窗口变化去抖合并；输出身份变化时即使尺寸相同也强制重新挂接；组件卸载后取消挂起的调整。
- 证据：`video_output_viewport_sizer.dart`；`test/video_output_size_policy_test.dart:6`；`test/video_output_viewport_sizer_test.dart:104`。
- 验收：单元＋真机（内存）。

### REG-PLAY-020 截图探测默认关闭

- 现象：ColorOS 上随机暂停或重新加载。
- 根因：画面内容的截图探测会临时拆掉硬解 Surface。
- 正确做法：截图探测必须显式开启，默认关闭。
- 证据：PM 311-316；`test/player_error_recovery_test.dart:806`。
- 验收：单元（默认值）＋真机（ColorOS）。

### REG-PLAY-021 直播缓冲与 mpv 属性

- 现象（潜在）：继承来的磁盘缓存和无限时长缓存让直播延迟和内存一直增长。
- 正确做法：直播使用有上限的内存缓冲，覆盖继承的磁盘缓存和无限时长缓存；低延迟缓冲预算有上限；不支持的原生属性要上报，不能忽略；保留直播属性集（含 `network-timeout=15`、`hwdec-software-fallback=1`）；设置界面显示播放器实际使用的值。
- 证据：`media_kit_adapter.dart:76-127,98-105`；`test/live_buffer_policy_test.dart:5`；`test/mpv_option_labels_test.dart:32`。
- 验收：单元（属性集快照）＋真机。

### REG-PLAY-022 旧式 codec 12 HEVC FLV 必须有画面

- 现象：17LIVE（以及已下线的 Shopee）只有声音。
- 根因：FFmpeg 8 以前不认识 codec 12；高通硬解对这类流静默丢帧。
- 正确做法：所有平台的 libmpv 都用 FFmpeg ≥ 8（已查明全部满足，Windows 为 Lavc63.13），旧的 HEVC 转写中继可以删除；录制写入时把 codec 12 改写为 Enhanced FLV（ADR 0005）；高通机型上硬解是否仍会静默丢帧需要实测 [待确认]，必要时对这类流改用软解。
- 证据：79f78e06、719f902f、5b7cb9c9；`test/flv_legacy_hevc_relay_test.dart:56`；DIAGNOSIS 待确认事项。
- 验收：样本（17LIVE codec 12 FLV 片段）＋真机（高通机型）。

### REG-PLAY-023 应用生命周期

- 现象（潜在）：通知栏下拉、短暂切应用就暂停播放。
- 正确做法：应用隐藏 1.5 秒后才暂停，Android 的瞬时 hidden 不暂停；hidden 与 paused 共用一个挂起令牌；每轮生命周期发一个新令牌；恢复只恢复同一会话、同一意图；detached 时暂停保留的引擎；快速重新挂接保持播放。
- 证据：`playback_lifecycle_coordinator.dart:44-48`；`test/playback_lifecycle_coordinator_test.dart:8,89,154`；`test/player_audio_mode_transition_test.dart:592`。
- 验收：单元＋真机。

### REG-PLAY-024 后台播放策略与通知

- 正确做法：后台选项全部关闭时，普通视频切后台暂停；手动纯音频遵守后台播放开关；全局后台播放或睡眠定时会话继续播放；通知栏元数据把房间标题和主播分别放在对应字段；后台播放期间 Android 持有 Wake 锁和 Wifi 锁（REG-ANDROID-006）。
- 证据：`global_player_service.dart:79-80`；`test/background_playback_policy_test.dart:6,28`；`test/live_audio_metadata_test.dart:5`。
- 验收：单元＋真机。

### REG-PLAY-025 音频焦点与打断的归属

- 现象（潜在）：切房后，上一个房间的打断事件让新房间暂停或改了音量。
- 正确做法：耳机拔出等事件归属到事件到达时绑定的播放器；打断结束只恢复它挂起的那个意图，并且只恢复一次，期间用户手动暂停则取消恢复；焦点申请被拒不启动播放；已退役播放器的 duck 结束不改新播放器的音量；duck 尊重房间音量并恢复用户当前的选择；一次焦点操作失败不影响之后的通知栏命令。
- 证据：`test/live_audio_handler_ownership_test.dart:51,189,207,256`（共 18 个用例）；`test/player_error_recovery_test.dart:3333`。
- 验收：单元＋真机（来电、拔耳机、其它应用抢焦点）。

---

## 3 中继与租期（REG-LEASE）

### REG-LEASE-001 租期是取流结果的一部分

- 现象：续流逻辑靠猜 URL 里的 `expire` 参数；恢复、预取、交接三套规则互相打架。
- 根因：租期是以 URL 为键的旁路接口（`live_site.dart:184-193`），外加静态表（`douyu_site.dart:33`）。
- 正确做法：每条线路自带租期：签发时刻、刷新时刻、失效时刻，以及到期是否断开连接（`cutsConnection`）。到期会断连（斗鱼）→ 拼接续流（REG-LEASE-002）；只限制新建连接（虎牙原生 FLV）→ 只预取，真正 EOF 才换（REG-LEASE-003）；租期未知 → 首帧栅栏交接；没有租期 → EOF 后按普通恢复。播放和录制按同一份数据决定方式；只有带租期的普通 FLV 才进入拼接中继，其它输入原样直连。
- 证据：DIAGNOSIS 跨模块结论 2；01 ⑥；02 ⑥；ADR 0005 决定 1；`test/flv_splice_relay_test.dart:199`。
- 验收：单元。

### REG-LEASE-002 到期断连型租期：在关键帧处拼接

- 现象：斗鱼原画每 5 分钟断一次；多画面斗鱼格 300 秒后冻结；录制约每 255 秒换一个文件。
- 根因：匿名 URL 带 `expire=300`，CDN 从签发时刻起算 300 秒断开；新旧两条连接的时间戳在同一条时间线上。
- 正确做法：到期前 45 秒续签同线路同画质；新连接找到旧连接还没送出的关键帧后切过去，不留缺口也不重复；两条时间线相差超过 60 秒时平移时间戳；等旧流最多 10 秒，找关键帧最多 15 秒；切换后不再转发 script tag，编解码配置变了先补发；续签失败时把旧流播到结束；旧流提前结束时，在新流的下一个关键帧接上；续期不走恢复链，不占“签名刷新”次数。旧流先结束时拼接会话会直接退出（`flv_splice_relay.dart:146-147`），外面需要再套一层会话循环。
- 证据：31982153；`flv_splice_relay.dart:94-320`；`test/flv_splice_relay_test.dart:70,180`（共 6 个用例）；`tool/probes/douyu_splice_probe_test.dart`；`test/player_error_recovery_test.dart:301`；`test/multiview_test.dart:1588`。平台侧：REG-DOUYU-001、REG-DOUYU-002（`expire=300` 租期）。
- 验收：单元（FLV tag 假源）＋样本（真实的两次续签 FLV）＋探针＋真机（斗鱼录 30 分钟，DTS 最大间隔不超过 1 帧）。

### REG-LEASE-003 只限新建连接的凭据：只预取

- 现象：虎牙 FLV 约 2 分钟 EOF；虎牙录到约 270 秒被切断且尾部损坏；健康的连接被无谓重开。
- 根因：把凭据到期当成连接截止；定时轮换取消了健康的连接。
- 正确做法：原生凭据过期不断开已建立的连接，也不设提前计时器。到刷新时刻只预取下一份凭据：预取不占播放队列，慢预取不阻塞其它操作，playing 事件不触发重复预取。真正 EOF 时消费仍有效的预取凭据，已过期就重新获取；EOF 后即使签名 URL 没变也要重开。预取失败不影响正在播放的媒体；用户停止让挂起的预取和计时器失效；旧会话的预取不能在新会话里重新布置维护任务。
- 证据：8a6fdce1、d6d4123c、f66cff51；`test/huya_transport_policy_test.dart`；`test/player_error_recovery_test.dart:2322,2364,2867`（仅 Windows）；`test/recorder_lease_lifecycle_test.dart:173,196,218`。平台侧：REG-HUYA-001、REG-HUYA-002、REG-HUYA-019（WUP 凭据与 wsTime）。
- 验收：单元＋探针（虎牙连续 60 分钟不断开）＋真机。

### REG-LEASE-004 短租期网页源的提前交接 [待确认：是否仍有流量]

- 现状：虎牙网页 FLV/HLS 源按 100/125 秒短租期处理。Windows 在到期前 40 秒热交接到预热好的第二个播放器，失败 10 秒后重试，已走拼接的跳过。诊断认为现在只有网页回退源会走这条路径。
- 正确做法（如果保留）：交接失败时保留健康的当前传输；交接期间尊重用户暂停；签名解析期间用户暂停，不做过期交接；连续交接在两个已初始化的播放器之间交替；关闭立即撤销候选；其它签名平台只预取，不替换健康的 Windows 传输。
- 证据：`huya_site.dart:57-58`；PM 4172-4234、4616-4673；`test/player_error_recovery_test.dart:1995,2280,2441,2484,2543,2761,2810`（均仅 Windows）；02 ③-7。
- 验收：第 1 阶段先用探针确认虎牙是否还会返回网页回退源，没有则作废本条；保留则写单元测试。

### REG-LEASE-005 恢复必须重新获取身份和令牌

- 现象：恢复时重开了已经过期的地址。
- 根因：恢复逻辑复用了缓存的 URL。
- 正确做法：恢复、重试、会话关闭后继续播放，都重新获取身份和签名，不复用旧 URL；恢复时缺失的画质确认保持“未知”；恢复保持当前的画质和线路游标（斗鱼只刷新 URL 代次）。
- 证据：`live_site.dart:164-169`；`test/douyu_playback_parser_test.dart:45`；`test/stream_selection_controller_test.dart`（斗鱼恢复只刷新 URL 代次，不改画质和线路游标）；`test/multiview_owned_input_test.dart:434`。
- 验收：样本＋单元。

### REG-LEASE-006 按需签名

- 现象：录制启动慢；录制启动时，第一个 URL 已经过期。
- 根因：启动前给所有“画质 × 线路”都签了名。
- 正确做法：播放和录制都只签本次要用的那一条线路；续签保持已应用的画质和 CDN 线路；越界的游标不发请求，也不声明画质。
- 证据：065427ed；`live_site.dart:148-155`；`test/huya_play_url_test.dart:546`；`test/douyu_playback_parser_test.dart:148`；`test/recorder_stream_resolver_test.dart:106,142`；`test/owned_record_input_test.dart:33,61`；`test/douyu_quality_ack_test.dart`（越界游标不发请求）。
- 验收：样本（请求计数）＋单元。

### REG-LEASE-007 每个会话独立签名

- 正确做法：播放和录制分别打开同一个房间时，各自获取签名（虎牙每次打开都生成新的 seqid），不共享同一个签名地址。如果 v4 实现“录制复用播放连接”（可选），前提是画质和线路相同，共享的是中继输出，不是签名 URL。
- 证据：`test/huya_play_url_test.dart:318`；`huya_site.dart:1063-1130`；04 ⑥（共用连接）。平台侧：REG-HUYA-007（seqid）。
- 验收：单元。

### REG-LEASE-008 源事务：成功才替换

- 现象（潜在）：换源失败后连原来的源也没了；旧代次的迟到结果覆盖新源。
- 正确做法：每次开源递增代次 → 取消未完成的开源 → 带取消令牌获取输入 → 内核打开本地 URI → 成功后才替换，旧输入随后关闭。失败的候选只关闭自己，保留上一个可用的输入；较新的打开胜过旧代次迟到的结果；创建输入期间关闭，迟到的输入被回收，不再打开原生；源策略不匹配时在分配输入之前就失败。
- 证据：`playback_source_transport.dart:59-303`；`test/playback_source_transport_test.dart:66,89,143`；`test/playback_owned_input_test.dart`；`test/player_owned_source_test.dart`；02 ④。
- 验收：单元。

### REG-LEASE-009 本地输入绕过代理，上游走代理策略

- 现象：录制不走应用代理；本地中继地址被送进代理，导致打不开。
- 根因：FFmpeg 直连上游；内核的代理设置对本地回环地址也生效。
- 正确做法：内核打开本地回环 URI 时清除内核代理，下一个远程源再恢复；中继的上游请求按代理策略走：播放中继用播放器代理，录制上游和弹幕 WebSocket 用应用代理，两者不互相借用（REG-NET-003）；HLS 的子请求和 FLV 上游都遵守所属会话的策略；未配置时直连。
- 证据：17a192f1；`playback_proxy_policy.dart`；`initialized.dart:94-108`；`test/playback_source_transport_test.dart:234,241`；`test/recorder_proxy_routing_test.dart:12`；`test/web_socket_util_test.dart:68`。
- 验收：单元（本地代理服务器）。

### REG-LEASE-010 回环中继的访问控制

- 现象（潜在）：同机其它程序可以读取中继里带签名的媒体流。
- 正确做法：只绑定回环地址；每个会话一个随机路径，拒绝其它本地路径；包含换行等分隔字符的请求头在原生 open 之前失败；私有输入地址不出现在状态、日志、投屏、复制直链和持久化数据里（REG-LEASE-017）。
- 证据：`test/flv_legacy_hevc_relay_test.dart:131`；`test/playback_source_transport_test.dart:213`；02 ⑥（统一为一个回环服务器，每个会话一个随机路径）。
- 验收：单元。

### REG-LEASE-011 FLV 分帧不丢字节，不转发残缺 tag

- 正确做法：网络按任意边界分块到达时，保留每个文件头和 tag 的全部字节；不完整的 tag 留在缓冲里，不作为媒体转发；拒绝非法文件头和无上限的头长度；保留旧式 previous-tag-size 值；完整 tag 送出后不累积内存；停止卡住的输入时，在最后一个完整 tag 处结束。
- 证据：`test/ffmpeg_flv_input_relay_test.dart:29,48,57`（共 11 个用例）；02 ④（分帧器移入 live_media）。
- 验收：单元（含模糊测试）。

### REG-LEASE-012 读取有超时，停止能解除阻塞

- 现象（潜在）：续流读取没有空闲超时；上游慢速滴流时响应永远不结束。
- 正确做法：每个上游读取都有空闲超时和总截止时间，持续滴流也要在总截止前结束；停止或关闭能解除还在等响应头的请求；连接前就停止则不打开上游；取消要传到真实的 TCP 连接，而不只是结束一个 Future；空闲超时后释放容量。
- 证据：02 ③-6；`test/ffmpeg_hls_body_idle_test.dart:79`；`test/hls_prefetch_pool_test.dart:299`；`test/ffmpeg_flv_input_relay_test.dart:219`；`test/platform_response_lifecycle_test.dart:354`。
- 验收：单元（本地慢速服务器）。

### REG-LEASE-013 HLS 整片发布与资源上限

- 现象：HLS 交给下游半个分片；截断的响应被当成成功。
- 根因：流式转发，分片还没收完就交出去。
- 正确做法：分片整片收完、长度校验通过才发布；上游被截断时，在任何字节到达读者之前失败；超过 128 MiB 的资源直接拒绝；解压后按实际长度校验；停止时冻结播放列表，进行中的刷新不能再发布新分片；滚动播放列表只保留两代地址；重定向最多 5 跳；上游的 403 原样传出，不变成笼统的 503；没有 `.m3u8` 后缀的播放列表按内容识别。
- 证据：6415d42e、29caea0b、dffc351d；`test/ffmpeg_hls_input_relay_test.dart:11,150,337,553,593`；`test/ffmpeg_hls_staging_limits_test.dart:96`；`test/hls_media_spool_test.dart:42`；`test/ffmpeg_hls_prefetch_integration_test.dart:573`。
- 验收：单元（本地 HTTP 服务器）＋样本（B 站 fMP4 HLS、Twitch、niconico）。

### REG-LEASE-014 HLS 的 Cookie 与凭据作用域

- 现象（潜在）：调用方的 Cookie 被重定向带到第三方域名；过期的会话 Cookie 被复活。
- 正确做法：播放列表下发的会话 Cookie 带到 init 和分片请求，但不暴露给本地读者；重定向时 Cookie 随之轮换，调用方自己的凭据只发给原始源站；host-only 与 domain Cookie 固定在签发它的源；Cookie 的数量和大小有上限；会话关闭时丢弃全部 Cookie；每次重定向都重新解析运行时 Cookie，不复活过期值。
- 证据：`test/ffmpeg_hls_input_relay_test.dart:212,241`；`test/hls_session_cookies_test.dart:7`（共 8 个用例）；`test/hls_runtime_cookies_test.dart:14`；`test/hls_upstream_client_test.dart`。
- 验收：单元。

### REG-LEASE-015 HLS 播放列表刷新节奏

- 正确做法：首次加载和内容变化后，等一个目标时长再刷新；内容逐字节相同，等半个目标时长；慢速但成功的刷新不再叠加额外间隔，也不重叠，不丢滚动窗口（RFC 8216 §6.3.4）。
- 证据：`test/hls_reload_cadence_test.dart:16`。
- 验收：单元（fake_async）。

### REG-LEASE-016 HLS 变体与音轨按身份选择

- 正确做法：每个显式变体保留其关联的音轨；选择按身份，不按下标；多语言音轨需要显式选择，默认轨不算用户意图；已经混合音频的视频不附加无关的外部音轨；master 有歧义或不支持时保持原始路径，不猜。
- 证据：`test/hls_master_selection_test.dart:33,60`；`test/hls_prefetch_plan_test.dart:49`。
- 验收：单元＋样本（niconico 分离音频）。

### REG-LEASE-017 会话型输入不导出私有地址

- 现象（潜在）：投屏或复制直链拿到的是本地中继地址，在别的设备上打不开，还泄露观看页凭据。
- 正确做法：会话型流（niconico，以及建议下线的 FC2、Bigo）打开时不需要占位 URL；本地地址和观看页地址不导出到投屏、复制直链、持久化的录制任务；投屏和复制时明确提示“需要会话”；同一个公开源在两个格子里打开，得到两个独立的私有输入；失败的候选只关闭自己；远端会话关闭后继续播放时重新获取一次。
- 证据：`playback_source.dart:31-41`；`test/live_owned_input_resolution_test.dart:39`；`test/multiview_owned_input_test.dart:236,280,434`；`test/toolbox_direct_link_flow_test.dart:55`；`test/recorder_lease_lifecycle_test.dart:155`。
- 验收：单元。

### REG-LEASE-018 HLS 查询 token 策略 [待确认：是否保留]

- 现状：唯一产出它的 TTingLive 已在 1495f56b 下线，站点层没有调用者。
- 正确做法（如果保留）：嵌套媒体只获得精确的 token 对；不在源作用域之外隐式传播；两个会话不共享 token；策略不匹配时，在中继改用其它输入之前失败；诊断不回显 token。
- 证据：`test/hls_source_query_policy_test.dart:50`；`test/ffmpeg_hls_source_query_test.dart`；02 1.4；DIAGNOSIS 待确认事项。
- 验收：第 1 阶段查证是否还有平台产出，没有就作废本条。

---

## 4 直播间交互（REG-ROOM）

### REG-ROOM-001 小窗不挡弹出菜单

- 现象：应用内小窗下面弹出的菜单点不动。
- 根因：小窗是 Overlay 条目，之后打开的弹窗在它下层；flutter_floating 自带不透明的拖动手势层，加 IgnorePointer 也拦不住。
- 正确做法：有弹出路由（菜单、对话框、底部弹层）时，整个小窗 Offstage；弹窗关闭后恢复交互。
- 证据：44e3cb1b、c766d319；`test/popup_route_tracker_test.dart:66`。
- 验收：截图（组件测试）＋真机。

### REG-ROOM-002 双击按源方向进入全屏

- 现象：竖屏源双击进了横屏式全屏。
- 根因：双击没有区分竖屏源。
- 正确做法：双击统一走“手势全屏”：宽屏时先退出宽屏；竖屏源（移动端，且开启竖屏适配）进入或退出竖屏全屏；其余情况切换普通全屏；锁定时双击无效。
- 证据：6d6b97ee；`video_controller_panel.dart:246-252`；`video_controller.dart:1355-1372`；PLAN §07。**没有自动化测试**，见 G-04。
- 验收：组件测试（新增）＋真机。

### REG-ROOM-003 单击显示或隐藏控制层

- 现象：手机上单击无法收起控制栏（upstream #886）。
- 正确做法（沿用 3.2.10）：手机上控制层可见且正在播放时，单击隐藏；否则显示控制层，暂停中同时继续播放；桌面单击只显示（暂停中同时继续播放）；命中弹幕时打开弹幕操作。
- 证据：6d6b97ee；`video_controller_panel.dart:201-232`；PLAN §07。**旧版没有针对“单击收起”的测试**，见 G-05。
- 验收：组件测试（新增）＋真机。

### REG-ROOM-004 控制条范围内不做弹幕命中

- 现象：点控制条上的按钮，却弹出了弹幕操作菜单。
- 根因：全屏手势层仍会收到控制条区域的点击。
- 正确做法：控制条可见时，控制条高度范围内的点击和长按只用来显示控制层，不做弹幕命中；控制层开始隐藏时立即不可点击，不等动画结束。
- 证据：bab0af08；`video_controller_panel.dart:74-83`；`test/live_play_navigation_ui_test.dart:68`；`test/bottom_control_surface_test.dart`。
- 验收：组件测试。

### REG-ROOM-005 返回键层级

- 现象：返回键跳过全屏直接离开房间，或弹窗开着时房间被关闭。
- 根因：Android 原生返回回调注册得晚。
- 正确做法：返回回调在整个路由生命周期内有效。顺序：先关弹窗 → 全屏或宽屏先恢复普通 → 普通状态离开房间；开启“浮窗播放”且有画面时，离开房间转为应用内小窗（REG-ROOM-007）。
- 证据：c00b2069、81433454；`live_play_back_scope.dart:171-193`；`navigation_observer.dart:50-58`；`test/live_play_back_scope_test.dart:56,81`。关联 REG-ANDROID-004。
- 验收：组件测试＋真机（预测性返回手势）。

### REG-ROOM-006 Esc 与键盘焦点

- 现象：Esc 失效；按住 Esc 连退好几层。
- 根因：弹幕渲染用的 Flame GameWidget 会自动抢焦点。
- 正确做法：弹幕渲染层不获取焦点（REG-DANMAKU-010）。Esc 依次：退出全屏 → 退出宽屏 → 离开房间；按住 Esc 只退出一层，不会离开房间；焦点在子控件时由子控件先处理；全屏下菜单里的 Esc 只关菜单；画中画状态下由画中画处理 Esc；还没有播放控制器的离线房间也能用 Esc 离开。Space 和媒体键播放暂停，R 刷新，↑↓ 调音量 ±5%；控制器已退役、读不到有效音量时忽略方向键，不写音量也不弹音量提示，不能默认成最大音量。
- 证据：1c22bffe；`video_keyboard.dart:53-84,92-101`；`test/danmaku_keyboard_focus_test.dart:68`；`test/video_keyboard_escape_test.dart:47,134,161,373`（共 12 个用例）。
- 验收：组件测试。

### REG-ROOM-007 失败的房间不留黑色小窗

- 现象：加载失败的房间离开后留下一个黑色小窗；加载失败时一直转圈。
- 根因：离开房间时一律转成小窗。
- 正确做法：只有“有画面且没有加载错误”时才转小窗；加载失败显示带重试的占位，而不是无限转圈。
- 证据：928ea47d；`test/live_play_placeholder_test.dart:6,14`。
- 验收：组件测试。

### REG-ROOM-008 小窗接回与资源释放时机

- 现象：从小窗回到房间时状态丢失；小窗相关资源释放过早。
- 根因：旧页面的返回动画还在订阅状态时资源就被释放。
- 正确做法：等页面真正卸载后再释放（最多等 50 毫秒，不能无限等一帧）；从小窗回到房间的交接是显式的、限定在同一房间、只能用一次；清理小窗时保留同房间的回房交接。
- 证据：5d4778f3；`live_play_controller.dart:1081-1085`；`test/player_audio_mode_transition_test.dart:1140,1261`。
- 验收：单元＋组件测试。

### REG-ROOM-009 状态模型能显式清空字段

- 现象：切到纯音频后一直显示加载。
- 根因：`copyWith` 的可空参数分不清“没传”和“清空”，把播放器字段清掉了。
- 正确做法：清空用显式标志；状态模型能单独清除当前弹幕房间 id 和上一次加载错误。
- 证据：`player_state.dart:108-111`；`test/live_play_state_test.dart`。
- 验收：单元。

### REG-ROOM-010 进房不覆盖设备音量

- 现象：进入直播间时手机音量被改成房间保存的值。
- 根因：进房时回放了房间保存的音量。
- 正确做法：手机音量属于设备，只读不写；进房时采用设备当前音量，不覆盖房间保存的偏好；全局静音例外，照常生效；已静音的设备保持静音；用户在初始读取期间的操作优先于恢复；读取卡住有上限，迟到的结果不写设备。桌面房间音量不受手机默认值影响。
- 证据：789f03cc；`test/video_source_commit_listener_test.dart:75,187`（共 18 个系统音量用例）；`test/volume_control_lifecycle_test.dart:111`。
- 验收：单元＋真机。

### REG-ROOM-011 全屏方向

- 现象：强制横屏全屏退出后不回竖屏。
- 正确做法：全屏方向有“跟随源、跟随系统、强制横屏”三种；竖屏房间可以一次性强制横屏，退出时先释放沉浸模式再恢复竖屏，恰好一次；之后普通地进入全屏会清掉未完成的恢复；设置开启时，进房 1 秒后自动全屏。
- 证据：039f8ff3；`video_controller.dart:626-643,1374-1494`；`test/fullscreen_orientation_restore_test.dart`。
- 验收：单元＋真机。

### REG-ROOM-012 展示状态只有一份真相

- 现象（潜在）：全屏、宽屏标志在两处不同步，桌面标题栏状态错乱。
- 根因：全局 `GlobalPlayerState` 与 `UIState.screenMode` 各存一份，手动同步；多画面还会写全局全屏标志控制标题栏。
- 正确做法：展示状态只有一个枚举（内嵌、剧场、全屏、竖屏全屏、画中画、小窗）；系统栏和屏幕方向由副作用层订阅这个枚举。
- 证据：`live_play_controller.dart:394-420`；`multiview_page.dart:185`；03 ③-3、⑥。
- 验收：单元（状态机）。

### REG-ROOM-013 画质和线路切换

- 现象（潜在）：连续切画质时停在中间的某一档；切换失败后画质、线路、URL 三者不一致。
- 正确做法：切换不重建控制器，以最后一次请求为准；URL 解析出来之前保持旧状态；切画质保留当前线路；非签名平台切线路复用当前 URL，不重新取画质元数据；签名平台切线路重新获取 URL；原生 open 失败时，画质、线路、URL 原子回滚；回到当前画质会取代挂起的 URL 请求；不同标签解析到同一个流时不重复提交。
- 证据：`player_controller.dart:686-847`；`test/stream_selection_controller_test.dart:389,423,501,735`（共 25 个用例）。
- 验收：单元。

### REG-ROOM-014 竖屏房间面板与竖屏全屏

- 正确做法：竖屏源的房间面板三档拖动，档位与列表滚动互不干扰；拖过最低档或点把手进入竖屏全屏（需要有意的距离或向下快滑），短距离下拉恢复面板；竖屏全屏底部 96 dp 内向上滑退出；横屏源不出现竖屏全屏的入口；竖屏房间保留“横屏全屏”按钮；被拒绝的进入恢复面板，可以再次手势；视频区平衡模式下至少给弹幕列表留 200 px；只有视频的平台不预留空的互动面板。PLAN §08 要求紧凑宽度沿用三档面板。
- 证据：`live_play_content.dart:162-253,390-431`；`portrait_fullscreen_interaction.dart:7,39`；`test/live_play_normal_layout_test.dart:116,179,325`；`test/portrait_fullscreen_interaction_test.dart:39,58`；`test/portrait_room_transition_test.dart:164`；`test/portrait_stream_support_test.dart:356`。
- 验收：组件测试＋真机。

### REG-ROOM-015 终态错误与未知元数据

- 正确做法：终态播放错误持续显示，并保留视频元素；重试去重，失败后仍可再试；房间元数据未知时结束加载状态，不无限等待；同一房间元数据刷新失败时，保留已收到的醒目留言。
- 证据：`test/playback_failure_overlay_test.dart:34`；`test/live_play_unknown_metadata_test.dart:91`。
- 验收：组件测试。

### REG-ROOM-016 打开原站、投屏、复制直链

- 现象（潜在）：把空地址或本地地址交给系统打开；投屏在设置源之前就开始播放。
- 正确做法：打开原站只用经过验证的官方地址，房间身份无效时不拼接猜测的地址，不把空目标或本地目标交给系统；打开失败不按原样重试；重复点击共用一次打开；房间在等待期间被替换时，结果不影响新房间。投屏只接受规范化的网页地址；投屏命令单次执行，先设置源再播放；切换接收设备前等上一个设备暂停完成。复制直链只在剪贴板确认写入后才报告成功。会话型输入不导出私有地址（REG-LEASE-017）。
- 证据：`test/room_external_opener_test.dart:251`；`test/live_room_external_open_test.dart:81`；`test/live_dlna_dialog_test.dart:21,169`；`test/known_room_link_action_test.dart:219`；`live_play_menu_button.dart:189-206`。
- 验收：单元。

### REG-ROOM-017 控制层自动隐藏与悬停

- 正确做法：控制层静止一段时间后自动隐藏（旧值 4 秒，PLAN §07 桌面改为 2 秒），鼠标悬停在控制条上或菜单打开时不隐藏，隐藏时同时隐藏鼠标指针。悬停归属按指针计数：组件移除时释放、多个指针共享、替换后的控制器拿到自己的归属，稳定重建不反复抢占。
- 证据：`video_controller.dart:319-323,864-944`；`test/control_hover_region_test.dart:34`；`test/player_control_hover_test.dart`。
- 验收：组件测试。

### REG-ROOM-018 亮度和音量手势的平台边界

- 正确做法：上下滑动左半边调亮度（仅手机）、右半边调音量；锁定时无效；桌面永远不提供应用内亮度调节，也不引入调节显示器亮度的插件；鼠标滚轮调音量（PLAN §07：v4 在整个画面上生效）。
- 证据：`video_controller_panel.dart:851-903,951-956`；`test/brightness_platform_boundary_test.dart:8`。
- 验收：组件测试。

### REG-ROOM-019 定时关闭

- 正确做法：房间定时关闭的取消不改变正在运行的计时；预设和自定义时长只提交一次；时长无效时对话框保持打开、运行中的计时不变；应用退出计时的输入限制在 1 年以内，持久化值在调度器读取之前修复。
- 证据：`test/room_timer_dialog_test.dart:81`；`test/deferred_timer_settings_test.dart:36`；`test/app_settings_controller_test.dart`（长时间睡眠计时钳制到 1 年）。
- 验收：单元。

---

## 5 多画面（REG-MULTI）

### REG-MULTI-001 卡顿恢复保留手动选择的画质和线路

- 现象：多画面卡顿恢复后，丢了手动选的线路。
- 根因：重新解析后按默认线路开流。
- 正确做法：恢复只刷新受影响的格；按选择 id 先还原画质，再还原线路；用户的手动操作让进行中的恢复作废。
- 证据：4fe4f7b7；`test/multiview_test.dart:1472,1507`。
- 验收：单元。

### REG-MULTI-002 源结束即重载，恢复次数按时间窗口

- 现象：斗鱼格每 5 分钟冻结一次，几次之后永久冻结。
- 根因：CDN 在 300 秒断开，播放器进入 completed 而不是卡顿，看门狗不触发；恢复次数一辈子只有 2 次。
- 正确做法：订阅 completed 事件触发重载，并保持画质和线路；恢复次数按时间窗口计算，与单房间共用恢复策略（REG-PLAY-010）；紧密的失败循环必须停下；暂停中的格子不因源结束而重载。
- 证据：bf570796；`test/multiview_test.dart:1540,1560,1610`；`multiview_controller.dart:355`。平台侧：REG-DOUYU-001、REG-DOUYU-002（`expire=300` 租期）。关联 REG-PLAY-001。
- 验收：轨迹＋单元。

### REG-MULTI-003 租期续流交给每格的中继

- 正确做法：会到期的线路在开播和换线时把租期交给该格的拼接中继；续签按同一线路、同一画质重新解析（REG-LEASE-002）；每格的租期互相隔离，交给播放后端的只有私有 URL 和空请求头。
- 证据：31982153；`multiview_controller.dart:219-265,944-947`；`test/multiview_test.dart:1588`；同文件“real cell owner isolates leases”。
- 验收：单元＋真机。

### REG-MULTI-004 退出多画面先卸载视频再出栈

- 现象：退出多画面时崩溃。
- 根因：返回动画期间，外部纹理注销与合成冲突。
- 正确做法：先卸载所有视频，等两帧，再出栈。
- 证据：6ec8713d；`multiview_page.dart:145-160`。
- 验收：真机（Windows、Android 各退出 20 次）。

### REG-MULTI-005 格状态机与严格解析

- 正确做法：格状态依次为空 → 解析中 → 播放中，第一个开播的格自动成为声音焦点；已知未开播的房间进入“未开播”空态，不解析、不创建播放器；严格解析区分“确认未开播”与“解析失败”（REG-COMMON-001）；解析失败置错误态，不留下旧画质上下文；向已占用的格选台，先按顺序释放旧播放器；移除格按严格顺序释放；全部释放时同步清空状态、后台销毁，单个销毁出错不中断其余；离线和失败的格仍可重新选台；选台列表按直播状态排在观众数之前。
- 证据：`test/multiview_test.dart:698,719,1045`（多画面测试共 66 个）；`test/multiview_room_picker_test.dart:6`。
- 验收：单元。

### REG-MULTI-006 声音焦点互斥与一键静音

- 正确做法：切换声音焦点后新旧格静音状态互斥；连续切换以最后一次为准；一键静音让所有格静音，切换焦点也不出声，再点一次恢复焦点格的声音（upstream #879）；“一大多小”布局下向小格选台不抢声源，晋升为大画面后才出声。
- 证据：`test/multiview_test.dart:752,769,795,1000`。
- 验收：单元。

### REG-MULTI-007 布局与容量上限

- 正确做法：单画面、双画面、四宫格、一大多小；手机最多 4 格，桌面最多 9 格，移动端的上限阻止额外解码器；四宫格切双画面保留前两格的播放状态，释放第三、四格；一大多小布局可动态加格直到上限；切换布局时钳制越界的焦点下标。
- 证据：`multiview_models.dart:15-45`；`multiview_controller.dart:73,84`；`test/multiview_test.dart:835,1116`。
- 验收：单元。

### REG-MULTI-008 每格独立的取流令牌与迟到结果栅栏

- 正确做法：每格有自己的取流令牌，同一格被替换和另一格互不影响；布局缩小时，先取消被移除格的全部取流；格下标复用后，拒绝缩小前的旧解析结果；换清晰度期间重新分配的格丢弃迟到结果；同一播放器换流，并保持当前线路。
- 证据：`test/discovery_scope_owners_test.dart:121,149`；`test/multiview_test.dart:1157,1457`；03 ④（沿用纪元防过期结果的算法）。
- 验收：单元。

### REG-MULTI-009 小格降质联动

- 正确做法：开启联动时，小格取最低档，晋升或降格时自动换档；关闭时晋升不触发任何换流；开关切换即时作用于正在播放的小格。旧版默认关闭，只在一大多小布局生效；v4 由资源调度器自动决定 [待确认：默认值]。
- 证据：`multiview_controller.dart:414,493-504,641-665`；`test/multiview_test.dart:1190`。
- 验收：单元。

### REG-MULTI-010 帧看门狗的可见性与宽限

- 正确做法：出过首帧后才开始计算停滞；没有首帧、以及持续有帧进度时都不判定停滞；被隐藏的路由恢复可见时给完整宽限，短暂隐藏后立即重置截止时间；暂停的格不因画面超时而刷新；屏幕外的小格不刷新，滚动进入视口时给新的宽限；晋升时先丢弃旧的小格映射再监控新的大格；自动恢复有有限预算。旧版看门狗只在 Windows 生效。
- 证据：`test/multiview_frame_watchdog_test.dart:6,60`；`test/multiview_test.dart:1622,1677,1710`；`test/focus_rail_visibility_test.dart:7`。
- 验收：单元＋真机（Android 依赖 REG-ANDROID-010）。

### REG-MULTI-011 弹幕会话跟随大画面和声音焦点

- 正确做法：多画面弹幕由页级开关控制，只显示在大画面（一大多小）或声音焦点格（其它布局）上；房间变化、大画面切换、大画面解析失败都同步弹幕会话；不支持弹幕的平台不建立会话；过滤链与直播间是同一份（REG-DANMAKU-004）。
- 证据：`multiview_controller.dart:506-550`；`test/multiview_test.dart:1233,1285`。
- 验收：单元。

### REG-MULTI-012 进入多画面与每格音量

- 正确做法：进入多画面时暂停全局播放器，恰好一次；每格音量与静音相互独立，越界钳制；房间音量在格子重建后恢复，并写入与直播间共用的存储。
- 证据：`test/multiview_test.dart:926,1414`。
- 验收：单元。

### REG-MULTI-013 渲染分辨率按格子尺寸

- 正确做法：创建播放器时，按屏幕物理像素除以行列数固定每格的渲染分辨率；挂载后按实际格子尺寸重设；晋升时交换大小格的渲染目标。旧版 Android 忽略宽高设置、按原分辨率解码，v4 在 Android 上的实现手段 [待确认]。
- 证据：`multiview_controller.dart:1391-1398`；`multiview_page.dart:1002-1011`；`test/multiview_test.dart:738`；`test/video_output_viewport_sizer_test.dart:164`。
- 验收：单元＋真机（4 格内存）。

### REG-MULTI-014 全屏退出入口

- 正确做法：多画面全屏时，安全区内始终有退出入口，并且不抢格子的点击；Esc 退出沉浸或全屏。
- 证据：`test/multiview_fullscreen_surface_test.dart:6`；`multiview_page.dart:162-168`。
- 验收：组件测试。

---

## 6 弹幕（REG-DANMAKU）

### REG-DANMAKU-001 快速切房不串房

- 现象：快速切换直播间时，上一个房间的弹幕出现在新房间。
- 根因：旧连接的回调没有会话令牌。
- 正确做法：连接串行化，并带会话令牌和房间 key；协议层丢弃明确标记为其它房间的消息；旧房间的刷新不能压制新房间的通知。
- 证据：`danmaku_controller.dart:13-18,248-250`；`test/douyu_danmaku_protocol_test.dart:24`；`test/douyin_danmaku_protocol_test.dart:36`；`test/huya_danmaku_protocol_test.dart:178`。
- 验收：单元＋样本（录制的弹幕帧）。

### REG-DANMAKU-002 画中画返回后恢复弹幕

- 现象：从画中画返回后，弹幕列表停住不动。
- 根因：画中画期间列表被移出界面树，收不到状态恢复。
- 正确做法：由房间级控制器发布恢复通知，并补刷积压的批次；恢复要等紧凑展示真正结束；结束前的多个返回信号合并为一次重连，重连进行中又来的返回信号在其后补做；匹配且健康的连接保留，已显示的消息不丢；只重建断开的连接，不打断正在进行的连接尝试。
- 证据：`live_play_controller.dart:195-220`；`test/danmaku_presentation_recovery_test.dart`；`test/danmaku_controller_lifecycle_test.dart:85`。
- 验收：单元＋真机。

### REG-DANMAKU-003 平台级过滤默认关闭，切换不重连

- 现象：斗鱼弹幕缺了一大部分。
- 根因：上游重构把“疑似机器人过滤”的开关丢了，默认过滤了未标记的消息。
- 正确做法：平台级过滤（斗鱼疑似机器人）默认关闭，弹幕默认完整；用户切换开关后立即生效，不重连；导入备份时保留用户的显式选择。
- 证据：31ee5cd7、4cbb43ba；`douyu_danmaku.dart:128-129`；`test/douyu_danmaku_protocol_test.dart:34,60`；`test/danmaku_settings_controller_test.dart`（保留备份中的斗鱼过滤选择）。平台侧：REG-DOUYU-020（未标记房间消息）。
- 验收：样本＋单元。

### REG-DANMAKU-004 过滤链只有一份，大小写一致

- 现象：含大写字母的屏蔽词和屏蔽用户在多画面里不生效（旧版缺陷，3.3.x 修复）。
- 根因：多画面复制了一份过滤链，只把消息转小写，屏蔽词按原大小写保存。
- 正确做法：直播间和多画面共用一份过滤链；屏蔽词、屏蔽用户和消息都做同样的大小写归一；添加屏蔽词时保留首次的写法，拒绝只有大小写不同的重复项。
- 证据：`multiview_danmaku_session.dart:199-201`；`favorite_room_controller.dart:446-453`；DIAGNOSIS 旧版缺陷表；`test/shield_management_page_test.dart:357`。多画面的大小写问题没有测试，见 G-17。
- 验收：单元（同一组用例同时跑直播间和多画面）。

### REG-DANMAKU-005 去重闸门

- 正确做法：超过 45 秒的积压消息丢弃，时间戳超前 10 分钟以上视为畸形；有平台消息 id 的 10 分钟内去重；没有 id 的按“类型＋用户＋文本”2.5 秒去重，窗口外真实的重复发言保留；指纹数量有上限。
- 证据：`danmaku_message_gate.dart:24-52`；`test/danmaku_message_gate_test.dart:21`。
- 验收：单元（fake_async）。

### REG-DANMAKU-006 重复合并

- 正确做法：可选开启，窗口 1–30 秒，只在窗口内合并不同用户的相同文本；本地消息不参与；关闭时清空已记录的条目。
- 证据：`test/repeated_danmaku_filter_test.dart:15,40`；`test/danmaku_settings_controller_test.dart`（导入时钳制合并窗口）。
- 验收：单元。

### REG-DANMAKU-007 相似度过滤

- 正确做法：默认关闭（旧参数 85 / 3 / 100）；每条消息的比较次数有上限（旧值 96 次）；缓存和比较次数分别有上限；空文本忽略；清空时重置缓存。v4 不再用 fuzzywuzzy（GPL-2.0，ADR 0006），换算法后阈值怎么对应 [待确认]。
- 证据：`danmaku_similarity_filter.dart:96-112`；`test/danmaku_similarity_filter_test.dart:30`。
- 验收：单元（同一组样本在新旧算法上的通过率对照）。

### REG-DANMAKU-008 渲染密度与队列上限

- 现象：热门房间弹幕堆积、掉帧，内存持续增长。
- 正确做法：初始预算沿用旧值：每 50 毫秒发一条，同屏最多 48 条，待发队列 120 条（超出丢最旧的），待发超过 5 秒丢弃；暂停和活动队列共用一个上限。没有弹幕或渲染层未挂载时不跑 ticker，按配置的帧率绘制。排版和图片缓存有上限，淘汰时释放原生对象；透明度、字体、阴影、时长都是缓存键的一部分；低透明度弹幕保留描边，保证对比度。
- 证据：`video_controller.dart:955-975`；`barrage_engine.dart:26-31,125-185,321-338,407-415`；`test/barrage_queue_test.dart:22,73,83,96,141`（共 11 个用例）；07 ⑤（flame_barrage 本地补丁）。
- 验收：单元＋真机（回放每秒 200 条的弹幕流，主线程每帧不超过 3 毫秒）。

### REG-DANMAKU-009 渲染帧率策略

- 正确做法：“最高”策略让房间和画中画的弹幕同步到设备的最大刷新率；检测到非标准的最大值（如 144）时照用，不写死 60；省电和平衡策略保留有上限的渲染预算；自适应帧率只限制弹幕的工作量，不降低应用的显示模式。
- 证据：`test/danmaku_refresh_rate_policy_test.dart:53`；`test/danmaku_settings_controller_test.dart:7`。
- 验收：单元。

### REG-DANMAKU-010 渲染层不抢焦点

- 现象：Esc 失效；同时挂载两个弹幕层时输入框失去焦点。
- 根因：Flame 的 GameWidget 自动获取焦点。
- 正确做法：弹幕渲染层排除在焦点树之外，不自动获取焦点。
- 证据：1c22bffe；`flame_barrage_widget.dart:81-100`；`test/danmaku_keyboard_focus_test.dart:68`。关联 REG-ROOM-006。
- 验收：组件测试。

### REG-DANMAKU-011 连接生命周期与类型化通知

- 现象（潜在）：连接卡住时房间无法退出；不支持弹幕的平台反复尝试连接。
- 正确做法：连接启动卡住有上限，超时停止并允许重连；停止卡住不能永远阻塞房间销毁；不支持弹幕的平台只报告一次“不支持”，不伪造连接，画中画也不反复启动；重连和终止通知是类型化事件，与显示文案无关；轮询型实现（快手）在失败响应时不显示“已连接”，停止时取消挂起的请求。
- 证据：`test/danmaku_controller_lifecycle_test.dart:14,46,141`；`test/kuaishou_danmaku_test.dart:46,92`。平台侧：REG-KUAISHOU-011～REG-KUAISHOU-014（移动端 feed 轮询）。
- 验收：单元。

### REG-DANMAKU-012 WebSocket 通用行为

- 正确做法：检测到静默的半开连接就关闭，并换下一个节点重连；收到服务器心跳保持同一连接；配置的代理用于握手，直连时用默认客户端；远端关闭的诊断带关闭码和原因；手动关闭能中止卡住的握手；重复连接请求加入正在进行的握手；关闭确认卡住时销毁有上限。
- 证据：`test/web_socket_util_test.dart:9,68,216`（共 9 个用例）。平台侧：REG-DOUYIN-002、REG-DOUYIN-003（多个 webcast 节点故障切换，f491afd7）。
- 验收：单元（本地 WebSocket 服务器）。

### REG-DANMAKU-013 协议解析健壮

- 正确做法：一个帧里的嵌套包、拼接包全部解出；长度为 0 的畸形帧不能导致死循环，也不能丢掉前面已解出的消息；压缩包的递归层数有上限；空消息不影响下一个包；需要应答的协议（B 站 op24 ACK）由连接器回写应答，不丢消息。
- 证据：`test/bilibili_danmaku_protocol_test.dart:52,71,157`；`test/douyu_danmaku_protocol_test.dart`。平台侧：REG-BILIBILI-008、REG-BILIBILI-011、REG-BILIBILI-012（认证包字段与 ACK），REG-DOUYU-021（STT 合包）。B 站实际走 brotli 的路径没有测试，见 G-11。
- 验收：样本（录制的真实弹幕帧）＋模糊测试。

### REG-DANMAKU-014 醒目留言的身份与过期

- 正确做法：醒目留言用平台稳定的事件 id 去重，重复的快照合并为一个事件；内容相同但 id 不同的付费消息都保留；没有 id 的重复快照按模型身份去重，不按重建出来的时间；没有留言时不定时唤醒，只为最早的截止时间安排一次唤醒，过期的在下一轮事件循环中移除；平台颜色格式错误时用默认色，不隐藏付费消息。
- 证据：`test/huya_danmaku_protocol_test.dart:153`；`test/super_chat_expiry_policy_test.dart:25`；`test/super_chat_page_test.dart:154`。平台侧：REG-HUYA-021、REG-HUYA-022（留言板轮询）。
- 验收：单元。

### REG-DANMAKU-015 弹幕列表跟随与恢复

- 正确做法：列表默认跟随最新消息；用户第一次拖动在移动之前就暂停跟随，桌面滚轮立即暂停；程序触发的滚动、Android 画中画视口的方向事件都不暂停；按下时作废上一帧排队的“跳到末尾”；一次显式的“恢复”追上最新，并在下次拖动时重新计数；表情解析缓存有上限。
- 证据：`test/danmaku_list_scroll_policy_test.dart:16,31,57`；`test/danmaku_list_resume_test.dart:185`。
- 验收：单元＋组件测试。

### REG-DANMAKU-016 历史列表增量更新

- 现象：弹幕多时整个直播间卡顿。
- 根因：每 64 毫秒把最多 500 条历史整表复制一次再整体替换；弹幕解码和过滤都在 UI isolate。
- 正确做法：解码、过滤、抽样在后台 isolate 完成，按 16–64 毫秒批量发到主线程；历史改为环形缓冲，增量通知；新到消息的计数准确：历史满时新批次的每一条都算，屏蔽最新一条和清空历史都不算新到，快照不变或只是重排不增加计数。
- 证据：`live_play_controller.dart:515-525`；`web_socket_util.dart:214,264`；03 ③-1、③-4；`test/danmaku_arrival_counter_test.dart:5`。
- 验收：单元＋真机（性能预算，见 PLAN §10）。

### REG-DANMAKU-017 弹幕设置与模板导入

- 正确做法：导入的数值钳制到控件的范围，非有限值用默认值；旧备份缺少的字段用紧凑默认值；显示模板往返保留所有已渲染的设置，格式错误或越界的模板整体拒绝，不部分应用；画中画弹幕设置（15 项）单独保存，重置恢复全部画中画默认值。
- 证据：`test/danmaku_settings_controller_test.dart`（共 12 个用例）；`test/danmaku_viewing_preset_test.dart:120`；`test/danmaku_settings_surface_test.dart:191`；`test/pip_danmaku_preview_test.dart`。关联 REG-STORE-012。
- 验收：单元。

---

## 7 录制（REG-RECORD）

录制的后台保障见 REG-ANDROID-007（前台服务）和 REG-WINDOWS-013（退出提示）。

### REG-RECORD-001 租期续流下录制文件连续

- 现象：斗鱼录制约每 255 秒切成一个新文件，文件之间有缺口；虎牙网页源约每 100 秒一次。
- 根因：每次续期都新开一次录制尝试（新目录、新前缀、新 MP4），中间有排空、重连、解析、探测的空档。
- 正确做法：一次录制会话就是一个连续的文件（或按时间、大小在关键帧处切分的分段）；续期由中继完成（REG-LEASE-002、REG-LEASE-003），不打断写入；旧流先结束时由外层会话循环续接；无法避免的缺口写入 `gaps.json`。
- 证据：31982153；`recorder_controller.dart:883-887,1080-1085`；`recorder_continuation_policy.dart:58-71`；04 ③-1；ADR 0005。平台侧：REG-DOUYU-012～REG-DOUYU-014、REG-HUYA-015。
- 验收：真机（斗鱼录 30 分钟，DTS 最大间隔不超过 1 帧；虎牙录 60 分钟无断开）＋单元（FLV 写入器）。

### REG-RECORD-002 流结束快速重连，不进慢轮询

- 现象：直播中流意外结束，录制被当成下播，进入慢轮询，漏录一大段。
- 根因：直播流没有自然的 EOF。
- 正确做法：直播中的意外 EOF 快速重连（2 秒起，逐步到 15 秒），不进入离线慢轮询；自动重连开启时意外退出后恢复监控；配置的失败类型仍按配置处理。
- 证据：7c3275b4；`test/recorder_continuation_policy_test.dart:94,127`。
- 验收：单元（fake_async）。

### REG-RECORD-003 4xx 重新解析，5xx 才原地重试

- 现象：403/404 反复用旧签名重试。
- 根因：FFmpeg 内部重连用的是同一个签名 URL。
- 正确做法：CDN 过期和 I/O 失败先重新解析，拿到新地址再重试；只有 5xx 在原地址上重试。
- 证据：cf35dcf9；`ffmpeg_command_builder.dart:182-210`；`test/recorder_continuation_policy_test.dart:26`。
- 验收：单元。

### REG-RECORD-004 本地存储失败不重连

- 现象（潜在）：磁盘满或路径错误时录制无限重试。
- 正确做法：本地存储耗尽是单独的错误类型，永不进入重连；本地路径和输出格式错误不循环重试；只有用户显式停止才算“成功完成”。
- 证据：`test/ffmpeg_failure_classifier_test.dart:110`；`test/recorder_continuation_policy_test.dart:39`。
- 验收：单元。

### REG-RECORD-005 严格房间状态决定开录

- 现象：元数据请求失败被当成下播，录制没有开始或被停止。
- 根因：界面加载器保留了旧卡片状态，录制沿用了界面的兜底。
- 正确做法：录制用严格房间接口（REG-COMMON-001），状态未知按网络错误重试；确认未开播和未知平台在开始写入之前停止；“立即录制”不看卡片状态，由严格解析判定。
- 证据：233d858d；`stream_resolver_service.dart:133-157`；`recorder_controller.dart:701-704`；`test/recorder_stream_resolver_test.dart:173,218`。
- 验收：样本＋单元。

### REG-RECORD-006 先重连，后收尾

- 现象：重连被 MP4 合并阻塞 10–20 秒。
- 根因：先合并再重连。
- 正确做法：会话进行中先重连；用户停止或放弃时才收尾（转封装）。
- 证据：db7d0df3；`recorder_controller.dart:457-466`。
- 验收：单元。

### REG-RECORD-007 停止与尾部完整性

- 现象：停止后文件尾部损坏，但转 MP4 仍报成功；尾部只剩 SEI、没有画面。
- 根因：取消同时中断了输出 I/O；stream copy 不解码，发现不了损坏；完整的 tag 不等于完整的访问单元。
- 正确做法：停止时先让输入自然结束；FLV 写入在下一个完整画面处结束（旧预算 3 秒），普通画面和填充尾不需要额外等待；有损坏证据时阻止转封装并保留源文件；转封装失败或取消只删除自己的部分输出，保留源文件。v4 的 FLV 写入器是否还会出现“无画面尾包” [待确认]。
- 证据：263e458a、a65638bd、9a588f4b、1abbff9a、26de4378；`test/video_processor_lifecycle_test.dart:152,299`；`test/ffmpeg_flv_access_unit_stop_test.dart:91`。
- 验收：单元＋样本（Kilakila SEI 尾）。

### REG-RECORD-008 旧录制的 90 毫秒时钟阶跃（仅迁移）

- 现象：分段边界处约 90 毫秒的时钟阶跃。
- 根因：concat 按文件时长累加，而不是按真实起点。
- 正确做法：v4 不再产生 TS 分段；遗留的 clock-v1 分段在首次启动时一次性收尾：用 CSV 记录的起点差加 `inpoint 0`，下一段的起点而不是上一段的终点；缺少时钟清单的旧前缀录制照常可读，不套用 clock-v1；不同尝试的分段不混合。
- 证据：f46ebe56、608c1d5d；`test/recording_segment_clock_test.dart:53`；`test/video_processor_lifecycle_test.dart`；`test/video_processor_manifest_test.dart`；ADR 0005 决定 7。
- 验收：样本（真实遗留分段）＋单元。

### REG-RECORD-009 时长和码率统计

- 现象：时长显示 596523:14:08；码率显示偏低。
- 根因：第一个统计时间是 INT32_MAX 哨兵值；码率用源时间戳做分母。
- 正确做法：时长以墙钟封顶，持久化的时长超过 1 年归零，进度不为负；码率按文件增长的时间窗计算并平滑突发写入，字节数回落时重新开始。
- 证据：e9d11a09、ff0119b0；`ffmpeg_service.dart:29-37`；`test/ffmpeg_progress_time_test.dart:9`；`test/recording_bitrate_window_test.dart:8`。
- 验收：单元。

### REG-RECORD-010 签名地址和 Cookie 不落盘

- 现象：任务持久化泄漏了签名 URL 和 Cookie。
- 根因：`currentUrl` 被写进了任务数据。
- 正确做法：任务只保存画质 id 和线路游标；失败诊断持久化时去掉签名 URL 和凭据；导入的诊断先脱敏，丢弃未知的阶段 id；私有输入不进入持久化任务。
- 证据：cf35dcf9；`test/live_record_task_persistence_test.dart:124`（持久化相关共 18 个用例）；`test/recorder_lease_lifecycle_test.dart:155`。
- 验收：单元（对持久化结果做敏感字段扫描）。

### REG-RECORD-011 文件命名防碰撞与原子提交

- 现象：重试混入旧分片；同一秒开始的两次录制互相覆盖。
- 根因：文件名只精确到秒。
- 正确做法：文件前缀精确到毫秒并防碰撞；输出先写 `.partial`，完成后原子改名；不覆盖已有文件；安全的路径组件（保留名、空名、长度）；房间目录名可移植，不依赖拼音模式。
- 证据：`test/video_processor_lifecycle_test.dart:284`；`test/live_record_task_persistence_test.dart:109`；`test/recorder_storage_policy_test.dart:214`。
- 验收：单元。

### REG-RECORD-012 录制目录管理与活跃保护

- 现象：清理缓存删掉了正在写入的文件。
- 根因：没有活跃保护。
- 正确做法：只管理 `PureLiveRecords` 子目录；用户选择自定义目录时在其下建独立的 `PureLiveRecords` 子目录，已选中该子目录时不重复嵌套；目录先验证可写再提交；活跃目录引用计数保护，清理和容量限制都不动活跃目录；容量统计包括活跃字节，但只删除已完成的录制；开启容量限制或调低上限时立即回收；清理不动录制目录旁边的无关文件；Android 私有路径检测覆盖所有用户。
- 证据：cf35dcf9、f07d1861；`test/recorder_storage_policy_test.dart:37,145`（共 15 个用例）；`test/recorder_settings_persistence_test.dart:179`；`test/translation_contract_test.dart:7`。
- 验收：单元。

### REG-RECORD-013 迟到回调的栅栏

- 现象：旧会话的迟到回调覆盖了新任务的状态。
- 根因：事件没有代次。
- 正确做法：用会话 id 加任务身份做栅栏；同 id 被替换的任务不被旧请求覆盖；已删除的任务即使 id 复用也收不到迟到的输出；关闭后到达的结果丢弃；重复的终止回调共用一次最终快照和收尾；一个任务的采样卡住不阻塞其它任务。
- 证据：`test/recorder_output_lifecycle_test.dart:274`（共 18 个用例）；`test/recorder_poll_lifecycle_test.dart`（共 15 个用例）。
- 验收：单元。

### REG-RECORD-014 用户意图串行化与权限

- 现象：停止、启动、恢复之间出现竞态，任务状态错乱。
- 根因：用户意图没有串行化。
- 正确做法：新的开始等上一次停止完成；重复停止共用一次取消并等同一个完成；删除进行中拒绝新的开始；停止让等待存储权限的开始作废；重复开始共用一次权限请求；权限被拒保留统计，之后可显式重试；取消超时不代表原生录制已排空；关闭时保留保护直到真正排空。
- 证据：e7670220；`test/recorder_user_intent_test.dart:116,166`（共 30 个用例）。
- 验收：单元。

### REG-RECORD-015 开机恢复

- 现象：开机恢复时弹出权限框。
- 根因：开机恢复不是用户手势，却请求了权限。
- 正确做法：普通启动不加载录制和转封装；只有用户开启了“继续录制”且有保存的任务时才恢复（旧版在启动 3 秒后）；恢复只检查存储，不请求权限，没有权限就保持停止；启动时把活跃状态改为停止并收尾残留文件；保留手动停止和已结束的历史，只恢复未完成的任务。
- 证据：723b4452；`test/recorder_user_intent_test.dart:243`；`test/initial_services_policy_test.dart:6`；`test/recorder_poll_lifecycle_test.dart:153`；`live_record_task.dart:324-378`。
- 验收：单元＋真机（杀进程后恢复）。

### REG-RECORD-016 解析游标

- 正确做法：每次只签一条线路（REG-LEASE-006）；游标顺序为同画质的下一条线路 → 下一档画质 → 回绕，单线路时用尽线路 0 才回绕；续签优先原线路；画质按平台给的等级排序，不比较不透明 id；去掉重复的画质 id；失败的 CDN 轮换掉；暂时的画质失败可重试，无效 URL 拒绝；显示实际应用的画质，同时保留请求的重试游标。
- 证据：`stream_resolver_service.dart:190-280`；`test/recorder_stream_resolver_test.dart:8`（共 13 个用例）；`test/owned_record_input_test.dart`；`test/douyu_quality_ack_test.dart`（录制显示实际画质）。
- 验收：单元＋样本。

### REG-RECORD-017 并发调度与轮询

- 正确做法：同时录制数有上限（默认 3），启动之间有间隔（旧值 5 秒）；取消活动任务时，槽位保留到它真正退出；同步和异步失败都释放槽位给下一个；启动时的状态检查最多同时发 3 个，一个慢房间不阻塞后面的；关闭自动检查会取消进行中的自动请求，但显式的单次检查仍可用；轮询退避有上限且可以关闭；超时的请求释放槽位，迟到的响应忽略；停止之后到达的状态响应不改变用户意图。重连期间释放槽位是否会被排队任务抢占 [待确认：真机]。
- 证据：`ffmpeg_scheduler.dart:9,124-150,164-170`；`test/ffmpeg_scheduler_lifecycle_test.dart:74`；`test/recorder_poll_lifecycle_test.dart:237`；`test/recorder_continuation_policy_test.dart`（轮询退避有上限）；04 ③-4。
- 验收：单元。

### REG-RECORD-018 缺口与损坏的证据

- 正确做法：观察到的输入缺口在重试之间保留，只有开始新的录制才清除；丢弃的输入、包损坏、覆盖率警告分别记录，互不混淆；警告有栅栏，并且持久化；不凭空制造开始或失败；界面能显示覆盖率警告和丢弃警告。v4 写入 `gaps.json`。
- 证据：`test/live_record_task_persistence_test.dart:7`；`test/recorder_output_lifecycle_test.dart`（覆盖率警告）；`test/ffmpeg_terminal_evidence_test.dart`；`test/recorder_page_test.dart`。
- 验收：单元。

### REG-RECORD-019 HLS 录制

- 现象：HLS 交给录制器半个分片；停止时丢了最后几个分片。
- 根因：流式转发；停止时播放列表还在滚动。
- 正确做法：录制器自己轮询播放列表，整片下载，按序号去重，序号跳变记为缺口；停止时冻结播放列表，保留已完整发布的分片，追加 ENDLIST；保存为本地 VOD 归档（原始分片＋本地化的 KEY、MAP）；LL-HLS 只录完整的父分片，不下载 part、hint 或其它 rendition，只有 part 或未完成的快照不能算完整录制；DATERANGE 元数据保留（必须有 PDT，不因此去取资源）；旧式 `ALLOW-CACHE:NO` 保持回退路径。Twitch 广告 DATERANGE 是否剔除 [待确认]。
- 证据：6415d42e、29caea0b；`test/hls_low_latency_recording_test.dart:125`；`test/ffmpeg_hls_prefetch_integration_test.dart:136`；`test/hls_daterange_test.dart:17`（共 15 个用例）；`test/hls_retained_window_test.dart`；`test/hls_retained_manifest_test.dart`；ADR 0005 决定 3。
- 验收：单元＋样本（B 站 fMP4 HLS、Twitch、niconico）＋真机（各 HLS 平台完整解码无错误输出）。

### REG-RECORD-020 录制上游的代理与 TLS

- 现象：录制不走应用代理；HLS 子请求证书校验失败。
- 根因：FFmpeg 直连；FFmpeg 不把 `ca_file` 传给子请求。
- 正确做法：录制上游按代理策略走（REG-LEASE-009）；HLS 的所有子请求（KEY、MAP、分片）用与播放相同的 TLS 栈，在 Dart 或 live_net 侧处理，不再注入 CA 文件。
- 证据：17a192f1、e35247d0；`test/recorder_proxy_routing_test.dart:12`。
- 验收：单元＋探针。

### REG-RECORD-021 录制弹幕

- 现象：Windows 上弹幕文件被锁，无法移动或删除。
- 根因：没有等文件关闭完成。
- 正确做法：弹幕随录制保存为 XML，时间相对于录制起点；关闭时等写入完成；关闭弹幕录制时不做任何事；连接失败按延迟重试。旧版时间基取“尝试开始”（在解析之前），早于第一个媒体包，偏差量 [待确认]；v4 应以第一个媒体包为零点。
- 证据：8c5fb87e；`recording_danmaku_service.dart:193`；`test/recording_danmaku_service_test.dart:48`。
- 验收：单元＋真机（Windows）。

### REG-RECORD-022 转封装进度与失败保留源

- 现象：收尾时界面只能显示“处理中”（旧版缺陷）。
- 根因：合并进度事件没有订阅者。
- 正确做法：转封装按输出字节报告进度；文件提交之前进度不到 100%；输入大小和时长未知时显示不确定进度，不假装完成；哨兵值、负数、非有限值不能变成进度；转封装可中断，超时覆盖正在运行的原生调用；失败或取消时保留源文件。
- 证据：DIAGNOSIS 旧版缺陷表；`video_processor_service.dart`；`test/video_processor_progress_test.dart:16`；`test/video_processor_lifecycle_test.dart:299`；ADR 0005 决定 4。
- 验收：单元。

### REG-RECORD-023 任务持久化容错

- 正确做法：任务数据兼容数值漂移，优先用枚举名；枚举缺失或损坏时退回“已停止”和“未知”；用户会话的开始时间跨重试保留，显式重新开始时重置；重新开始的录制有新的时间戳和清零的进度；观众数语义跨更新和持久化保持不变。
- 证据：`test/live_record_task_persistence_test.dart:94`；`test/recorder_continuation_policy_test.dart`（重新开始的录制时间戳和进度）。
- 验收：单元＋迁移样本（旧版 `recorder_tasks` schema 9）。

### REG-RECORD-024 录制期间的权限与平台拒绝

- 正确做法：平台拒绝开始时不入队，用户显式重试可以恢复；原生激活期间停止，永不入队；多个排队任务共享保护直到最后一个停止。
- 证据：`test/recorder_user_intent_test.dart`（平台拒绝、激活期间停止、排队共享保护）；`test/record_action_button_dialog_test.dart`（对话框打开期间新增的任务在开始前重新校验）。
- 验收：单元。

---

## 8 存储与迁移（REG-STORE）

### REG-STORE-001 存储就绪是启动的硬依赖，构造期没有副作用

- 现象：升级后第一次启动界面异常，第二次才正常；冷启动迁移时首帧卡住。
- 根因：设置注册没有等完成，界面先于设置服务构建；在设置服务初始化里注册 IPTV 控制器，依赖注入重入；设置控制器在构造时发网络请求（虎牙 UA）。
- 正确做法：runApp 之前只打开数据库并读取主题、语言等少量键，这一步必须完成；其余服务懒加载；构造期不做 I/O 和网络；注册顺序显式；IPTV 设置只有一个常驻的生命周期所有者，普通设置保持懒加载。
- 证据：842fe3a3、c5072259；`initialized.dart:81-86`；`initial_services.dart:22-27`；`startup_controller.dart:36-50`；`test/settings_service_lifecycle_test.dart:35`。
- 验收：单元＋真机（覆盖安装后首次启动）。

### REG-STORE-002 关注集合的两种旧格式

- 现象：直接复制旧 Hive 文件后关注显示为空。
- 根因：集合格式变过：2.0 及以前是 `List<String>`（每项一个 JSON 字符串），之后是 `{"list":[...]}`。
- 正确做法：两种格式都识别；多个来源按“平台＋房间号”取并集；空字段互相补齐；`tagIds` 取并集；屏蔽列表同样取并集，并容忍损坏的集合值。
- 证据：6d086e2f；`settings_upgrade_migration.dart:22-28,158-210`；`test/settings_upgrade_migration_test.dart:17`。
- 验收：迁移样本（真实旧版数据副本，含 2.0 以前的格式）＋单元。

### REG-STORE-003 房间与分区身份

- 现象：关注里有打不开或重复的房间。
- 根因：房间号为 0、null、undefined、nan、none，或平台大小写不一致；旧版房间身份有 4 种格式。
- 正确做法：房间身份 = 平台（转小写、去空格）＋房间号（去空格、保留大小写）；读入、导入、写入三处统一校验并去重；备份导出丢掉无效身份。分区身份是三元组（平台、命名空间、分区 id），命名空间只有猫耳使用；不同平台的相同分区 id 可以同时关注；缺少命名空间不是通配；无法识别的旧条目保留，但不参与匹配，也不新增；取消关注只删除所选身份的重复副本。房间级偏好的键统一为同一种身份（REG-STORE-026）。
- 证据：c22ae2f4；`favorite_room_controller.dart:162-214`；`live_area.dart:14-50`；`test/favorite_room_validity_test.dart:7`；`test/favorite_area_identity_test.dart:48,84,99,117`；05 ⑦-3。
- 验收：单元＋迁移样本。

### REG-STORE-004 标签映射以“平台:房间号”为准

- 现象：标签串到别的房间，或者丢失。
- 根因：旧映射只用房间号作键。
- 正确做法：映射迁到“平台:房间号”；映射表是权威来源，`LiveRoom.tagIds` 是陈旧副本，不可信；只有房间号的旧映射与已有的平台映射合并，不丢数据；加载时清除空键、重复 id 和孤立 id；删除标签同时删除其房间分配；标签身份冲突时修复并持久化稳定键。
- 证据：4d8ed292；`tag_management_controller.dart:78-121`；`test/room_card_tag_assignment_test.dart:46-83`；`test/tag_management_page_test.dart:465`。
- 验收：迁移样本＋单元。

### REG-STORE-005 启动时直播状态一律未知

- 现象：启动时已下播的房间显示“直播中”，卡片来回跳。
- 根因：持久化了上次的直播状态；多次刷新互相取消。
- 正确做法：启动快照不带直播状态，一律显示未知；校验结果一次性发布（包括成功和失败）；刷新串行执行；刷新合并保留本地标签，不恢复已删除的房间；响应绑定到请求的身份；平台刷新只把请求过且失败的房间标为失败。
- 证据：d6c3d8df；`favorite_controller.dart:652-706`；`test/favorite_startup_policy_test.dart:18,113`。
- 验收：单元。

### REG-STORE-006 写入等待完成，退出前 flush

- 现象：快速修改后或立即退出，关注丢失。
- 根因：写入不等待完成。
- 正确做法：写入等待完成并 flush，失败回滚；退出前 flush（旧版超时 2 秒）。
- 证据：69e5b80b；`favorite_room_controller.dart:404-436`；`plugins/utils.dart:20`。
- 验收：单元＋真机（修改后立即杀进程）。

### REG-STORE-007 导入和恢复：先整体校验，再事务写入

- 现象：恢复失败后设置半新半旧。
- 根因：各控制器逐个写入。
- 正确做法：先校验全部分区，再一次事务写入，失败按快照回滚；禁止并发恢复；后面的分区格式错误不改动前面的设置；空 JSON 或无关 JSON 拒绝，不重置当前设置；保留 null、省略和向前兼容的字段；存储失败报告恢复失败，之后可以重试；只恢复关注时，只改关注列表，保留其它关注偏好。
- 证据：`backup_controller.dart:435-455`；`test/backup_roundtrip_test.dart:128-255`；`test/backup_import_validation_test.dart:45`（共 14 个用例）；`test/backup_collection_validation_test.dart`。
- 验收：单元＋样本（各版本备份文件）。

### REG-STORE-008 平台目录版本表

- 现象：新增的平台老用户看不到；已下线的平台又出现在首页。
- 根因：平台列表按用户自定义顺序保存。
- 正确做法：平台目录有版本号（旧键 `siteCatalogMigration`，当前 38）；v2 一次加入全部平台，v3–v38 每版只追加一个平台；已下线平台保留槽位、永不重新加入，其关注和历史仍可读；隐藏首选平台时自动选第一个可见平台；排序只保存可见平台。
- 证据：1495f56b；`favorite_room_controller.dart:58-120`；18 个 `*_catalog_migration_test`；`test/platform_settings_page_test.dart:185`。
- 验收：迁移样本＋单元（旧的逐版本迁移代码不继承，见 N-06）。

### REG-STORE-009 旧键迁移

- 现象：旧键导致新行为错误。
- 根因：全局 `audioOnly`、布尔型高刷开关已废弃，但仍被读取。
- 正确做法：一次性迁移：全局纯音频默认值作废，旧备份缺该字段时保持关闭；布尔高刷 true 映射为“平衡”，显式的刷新率模式优先；没有刷新率偏好的备份用“省电”；老用户缺键时，多画面和新窗口入口默认开启；已显式关闭的桌面入口保持关闭。
- 证据：`initial_services.dart:67-75`；`app_settings_controller.dart:25-40,57-61,106-112`；`test/app_settings_controller_test.dart:7,29`；`test/player_settings_controller_test.dart:141`。
- 验收：迁移样本＋单元。

### REG-STORE-010 备份与同步默认不含敏感数据

- 现象（潜在）：备份文件或局域网同步泄露 Cookie。
- 正确做法：备份默认不含 Cookie 和 WebDAV 凭据，用户设置口令时才加密导出；局域网同步需要 6 位配对码，并在本机确认，正确的配对码也要本机允许；不开 CORS，同网段的网页读不到响应；局域网同步在 Android 17 上需要本地网络权限（REG-ANDROID-001）。
- 证据：`backup_controller.dart:56-110`；`test/backup_privacy_test.dart:5`；`test/remote_sync_test.dart:64,80,95`；`remote_sync_service.dart:154`；ADR 0004 决定 7。
- 验收：单元。

### REG-STORE-011 历史记录

- 现象：清空历史时误删了刚产生的新记录；升级后“不限”的历史被截断。
- 根因：按身份清空；升级时按默认上限截断。
- 正确做法：历史默认保留最近 50 条，0 表示不限；升级不截断“不限”的历史；清空和删除只移除确认时快照里的对象，保留确认期间新增的观看；刷新不复活已清空的记录，遵守请求期间调低的上限，部分失败保留旧条目；空历史刷新不发请求。
- 证据：db3ef116；`test/history_metadata_test.dart:31`；`test/history_page_test.dart:129`（共 24 个用例）；`test/settings_upgrade_migration_test.dart:74`。
- 验收：单元。

### REG-STORE-012 设置值规范化

- 现象（潜在）：部分设置存的是显示文案（`language='简体中文'`、`preferResolution='原画'`、`themeMode='System'`），换语言后失效；导入越界值导致界面异常。
- 正确做法：显示文案转为枚举；语言转为 locale 代码，并与 easy_localization 保存的 `locale` 对齐（两者冲突时的优先级 [待确认]）；所有持久化值在第一个使用者读取之前修复（主题、字体、分页大小、窗口尺寸、代理端口、计时器、播放偏好、弹幕设置）；导入值钳制到控件范围，非有限值拒绝；导出只输出规范值；运行时的直接写入同样被修复。
- 证据：05 ③；ADR 0004 决定 6；`test/theme_settings_boundary_test.dart:58`；`test/player_settings_controller_test.dart:232`；`test/page_settings_boundary_test.dart`；`test/window_size_settings_boundary_test.dart`；`test/proxy_settings_boundary_test.dart`；`test/deferred_timer_settings_test.dart`；`test/font_settings_page_test.dart`。
- 验收：单元（设置注册表逐键测试）。

### REG-STORE-013 播放器内核设置迁移为 mpv

- 正确做法：旧设置里的 `ijk`、`exo`、`fvp` 一律迁移为 mpv；只属于其它平台的 mpv 选项在导入时归一；未知值用平台默认值；Windows 界面把 mpv 显示为固定内核。
- 证据：05 ⑨；ADR 0006；`test/player_settings_controller_test.dart`；`test/player_kernel_settings_page_test.dart`（仅 Windows）。
- 验收：迁移样本＋单元。

### REG-STORE-014 未支持平台的数据原样保留

- 正确做法：v4 首批只支持 5 个平台，这不能成为删除数据的理由；其余平台的关注和历史原样保留，标为“暂不支持”，并随备份导出。
- 证据：05 ⑨；ADR 0003、0004；`test/favorite_area_identity_test.dart:99`。
- 验收：迁移样本。

### REG-STORE-015 旧数据只读导入

- 现象：Windows 换盘重装后，旧数据被重复导入或丢失（Windows 侧见 REG-WINDOWS-006）。
- 正确做法：在后台 isolate 打开旧文件的副本读取，源文件永不修改；导入版本和来源指纹记录在账本里，同一来源只导入一次；被锁定的文件下次启动重试；迁移前备份到 `MIGRATION_BACKUP/app-v4-<时间戳>`（避开旧版已用的 `settings-v4` 和 `*_v4.lock`）；失败可以重试。
- 证据：`settings_upgrade_migration.dart:30-32,84-86`；`test/settings_upgrade_migration_test.dart:94`；ADR 0004 决定 5。
- 验收：迁移样本＋单元。

### REG-STORE-016 备份格式兼容与 WebDAV

- 正确做法：导入兼容无版本号的扁平格式、v2、v3 和“仅关注”备份；文件名 `purelive_<日期>.txt`、`purelive_favorites_<日期>_<uuid>.txt`，同一秒的两次备份名字不同；“仅关注”用单独的文件名，只含列表。WebDAV：只含集合本身的 PROPFIND 是空目录；HTTP 错误和畸形 XML 不能变成“空目录”；日常请求不开启带凭据的调试输出；密码按原字节保存；重名配置拒绝；服务被替换或目录变化后，已确认的恢复和删除不执行；上传进行中阻止恢复，恢复进行中阻止导出。
- 证据：`backup_controller.dart:33,56-233`；`backup_recovery_service.dart:28,59`；`test/webdav_service_test.dart:81`；`test/webdav_directory_state_test.dart`（共 39 个用例）；`test/webdav_page_test.dart`（共 31 个用例）；`test/backup_roundtrip_test.dart`（“仅关注”备份经真实 WebDAV 往返）。
- 验收：样本（各版本备份）＋单元（本地 WebDAV 服务器）。

### REG-STORE-017 缓存清理只清应用自有缓存

- 正确做法：清理范围只包括应用自有的临时目录（图片缓存、表情缓存等），用户数据一律不删；清理失败时报告剩余字节，不声称已清空；目录解析失败时保留上次测得的大小；重复清理共用一次操作。
- 证据：05 ③（文件目录）；`test/cache_controller_scope_test.dart:39`。
- 验收：单元。

### REG-STORE-018 敏感数据加密存储

- 现象：Cookie、WebDAV 密码、IPTV Xtream 账号密码明文存储。
- 正确做法：迁入系统密钥库（Android Keystore、Windows DPAPI），数据库里只存引用；`taobaoCookie` 在迁移时丢弃；WebView 自带的 Cookie 库不迁移。
- 证据：`cookie_settings_controller.dart:10-43`；`web_dav_controller.dart:15-26`；`tables.dart:11-12`；宪法第 8 条；ADR 0004 决定 3。
- 验收：单元＋迁移样本。

### REG-STORE-019 预览包与签名切换的保底

- 现象（预期）：`.next` 预览包读不到旧沙盒；换签名后需要重装的 Android 8 用户会丢数据；只在 Firestore 上有配置的用户，v4 读不到。
- 正确做法：3.3.x 增加“导出 v4 备份”，并提示只在 Firestore 上有配置的用户导出；v4 首次启动提供从文件、WebDAV、局域网导入的向导；自动迁移只在 v4.0.0 同包名覆盖安装时进行。
- 证据：ADR 0004 决定 8；05 ⑥、⑨；STATUS 旧应用待办。
- 验收：真机（3.3.x 导出 → v4 导入）。

### REG-STORE-020 迁移检查只在需要时运行

- 现象：每次启动都变慢。
- 根因：每次启动都把全部键转成 map、`jsonEncode` 比较两遍、解码关注和历史；Windows 每次启动都枚举注册表。
- 正确做法：迁移完成后写标记，之后的启动不再检查；只有需要迁移时才显示迁移页。
- 证据：`settings_upgrade_migration.dart:45-99`；`app_path_manager.dart:73-83`；05 ④、⑦-5。
- 验收：单元＋真机（冷启动时间）。

### REG-STORE-021 IPTV 数据库原样沿用

- 正确做法：`IPTV_CACHE/pure_live_tv/pure_live_tv.db`（schemaVersion 9，13 张表）原样沿用，继续按版本号升级，不重建；未来版本的数据库拒绝降级并保持原样；历史 schema 依次升级到 9；迁移失败回滚，停在原版本可重试；`playlists/` 目录与数据库一起保留。
- 证据：`database.dart:25-105,631-647`；`test/epg_source_identity_test.dart:561`（schema 迁移相关用例）；ADR 0004 决定 2。
- 验收：迁移样本（各历史 schema 的数据库文件）。

### REG-STORE-022 IPTV 导入的原子性与频道身份

- 正确做法：M3U 部分解析失败、HTTP 失败、写入失败，都保留旧数据库和已保存的播放列表文件，清理自己的临时文件；上千个频道的替换在后期失败时保留全部旧频道；频道身份稳定（TVG id 加流地址），刷新后保留收藏和锁定的 EPG 映射；相同 TVG id 的不同流是不同频道；共享同一流地址的频道不猜 id；同名导入并发时收敛为一个提供方；不删除旧提供方引用的外部源文件。
- 证据：`test/iptv_import_manager_test.dart:628`（共 37 个用例）；`test/epg_import_manager_test.dart`（共 21 个用例）。
- 验收：单元＋样本（真实 M3U、XMLTV）。

### REG-STORE-023 EPG 源隔离与自动映射

- 正确做法：两个 EPG 源里相同的原始 id 互不混用，节目和“正在播放”只取所选源；锁定的映射不被覆盖，也不做模糊重配，缺失时保持未解析；原始 TVG 匹配优先于旧频道 id；有歧义时不按行序决定；空的规范化名字不匹配任何行；选择在读取或写入期间变化时，作废过期的工作并整体回滚。
- 证据：`test/epg_source_identity_test.dart:330`（共 25 个用例）；`test/iptv_auto_mapping_test.dart`（共 23 个用例）。
- 验收：单元。

### REG-STORE-024 M3U 解析边界

- 正确做法：引号内的逗号不作为显示名分隔；显示名保留分隔符之后的全部逗号；像属性的显示文本不覆盖真实元数据；`EXTGRP` 开始持久分组，空指令清除；BOM、空白前缀、各种换行都能解析；畸形属性报错，不凭空造频道；缺 URL 的条目报告截断；条目级 HTTP 指令和 URL 选项变成请求头，不混进媒体 URL；`EXTHTTP` 格式错误让整个快照无效；回看元数据和旧的 `timeshift`、`tvg-rec` 参数保留。
- 证据：`test/m3u_parser_test.dart:253`（共 37 个用例）。
- 验收：单元（旧用例直接转样本）。

### REG-STORE-025 IPTV 回看地址

- 正确做法：节目时间区间左闭右开，节目表与点击共用；支持 playseek、offset、append、shift、Flussonic、Xtream Codes 等模式和提供方模板；未来的开始时间钳制到 0；显式禁用、未知或畸形的模式不发请求；回看播放在启动完成之前保持加载，旧的请求不能覆盖新的；“回到直播”清除整个回看区间，再打开原地址。
- 证据：`test/iptv_programme_policy_test.dart:9`（共 14 个用例）；`test/iptv_playback_transaction_test.dart`；`test/video_source_commit_listener_test.dart`（回看与回到直播）。IPTV 的完整规格由 `spec/modules/iptv.md` 负责 [待确认：归属]。
- 验收：单元。

### REG-STORE-026 字体文件与房间级偏好

- 正确做法：字体管理与下载共用一个字体目录；备份迁移时分别保留界面字体和弹幕字体文件；已删除的自定义字体 id 不保留；Windows 保留优化过的中日韩回退字体。房间级偏好（房间音量 `room_vol_{平台}_{房间号}`、竖屏覆盖 `平台:房间号`）迁移为统一的房间身份；非有限的音量值拒绝，导入值钳制到支持范围。
- 证据：`live_room_volume_manager.dart:9`；`player_settings_controller.dart:71,173`；`test/font_storage_path_test.dart:7`；`test/theme_font_resolution_test.dart`；`test/room_volume_dialog_test.dart:42`；`test/backup_import_validation_test.dart`（音量规范化）。
- 验收：迁移样本＋单元。

---

## 9 网络与代理（REG-NET）

Android 17 本地网络权限见 REG-ANDROID-001，Windows 系统代理见 REG-WINDOWS-003。

### REG-NET-001 取消只作用于自己的请求

- 现象：取消一个请求，影响了别的请求。
- 根因：取消时关闭了共享的客户端。
- 正确做法：取消只作用于自己的请求；同一令牌下一个兄弟请求失败，不停止其它进行中的请求；调用方取消要传到卡住的上游连接；已取消的调用方不发请求；连接超时取消自己的 TLS 连接，不关闭会话；替换时只取消前一次的取流，销毁时等两者都清理完。
- 证据：a482e576；`live_quality_discovery.dart:9-11`；`test/platform_response_lifecycle_test.dart:192,214`；`test/cancellable_http_connections_test.dart:176`；`test/quality_discovery_cancellation_test.dart:107`；`test/search_request_cancellation_test.dart`。
- 验收：单元（本地服务器）。

### REG-NET-002 响应体上限与截止时间

- 正确做法：响应体超过字节上限时关闭上游，并保留调用方的令牌；HTTP 错误关闭上游，而不只是结束转换流；持续的小块传输受总截止时间约束，并关闭所有上游；跨块的 UTF-8 正确拼接，非法 UTF-8 拒绝；大 JSON 在后台 isolate 解析。
- 证据：`test/platform_response_lifecycle_test.dart:158,354`（共 18 个用例）；PLAN §10。
- 验收：单元。

### REG-NET-003 代理设置：两个代理、输入归一、注入防护

- 现象：中文输入法把 `127.0.0.1` 打成 `127。0。0。1`，所有请求静默失败；端口编辑到一半时代理失效。
- 根因：`HttpClient.findProxy` 把整个字符串当成域名解析；自动保存把半截的端口写了进去。
- 正确做法：有两个代理，各自独立开关：应用代理用于接口请求、弹幕 WebSocket、图片缓存和录制上游；播放器代理只用于播放的媒体传输（内核和播放中继的上游）。主机名归一中文标点（`。`、`．`、`：`、全角括号）并去空白；只接受 1–65535 的完整端口，编辑到一半的值不替换最后一个有效值；持久化值在任何代理使用者之前修复（默认端口 7897）；主机含 `;`、回车、换行时一律直连，防止注入代理指令；导出不泄漏未校验的直接写入。
- 证据：`proxy_routing.dart:1-57`；`proxy_settings_controller.dart`；`playback_proxy_policy.dart`；`initialized.dart:94-108`；`test/proxy_routing_test.dart:6,37`；`test/network_proxy_settings_page_test.dart:72`；`test/proxy_settings_boundary_test.dart`；`test/player_kernel_settings_page_test.dart`（播放器代理编辑保留最后有效端口）。
- 验收：单元。

### REG-NET-004 TLS 指纹被拒

- 现象：Kick 的全部接口 403；Twitch 在 Android 上走代理时连接被重置。
- 根因：Cloudflare 按 TLS 指纹拦截 `dart:io`（curl 与手机 curl 均为 200）；`dart:io` 的 TLS 在代理 CONNECT 之后被重置。
- 正确做法：网络层提供平台原生 TLS 通道：Android 用系统栈（Cronet 内嵌版或 HttpURLConnection），Windows 用 WinHTTP/Schannel；按平台和域名启用，其它请求不受影响；原生通道失败时退到浏览器完整性校验（Twitch）。Linux 没有可用的原生通道（REG-LINUX-003）。Kick 已在 3.2.11 下线；Twitch 属第二批平台。
- 证据：aeb8651b、f1511974、76a59f31、8435e9e2；`docs/PLATFORM_PROBE_2026_09_25.md:45`；`docs/PLATFORM_COMPATIBILITY.md:6`；`twitch_site.dart:122-126`；`test/android_native_http_test.dart`（只测响应解码）。没有覆盖真实指纹的测试，见 G-03。
- 验收：探针（每晚在 Android、Windows 上跑）＋真机。

### REG-NET-005 代理出口 IP 轮换导致签名失效

- 现象：FC2、NimoTV、VK 间歇性 403，重试又可能成功。
- 根因：Clash 负载均衡组的出口 IP 在多个地址间轮换；分片签名与请求 IP 绑定。
- 正确做法：检测到签名链接与出口 IP 绑定时（同一链接先成功后 403），提示用户把代理固定到单个节点；探针和测试时把 Clash 固定到单节点，结果中记录出口；这类 403 不能被当成平台接口变更。
- 证据：`docs/PLATFORM_PROBE_2026_09_25.md:89-97`；PLAN §12（网络与代理）。
- 验收：探针（固定节点与轮换节点两种配置）。见 G-16。

### REG-NET-006 请求头与 Cookie 卫生

- 现象（潜在）：粘贴的 Cookie 带 `Cookie:` 前缀或换行，导致请求头注入或请求失败。
- 正确做法：Cookie 去掉 `Cookie:` 前缀、首尾空白和控制字符后保存；所有平台的 Cookie 编辑都用同一套规范化；请求头名规范化，值里不允许控制字符，带换行的请求头在发出前丢弃或拒绝；UA 只出现一次。
- 证据：`test/account_cookie_editor_test.dart:58`；`test/douyu_cookie_session_test.dart`（去掉粘贴的前缀和控制字符）；`test/ffmpeg_record_command_test.dart:119`；`test/fvp_adapter_test.dart:14`；`test/playback_source_transport_test.dart:213`；`test/history_metadata_test.dart`（IPTV 请求头规范化）。
- 验收：单元。

### REG-NET-007 外部 URL 校验

- 正确做法：接受完整的公网、长顶级域名、回环和 IPv6 地址；拒绝嵌在文本中的地址、缺少协议的地址、不支持的协议和带凭据的地址；网页搜索的启动参数只接受一个规范化的 HTTP(S) 地址；下载入口和 IPTV 网络导入使用同一套规则。
- 证据：`test/file_utils_url_test.dart:23`；`test/update_source_test.dart:31`；`test/web_search_lifecycle_test.dart:42`；`test/iptv_settings_page_test.dart`（长顶级域名与嵌入子串）；`test/live_dlna_dialog_test.dart:21`。
- 验收：单元。

### REG-NET-008 图片地址

- 正确做法：协议相对的图片地址补成 HTTPS；绝对地址原样保留；空白和畸形值拒绝；B 站图片请求带限定范围的 Referer，同时保留浏览器 UA；封面按显示尺寸解码。
- 证据：`test/network_image_url_test.dart:6`；PLAN §10。
- 验收：单元。

### REG-NET-009 WebView 代理

- 正确做法：WebView2（Windows）跟随系统代理，不改动；Android WebView 的代理规则需要主机和有效端口；不同解析器的 WebView 工作不重叠；失败的解析器释放队列。
- 证据：`webview_proxy_scope.dart:12`；`test/webview_proxy_scope_test.dart:15`。
- 验收：单元。

### REG-NET-010 本机与局域网服务的安全默认值

- 正确做法：日志浏览服务只绑定回环地址；响应禁止缓存、禁止被嵌入框架、禁止跨源复用；日志文本转义；清空日志必须是显式的同源操作；运行时的日志服务地址不从旧存储里恢复；局域网同步见 REG-STORE-010。
- 证据：`test/log_controller_transaction_test.dart:126`；`test/log_browser_page_test.dart:35`。
- 验收：单元。

---

## 10 平台特定

### 10.1 Android（REG-ANDROID）

#### REG-ANDROID-001 Android 17 本地网络权限

- 现象：3.2.7 起，在 Android 17 上配置了局域网代理（电脑上的 Clash、软路由）后，所有经代理的请求全部失败。
- 根因：targetSdk 37 起，连接局域网地址需要 `ACCESS_LOCAL_NETWORK`。
- 正确做法：Manifest 声明该权限；启用的代理主机是局域网地址（10/8、172.16/12、192.168/16、169.254/16、`.local`、`.lan`、`.home.arpa`、IPv6 fc00::/7、fe80::/10，先归一中文标点）时，在用户停止输入后请求一次（每个会话一次）；回环、公网、畸形地址不请求；局域网同步开始前同样检查；拒绝时提示，不静默失败；权限查询本身出错时不阻塞请求。
- 证据：`AndroidManifest.xml:21`；`proxy_routing.dart:57-80`；`local_network_access.dart`；`proxy_settings_controller.dart:37-56`；`remote_sync_service.dart:154`；`test/local_network_proxy_host_test.dart:5`（只测主机分类）；08 ①（3.2.7 回归的教训）。
- 验收：单元（主机分类）＋真机（Android 17 设备：授予、拒绝、未决定三种）。权限流程没有测试，见 G-01。

#### REG-ANDROID-002 首帧黑屏与 Surface 管理

- 现象：Android 首帧黑屏；从其它页面返回后黑屏。
- 根因：替换视频子树时和 Surface 回调竞态。
- 正确做法：视频被遮挡时用 Offstage 保持挂载，不卸载；Surface 只由补丁后的控制器管理（当前 Surface 与引用的 Surface 不同才替换，释放时先解除回调）；Surface 延迟挂接前后都保持视频模式；纯音频模式在生命周期变化后保持。
- 证据：403772f1、1e609cb0；`video_player.dart:69-104,166-234`；`test/stable_video_layer_test.dart:6`；`test/android_surface_contract_test.dart`（源码断言）；`test/player_audio_mode_transition_test.dart:413`。
- 验收：真机（K90：进出房间、覆盖页面、切后台各 20 次）＋组件测试。

#### REG-ANDROID-003 画中画

- 现象：进入画中画时闪出应用图标或黑块；连续点击进入两次；房间已关闭，画中画又被打开。
- 根因：系统在画中画动画开始时截图；状态查询和进入请求没有归属。
- 正确做法：先渲染一帧只含视频的紧凑画面，再进入画中画；重复点击合并；跟随系统的恢复；状态查询期间关闭房间则不进入；迟到的进入结果不复活已关闭的房间；状态事件优先于较早的进入结果；重新进入房间只重启一个画中画观察者，空闲释放时释放观察者；画中画比例钳制到 Android 允许范围；状态观察出错后保持状态并在重置后重启。
- 证据：`player_manager.dart:2836-2841`；`test/player_audio_mode_transition_test.dart:92,137,179,199`；`test/floating_status_lifecycle_test.dart:8`；`test/portrait_stream_support_test.dart:371`；07 ⑤（floating 本地补丁：100 毫秒状态探测、几何更新、单一观察者）；`docs/ANDROID_PIP_RETURN_FAILURE_2026_09_05.md`。紧凑帧的视觉效果没有测试，见 G-10。
- 验收：单元＋真机。

#### REG-ANDROID-004 返回手势

- 现象：返回键层级错乱（REG-ROOM-005）。
- 根因：原生返回回调注册晚。
- 正确做法：支持预测性返回：路由稳定后，手势提交时返回，取消时保持当前路由；转场动画不使用手势自带的构建器；全屏状态下的返回先退出全屏（旧版在原生层以 PRIORITY_OVERLAY 优先级抢先处理，另有 `onBackPressed` 兜底）。v4 改用 Flutter 自带机制是否够用 [待确认]。
- 证据：c00b2069、81433454；`MainActivity.kt`（`pure_live/predictive_back`）；`test/get_native_predictive_back_test.dart:92`；08 ①。
- 验收：真机（Android 13+ 预测性返回）。

#### REG-ANDROID-005 音量键路由到媒体音量

- 正确做法：应用在前台可见时，硬件音量键始终调节媒体音量，每次回到前台都重新绑定。
- 证据：`MainActivity.kt`（onResume 中 `setVolumeControlStream(AudioManager.STREAM_MUSIC)`）；`test/android_volume_key_routing_test.dart:6`（源码断言）。
- 验收：真机。

#### REG-ANDROID-006 后台播放保活

- 正确做法：后台播放期间持有 Wake 锁和 Wifi 锁，停止后释放；通知栏、锁屏控制和耳机线控由媒体服务提供（REG-PLAY-024、REG-PLAY-025）。
- 证据：`MainActivity.kt:145,233-256`（`pure_live/background_playback`）；02 1.6。
- 验收：真机（锁屏播放 30 分钟）。

#### REG-ANDROID-007 录制前台服务

- 现象：锁屏或关闭界面后录制中断。
- 根因：Flutter 引擎随 Activity 一起销毁。
- 正确做法：录制使用独立的前台服务，通过绑定媒体服务保住引擎，并持有 CPU 锁和 Wifi 锁；多个任务共享一个服务，最后一个释放时才停止；启动和停止各有 15 秒超时；启动失败回滚，只有用户显式重试才重启；被系统中断后只允许用户手动重试，不自动重启服务；系统触发超时后留 45 秒排空，有界收尾并标记失败。Android 15 起 dataSync 类型 24 小时内限 6 小时，长时间录制是否改用其它服务类型 [待确认]。
- 证据：9a512919、f4d40174；`RecorderBackgroundPlugin.kt:291-300,419`；`RecorderForegroundService.kt:188-197`；`recorder_controller.dart:1038-1057`；`test/recorder_background_service_test.dart:7,43,66`（只测 Dart 侧）；ADR 0005 决定 5。
- 验收：单元（Dart 侧状态机）＋真机（锁屏录制 60 分钟；Android 15 上超过 6 小时）。见 G-15。

#### REG-ANDROID-008 分享接收与冷启动

- 现象：冷启动时分享进来的链接无效；Android 停在原生启动页。
- 根因：导航器还没挂载就尝试打开；字体初始化在首帧前访问了上下文。
- 正确做法：接收器在等待冷启动数据之前就订阅，消费后重置；等导航器就绪、启动页结束后再打开；首帧之前不访问上下文。分享内容中房间口令优先于文件附件，并且只处理一次；附件按路径去重，按扩展名路由（播放列表、EPG）；不支持和空的分享各给一次提示；一个导入失败不影响后面的分享；只清理自己暂存的临时文件，保留无关文件；分享声明只针对支持的内容类型。
- 证据：1836953e；`main.dart:105-131`；`font_settings_controller.dart:143-151`；`test/shared_media_intake_test.dart:11,156,273`（共 13 个用例）；`test/shared_media_temp_cleanup_test.dart:40`；07 ⑤（share_handler_android 补丁：先复制内容、保留文件名、清理暂存目录）。
- 验收：单元＋真机（冷启动分享链接、分享 m3u 文件）。

#### REG-ANDROID-009 显示刷新率

- 正确做法：“性能”模式在前台保持高刷，进入后台释放；“平衡”模式只在交互期间提高刷新率；“省电”模式忽略交互；新安装默认省电；显示器变化时回推当前模式；开机和切换刷新率设置都要等原生确认，失败回滚。
- 证据：`MainActivity.kt`（`pure_live/display_mode`）；`test/adaptive_refresh_rate_scope_test.dart:10`；`test/display_mode_service_test.dart`；`test/general_settings_refresh_rate_dialog_layout_test.dart`。
- 验收：单元＋真机（120 Hz 设备）。

#### REG-ANDROID-010 缺少画面进度信号

- 现象：Android 上黑屏只能从缓冲或暂停间接发现；画面停滞看门狗和候选首帧栅栏在 Android 上都用不了。
- 根因：帧进度（`frameRevision`）只在 Windows 的 media_kit_video 补丁里实现。
- 正确做法：在 Android 补丁里补上帧进度信号，让看门狗（REG-PLAY-012、REG-MULTI-010）和首帧栅栏（REG-PLAY-006）在两个主力平台都生效 [待确认：可行性]。
- 证据：02 ③-3、⑥；`third_party/media_kit_video`（Windows `frameRevision`）。
- 验收：真机（Android 断流黑屏自动恢复）。见 G-07。

#### REG-ANDROID-011 旧版数据路径 [待确认]

- 现状：2026-05-13 之前的数据在 `<应用文档目录>/pure_live/app_settings.hive`（2a68e00d）。目前只有 Windows 会查找旧路径，Android 不查。
- 正确做法：查清是否有正式版用过这个路径；用过则 v4 的迁移也查找它（只读导入，REG-STORE-015）。
- 证据：05 ③（Android 旧路径）。
- 验收：迁移样本。

#### REG-ANDROID-012 TV 方向键

- 现象：Manifest 声明了 Leanback 启动器，但没有焦点模型；遥控器的上下键被音量快捷键占用。
- 正确做法：TV 模式下方向键不绑定音量；所有操作都能用方向键完成（PLAN §07）。
- 证据：`AndroidManifest.xml:63,132`；03 ①.2、⑥。
- 验收：真机（TV 盒子）。见 G-20。

#### REG-ANDROID-013 VIEW 链接未处理（旧版缺陷）

- 现象：`purelive://`、`mystyle://` 链接点开后什么都不发生。
- 根因：Manifest 声明了 VIEW 过滤器，Dart 侧没有处理代码。
- 正确做法：v4 统一由路由处理：分享口令、分享链接、`--open-room` 和 `purelive://` 走同一个重定向入口，打开对应直播间。
- 证据：`AndroidManifest.xml:66-76`；DIAGNOSIS 旧版缺陷表；05 ⑤。
- 验收：单元（路由）＋真机（adb 发送 VIEW intent）。见 G-18。

### 10.2 Windows（REG-WINDOWS）

#### REG-WINDOWS-001 退出或多格长播时进程中止

- 现象：Windows 退出时，或多格长时间播放后，进程以 0xc0000409 中止。
- 根因：mpv 核心先于渲染上下文被释放。
- 正确做法：释放顺序固定为：停止回调 → 排空任务 → 注销纹理 → 同步释放渲染上下文 → 释放 D3D；Dispose 等原生完成后才返回；退出时直接结束进程，避免插件 DLL 卸载卡住（`main.cpp` 中的 TerminateProcess）。
- 证据：6973c57f、21a0c1ec；`docs/WINDOWS_MULTIVIEW_NATIVE_ABORT_2026_09_24.md`；07 ⑤（media_kit_video 退出释放顺序补丁）。
- 验收：真机（4 格播放 60 分钟后退出，连续 20 次无中止）。见 G-08。

#### REG-WINDOWS-002 被遮挡时拆掉纹理

- 现象：被其它页面覆盖后视频黑屏或崩溃；被遮挡时误判为画面停滞。
- 根因：纹理和合成器竞态；被遮挡时本来就不出帧。
- 正确做法：Windows 上被遮挡时卸载 Texture，并暂停帧看门狗；等覆盖页完全返回后再挂载，重新挂载时强制重设输出尺寸；故意隐藏的画面不重开传输。（Android 做法相反，见 REG-ANDROID-002。）
- 证据：1e609cb0；`video_player.dart:37-42,166-234`；PM 2465-2488；`test/stable_video_layer_test.dart:37`；`test/player_error_recovery_test.dart:1582`（仅 Windows）。
- 验收：真机＋组件测试。

#### REG-WINDOWS-003 系统代理

- 现象：Windows 上 `dart:io` 不跟随系统代理，用户必须在应用里单独填代理；而 WebView2 跟随系统代理，应用内行为不一致。
- 根因：`dart:io` 的 HttpClient 不读 WinINet 设置。
- 正确做法：v4 自动跟随系统代理（WinINet / WinHTTP 设置），应用内代理设置优先；系统代理变化时更新。PLAN 计划的 native_dio_adapter 只覆盖 Android 和 Apple，Windows 需要单独方案 [待确认：方案]。
- 证据：PLAN §02、§11；02 ③-6；07 ①-3；08 ②（缺口）；`webview_proxy_scope.dart:12`。
- 验收：真机（开启系统代理、关闭系统代理、PAC 三种）。见 G-02。

#### REG-WINDOWS-004 画中画（窗口缩小实现）

- 正确做法：画中画把主窗口缩成可拖动的小窗，双击退出；进入和退出串行执行，重复请求合并；只有宿主窗口切换成功才提交模式；退出时宿主恢复失败，保持画中画模式和位置，可以重试；关闭或销毁进行中的画中画会话时恢复主窗口，恰好一次；房间关闭后才完成的进入也要恢复普通窗口；画中画快照保留宽屏状态，全屏优先于宽屏；保存的位置在原显示器上恢复，屏幕外的位置钳制到主显示器工作区；退出后恢复应用的最小窗口尺寸；置顶更新在排队的退出之前完成；普通窗口只保存可恢复的尺寸。
- 证据：`fullscreen.dart:106-240`；`window_helper.dart`；`test/windows_pip_host_transaction_test.dart:41,124`（共 13 个用例）；`test/windows_pip_geometry_test.dart:7,23`；`test/windows_pip_presentation_test.dart:29`；`test/player_audio_mode_transition_test.dart:327`；`test/video_settings_resolution_dialog_test.dart`（置顶，仅 Windows）。
- 验收：单元＋真机（多显示器）。

#### REG-WINDOWS-005 单实例与多窗口

- 现象：深色模式下“新窗口打开”后是空配置。
- 根因：每个窗口实例使用独立的数据目录。
- 正确做法：无参数启动时，在创建引擎之前用互斥体拦下重复启动，并把已有窗口置前；设置 AUMID；新窗口通过临时文件交接设置，只接受启动器自己写入的文件，导入后删除；实例 id 规范化，畸形的房间参数忽略；房间参数不带平台原始响应，携带规范的离线状态；窗口标题与查找窗口用的标题一致。v4 建议改为命名管道转发参数。
- 证据：ef5f05c0；`main.cpp`；`windows_multi_instance_launcher.dart:19-66`；`test/windows_multi_instance_launcher_test.dart:34,51`；`test/windows_runner_title_test.dart`；08 ②。
- 验收：单元＋真机。

#### REG-WINDOWS-006 数据跟随安装目录

- 现象：Windows 换盘重装后数据“丢失”。
- 根因：数据在安装目录下，注册表只记录最新位置。
- 正确做法：数据根目录为 `{exe}\AppData`，只读时回退；带 `--instance` 时再分子目录；查找旧数据时，注册表、同级目录和搬迁账本 `previous_install_locations.txt` 一起查，先备份，源目录只读不改；识别 WindowsApps 包内的可执行文件，不把它当便携路径；查找只在首次做（加完成标记，REG-STORE-020）；安装包的 AppId（`C76CD88E…`）永远不改。
- 证据：`app_path_manager.dart:47-93,108-293`；`test/app_path_manager_test.dart:6`；`test/settings_upgrade_migration_test.dart:94`；`windows/packaging/exe/local_release.iss`；08 ②、⑥。
- 验收：真机（C 盘装 → D 盘重装）＋单元。

#### REG-WINDOWS-007 开机自启

- 现象：Windows 首次启动就注册了开机自启（旧版缺陷，是否有意 [待确认]）。
- 根因：`enableStartUp` 默认值是 true。
- 正确做法：v4 默认关闭；注册表命令必须指向当前可执行文件；只有原生确认后才提交开关状态，失败或无法确认时回滚到实际状态；启动时修复缺失的原生条目；多个请求时最后一个生效，但各调用方报告自己请求的目标。
- 证据：`startup_controller.dart:25`；DIAGNOSIS 旧版缺陷表；`test/windows_auto_start_command_test.dart:5`；`test/startup_controller_transaction_test.dart:68`。
- 验收：单元＋真机。

#### REG-WINDOWS-008 退出流程与托盘

- 正确做法：关闭窗口按用户选择退出或最小化到托盘；原生退出失败时恢复关闭拦截并让窗口保持可见；并发的关闭请求共用一个决定；关闭拦截关闭时，“记住最小化”走原生最小化；托盘菜单只有一个事件所有者，并发请求共用刷新，失败后可以重试；退出前 flush 数据（REG-STORE-006）；托盘在首帧之后再初始化。
- 证据：`plugins/utils.dart:20-75`；`test/utils_exit_dialog_test.dart:141,172`；`test/desktop_tray_menu_transaction_test.dart:8`；05 ④。
- 验收：单元＋真机。

#### REG-WINDOWS-009 全屏过渡

- 正确做法：Windows 进入全屏前先清除无边框保护；其它桌面平台不做这一步。
- 证据：`test/windows_fullscreen_transition_test.dart:5`。
- 验收：真机。

#### REG-WINDOWS-010 显示器刷新率

- 正确做法：枚举当前显示器支持的刷新率，在窗口移动、显示设置变化、DPI 变化时回推；窗口析构时有保护，防止子窗口回调导致崩溃。
- 证据：`flutter_window.cpp`（`pure_live/display_mode`）；`test/display_mode_service_test.dart:28`；08 ②。
- 验收：真机（多显示器、不同刷新率）。

#### REG-WINDOWS-011 鼠标滚轮

- 正确做法：滚轮滚动与鼠标拖动分开处理；Windows 上滚轮使用平滑滚动；横向标签栏上第一次滚轮就滚动标签，而不是后面的页面；侧边导航用滚轮能到达最后一项；显式受控的列表不挂到路由的滚动控制器上。
- 证据：`test/desktop_scroll_behavior_test.dart:9`；`test/scrollable_tab_bar_test.dart:7`；`test/home_tablet_view_test.dart`；`test/pure_live_route_scroll_scope_test.dart`。
- 验收：组件测试＋真机。

#### REG-WINDOWS-012 WebView2 缺失

- 正确做法：检测不到 WebView2 运行时时给出可操作的提示；提示单次打开，关闭后可以再次打开；搜索页关闭后丢弃挂起的下载动作；页面关闭后，迟到的检测结果不弹对话框。
- 证据：`test/search_webview2_missing_dialog_test.dart:78`；`test/search_lifecycle_test.dart`（仅 Windows）。
- 验收：组件测试＋真机（无 WebView2 的系统）。

#### REG-WINDOWS-013 录制中退出

- 现象：Windows 退出时不排空录制，依赖下次启动的恢复合并。
- 根因：退出时直接销毁窗口。
- 正确做法：退出前提示正在录制；用户确认后关闭文件即可（FLV 没有尾部结构）。
- 证据：`plugins/utils.dart:20-75`；`recorder_controller.dart:1569`；ADR 0005 决定 5。
- 验收：真机。

### 10.3 Linux（REG-LINUX）

#### REG-LINUX-001 libmpv 系统库优先，自带库兜底

- 现象：部分发行版上缺少 VA-API 等依赖库，libmpv 加载失败。
- 正确做法：系统库存在时优先使用，只有缺失的才从包内加载；兜底列表与 CMake 安装列表一致。
- 证据：`linux_mpv_runtime.dart`；`test/linux_mpv_runtime_test.dart:7,26`；PLAN §02；STATUS 已完成的前置工作。
- 验收：单元＋真机（最小化安装的发行版）。

#### REG-LINUX-002 应用 ID 与数据目录 [待确认]

- 现状：`APPLICATION_ID` 仍是 `com.example.pure_live`，窗口标题是 `pure_live`。修改 ID 会改变数据目录。
- 正确做法：修正 ID 时同时迁移数据目录（只读导入，REG-STORE-015）。
- 证据：`linux/CMakeLists.txt`；`my_application.cc`；08 ②。
- 验收：迁移样本。

#### REG-LINUX-003 没有平台 TLS 通道 [待确认]

- 现状：按 TLS 指纹拦截的站点（Kick）在 Linux 上没有原生通道可绕，仍然受阻。
- 正确做法：v4 在 Linux 上的方案待定；在方案确定前，受影响的平台在 Linux 上明确显示“当前平台不可用”，不能无限重试。
- 证据：`docs/PLATFORM_PROBE_2026_09_25.md:45`；`docs/PLATFORM_COMPATIBILITY.md:6`。
- 验收：探针（Linux）。

---

## 11 构建与发布（REG-BUILD）

### REG-BUILD-001 签名与覆盖安装

- 现象：v3.1.1–v3.2.11 全部正式版用本机 debug 证书（`1e832295…`）签名；v2.7–v3.0.23 用 `c0bb9574…`；两批用户需要都能覆盖安装。
- 根因：缺少 `key.properties` 时，release 构建只打一条警告，悄悄改用 debug 证书。
- 正确做法：构建在缺少密钥时直接失败，不回退到 debug 证书；先把 debug keystore 备份进 Secrets（它已成为必需资产）；确认 `c0bb` 的原始 keystore 是否还在 [待确认]；用 APK 签名 v3 轮换谱系（1e83 → 正式密钥）；minSdk 26 下 Android 8 只校验 v2，需要旧密钥签 v1/v2、新密钥签 v3 [待确认：实测]。
- 证据：`build.gradle.kts:73-78`；`assets/releases.json`；`README.md:407`；08 ①（签名）；宪法（换正式密钥、v3 轮换）。
- 验收：真机（Android 8、9–12、13+ 三档覆盖安装）＋门禁（缺少密钥时构建失败）。见 G-14。

### REG-BUILD-002 发布工作流的签名与 Secret

- 现象：`feature-build.yml` 用 `c0bb` 签名，产物无法覆盖安装在现有用户手机上；`build_pure_live_release.yml` 引用的 `KEYSTORE_BASE64`、`CERTIFICATE` 不存在，发布必然失败。
- 正确做法：第 3 阶段重写 CI 时删除旧工作流；release 工作流只有一个签名来源，签名证书指纹在发布前校验。
- 证据：DIAGNOSIS 旧版缺陷表；`sign-staged-android.yml:41`；08 ④。
- 验收：门禁（发布流水线核对证书指纹）。

### REG-BUILD-003 APK 门禁

- 正确做法：APK 只含目标 ABI；关键原生库齐全；通过 `zipalign -P 16`；ELF 的 LOAD 段对齐 ≥ 0x4000（16 KB 页）；核对 split-per-abi 带来的 versionCode 偏移；发布 armeabi-v7a 包（很多 TV 盒子是 32 位）。
- 证据：`BUILD_POLICY.md` §1.1、§4；`tool/verify_android_apk.ps1`；`tool/verify_android_elf_alignment.ps1`；08 ⑥。
- 验收：门禁（release.yml）。

### REG-BUILD-004 许可证合规

- 正确做法：发行物不含专有组件（fvp 的 libmdk、Syncfusion、ML Kit、GMS）、GPL-2.0-only 代码（fuzzywuzzy）或许可证不明的代码（pinyindart）；FFmpeg 以 `--disable-gpl --enable-version3 --disable-nonfree` 构建，绝不使用 `--enable-nonfree`；每个发布附原生库的对应源码（FFmpeg、mpv、libplacebo、dav1d、mbedtls 的确切提交、configure 参数和补丁）；应用内自动生成开源许可页。
- 证据：ADR 0006；07 ④；宪法第 11 条。
- 验收：门禁（许可证检查、原生库字符串检查、Release 资产清单）。

### REG-BUILD-005 应用内更新

- 现象：下载的安装包没有哈希校验（旧版缺陷）。
- 正确做法：更新信息与发布资产来自同一个仓库；镜像列表有序、去重，GitHub 直连排第一；并发探测镜像时用 Range 请求，返回第一个健康的，全部失败时返回空而不是挂起；下载链接只来自实际发布的资产，Android 只给更新源声明的 APK 变体，一个平台的更新不宣告其它平台未发布的产物；版本比较能处理前缀、构建元数据和畸形值；下载文件名限定在受管目录内，长 Unicode 名截断时保持完整字符；先写暂存文件，完成后原子提交，取消或传输失败删除暂存文件；打开失败保留文件并提供重试；只有 APK 才请求安装权限；桌面上下载完成不结束正在运行的进程；v4 校验 `SHA256SUMS`。
- 证据：DIAGNOSIS 旧版缺陷表；`version_util.dart:33-39`；`test/github_mirror_test.dart:5`；`test/race_http_test.dart:34`；`test/release_asset_urls_test.dart:85,108`；`test/version_controller_state_test.dart:55,100`；`test/download_apk_dialog_test.dart:38,283,381`；`test/update_source_test.dart:46`。
- 验收：单元＋门禁（发布后重新下载核对哈希）。见 G-19。

### REG-BUILD-006 Windows 安装包

- 正确做法：只保留 `local_release.iss`，CI 直接调用 ISCC；普通用户权限安装；沿用旧安装目录，写搬迁账本；AppId 不变；随包附带 msvcp140、vcruntime140、vcruntime140_1，缺一个就构建失败；同时提供便携包。
- 证据：`windows/packaging/exe/local_release.iss`；`windows/CMakeLists.txt`；08 ②、⑥。
- 验收：门禁＋真机（覆盖安装、换目录安装）。

### REG-BUILD-007 CI 必须覆盖 Windows 分支

- 现象：12 个文件共 66 个 Windows 专属用例在 CI 上从未运行；`version_page_layout_test` 在非 Windows 上直接返回（假通过）；`media_kit_video_geometry_test` 的期望值随宿主系统变化。
- 根因：业务代码直接读 `Platform.isWindows`；CI 只在 ubuntu 上跑；CI 没有 push/PR 触发。
- 正确做法：平台差异通过注入的宿主平台对象处理，让 Windows 分支也能在 Linux CI 上跑；CI 同时跑 Linux 和 Windows；push 和 PR 都触发门禁；analyze 的警告让检查失败。
- 证据：06 ⑤；08 ④；`.github/workflows/build_pure_live_release.yml:89`。
- 验收：门禁。见 G-09。

### REG-BUILD-008 供应链规则

- 正确做法：Secret 不进仓库；Action 按 40 位 SHA 固定；禁止 `pull_request_target`；工作流输入走环境变量；Release 写明平台、ABI、签名和 SHA256；生成 SBOM 和构建来源证明；上传后重新下载核对哈希。
- 证据：AGENTS.md；`UPSTREAM_REVIEW_POLICY.md` §1；`MAINTENANCE_POLICY.md` §7；08 ④、⑥。
- 验收：门禁。

### REG-BUILD-009 Windows libmpv 来源

- 现状：Windows 的 `libmpv-2.dll` 来自 Predidit 的预编译包（`mpv v0.41.0-1049-g0b7ed670f-dirty`，FFmpeg master），既不是自编，也不是正式版。
- 正确做法：按正式版标签自编，并与录制转封装共用一份 FFmpeg；构建配方和对应源码随发布提供。
- 证据：07 ⑥；PLAN §04（工具链）。
- 验收：门禁（原生库版本字符串检查）。

### REG-BUILD-010 翻译完整性

- 正确做法：每个注册平台、每条界面文案在所有内置语言里都有翻译，缺失在 CI 报错；界面使用的键与代码一致（例如录制私有路径提示）。
- 证据：`test/sites_test.dart:12`；`test/translation_contract_test.dart:7`；`test/account_cookie_editor_test.dart`（中英文完整）；PLAN §12（多语言）。
- 验收：门禁。

---

## 12 没有自动化测试的缺口

这些行为在旧版中靠人工或真机发现，没有能在 CI 上运行的测试。v4 必须为每一项给出验收方式；只能真机验证的，写进第 8 阶段的对齐清单和每晚的设备任务。

| 编号 | 缺口 | 旧版现状 | 关联条目 | v4 验收 |
|---|---|---|---|---|
| G-01 | Android 17 本地网络权限 | 只有主机分类的单元测试（`local_network_proxy_host_test`）；权限请求、拒绝提示、Manifest 声明都没有测试 | REG-ANDROID-001 | 真机（Android 17：授予、拒绝、未决定）＋单元（注入权限接口） |
| G-02 | Windows 系统代理 | 功能本身缺失，`dart:io` 不跟随系统代理 | REG-WINDOWS-003 | 真机（系统代理开、关、PAC）＋单元（注入代理解析） |
| G-03 | TLS 指纹被拒 | 只能用真实网络复现；`android_native_http_test` 只测响应解码；Kick 的 Windows 集成测试随 Kick 下线已删除 | REG-NET-004、REG-LINUX-003 | 探针（每晚 Android、Windows、Linux） |
| G-04 | 竖屏源双击全屏 | 6d6b97ee 修复后没有测试 | REG-ROOM-002 | 组件测试（新增）＋真机 |
| G-05 | 手机单击收起控制栏 | upstream #886，只有控制条命中区域的测试，没有“单击收起”的测试 | REG-ROOM-003 | 组件测试（新增）＋真机 |
| G-06 | 真实适配器的“流结束”映射 | 驱动真实适配器的测试里 `completed` 是空流（`media_kit_buffering_state_test.dart:294`）；替身只发部分事件 | REG-PLAY-001 | 轨迹（真实 libmpv 录制） |
| G-07 | Android 画面进度信号 | 功能缺失，Android 黑屏只能间接发现 | REG-ANDROID-010 | 真机 |
| G-08 | Windows 退出和长播中止（0xc0000409） | 只有文档记录，原生释放顺序没有自动化测试 | REG-WINDOWS-001 | 真机（每晚 Windows 长播＋退出循环） |
| G-09 | Windows 专属用例 | 66 个用例在 CI 上从未运行；1 个假通过；1 个随宿主变化 | REG-BUILD-007 及标“仅 Windows”的证据 | 门禁（Windows CI）＋注入宿主平台 |
| G-10 | Android 进入画中画的紧凑帧 | 只测了状态标志，系统截图时的视觉效果没有验证 | REG-ANDROID-003 | 真机（录屏） |
| G-11 | B 站弹幕 brotli 路径 | 握手声明 `protover: 3`（brotli），测试只构造了 zlib 包 | REG-DANMAKU-013 | 样本（录制的真实 brotli 帧） |
| G-12 | 5 个主力平台没有录制样本 | 接口响应和弹幕帧都是测试里手写的最小数据，接口变了测试也看不出来 | 附录 B 全部平台条目 | 样本（第 1 阶段录制，用 v3 静态解析生成 `expected.json`） |
| G-13 | codec 12 HEVC 在高通硬解 | 只覆盖了 17LIVE 的中继改写，硬解丢帧只能真机发现 | REG-PLAY-022 | 样本＋真机（高通机型） |
| G-14 | 签名覆盖安装 | 没有任何自动化测试 | REG-BUILD-001 | 真机（Android 8、9–12、13+） |
| G-15 | 录制的前台服务与系统限制 | 只测了 Dart 侧状态机；锁屏、杀进程、Android 15 的 6 小时上限都没有测试 | REG-ANDROID-007、REG-RECORD-015 | 真机（锁屏 60 分钟、杀进程恢复、超过 6 小时） |
| G-16 | 代理出口 IP 轮换 | 只在探针文档里记录，没有可重复的检查 | REG-NET-005 | 探针（固定节点与轮换节点对照） |
| G-17 | 多画面屏蔽词大小写 | 缺陷本身没有测试 | REG-DANMAKU-004 | 单元（同一组用例跑两处） |
| G-18 | `purelive://`、`mystyle://` VIEW 链接 | 功能缺失 | REG-ANDROID-013 | 单元（路由）＋真机 |
| G-19 | 应用内更新哈希校验 | 功能缺失 | REG-BUILD-005 | 单元＋门禁 |
| G-20 | TV 方向键焦点 | 没有焦点模型 | REG-ANDROID-012 | 真机（TV 盒子）＋组件测试 |
| G-21 | 源码字符串断言 | `android_volume_key_routing_test`、`android_surface_contract_test`、`shared_media_intake_test` 的 Android 声明部分只检查源文件里的字符串 | REG-ANDROID-002、REG-ANDROID-005、REG-ANDROID-008 | 真机（行为）；字符串检查删除 |
| G-22 | 厂商机型差异 | ColorOS 截图探测、高通硬解等只能在对应机型发现 | REG-PLAY-020、REG-PLAY-022 | 真机（测试设备矩阵，PLAN §12） |
| G-23 | 替身与真实库不一致 | 同一接口有 7 份替身；10 个文件用同步广播；Dio 拦截器直接返回已解码的 Map，跳过字符串解码 [待确认影响] | REG-PLAY-001 及所有播放、平台条目 | 轨迹（只保留一个回放替身）＋样本（从原始字节解码） |

---

## 13 明确不继承的旧行为

以下旧行为或旧测试随技术决定作废。作废的是实现和测试代码；其中仍有价值的需求已并入上面的条目。

| 编号 | 内容 | 原因 | 需求去向 |
|---|---|---|---|
| N-01 | IJK、Exo 专属行为：IJK 的 freeze 缓冲事件、`disable-vid`、Exo 不支持代理、纯音频只改标志；降级链 mpv → IJK → Exo → fvp；`fijk_buffering_event_test`、`engine_fallback_manager_test` | 宪法：全平台只用 mpv | 恢复链见 REG-PLAY-010 |
| N-02 | fvp 专属行为：OpenSL 优先、纹理尺寸为 null 时重新 prepare、Android 上 codec 12 强制软解、`isReusable`；`fvp_adapter_test`；5b7cb9c9、cabd2c83 | ADR 0006（libmdk 是专有库） | codec 12 见 REG-PLAY-022；请求头卫生见 REG-NET-006 |
| N-03 | FFmpegKit 专属实现：FLV 输入桥、AVC 边界等待的 FFmpeg 形式、HLS 暂存与预取的 FFmpeg 参数形式、CA 文件注入、按日志字符串分类、Android 冷启动预热 FFmpegKit、新录制的 TS 分段与 clock-v1；13 个 FFmpegKit 会话替身测试 | ADR 0005 | 语义见 REG-RECORD-001 至 REG-RECORD-024、REG-LEASE-011 至 REG-LEASE-016 |
| N-04 | Firebase：邮箱和 GitHub 登录、云备份、登录后自动恢复、管理员权限；42 个用例 | 宪法：移除 Firebase | 首次启动导入向导见 REG-STORE-019 |
| N-05 | HEVC 转写中继（`FlvLegacyHevcRelay`）的实现 | 所有平台的 FFmpeg 都 ≥ 8 | “codec 12 必须有画面”见 REG-PLAY-022 |
| N-06 | `siteCatalogMigration` 的逐版本迁移代码；18 个 `*_catalog_migration_test` | 旧 Hive 键，v4 换存储 | 读取语义见 REG-STORE-008 |
| N-07 | `validate_build_policy.ps1` 等“源码必须包含某字符串”的检查 | 把文档文字和代码绑死，不能证明行为 | 换成真实测试（G-21） |
| N-08 | 全局 `audioOnly`、布尔型高刷开关等旧键的运行时读取 | 已废弃 | 只在迁移时读取，见 REG-STORE-009 |
| N-09 | MSIX 打包、fastforge 模板、feature-build 与 staged 签名流程 | 08 ④：v4 的 CI 全自动构建和签名 | 见 REG-BUILD-002、REG-BUILD-006 |

---

## 14 待确认汇总

| 条目 | 待确认的内容 |
|---|---|
| REG-PLAY-010 | Android mediacodec 兼容模式是否作为恢复链里独立的一步 |
| REG-PLAY-022 | 高通机型上 mpv 硬解 codec 12 流是否仍静默丢帧 |
| REG-LEASE-004 | 虎牙网页回退源是否还有真实流量，决定是否保留 40 秒交接 |
| REG-LEASE-018 | HLS 查询 token 策略是否还有平台产出 |
| REG-MULTI-009 | v4 自动降质的默认值 |
| REG-MULTI-013 | Android 上按格子尺寸降低解码尺寸的实现手段 |
| REG-DANMAKU-007 | 替换 fuzzywuzzy 后相似度阈值如何对应 |
| REG-RECORD-007 | v4 的 FLV 写入器转 MP4 后是否还会出现“无画面尾包” |
| REG-RECORD-017 | 重连期间释放调度槽是否会被排队任务抢占 |
| REG-RECORD-019 | Twitch 广告 DATERANGE 是否需要剔除 |
| REG-RECORD-021 | 旧版弹幕时间基相对第一个媒体包的偏差量 |
| REG-STORE-012 | Hive `language` 与 easy_localization `locale` 冲突时的优先级 |
| REG-STORE-025 | IPTV 回看的规格归属（`spec/modules/iptv.md`） |
| REG-ANDROID-004 | Flutter 自带的预测性返回能否覆盖全屏返回场景 |
| REG-ANDROID-007 | Android 15 起长时间录制是否改用 specialUse 等服务类型 |
| REG-ANDROID-010 | Android 补丁加帧进度信号的可行性 |
| REG-ANDROID-011 | Android 旧数据路径是否在正式版用过 |
| REG-WINDOWS-003 | Windows 跟随系统代理的实现方案 |
| REG-WINDOWS-007 | 旧版默认开启开机自启是否有意 |
| REG-LINUX-002 | 修改 Linux 应用 ID 后的数据迁移 |
| REG-LINUX-003 | Linux 上 TLS 指纹站点的方案 |
| REG-BUILD-001 | `c0bb` 原始 keystore 是否还在；Android 8 的 v1/v2 双密钥方案需实测 |
| REG-COMMON-010 | 短链防御是否有对应的事故提交 |
| G-23 | Dio 拦截器跳过字符串解码的实际影响 |
| 附录 A | 未收录的本地互动（虚拟金币等，约 1780 行）是否保留，需要产品决定 |

---

## 附录 A 旧测试名的导出与归并

**导出命令**（在仓库根目录运行）：

```bash
rg -U -o --no-heading -N "\b(test|testWidgets)\(\s*['\"][^'\"]+" test/ \
  | tr '\n' ' ' | sed 's/ test\//\ntest\//g'
```

得到 3557 条（`-U` 能匹配跨行的测试名）。不加 `-U` 的单行写法得到 3568 条，诊断报告的口径是 3565 条；差异来自跨行声明和字符串插值，不影响归并。

**按被测对象归并**（按文件名启发式归类，误差约 ±5%）：

| 被测对象 | 测试名数 | 去向 |
|---|---:|---|
| 平台适配器（32 个平台前缀的文件） | 884 | 交给 `spec/sites/<平台>.md`；影响模块的写进本文（附录 B） |
| 设置、存储、备份、同步 | 472 | REG-STORE、REG-NET-003、REG-COMMON-015 |
| 录制与 FFmpeg | 417 | REG-RECORD；FFmpegKit 专属的见 N-03 |
| 播放器 | 371 | REG-PLAY、REG-ANDROID、REG-WINDOWS |
| 浏览、搜索、分享、工具箱 | 348 | REG-COMMON-010 至 REG-COMMON-014、REG-ROOM-016 |
| 直播间界面 | 270 | REG-ROOM |
| HLS、FLV 中继与传输 | 216 | REG-LEASE |
| IPTV | 213 | REG-STORE-021 至 REG-STORE-025 |
| 弹幕 | 114 | REG-DANMAKU |
| 桌面、应用骨架、更新 | 112 | REG-WINDOWS、REG-COMMON-018、REG-BUILD-005 |
| 多画面 | 83 | REG-MULTI |
| Firebase | 42 | 不继承（N-04） |
| IJK、fvp | 16 | 不继承（N-01、N-02） |

**收录原则**：只收描述外部可观察行为、并且上面还没有覆盖的测试。以下几类没有逐条收录：

- 约 139 个测试名断言小屏、大字号下的布局可达性，归为一条设计不变量（REG-COMMON-019），细节由 `spec/design` 负责。
- 约 250 个测试名断言“迟到结果无副作用、重复点击只执行一次”，归为一条通用规则（REG-COMMON-017），只把有独立业务含义的写进各领域条目。
- 断言内部调用顺序、依赖 GetX 注入或测试钩子的测试，只提取了场景语义。
- 本地互动（虚拟金币、本地弹幕样式等，`local_interaction_*` 测试）是否保留需要产品决定 [待确认]，暂不收录。
- 录制时钟探针的支持代码（`frame_hash_timeline_test`、`media_packet_timeline_test`、`hls_capture_contract_test`、`recording_clock_probe_support_test`）属于验证工具，不是产品行为；它们的判定方法（包计数守恒、内部空洞检测、不猜帧率）供 `live_cli record` 的验收脚本沿用。

---

## 附录 B 平台坑与模块条目的对照

平台规格负责平台侧的契约；本表列出平台坑在本文中对应的模块侧要求。

| 平台坑（诊断报告） | 平台规格 | 本文条目 |
|---|---|---|
| 斗鱼匿名原画 `expire=300`，每 5 分钟断一次 | REG-DOUYU-001、REG-DOUYU-002 | REG-LEASE-001、REG-LEASE-002、REG-MULTI-002、REG-MULTI-003、REG-RECORD-001 |
| 斗鱼 rate 是不透明请求码，画质顺序与服务端确认 | REG-DOUYU-005～REG-DOUYU-007、REG-DOUYU-027 | REG-COMMON-005、REG-RECORD-016 |
| 斗鱼恢复不复用旧 URL，缺失确认保持未知 | REG-DOUYU-011 | REG-LEASE-005 |
| 斗鱼疑似机器人过滤默认关闭 | REG-DOUYU-018、REG-DOUYU-019 | REG-DANMAKU-003 |
| 斗鱼会话同时影响签名、播放和录制请求头 | REG-DOUYU-004、REG-DOUYU-014、REG-DOUYU-022 | REG-COMMON-008 |
| 虎牙原生 FLV 凭据过期不断开已建立的连接 | REG-HUYA-001、REG-HUYA-002 | REG-LEASE-001、REG-LEASE-003、REG-RECORD-001 |
| 虎牙网页源短租期与 40 秒交接 | REG-HUYA-002、REG-HUYA-019 | REG-LEASE-004 |
| 虎牙每次打开生成新 seqid，播放与录制各自签名 | REG-HUYA-007 | REG-LEASE-007 |
| 虎牙按 CDN 主机、格式、凭据类型识别线路 | REG-HUYA-010、REG-HUYA-018 | REG-COMMON-006 |
| 虎牙 8006 是热度，不是在线人数 | REG-HUYA-014 | REG-COMMON-004 |
| 虎牙只有明确的非直播状态才算离线 | REG-HUYA-015 | REG-COMMON-001 |
| 虎牙录制只签当前线路 | huya.md §5.3（无单独编号） | REG-LEASE-006 |
| B 站游客被降档，以 `current_qn` 为实际画质 | REG-BILIBILI-001 | REG-COMMON-005 |
| B 站 -352 风控 | REG-BILIBILI-003、REG-BILIBILI-006 | REG-COMMON-001、REG-COMMON-002 |
| B 站弹幕认证字段与 op24 ACK | REG-BILIBILI-008、REG-BILIBILI-011、REG-BILIBILI-012 | REG-DANMAKU-013 |
| B 站弹幕 brotli | bilibili.md §7、§12 第 16 项（无单独编号） | G-11 |
| 抖音纯音频档 `ao` | REG-DOUYIN-001 | REG-COMMON-007 |
| 抖音弹幕多节点故障切换 | REG-DOUYIN-002、REG-DOUYIN-003 | REG-DANMAKU-012 |
| 抖音 `total_user` 是累计人数 | REG-DOUYIN-008 | REG-COMMON-004 |
| 抖音、斗鱼协议层丢弃其它房间的消息 | douyin.md §7（无单独编号）、REG-DOUYU-020 | REG-DANMAKU-001 |
| 快手弹幕改走移动端 feed 串行轮询 | REG-KUAISHOU-011～REG-KUAISHOU-014 | REG-DANMAKU-011 |
| 快手匿名直播搜索改用主播搜索 | REG-KUAISHOU-009、REG-KUAISHOU-015 | 无模块侧要求 |
| 斗鱼 DID 统一、`rtmp_live` 绝对地址、Cookie 令牌类型 | REG-DOUYU-003、REG-DOUYU-009、REG-DOUYU-010、REG-DOUYU-024、REG-DOUYU-025 | 无模块侧要求 |
| 虎牙 wsTime 不延长、fm 模板整体替换、HLS 与 FLV 令牌分开 | REG-HUYA-004～REG-HUYA-006、REG-HUYA-026 | 无模块侧要求 |
| 抖音签名 URL 编码 | REG-DOUYIN-002、REG-DOUYIN-015 | 无模块侧要求 |
| FC2 播放列表没有 `.m3u8` 后缀（非首批） | 第三批以后 | REG-LEASE-013 |
| Twitch 在 Android 代理下 TLS 被重置（第二批） | 第二批 | REG-NET-004 |
| CHZZK 受限直播导致整页失败（非首批） | 第三批 | REG-COMMON-002（地区限制是类型化错误） |
| 17LIVE codec 12 HEVC（非首批） | 第三批 | REG-PLAY-022 |

---

## 附录 C 旧代码短名与完整路径

| 短名 | 路径 |
|---|---|
| PM、`player_manager.dart` | `lib/player/core/player_manager.dart` |
| `media_kit_adapter.dart` | `lib/player/adapters/media_kit_adapter.dart` |
| `playback_source_transport.dart` | `lib/player/core/playback_source_transport.dart` |
| `flv_splice_relay.dart` | `lib/player/core/flv_splice_relay.dart` |
| `playback_header_resolver.dart` | `lib/player/core/playback_header_resolver.dart` |
| `playback_lifecycle_coordinator.dart` | `lib/player/core/playback_lifecycle_coordinator.dart` |
| `playback_proxy_policy.dart` | `lib/player/core/playback_proxy_policy.dart` |
| `portrait_stream_support.dart` | `lib/player/core/portrait_stream_support.dart` |
| `linux_mpv_runtime.dart` | `lib/player/core/linux_mpv_runtime.dart` |
| `live_site.dart` | `lib/core/interface/live_site.dart` |
| `douyu_site.dart`、`huya_site.dart`、`bilibili_site.dart` | `lib/core/site/<平台>/<平台>_site.dart` |
| `huya_transport_policy.dart` | `lib/core/site/huya/huya_transport_policy.dart` |
| `proxy_routing.dart` | `lib/core/common/proxy_routing.dart` |
| `live_room.dart` | `lib/common/models/live_room.dart` |
| `video_controller.dart`、`video_controller_panel.dart`、`video_player.dart` | `lib/modules/live_play/widgets/video_player/` |
| `live_play_controller.dart`、`danmaku_controller.dart`、`danmaku_message_gate.dart`、`danmaku_similarity_filter.dart` | `lib/modules/live_play/controllers/` |
| `live_play_back_scope.dart` | `lib/modules/live_play/widgets/layout/live_play_back_scope.dart` |
| `video_keyboard.dart` | `lib/modules/live_play/widgets/keyboard/video_keyboard.dart` |
| `multiview_controller.dart`、`multiview_page.dart` | `lib/modules/multiview/` |
| `multiview_danmaku_session.dart` | `lib/modules/multiview/danmaku/multiview_danmaku_session.dart` |
| `recorder_controller.dart` | `lib/recorder/pages/recorder/recorder_controller.dart` |
| `stream_resolver_service.dart`、`video_processor_service.dart`、`recording_danmaku_service.dart`、`recorder_continuation_policy.dart`、`cache_service.dart` | `lib/recorder/services/` |
| `live_record_task.dart` | `lib/recorder/models/live_record_task.dart` |
| `ffmpeg_scheduler.dart` | `lib/recorder/ffmpeg/ffmpeg_scheduler.dart` |
| `favorite_room_controller.dart`、`backup_controller.dart`、`app_settings_controller.dart`、`proxy_settings_controller.dart`、`startup_controller.dart` | `lib/common/services/settings/` |
| `settings_upgrade_migration.dart` | `lib/common/services/utils/settings_upgrade_migration.dart` |
| `local_network_access.dart` | `lib/common/services/local_network_access.dart` |
| `app_path_manager.dart`、`initialized.dart`、`initial_services.dart` | `lib/common/global/` |
| `desktop_manager.dart` | `lib/common/global/platform/desktop_manager.dart` |
| `favorite_controller.dart` | `lib/modules/favorite/favorite_controller.dart` |
| `version_util.dart`、`windows_multi_instance_launcher.dart` | `lib/common/utils/` |
| `share_command_handler.dart` | `lib/plugins/share_command_handler.dart` |
| `barrage_engine.dart` | `plugins/flame_barrage/lib/src/core/barrage_engine.dart` |
| `flame_barrage_widget.dart` | `plugins/flame_barrage/lib/src/widget/flame_barrage_widget.dart` |
| `global_player_service.dart` | `lib/player/global_player_service.dart` |
| `playback_source.dart`、`live_room_volume_manager.dart` | `lib/player/core/` |
| `video_output_viewport_sizer.dart` | `lib/player/widgets/video_output_viewport_sizer.dart` |
| `fullscreen.dart`、`window_helper.dart` | `lib/player/utils/` |
| `live_directory.dart`、`live_quality_discovery.dart` | `lib/core/interface/` |
| `web_socket_util.dart` | `lib/core/common/web_socket_util.dart` |
| `webview_proxy_scope.dart` | `lib/core/utils/webview_proxy_scope.dart` |
| `douyu_danmaku.dart` | `lib/core/danmaku/douyu_danmaku.dart` |
| `twitch_site.dart` | `lib/core/site/twitch/twitch_site.dart` |
| `sites.dart` | `lib/core/sites.dart` |
| `database.dart`、`tables.dart` | `lib/core/iptv/local/` |
| `live_area.dart` | `lib/common/models/live_area.dart` |
| `cookie_settings_controller.dart`、`web_dav_controller.dart`、`player_settings_controller.dart`、`font_settings_controller.dart` | `lib/common/services/settings/` |
| `tag_management_controller.dart` | `lib/modules/tags/tag_management_controller.dart` |
| `player_controller.dart` | `lib/modules/live_play/controllers/player_controller.dart` |
| `live_play_content.dart`、`portrait_fullscreen_interaction.dart` | `lib/modules/live_play/widgets/layout/` |
| `live_play_menu_button.dart` | `lib/modules/live_play/widgets/button/live_play_menu_button.dart` |
| `multiview_models.dart` | `lib/modules/multiview/models/multiview_models.dart` |
| `remote_sync_service.dart` | `lib/modules/remote_receiver/remote_sync_service.dart` |
| `navigation_observer.dart` | `lib/routes/navigation_observer.dart` |
| `plugins/utils.dart`、`backup_recovery_service.dart` | `lib/plugins/` |
| `ffmpeg_service.dart` | `lib/recorder/services/ffmpeg_service.dart` |
| `ffmpeg_command_builder.dart` | `lib/recorder/ffmpeg/ffmpeg_command_builder.dart` |
| `MainActivity.kt`、`RecorderBackgroundPlugin.kt`、`RecorderForegroundService.kt` | `android/app/src/main/kotlin/com/mystyle/pure_live/` |
| `main.cpp`、`flutter_window.cpp` | `windows/runner/` |
