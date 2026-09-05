# 虎牙录制凭据与停止收尾审计（2026-09-05）

## 基线、来源与问题拆分

- 本地基线 `81433454c6f1694bd86101e1e2327d350cea5af3`；上游只读参考
  `c6c9bd70aedc503c003110dae10a83ad0bb891d8`，本批没有合并上游。
- `RecorderController._scheduleRecorderLeaseRefresh` 的定时断开来自维护分支
  `db7d0df33`；冻结上游也包含此段代码。按最初来源归为 `fork-regression`，
  不是仅因上游目前也有相同代码就把责任归为上游。
- 另一个问题是原生取消导致文件尾写入中断，封装却继续接受损坏数据并删除 TS。
  这是独立的原生取消/输出完整性合同问题，不把它当成同一次凭据刷新故障。

## 1. 健康连接被计时器主动结束

旧链路：取流地址 `refreshAt` → 预取地址 → 到刷新时刻执行 `refreshLease` →
`FFmpegKit.cancel` → 结束当前输入/封装 → 再打开新输入。先前 GUI 录制的约 270 秒
尝试边界与该策略一致，但单凭时间一致还不足以解释输出损坏。

已有长读对照证明原生 WUP FLV 的凭据期限是新建连接的期限，并非已连接媒体的强制结束时间，
见 [原生凭据对照](HUYA_NATIVE_LEASE_FIX_2026_09_05.md)。播放管理器已按此区分，
本次找到录制控制器仍保留旧的统一定时取消策略。

### 修复

1. 使用共享 `HuyaTransportPolicy.hasNativeFlvCredential` 精确识别虎牙原生 FLV，
   只预取后续恢复地址，不主动取消正在增长的录制。
2. 网页 FLV、HLS、其他平台原有租约策略保持；只凭 `ctype`、忽略域名/扩展名的匹配不成立。
3. 预取完成后按下一凭据期限安排一次后续维护，失败/缺失/过期元数据设 30 秒最短间隔，
   防止定时器立即重入；每个任务最多一个当前预取请求和一个未来定时器。
4. 任务对象、原生会话、源 URL 和异步请求身份共同决定所有权；停止、删除/替换同 ID 卡片、
   新会话、控制器销毁后，旧异步结果不再缓存或重新排队。
5. 真正 EOF/访问失败时保留仍有效的预取地址；使用前再次检查来源 URL、期限和线路语义。
   过期地址重新解析，用户手动停止仍保持停止。

### 确定性证据

`test/recorder_lease_lifecycle_test.dart` 使用实际 RecorderController、调度器、Hive 和缓存，
只替换网络/原生执行边界，而不是测试另一个复制的策略实现。

- 旧生产代码红测：5 通过、4 失败，记录 `20260905T105048016Z-quality-focused.json`。
  实际复现健康原生连接被取消、预取失败仍断开、EOF 删除预取导致额外请求、旧卡片计时器仍生效。
- 修复后第一组相邻回归 54/54：`20260905T105317962Z-quality-focused.json`。
- 后续新增新会话隔离和维护间隔边界；真实探针运行前 19 项确定性测试通过。
  最终模块门禁单列，不将旧通过数当成后来新增代码的结果。

## 2. 连续录制成功，但手动停止损坏文件尾

真实探针 `tool/probes/huya_recorder_continuity_probe_test.dart` 使用公开房间 660000、AL 原画：

- 房间信息从官网引导；探针固定线路，由实际 `HuyaSite.getPlayUrl` 取得 WUP 地址；
  真实 RecorderController、请求头、FFmpegKit、输出采样和 MP4 收尾均参与。
- 325 秒观察期中 1 次 native start、0 次租约取消，凭据解析 2 次；所有逐秒样本均为 running。
- 到用户停止生成 2 个原始 TS：65,798,120 B 和 **3,145,728 B**；后者长度除 188 余 144，
  最后一个 MPEG-TS 包未写完整。MP4 生成 64,649,817 B，原生封装退出码仍是 0。
- 日志明确出现 `error writing trailer: immediate exit requested`，然后封装输入报
  `pes packet size mismatch` / `corrupt input packet in stream 1`。
- 独立 FFmpeg 对完整 TS 和完整 MP4 解码都失败（-1094995529）；MP4 尾部 AAC 报
  `Input buffer exhausted before END element found`。错误接近 329 秒媒体尾部。
- **整轮结果仍为 FAIL**：`20260905T110429901Z-quality-focused.json`，408.292 秒，
  结束活跃重型进程 0。连续捕获通过不覆盖文件完整性失败。

原始证据保留于 ignored `local-artifacts/recording-probes/huya-controller-1788605898749307/`。
探针在真实终止事件交给控制器前复制 TS，稍延后封装；未改变停止调用或原生输入。
官网引导的固定线路不等同完整 UI 搜索/选线流程，也不代表 Android 原生验收。

### 原生源码核对

已安装 Dart 包为 `ffmpeg_kit_extended_flutter 0.6.2`，Windows native builder 为 `0.11.1`。
其发布 tag `v0.11.1-windows` 对应 `4dc903c2a29741b8f9b61dd94b10185bae69a493`。
原生 `decode_interrupt_cb` 在 session cancel 后直接返回 1；输出上下文也设置同一中断回调。
FFmpeg segment muxer 把输出回调传给分片。因此取消请求会同时阻止输入读取和输出尾部写入，
与本机实际错误一致；并非已证明虎牙服务器主动发送损坏包。

参考：
- [锁定 native 版本的中断回调](https://github.com/akashskypatel/ffmpeg-kit-builders/blob/4dc903c2a29741b8f9b61dd94b10185bae69a493/FFmpegKit/src/ffmpeg.c)
- [FFmpeg segment 输出上下文](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/segment.c)
- [FFmpeg streamcopy 文档](https://ffmpeg.org/ffmpeg.html#Streamcopy)：复制封装不进行完整解码，
  所以退出码 0、MP4 可读、文件大小增长都不是完整比特流正常的充分证据。

### 处置与后续门禁

先阻止已知损坏被误报成功并删除唯一 TS，再单独修复原生停止时的输入中断/输出排空。

实际保留的首段与末段复制到独立目录，通过真实 `VideoProcessorService` 重做封装，
不读取网络、不操作原始证据、不伪造 FFmpeg 返回值：

- 旧实现红测 `20260905T111400136Z-quality-focused.json`：7 通过、2 失败，
  截断输入仍返回 true、产生 MP4 并删除 TS。之前两轮格式门禁失败没有执行行为测试，
  不计入行为复现。
- 仅增加 FFmpeg `-xerror` 后依然复现：`20260905T111508070Z-quality-focused.json`，
  8 通过、1 失败。该 native 构建仍打印 corrupt input packet 并返回 0；
  因此没有把“加了严格参数”当成修复已成立。
- 加入每个 native session 的完整性错误锁存后，`20260905T111741345Z-quality-focused.json`
  16/16 通过：完整输入成功且收尾，截断输入返回 false、源 TS 保留、没有提交 MP4，
  两次操作所有权均释放。
- 锁存只识别明确的 PES/packet/trailer/demux/mux 错误，不把全部 warning 判失败；
  日志环形尾部被后续正常行覆盖也保持该会话错误结论，新会话不继承。
  仅显式 `-xerror` 的严格输出任务应用该判定，普通录制/播放结束策略不被连带覆盖。
- 保留严格命令参数供正确传播该选项的 native 构建使用，但独立诊断判定才覆盖本机已复现缺陷。

这些改动解决“损坏录制误报封装成功并删源”，**尚未修复取消本身的尾部截断**。
不通过忽略损坏包、裁掉文件尾、增加缓冲或定时重连来掩盖缺失内容。
修复停止合同须包含本地确定性输入的正常 EOF/手动停止/网络停滞/重复停止/多任务隔离，
以及真实录制原始 TS 和 MP4 全文件独立解码；只验证改过参数的命令字符串不够。

## 影响范围与回滚

最终模块门禁 `20260905T112011513Z-quality-focused.json`：**207 通过、1 个显式未启用的
325 秒联网探针跳过**，覆盖 26 个录制/FFmpeg/封装/虎牙测试文件和 2 个 opt-in 探针。
其中保留源文件的真实 native 重封装再次通过；不把跳过的连续联网探针列为此次通过。
本批 analyze 仅一次（38.1 秒），0 error、2 个 `visibleForTesting` 路径提示：
探针位于 `tool/probes` 而非 `test`。已在两处有意依赖注入调用添加带原因的局部抑制；
没有修改生产可见性或全局关闭规则，没有虚构第二次 analyze 结果。
记录的源码是 `81433454` 加本批工作树，业务变更与随后提交一致；不是新的安装包证据。

本批不更改播放器渲染、比例、弹幕、主题、暂停意图或 UI；原生 FLV 录制减少多余会话重建。
没有新增依赖、永久凭据缓存、设备操作、全平台构建或 3.2.0 Release。
回滚本批提交会恢复原先定时取消和原有封装行为，保留此前独立播放器修复。
手动停止损坏、完整客户端资源释放、其他验收缺口仍按各自证据推进，未承诺全部场景零卡顿。
