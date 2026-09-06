# 录制中转代理接入审计（2026-09-06）

## 缺口与修复

API、弹幕和图片已有代理配置，但 HLS/FLV 录制中转各自创建的
`dart:io.HttpClient` 没有设置 `findProxy`。应用代理打开时，录制上游仍走直连。

新增独立的录制代理回调，在应用服务初始化后接入现有应用代理设置。
HLS 清单及分片、FLV 上游请求使用此回调；FFmpeg 到本地中转的连接保持直连。
回调读取实时设置，不复制过期配置；默认或关闭代理时为 DIRECT。
HTTPS 证书验证、请求头过滤、停止排空与超时策略保持不变。
本次覆盖 HTTP(S) HLS/FLV 中转，不宣称其他原生输入协议已有代理支持。

## 验证

- 新增本地 HTTP 代理夹具，上游指向没有服务的回环端口，证明请求必须经代理成功。
- 修复前：1 项通过、2 项失败。FLV 返回 502；HLS 请求失败并超时。
  记录：`local-artifacts/build-records/20260906T012645718Z-quality-focused.json`。
- 修复后：3 个测试文件共 **23 项通过**；完整静态分析 **No issues found!**（129.9 秒）。
  记录：`local-artifacts/build-records/20260906T013054050Z-quality-focused.json`。
  日志：`local-artifacts/recorder-proxy-green.log`。
- 另外修正 SUBST 脚本测试对可选 Hashtable 键的点访问：严格模式下原报错
  `The property 'Throws' cannot be found on this object.`，改用键索引后前置检查通过。

## 剩余验收

Soop 先前 Android 录制没有字节增长，与本缺口相符但尚无同因证明。
新代码尚未构建安装；需要新候选包验证代理下的 Soop 录制、正常结束与产物解码。
若仍失败，先采集活动 FFmpeg 会话诊断，再结束应用，保留首次失败状态。
此结果不是全部平台验收通过或 3.2.0 正式发布证据。
