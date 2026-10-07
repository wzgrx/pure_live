# W01.1 2026-10-03 上游对照：pure_live 271 个、pure_live_TV 167 个、media_core 66 个提交

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（完成，2026-10-03，提交 `d54772d54`）
- 类型：工程（上游对照）
- 来源：D-027（用户 2026-10-03：“新增参考借鉴上游的模块”）；第一次对照，同时把手机版上游加进参考仓库（[W02.1](../../W02-参考仓库/W02.1-加入手机版上游仓库/README.md)）
- 旧文档：`docs/T00/upstream-2026-10-03.md`（docs v1 之前的位置）
- 相关：决定 D-027、D-026；开出的任务见“结果”


看了五个上游仓库在上次对照之后的提交，逐条对照 4.x 现在的代码，记下可以借鉴的、我们也有的问题、已经有的和不适用的。以后每周看一次（[W01.2](../W01.2-上游跟踪/README.md)）。

## 看了哪些

| 仓库 | 范围 | 提交数 | 说明 |
|---|---|---:|---|
| [liuchuancong/pure_live](https://github.com/liuchuancong/pure_live)（手机和桌面版，3.x 的上游） | `v3.2.11` → `20817480d`（2026-10-03） | 271 | 就是在 v3.2.11 上接着做的；本机主仓库加了远程 `upstream`（不拉标签），用 `git log v3.2.11..upstream/master` 看 |
| [liuchuancong/pure_live_TV](https://github.com/liuchuancong/pure_live_TV)（电视版） | `e1cca224` → `37660afc`（2026-10-02） | 167 | 大部分是点播、音乐和电视界面；直播相关 19 个 |
| [liuchuancong/media_core](https://github.com/liuchuancong/media_core)（播放核心） | `34b3cca` → `69af860`（2026-10-02） | 66 | 画中画、小窗、投屏、复合源、状态对账 |
| [liuchuancong/flame_barrage](https://github.com/liuchuancong/flame_barrage)（弹幕引擎） | 没有新提交 | 0 | 上次看过的 `3eddae8` 加了按住定住弹幕 |
| [liuchuancong/flv_lzc](https://github.com/liuchuancong/flv_lzc) | 没有新提交 | 0 | — |

## 4.x 也有的问题（要修）

| 上游提交 | 问题 | 4.x 的位置 | 任务 |
|---|---|---|---|
| pure_live `2b9ffc7a3` | 主播下播后流被关掉（EOF）不计重试上限，一直快速重试；合并时只要有一个 0 字节分段整段合并失败 | `packages/live_record/lib/src/policy.dart` 的 `shouldEnterPollingAfterRetryLimit`（EOF 永不进轮询）；`merge.dart` 遇到空分段直接报 `segmentClock` | [H01.5](../../../H-录制/H01-录制核心/H01.5-主播下播后不再无限快速重试/README.md) |
| pure_live `fa67c637f`、pure_live_TV `5bc53016` | 房间详情缺封面时，用卡片里的值补齐漏了封面，观看记录等处封面变空 | `packages/live_core/lib/src/live_room.dart` 的 `fillFromDetail` 只补标题、分区、昵称、头像 | [E05.3](../../../E-直播平台/E05-平台框架和模型/E05.3-房间详情补齐时连封面一起补/README.md) |
| pure_live `1cdcb7b2a` | 从屏幕底边上滑回桌面时，先触发了画面的亮度或音量调节 | `apps/pure_live/lib/features/live_play/player/player_gestures.dart` 的 `_onDragStart` 没有避开系统手势区（修的时候用系统给的手势区高度，比上游写死 48 更准） | [A07.15](../../../A-界面设计/A07-直播间界面/A07.15-画面上下滑避开系统手势区/README.md) |
| media_core `44710e1`、`2edc721` | “缓冲结束”的事件丢了时，画面在动但状态一直是缓冲 | `packages/live_player/lib/src/session.dart` 的 `_onFrame` 只记时间不对账；12 秒后会被缓冲看门狗当成卡住去重连 | [G02.2](../../../G-播放/G02-会话和恢复/G02.2-缓冲状态对账/README.md) |
| pure_live `a424399e6` | ColorOS 14 上开着预测返回时，全面屏手势返回卡死（上游是 GetX 路由，关掉了预测返回） | 4.x 也开着 `enableOnBackInvokedCallback`，但用的是 go_router，不一定有这个问题，要在 ColorOS 14 上实测 | [O06.1](../../../O-Android系统集成/O06-返回手势、平板和折叠屏/O06.1-预测返回在ColorOS14/README.md) |

## 可以借鉴的新功能

| 上游提交 | 内容 | 任务 |
|---|---|---|
| flame_barrage `3eddae8`、pure_live `2d2ad2039` | 按住弹幕让它停住，松手继续 | [V01.3](../../../V-需求和反馈/V01-新功能提议/V01.3-按住弹幕让它停住/README.md) |
| pure_live_TV `9a7bb104` | 同屏最大弹幕条数可以设置 | [V01.4](../../../V-需求和反馈/V01-新功能提议/V01.4-同屏最大弹幕条数可以设置/README.md) |
| pure_live `9483ccf03` | 设备同步在发送、接收前先勾选同步哪些内容（上游同时去掉了配对码，我们保留配对码） | [V01.6](../../../V-需求和反馈/V01-新功能提议/V01.6-设备同步选择同步内容/README.md) |
| pure_live `f9e03f446`、`582e355f7`、`b2cca41c7`；media_core 画中画系列 | 小窗拖角改尺寸、小窗尺寸设置、画中画里的弹幕随窗口缩放 | [V01.5](../../../V-需求和反馈/V01-新功能提议/V01.5-小窗拖角改尺寸/README.md) |
| pure_live_TV `6ba16c55` | 哔哩哔哩多账号（账号名册、切换） | [V01.2](../../../V-需求和反馈/V01-新功能提议/V01.2-哔哩哔哩多账号/README.md) |
| pure_live `daa891853` 等 | 播放设置的说明页（mpv 各选项的中文说明和搭配建议） | 先不登记；需要时并进 A11 |

## 4.x 已经有的（不用做）

- 斗鱼登录：Cookie 按 JWT 或网页 `dy_auth` 判断登录、LTP0 和 dy_did 续期、7 天自动刷新、续期凭据不进播放请求（pure_live `2e2cb0d42`、`7d5187ca0`、`7b9174673`、`c29a3b85d`）——这几个提交来自你自己的分支，已在 [E01.2](../../../E-直播平台/E01-国内五大平台/README.md) 做进 4.x。
- 硬件解码默认 `auto-safe`（pure_live `8b135c0eb` 吸收 Kazumi 的做法）——4.x 的 `mpv_options.dart` 本来就是。
- 刷新关注时空字段不覆盖已有的封面、昵称（`LiveRoom.mergeFrom`）。
- 小窗和画中画挂弹幕（pure_live `fa3d739e4`）——4.x 已接上（[A07.10](../../../A-界面设计/A07-直播间界面/README.md)）。
- 多画面里每格的音量、刷新地址（media_core `f6332a6`）——4.x 的多画面已有房间音量和恢复时刷新地址。

## 不适用

- 上游把播放全部换到 media_core（“kernel player”）以及随后修的一串问题（进直播间黑屏、切清晰度或线路后状态卡在第一个、小窗回直播间崩溃）：4.x 自己做了播放层，这些问题来自它的新架构。
- Windows 画中画、全屏窗口边界、mpv 原生窗口：桌面以后做（X）时再看。
- 点播、音乐、壁纸、电视界面样式：电视端（X）开工时再看；电视版 `a3b61953` 给所有长按卡片加了“弹窗开着时不响应”的锁，是遥控器才有的问题。
- Anime4K 超分辨率（pure_live `d90f85468`）：耗电和发热大，先不做（[V04.2](../../../V-需求和反馈/V04-不做的/V04.2-Anime4K超分辨率/README.md)）。

## 结果

- 看到的提交范围（下次从这里接着看）：pure_live `20817480d`（2026-10-03）、pure_live_TV `37660afc`（2026-10-02）、media_core `69af860`（2026-10-02）、flame_barrage `3eddae8`、flv_lzc `162030d`（本机副本 2026-10-03 00:21 拉取）。
- 开出的任务（2026-10-07 的登记表状态）：

| 任务 | 对应上游 | 档位 | 状态 |
|---|---|---|---|
| [H01.5](../../../H-录制/H01-录制核心/H01.5-主播下播后不再无限快速重试/README.md) 主播下播后不再无限快速重试；合并跳过 0 字节分段 | pure_live `2b9ffc7a3` | 第一档 | 未开始 |
| [E05.3](../../../E-直播平台/E05-平台框架和模型/E05.3-房间详情补齐时连封面一起补/README.md) 房间详情补齐时连封面一起补 | pure_live `fa67c637f`、pure_live_TV `5bc53016` | 第二档 | 未开始 |
| [A07.15](../../../A-界面设计/A07-直播间界面/A07.15-画面上下滑避开系统手势区/README.md) 画面上下滑避开系统底部手势区 | pure_live `1cdcb7b2a` | 第二档 | 未开始 |
| [G02.2](../../../G-播放/G02-会话和恢复/G02.2-缓冲状态对账/README.md) 缓冲状态对账 | media_core `44710e1`、`2edc721` | 第二档 | 未开始 |
| [O06.1](../../../O-Android系统集成/O06-返回手势、平板和折叠屏/O06.1-预测返回在ColorOS14/README.md) 预测返回在 ColorOS 14 上验证 | pure_live `a424399e6` | 第二档 | 未开始 |
| V01.2～V01.6 五个新功能提议 | 见上“可以借鉴的新功能” | 第三档 | 未开始 |
| [V04.2](../../../V-需求和反馈/V04-不做的/V04.2-Anime4K超分辨率/README.md) Anime4K 不做 | pure_live `d90f85468` | — | 不做 |

- 同时做的：主仓库加远程 `upstream`（不拉标签，W02.1）；参考仓库表加手机版上游（`docs/specs/ENGINEERING.md` 第 5 节）。

## 验证

- 对照没有测试；每条“4.x 也有的问题”都写了 4.x 的位置（文件和方法），开出的任务各自先写改之前会失败的测试再修。
- 2026-10-07 核对：链接改到各任务文件夹（原来指向子分类页或 A 组）；登记表里这 5 个任务没有 `from`（建议补上上游仓库和提交）。

## 留下的问题

- “播放设置的说明页”（pure_live `daa891853` 等）没有登记，需要时并进 A11 或在 V01 提议。
- 下一次对照：W01.2，从上面的提交范围接着看。
