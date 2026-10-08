# 平台样本

真实接口的录制样本，用作新旧对照的验收标准。脱敏和门禁规则见 [ENGINEERING.md](../docs/specs/ENGINEERING.md) 第 3 节“安全”和 `tools/gate/check_fixtures.py`；每个平台录了哪些样本、为什么录，见 [E 组](../docs/E-直播平台/README.md)各平台任务的说明和记录。

## 目录

```
fixtures/<平台>/<样本编号>-<情况>/
  body.<扩展名>   脱敏后的响应体
  meta.json       请求、状态码、响应头、直连或代理、原始 SHA-256、脱敏记录
  expected.json   旧版解析器的输出（审核后冻结）
```

## 录制

master 上的 `tools/live_cli` 现在只有 `probe` 和 `patrol`（E07.1）；录样本的 `fixture capture` 命令还没取回，在归档标签 `v4-archive` 的 `tools/live_cli/lib/src/fixture/`。在它取回之前，样本按下面“手工补录”一条手工写 `body.*` 和 `meta.json`。归档工具的用法是：

```bash
dart run tools/live_cli/bin/live_cli.dart fixture capture douyu S05-live \
  --url https://www.douyu.com/betard/5526219 \
  -H "User-Agent: <浏览器 UA>" -H "Referer: https://www.douyu.com/5526219"
```

- 登录态放在文件里用 `--cookie-file` 传入，不要写在命令行上。
- 错误响应加 `--allow-error`；海外站点加 `--proxy env`（走 `HTTPS_PROXY`）。
- 每个平台的脱敏规则在归档标签 `v4-archive` 的 `tools/live_cli/lib/src/fixture/rules/<平台>.dart`，手工补录时照着做。归档工具在还能从输出里找到任何被替换的原值时拒绝写入；手工补录时自己检查一遍。
- 有些平台会在响应头里回显调用方的地址（`x-real-ip`、`x-ksclient-ip`、`xhs-real-ip`，百度的 `x-bfe-svbbrers` 是 Base64）。归档的规则漏过几处，录制时的真实出口地址进了 git，已在 2026-09-28 换成 `203.0.113.7`。现在门禁的 `fixture privacy`（`tools/gate/check_fixtures.py`）检查所有 JSON 样本：名字表示客户端地址的字段，只要含有保留段和文档段以外的 IPv4（明文或 Base64），就不通过。服务端地址（负载均衡、CDN 节点）不算。
- 手工补录或改动样本后，同样要换掉访客编号、设备编号、令牌和 Cookie 值，改成同形的合成值，并记进 `meta.json` 的脱敏记录。
- 2026-09-30 起门禁也检查弹幕帧（`*.jsonl`，逐行）：帧文字里、字符串里套着的 JSON 里、Base64 载荷里（gzip、zlib 会先解开）的客户端地址字段；地址写成 32 位整数也算（BIGO 登录回答的 `clientIp` 是小端整数的十进制，M5.20 发现，已换成 `3362010054`，即 198.51.100.200）。整数的两种字节序只要有一种落在保留段或文档段就放过，所以合成值要用文档段。
- 弹幕帧是二进制（`frames.jsonl` 里的 `b64`）时，没有字段名的内容门禁仍然看不到。有的协议会在二进制里回显调用方地址，例如 YY 的 AP 登录回答（M5.6 发现，已换成 `203.0.113.7`，并有测试守着）。录制或补录弹幕帧后，要按协议逐个字段检查，把地址、用户编号、头像路径这类标识换成同形同长度的合成值。

## 生成和比对期望值

归档标签 `v4-archive` 里的 `test/fixtures_expected/<平台>_test.dart`（master 上没有）用生产环境的 Dio（只替换网络适配器）回放样本，调用旧版的解析入口：

```bash
PURELIVE_UPDATE_EXPECTED=1 flutter test test/fixtures_expected/douyu_test.dart   # 写入 expected.json
flutter test test/fixtures_expected/douyu_test.dart                              # 比对
```

`expected.json` 第一次生成后要人工审核再提交。之后它的每次变化都要在提交说明里讲清楚，是平台接口变了还是解析器改了。

## 自己补的期望值

归档时的旧版对照工具只覆盖了前五个平台（哔哩哔哩、斗鱼、虎牙、抖音、快手），3.x 也已经不能构建。其余平台重构时，`expected.json` 由该平台目录下的 `legacy_expected.dart`（Twitch 是 `legacy_expected.py`）生成：它把 v3 对应的解析代码原样搬进一个独立程序，只把网络、设置、日志换成读样本或桩。每个 `expected.json` 的 `generator` 字段写明了来源；生成方法见 [E 组](../docs/E-直播平台/README.md)各平台任务的记录。
