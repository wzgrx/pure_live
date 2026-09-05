# AcFun 接入合同与实施记录

## 基线与决策

- 维护分支基线 `d19ca18f91a61428010191a66a46908cd849cdd5`，本轮不合并上游。
- 参考 biliup `906e0f6fdb104d65989d12b76c9a6f02205384cb` 的游客会话和 startPlay 分层；
  用本项目 Dart 实现，不照搬“所有非成功结果均是下播”或“数组末项就是最高画质”的假设。
- bililive-go OPENREC 页面正则实现只作参考；当前公开 API 经系统网络及显式 Clash
  `127.0.0.1:7897` 均返回 HTTP 403。此为当前网络样本，不等于站点永久失效。
- AcFun 是新增适配，不是旧平台替换；正式加入导航前需要完成目录、分类、搜索、房间、
  画质、在线指标、远端弹幕能力说明、播放/录制和地址入口的集成验收。

## 公开接口实际观测

2026-09-05，从官方页面当前 `app.621a5146.js` 核对目录及房间路径，再发出只读请求：

| 合同 | 实际结果 |
|---|---|
| `GET live.acfun.cn/api/channel/list` | `channelListData.result=0`，`liveList`、`count`、`pcursor`、`totalCount`；count=2 的连续两页不同房间，游标依次 1、2 |
| `GET live.acfun.cn/api/live/info?authorId=...` | 在播返回当前 `liveId`、`streamName`、user、onlineCount、portrait；未开播的有效用户返回 result=0、authorId、user，没有 liveId/streamName |
| `POST id.app.acfun.cn/rest/app/visitor/login` | Cookie 中临时 `_did`，表单 `sid=acfun.api.visitor`；result=0 返回 userId 与临时 visitor_st |
| `POST api.kuaishouzt.com/rest/zt/live/web/startPlay` | 绑定同一 did/userId/visitor_st，表单 authorId、pullStreamType=FLV；result=1，videoPlayRes 为嵌套 JSON 字符串 |
| 清晰度 | 本次房间有 STANDARD/HIGH/SUPER/BLUE_RAY，码率 1000/2000/4000/8000；稳定质量 ID、level、name 与 URL 分开处理，跨 manifest 合并同质量线路 |
| 指标 | onlineCount 是当前在线字段；likeCount 是点赞数，绝不冒充热度或在线人数 |

凭据仅用于内存中的游客会话，审计不保存 Token/Cookie、签名播放地址或页面反射的 IP。
`reverse-api-engineer` 0.13.0 / schema 1 的 dry-run 通过，但报告未配置默认 SDK 环境密钥；
没有启动其浏览器代理或声称取得 HAR。本轮来源是参考源码、官方静态脚本与直接 HTTP 合同核对。

## 实施门禁

1. 网络错误、异常 JSON、缺字段、403/429/5xx 保持错误/未知，只有有效房间元数据证明离线时才返回下播。
2. 游客会话短期单飞复用；失败清空本次认证缓存，凭据不进入持久化模型。
3. 不隐藏质量降级；续签重新读取当前 liveId 和质量表，质量消失时明确失败，由上层已有选择逻辑处理。
4. 网络错误诊断先修复脱敏缺口：现有共享拦截器只遮蔽两个请求头，仍会输出签名查询、请求体、响应体和原始异常；此外缺少 ts 时诊断自身可抛出错误。归类与回归另记。
5. 新增平台先完成协议/适配器的确定性测试和真实公开流读取，再集成 UI 与录制入口；未完成的能力如实保留，不把空弹幕实现称为连接成功。

## 验证

已加入 `acfun_api.dart` 与 `acfun_site.dart`：游客单飞/短期复用、目录游标、严格房间状态、
质量稳定 ID、多 CDN 合并、服务器 level 与码率量纲隔离、同质量重新取流以及录制元数据入口。
旧房间中的地址不会被续签原地改写；已选画质消失会明确返回质量不可用，不悄悄降级。

- 18 项 AcFun 确定性案例，与 5 项 HTTP 诊断回归合并 23/23 通过：
  `20260905T035129146Z-quality-focused.json`，43.424 秒，结束后重型进程 0。
- 生产适配器的公开网络探针：`tool/probes/acfun_public_contract_probe_test.dart`，通过显式
  Clash 代理取得 2 个目录房间、4 档画质。BLUE_RAY / 蓝光 8M 连续读取 8001 ms、
  13,799,705 B；STANDARD / 高清读取 8073 ms、2,531,207 B；均为 FLV 文件头且在主动
  限时结束前持续有数据，同一质量重新取流成功。记录
  `20260905T035711137Z-quality-focused.json`，完整工具阶段 58.049 秒，结束后重型进程 0。
- 首次探针仅发生 Dart 请求头回调类型编译错误，没有发出网络请求；修正探针后再运行以上
  成功样本，不把工具编译错误归为平台缺陷。
- 该网络探针验证**本项目生产解析器与流输入**，不等于画面渲染、实际分辨率/帧率、
  FFmpeg 录制文件收尾或后台长时验收。八秒读取包含起始缓冲，不拿字节速率证明平台标签的码率。
- 本轮没有新增依赖、APK、入口或宣称远端弹幕已支持；新平台尚未进入默认导航。
- 与共享 HTTP、代理路由、并发探测和 Android 原生 HTTP 合同合并回归 **34/34 通过**；
  一次静态分析错误/警告 0，3 项空值元素/花括号样式 info 已等价修正。
  记录 `20260905T040118755Z-quality-focused.json`，130.471 秒，analyze 66.3 秒，
  结束后活跃重型进程 0。该记录对应 `d19ca18f` 基线加本批工作树，不冒充最终干净提交。
- 样式收尾后 24/24 新增合同与 HTTP 测试再通过，未重复 analyze：
  `20260905T040341851Z-quality-focused.json`。签名、APK 和全仓最终交付门禁仍为后续阶段。

复跑（串行本地质量门禁，环境变量仅存在于当前进程）：

```powershell
$env:PURELIVE_ACFUN_LIVE_PROBE='1'
$env:PURELIVE_PROBE_PROXY='http://127.0.0.1:7897'
.\tool\local_ci.ps1 -Scope Focused -SkipPubGet -TestPath tool/probes/acfun_public_contract_probe_test.dart
```

后续集成仍须完成：目录页码与游标衔接、官网分类和搜索合同、分享 URL、Sites/设置迁移、
播放与录制头、在线人数能力登记、远端弹幕能力说明及相邻 UI/录制/模式往返验收。
此阶段不替代整个新平台交付要求。

参考：[biliup AcFun](https://github.com/biliup/biliup/blob/906e0f6fdb104d65989d12b76c9a6f02205384cb/crates/biliup/src/downloader/live/acfun.rs)、
[bililive-go OPENREC](https://github.com/bililive-go/bililive-go/blob/ef71711a7c573b013d82fec01ee8d0609ee36aca/src/live/openrec/openrec.go)。
