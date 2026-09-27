# 虎牙续签线路身份审计（2026-09-05）

## 冻结范围与来源

- 本地起点：`427839a9176a642ea711ddf22fc43294b062b331`。
- `git ls-remote upstream refs/heads/master` 本轮核实为
  `c6c9bd70aedc503c003110dae10a83ad0bb891d8`，只读比较，没有合并上游。
- 新发现分类：`fork-regression`。`PlayerController._buildSourceResolver` 的旧序号选择来自
  `db7d0df33`；冻结上游的 PlayerController 没有这套续签 resolver。不是本轮上游又改坏播放器。
- 没有连接手机；旧 Android 安装包不等同于当前 master。

## 从取流到呈现重新分层

| 层 | 证据与结论 | 处置 |
|---|---|---|
| 取令牌 | 上游 `c5944dd5` 使用 WUP `getCdnTokenInfoEx`、原生身份与 `sFlvToken`；本地早期优先网页模板 | 当前本地已适配原生 FLV 优先，保留 HLS 独立令牌合同 |
| 连续传输 | 先前受控样本网页连接 120.841 秒 EOF，原生 AL/TX 各读到 420 秒主动结束 | 不再把网页短连接结论套用全部虎牙线路，也不把凭据过期等同于现存连接截止 |
| 客户端重开 | 本地旧 Windows 40 秒提前换播放器制造交接成本 | 健康原生 FLV 只预取；真实故障才恢复，原生缓存有界 |
| 本次新增：续签选线 | 旧列表序号在新列表失去线路身份含义 | 按活动 URL 的 CDN、格式和凭据家族匹配，不按旧序号盲选 |
| 异步所有权 | 前序审计已复现暂停、关闭、快速重进后旧请求仍提交 | 保留 session/intent fence；新增活动 URL 只属于当前请求，不重新引入轮询或重开 |
| 实际呈现 | 之前 Windows 候选 11 分 16 秒没有自动恢复记录；不是逐帧/音频缺口全覆盖 | 本轮确定性验证与外部探针单独记账，不声称所有网络零卡顿 |

上游原始改动与交叉参考：

- [上游 c5944dd5](https://github.com/liuchuancong/pure_live/commit/c5944dd5a529cd93eb29486500abd5d496618f80)
- [上游 Issue 808](https://github.com/liuchuancong/pure_live/issues/808)
- [biliup WUP 编解码](https://github.com/biliup/biliup/blob/master/crates/biliup/src/downloader/live/huya_wup.rs)
- [Streamlink 虎牙插件](https://github.com/streamlink/streamlink/blob/master/src/streamlink/plugins/huya.py)
- [mpv 缓冲合同](https://mpv.io/manual/stable/#options-cache-pause)

引用用于核对合同，不复制其它项目的固定参数或据 Issue 关闭状态推断全部设备通过。
完整旧样本见 [原生取流对照](HUYA_NATIVE_LEASE_FIX_2026_09_05.md) 与
[Windows 实际候选](WINDOWS_HUYA_CANDIDATE_RECHECK_2026_09_05.md)。

## 新错误的第一发生点

真实调用链：`PlayerManager` 预取/错误恢复 → `PlaybackSourceRefreshRequest` →
`PlayerController._buildSourceResolver` → `HuyaSite.resolvePlayUrlsForRecoveryRaw` →
重新加载房间线路、逐条生成 URL、过滤失败项 → 旧 `currentLineIndex` 直接用于新列表。

例：原来 `[AL FLV, TX FLV, TX HLS]`，正在播放序号 1 的 TX FLV。
AL 模板失败被过滤后，新列表为 `[TX FLV, TX HLS]`。旧算法仍选序号 1，即 TX HLS。
此外，显式“下一线路”还会在重排后从错误位置前进，跳过健康 FLV 或再次选中失败 CDN。
这是源选择的确定性错误；它可能把后续恢复带回短连接协议，不把它冒充本次用户每一次停顿的现场证据。

## 修复合同

1. 管理器发送请求时附带**此刻活动 URL**，覆盖预取与故障恢复两条入口。URL 只在内存传递，不输出签名查询。
2. 虎牙优先匹配相同 CDN、端口、媒体路径，忽略续签查询变化；主播重新开播导致流名变化时按同 CDN/格式匹配。
3. 原先使用原生 FLV 时优先保留有效原生 FLV 候选；原生全部失败后仍允许网页 FLV/HLS 后备，不删用户可选项。
4. 用户原来选 HLS 则保留 HLS 格式；只有实际失败、下一线路或对应格式缺失才按候选降级。
5. “下一线路”从匹配后的身份前进；当前 CDN 已被删除时直接使用首个合适后备，不额外跳过一个。
6. 新列表顺序不重排，选线后的 refreshAt/invalidAt 从**实际选中的 URL**读取。
7. 其他平台维持原行为；没有当前身份的旧调用兼容有界序号选择。普通、横屏、小窗、音频共用同一管理器合同。

本次不修改播放器内核、图像比例、弹幕布局、硬件解码和定时器时长；不存在为改选线而主动暂停健康连接的步骤。

## 验证记录

- 生产 PlayerController 的三项新增测试先失败，实际序号分别为 `1/2/1`，期望 `0/1/0`；
  记录 `20260905T135606921Z-quality-focused.json`。前置格式检查/夹具漏参失败属于测试准备错误，不计根因复现。
- 修复后四个目标文件 **149/149** 通过，记录 `20260905T140021141Z-quality-focused.json`。
  其中新增 3 项真实控制器场景、12 项纯策略边界；旧管理器测试补查预取/故障恢复实际活动 URL。
  同时覆盖所选 URL 的租约时间、重排、缺线、流名轮换、native/web/HLS 后备、单线路、无身份、外部域名。
- 完整门禁 `20260905T140742695Z-quality-full.json`：**1070/1070** 单元/Widget 回归，
  **42/42** 接口探测，唯一一次 analyze（46.8 秒）无问题，总耗时 236.278 秒。
  结束活跃重型进程为 0；并发 12，保留缓存，没有 clean。资源峰值工作集 13,262,209,024 B、
  CPU 10.15%，是验证工具开销而非客户端实测占用。
- 结构审计扫描 4,029 个文件，0 错误，保留 31 处 empty-catch 的一项盘点警告；
  此扫描不是逐字语义证明。门禁记录的 source_commit 是修改前 HEAD，实际执行对象包含本次补丁；
  后续提交保存同一业务实现，不把旧 HEAD 标签冒充新安装包来源。
- 外部复验 `20260905T141154951Z-quality-focused.json`：本次实际 Dart HuyaSite 取流、
  PlaybackHeaderResolver 请求头和 LiveBufferPolicy 属性，供给本地锁定的 Windows libmpv；
  房间 660000、TX CDN、请求码率 10000（请求值，不冒充实际平均码率），持续 180.064 秒主动结束。
  解码尺寸 1920×1080、估计帧率 60，EOF=0，暂停采样=0，缓存暂停采样=0，native 丢帧计数=0。
  播放时钟推进 178.678 秒，首次时钟 1377 ms；200 ms 级轮询观察的最大时钟进度间隔 414 ms，
  此数不是视频帧间隔，也不拿它判定可见掉帧或零卡顿。
  请求头经 native typed-node 回读一致，没有保存 token/Cookie/签名 URL。
- 上述 libmpv SHA-256 为 `24e848f59c047c9442501fdbe619ad39b98be7d4dd402691f79931c852c0070a`。
  该独立进程使用软件解码、`vo=null/ao=null`，不测 Flutter 纹理、硬解、屏幕合成或实际可听输出。
  进程 CPU 整机归一平均 0.699%；末次私有字节 222,363,648 B，停止后 43,827,200 B，
  销毁后 35,446,784 B。它验证本探针释放，不代表完整客户端或 Android 的内存上界。
  原始脱敏输出位于 `local-artifacts/huya-current-native-tx-20260905.log`。
- 本轮只有串行本地验证；没有新 APK 构建、签名或上传。GitHub 当前公开最新仍为 2026-09-01 的
  `v3.1.8`，不会把该附件称为包含本次源码修复的新安装包。

## 回滚与发布边界

独立回滚本次线路身份提交即可恢复旧选择行为；不会撤销前序 WUP、缓存、播放意图和录制排空修复。
回滚会重新暴露本节三项可复现错误。3.2.0 仍按总体验收推进，源码推送与 APK 构建/签名/上传分别确认。
