# 虎牙续签预取与播放器操作队列审计

## 实施前冻结与来源

- 本地 `124ec716055bd19902a18afd8dcf45e52eb6591d`。
- 只读上游 `c6c9bd70aedc503c003110dae10a83ad0bb891d8`；相对上次审查的
  `baab0eb4` 仅更新 `assets/releases.json`，没有新增虎牙播放修复。本轮未合并上游。
- GitHub 最新附件仍是 2026-09-01 的 `v3.1.8`，没有包含本地 `8a6fdce1`、
  `5e284f2e`、`d19ca18f` 等连续播放修复；附件版本与当前工作树分开验收。
  本轮重新核对远端标签解引用为 `e94f94d73953e9ee295738a121df522e4710bf58`；
  祖先关系检查确认上述原生取流/恢复事务修复不在该标签内。
- 来源：`fork-regression`。本分支把主动续签网络请求放进了原生播放器生命周期
  串行队列。上游 WUP 取令牌是取流修复，不含本分支的主动续签队列。

## 第一个错误状态

`_scheduleProactiveSourceRefresh` 先占据 `_playerLifecycleQueue`，再等待房间详情与
令牌请求。原生虎牙 FLV 已改为仅预取、不切健康连接，但其网络等待仍霸占同一队列。
因此续签慢时，用户换房/换源/关闭要等待与本操作无关的 HTTP 请求。
这不是 GPU 掉帧证据，也不是所有卡顿的唯一原因；是可独立复现的操作延迟来源。

## 设计

1. 不涉及播放器交接的预取只执行网络与内存缓存操作，移出原生生命周期队列。
2. 同一会话与播放意图只有一个预取；真实断流可复用正在获取的同一凭据。
3. 网络结果提交前重新核对会话、播放器和播放意图；旧房间结果与失败都不影响新房间。
4. Windows 网页/HLS 后备的真实播放器交接继续串行，不在后台并发操作原生播放器。
5. 暂停、关闭、切房、断流、预取失败/迟到和重复事件分别做确定性回归。

## 验证记录

- 实施前同一业务源码 5 组测试 **110/110 通过**：
  `local-artifacts/build-records/20260905T041742515Z-quality-focused.json`。
  这说明旧测试覆盖不足，不代表操作队列没有上述缺陷。
- 新增两个红测分别阻塞续签 HTTP，然后换房/关闭：两项均在旧实现失败
  （61 通过 / 2 失败），不是编译错误。
  `local-artifacts/build-records/20260905T042122595Z-quality-focused.json`。
- 修复后同一组五文件 **112/112 通过**，包括七种恢复与预取共享请求情形；
  `local-artifacts/build-records/20260905T042433484Z-quality-focused.json`。
  随后补入旧请求迟到失败、重复 playing 事件的三个扩展案例，连同留言板及弹幕传输
  在 **130/130** 定向回归通过：`20260905T045039282Z-quality-focused.json`。
  再补入旧会话结束时不清除新会话单次预取所有者的用例，由最终完整门禁验证。

## 上游方案、本分支差异与本轮审查边界

| 链路 | 已核对的代码/合同 | 结论 |
|---|---|---|
| 取流与身份 | `HuyaSite.getPlayUrl`、WUP 请求结构、FLV/HLS 与 UA | 上游关键思路是原生 WUP FLV 取流；本分支已采用，保留协议对应的 HLS 后备，不交叉使用身份/令牌 |
| 凭据寿命 | `getPlayUrlRefreshAt/InvalidAt`、`HuyaTransportPolicy` | 入站连接凭据 TTL 与已打开连接寿命分开；健康原生 FLV 不按 40/100/120 秒定时重开 |
| 更新 URL | `PlayerController._buildSourceResolver`、`PlaybackSourceRefreshResult` | 预取不改 UI 画质选择，不提前打开备用解码器；同会话合并请求，失效结果受代次隔离 |
| 恢复事务 | `PlayerManager` 恢复预算、队列、候选准备与交接 | 真实 EOF 与推断停帧区别处理；已恢复、已暂停或旧会话的任务在每个异步边界撤销；本轮修复预取队列所有权 |
| 原生事件 | `MediaKitAdapter`、`FijkAdapter`、Fijk helper、Windows video output | IJK 原生缓冲独立订阅；真实渲染进度有界上报，不以播放标志直接判定首帧 |
| 生命周期 | `PlaybackLifecycleCoordinator`、音频服务与 presentation 可见性 | 不新增第二套生命周期暂停/恢复机制，保留用户暂停与系统暂挂的区别 |
| 缓冲资源 | `LiveBufferPolicy`、mpv 属性、窗口资源采样 | 前向/回看预算、关闭磁盘缓存及 donation 保持一致；不靠无限堆缓冲掩饰断流 |
| 录制邻接 | `StreamResolverService`、请求头共享入口、录制租约元数据 | 保留独立录制会话与按需源解析，本轮不修改录制重连、写盘或统计合同 |
| 辅助请求 | Huya danmaku、TARS 留言板及两个调用入口 | 新发现超时后底层 HTTP 未关闭，独立修复与记录见 `HUYA_MESSAGE_BOARD_HTTP_AUDIT_2026_09_05.md` |

完整仓库静态扫描和全量测试用于检测这些修改的相邻回归；它们不等于逐个用户操作与
所有平台都已经实机验收。本轮没有升级依赖、整体替换播放器或合并上游业务代码。

### 公开资料核对

- [上游 c5944dd5](https://github.com/liuchuancong/pure_live/commit/c5944dd5a529cd93eb29486500abd5d496618f80)：
  核对实际 diff，而不是根据提交标题或 Issue 关闭状态推断修复范围。
- [biliup 原生 Huya WUP 实现](https://github.com/biliup/biliup/blob/master/crates/biliup/src/downloader/live/huya_wup.rs)：
  对照 TARS V3、`getCdnTokenInfoEx` 与 `sFlvToken`，不盲目套用网页 UID 到原生合同。
- [mpv cache-pause](https://mpv.io/manual/stable/#options-cache-pause)、
  [demuxer-donate-buffer](https://mpv.io/manual/stable/#options-demuxer-donate-buffer)：
  缓冲暂停与用户暂停分开；压缩媒体缓存预算不是整个进程内存上限。

## 本轮连续播放采样

使用生产 `HuyaSite.getPlayUrl`、请求头与 `LiveBufferPolicy`，送入当前 Windows
`libmpv-2.dll`。原画 `ratio=0`，不降到 500 kbps 来替代高画质验证。
房间、线路、时长以环境变量显式固定；签名只经标准输入传入，不输出或保存。

第一轮：房间 257085 / AL，1920×1080、60 fps，360.191 秒；媒体时钟推进 359.184 秒，
EOF 0、主动暂停样本 0、缓存暂停样本 0、解码器丢帧 0。VO 层 `frame-drop-count=50`，
不隐去该计数，也不把它等同于真实屏幕丢帧；探针使用 `vo=null` / 软件解码。
私有内存终点 210.75 MiB，最后两分钟增长 2.37 MiB，压缩缓存峰值 6.78 MiB，
销毁后私有内存回落到 36.45 MiB。没有据此宣称高画质长时资源已完全平台化。

原始计数：`local-artifacts/huya-source-quality-al-20260905.log`；
质量记录：`20260905T043359669Z-quality-focused.json`。

第二轮：房间 282712 / TX，1600×1200、60 fps，360.144 秒；媒体时钟推进 358.683 秒，
EOF、主动暂停、缓存暂停、VO 丢帧及解码器丢帧计数均为 0。
私有内存终点 186.25 MiB，最后两分钟增长 0.01 MiB，压缩缓存峰值 10.48 MiB，
销毁后私有内存回落到 34.40 MiB。
原始计数：`local-artifacts/huya-source-quality-tx-20260905.log`；
质量记录：`20260905T044228928Z-quality-focused.json`。

两次均只打开一个连接，均超过此前网页样本约 120 秒与令牌 TTL 300 秒边界。
样本说明这两路原生 FLV 无须为了凭据 TTL 主动重连，不是虎牙全部房间/CDN 的 SLA。
AL/TX 探针自身整机口径平均 CPU 分别 0.789% / 0.938%，仅作软件解码取样；
构建门记录还会统计其他存活重型进程，因此不拿门禁聚合峰值当作 Pure Live 客户端占用。

没有使用这些数据声称 Flutter 纹理呈现、实际声音输出、Android 硬解或每种网络条件都
“零卡顿”。

## 本批最终回归与交付边界

- 播放器代码提交 `393a10ca`，留言板代码提交 `4aefaa04`，最后一项新旧会话所有权
  回归一并通过。完整门禁运行于干净的 `4aefaa047fdfbcd9b20b228b2083850a773b03e5`。
- `local-artifacts/build-records/20260905T045902783Z-quality-full.json`：
  **868/868** 单元/Widget 测试、**42/42** 接口探测通过；一次 analyze 无诊断。
  全仓扫描 3992 个跟踪文件，错误 0，保留 1 项既有空 catch 清单提示（31 处）。
- 总耗时 253.604 秒，资源守卫记录结束后活跃重型进程 **0**；保留增量缓存，
  未执行 clean、并发平台打包或追加第二轮全量构建。
- 本批只提交源码与审计，没有安装/操作手机，没有构建或上传新安装包，3.2.0 最终
  全功能和跨平台交付仍按 `ACCEPTANCE_3_2_0.md` 逐项完成。之后的文档收尾不改变此源码。
- 如需隔离回滚，只回退 `393a10ca` 的队列所有权变更，不恢复已证伪的健康原生 FLV
  固定周期重开策略；留言板修复是独立提交，可单独审查。

播放器这批不改变签名算法、比例识别、UI、录制、弹幕协议或缓存容量。3.2.0 整体验收继续
保留；源码、测试、原生连续解码、安装包和设备体验仍分别列证据。
