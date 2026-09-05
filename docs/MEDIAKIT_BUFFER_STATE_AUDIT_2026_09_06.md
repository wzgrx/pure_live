# MediaKit 缓冲状态合同修复

## 范围与来源

应用源码基线 `3377ce300dfe254049e45b5eb0252bf0c17aeda1`；指令/工作流独立提交为 `ed8cc46975b69b6127493ebcc544cd338ac4239f`，不改变本次播放器代码。只读比较冻结上游 `c6c9bd70aedc503c003110dae10a83ad0bb891d8`，没有合并上游或操作手机。

本项接续 `HUYA_BUFFERING_DEADLINE_2026_09_06.md` 的适配器待查项。来源为 **fork-regression**：原生播放状态通知清除 loading 的路径由 `9e2cfa59b` 引入；首帧相关路径来自 `8738d391b`，后续去重仍保留相同错误。冻结上游的 playing 回调只更新播放值，并在 loading 为 false 时发布 playing/paused，没有在该回调无条件清除 loading。

## 根因与修复

`playing=true` 表示播放器处于播放意图/状态，并不保证当前有足够输入媒体。缓存尾帧、音频参数、打开请求返回也不等于 demux 缓冲已经结束。

旧 MediaKitAdapter 在这些路径写入 loading=false，会让 PlayerManager 提前取消持续缓冲监控。上一项修复仅保留计时器的最初期限，还不足以抵挡这个下层错误。

本次改动：

1. `_publishMediaProgressState` 统一读取原生 `state.buffering`，播放事件和媒体就绪保留各自作用，缓冲未结束时不提前清除 loading。
2. 成功 open 和视频/音频就绪快照使用同一状态合同。继续支持 Android 缺少可选首帧属性时的正常 playing 事件，不额外等待某个可选属性。
3. `setDataSource` 的旧请求 finally 必须仍拥有来源代次，避免旧 open 完成后修改新来源状态。
4. PlayerManager 的 open 完成分支保留当前 buffering；成功打开请求不再覆盖为 ready。

未修改 Huya 凭据、CDN 排序、几何/弹幕布局、默认缓存大小、重连次数或正常播放器数量。这是跨平台共用适配器修复；设备渲染表现仍分别验收。

## 确定性复现

`MediaKitAdapter.headlessForTest` 注入媒体事件源，实际执行生产适配器的 setDataSource、来源栅栏、事件绑定、快照与释放；不是在假适配器中重写同样逻辑。受控媒体状态遵循锁定 media_kit 的顺序：先更新 PlayerState，再发送事件。

`test/media_kit_buffering_state_test.dart` 八个场景：playing 切换、视频尾帧、音频尾帧、open 快照、Manager 完成状态、无可选元数据、换源自行恢复、旧 open 延迟结束。原始有效红基线四个场景全部失败；修复适配器后剩余 Manager ready 覆盖单独失败，再修复管理层。早期两个测试接口编译错误仅为夹具开发错误，不计为产品复现。

- 红基线：`local-artifacts/media-kit-buffer-red3.log`，`20260905T201146909Z-quality-focused.json`。
- 中间验证：`local-artifacts/media-kit-buffer-green1.log`，7 通过、1 失败（Manager ready 覆盖）。
- 修复后适配器 + 管理器恢复回归：**99/99**，`20260905T202241607Z-quality-focused.json`。

## 实际原生事件链验证

`tool/probes/media_kit_buffering_probe_test.dart` 将实际 media_kit NativePlayer/libmpv 接入生产适配器，无 Widget 纹理或扬声器输出。仅使用 FFmpeg 合成的色彩图/正弦音 FLV，由 loopback 按原始 DTS 输送；12 秒位置停发 2.4 秒后补发，字节和媒体时间戳保持原样。

显式环境参数：`PURELIVE_BUFFER_PROBE_LIB` 指向已核验候选的 libmpv DLL；`PURELIVE_BUFFER_PROBE_MEDIA` 指向 `local-artifacts/huya-synthetic-jitter.flv`。探针不连接 CDN，不改应用缓存默认值，未设置环境时跳过。

实际结果 `local-artifacts/media-kit-native-buffer2.log` / `20260905T203819249Z-quality-focused.json`：

- 32 秒观察，单次连接，注入完成，没有完成/EOF 状态；播放位置超过 20 秒。
- 原生运行中 buffering 12.780–14.566 秒，约 **1.786 秒**；适配器 12.781–14.566 秒，跟随原生，错误提前清除计数为 0。
- 输入恢复后原生与适配器均退出 buffering；finally 关闭媒体、订阅及 loopback 服务。
- 门禁耗时 61.283 秒，结束活跃重型进程 0。记录里的 CPU/工作集是整个验证进程组，不是客户端性能测量。
- 首次门禁因未格式化的新探针停止，未运行测试；格式化后完成本次成功运行。

该结果证明实际原生事件通过当前适配器正确传播，不证明任意网络间断都没有画面停顿。之前相同输入间断/缓冲余量实验仍有效；不以隐藏 loading 图标代替媒体连续性。

## 验收与回滚

最终全 test 目录 **1114/1114**，记录 `20260905T204149609Z-quality-focused.json`，180.745 秒、结束活跃重型进程 0。本轮一次 analyze 用时 38.1 秒，无错误；对 tool/probes 中测试接口调用的一项可见性提示已加有说明的局部注释，未改生产行为或重跑分析。该提示及证据层级同步记入 `ACCEPTANCE_3_2_0.md`。3.2.0 完整 UI/安装包/多平台验收继续进行。当前公开 APK 和旧 Windows 候选不包含本次源码改动。

独立回滚本次适配器、Manager 完成状态、测试/探针即可；保留此前 WUP 凭据、健康连接不定时重开和缓冲计时期限修复。没有设置键、存储格式或数据迁移变化。
