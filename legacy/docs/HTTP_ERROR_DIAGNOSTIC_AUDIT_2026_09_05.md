# HTTP 错误诊断的失败隔离与脱敏

## 来源和首个错误状态

维护分支基线 `d19ca18f`；只读核对冻结的 `upstream/master` 同名
`lib/core/common/custom_interceptor.dart`。归类为 **upstream-existing**，维护分支新增的底层
异常输出扩大了同一缺口。本轮 AcFun 游客凭据接入审查触发复核，影响现有全部共享 HTTP 客户端。

1. 错误回调直接计算 `now - request.extra['ts']`；缺少 ts 或 ts 类型变化时，诊断自己先抛
   TypeError，尚未调用后续 handler，掩盖原始 HTTP 错误。
2. 日志服务尚未初始化、关闭或写入失败时，`Log.e` 抛出的异常同样打断错误交付。
3. 只遮蔽 Cookie/Authorization 两个请求头，但原始 URI、查询、表单、响应体、响应头与
   异常字符串仍可能含签名播放地址、visitor_st、access-token、Set-Cookie 等。列举少数
   Token 名称再做黑名单替换，仍会漏掉新增平台字段。

## 实施

- 诊断和日志出口完全包在失败隔离内；无论日志状态如何，都把原始 DioException 交给下一 handler。
- 缺失、错误、负值、未来 ts 显示时间未知，只有有效毫秒时间参与差值。
- 只输出错误类型、方法、状态码、origin、路径段数和有界字段名/类型/长度。路径、查询值、
  所有头值、请求/响应内容、异常 message/toString 均不进入诊断字符串。
- 这一变更不改变 HTTP 请求、Cookie、代理或播放鉴权参数；只改变本地错误诊断内容。

## 确定性复现

- 初次测试调用 Dio 原始 handler 但没有 pipeline 等待其 Future，夹具额外产生未处理错误；
  该夹具噪声不计产品缺陷。之后用记录型 next handler 验证相同交付合同。
- 修正夹具后 `http-diagnostic-red2-20260905.log` 为 **1 通过 / 4 失败**：敏感信息进入消息、
  null ts、String ts、日志出口抛错。记录 `20260905T034659236Z-quality-focused.json`。
- 修复后 5/5 通过；与 AcFun 18 项协议/适配器测试合并 **23/23 通过**。
  记录 `20260905T035129146Z-quality-focused.json`。未以这些断言推断历史 PiP 黑屏已修复。
- 随后新增大响应体与未来时间戳的有界诊断案例，HTTP 共 6 项；与 AcFun、代理、并发 HTTP
  和 Android 原生 HTTP 相邻测试合并 **34/34 通过**。记录
  `20260905T040118755Z-quality-focused.json`；本轮一次 analyze 错误/警告 0，
  3 项均属于 AcFun 新代码的样式 info，随后按建议等价修正。
- 样式收尾后的 AcFun/HTTP 24/24 再通过，记录 `20260905T040341851Z-quality-focused.json`；
  本轮未重复静态分析，也未追加全量构建。

后续完整交付门禁继续按 3.2.0 验收入口执行；本批不发布新版本。
