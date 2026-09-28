# 平台样本

真实接口的录制样本，用作新旧对照的验收标准。格式和规则见 [ADR 0009](../docs/adr/0009-fixture-format.md)，每个平台要录哪些样本见 `spec/sites/<平台>.md` 第 11 节“样本清单”。

## 目录

```
fixtures/<平台>/<样本编号>-<情况>/
  body.<扩展名>   脱敏后的响应体
  meta.json       请求、状态码、响应头、直连或代理、原始 SHA-256、脱敏记录
  expected.json   旧版解析器的输出（审核后冻结）
```

## 录制

```bash
dart run tools/live_cli/bin/live_cli.dart fixture capture douyu S05-live \
  --url https://www.douyu.com/betard/5526219 \
  -H "User-Agent: <浏览器 UA>" -H "Referer: https://www.douyu.com/5526219"
```

- 登录态放在文件里用 `--cookie-file` 传入，不要写在命令行上。
- 错误响应加 `--allow-error`；海外站点加 `--proxy env`（走 `HTTPS_PROXY`）。
- 脱敏规则在 `tools/live_cli/lib/src/fixture/rules/<平台>.dart`。只要还能在输出里找到任何被替换的原值，工具就拒绝写入。

## 生成和比对期望值

`test/fixtures_expected/<平台>_test.dart` 用生产环境的 Dio（只替换网络适配器）回放样本，调用旧版的解析入口：

```bash
PURELIVE_UPDATE_EXPECTED=1 flutter test test/fixtures_expected/douyu_test.dart   # 写入 expected.json
flutter test test/fixtures_expected/douyu_test.dart                              # 比对
```

`expected.json` 第一次生成后要人工审核再提交。之后它的每次变化都要在提交说明里讲清楚，是平台接口变了还是解析器改了。

## 自己补的期望值

归档时的旧版对照工具只覆盖了前五个平台（哔哩哔哩、斗鱼、虎牙、抖音、快手），3.x 也已经不能构建。其余平台重构时，`expected.json` 由该平台目录下的 `legacy_expected.dart`（Twitch 是 `legacy_expected.py`）生成：它把 v3 对应的解析代码原样搬进一个独立程序，只把网络、设置、日志换成读样本或桩。每个 `expected.json` 的 `generator` 字段写明了来源；生成方法见各平台的模块记录（`docs/modules/M4.*.md`）。
