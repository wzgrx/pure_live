# 斗鱼新源恢复与提交状态审计（2026-09-06）

## 起点与红基线

关联 [Windows GUI 证据](WINDOWS_DOUYU_GUI_AUDIT_2026_09_06.md)：应用 `6babe449` 在 Windows 斗鱼长暂停恢复后依次卡帧、EOF、重试耗尽，房间仍直播；重新进房重新取流才产生新帧。旧会话没有安装平台新地址 resolver，终态错误也只以短时 Toast 呈现。

基于 `1343f3e6` 的确定性跨层红测：`DouyuSite` 实例切线路仍直接复用旧 URL，fresh 解析计数期望 1、实际 0。`20260905T233416349Z-quality-focused.json`，**18 通过 / 1 失败**，81.286 秒，结束活跃重型进程 0。此处稳定复现的是恢复能力缺口，不宣称已经区分 URL 到期、连接回收与 CDN 策略。

## 实现与状态所有权

- Douyu 实现 `LivePlayRecoveryResolver`：重新获取画质/CDN 元数据，使用当前实际档位请求新签名 URL；服务端降档或未确认结果原样进入既有确认映射。未新增无界轮询，也不因服务端降档直接丢弃可播放新源。
- `PlaybackSourceRefreshRequest.currentQuality` 使用 Manager 当前源 cohort 的档位，替代最初路由闭包永久捕获的档位；resolver 只计算结果，不直接改界面。
- `PlaybackSourceQualitySelection` 以不可修改的列表携带已映射档位及未确认标记；`PlaybackSourceRefreshResult.selection` 经 prefetch、普通打开、Windows 首帧门禁 warm-swap 传递。
- Manager 将内部正在尝试的 URL cohort 元数据与已成功提交的 `PlaybackSourceCommitSnapshot` 分开。首个新地址打开失败后，后续同 cohort 的线路/引擎恢复继承对应档位，而不是沿用旧源标签。
- 只在真正成功的源提交出口替换 canonical snapshot 并发布事件。候选取消、错误、回滚、过期请求不发布成功；换引擎后直接打开当前源的成功出口也在合同范围内。
- VideoController 先订阅再读取 canonical snapshot；保留会话路由重入可补收路由离开期间的提交，随后持续监听。新建非复用会话在自己的 `play()` 之前不回放旧的同房源；关闭、取消监听、过期 revision 和非当前 snapshot 均隔离。
- PlayerController 原子更新画质列表、当前档、URL 和线路；真正 native commit 优先于更早的手动请求 payload，后续展示异常也不把新源状态滚回旧标签。
- 应用内小窗交接缓存合并最新 canonical 元数据；消耗一次交接 token 不清掉当前源真相。暂停不令同源标签失效；音频模式是独立状态，交接取 Manager 当前 desired audio-only，而非历史 source snapshot 的布尔值。

## 验证状态

八组定向回归全部通过：`20260906T000029899Z-quality-focused.json`，351.727 秒，结束活跃重型进程 0。一次 analyze 146.8 秒无诊断。测试范围包含恢复/音频模式、跨层选源、斗鱼解析/确认、录制游标、新真实 VideoController 监听夹具和加载代次。用户输入到达后原终端句柄已结束；通过持久化成功记录核实结果，未为找回测试计数重复运行。独立接线审查未发现阻断问题。

## 剩余验收

终态持久错误/重试界面仍需独立修复；之后用包含本次源码的新 Windows 候选重验长暂停、小窗往返和 UI 响应。旧录制文件解码通过和旧候选的局部 GUI 成功不能替代新实现验收。当前没有手机操作、上游合并或 3.2.0 正式发布。
