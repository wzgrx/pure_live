# S07 签名向量（合成）

离线生成，不是录制的接口响应，所以没有 `body.*` 和 `meta.json`。

- `vectors.json` 的每一项：`input` 是合成的加密描述符 + rid + tt + did（+ rate、cdn），`output` 是旧版 `DouyuUtils.buildSignedData` 生成的表单，以及 `DouyuUtils.isEncryptionKeyUsable(nowSeconds: tt)` 的结果；描述符不可用时记录抛出的异常。
- 第一项是 `spec/sites/douyu.md` §6.2 的测试向量（auth `1834439993932d590bceb2593c1c0cd0`）。
- 输入是手写的合成值；输出由 `test/fixtures_expected/douyu_test.dart` 在 `PURELIVE_UPDATE_EXPECTED=1` 时写入，平时用来比对。
