# S12 passport Set-Cookie（合成）

没有可用的登录账号，这里不是录制的 `safeAuth` 响应，所以没有 `body.*` 和 `meta.json`。

- Cookie 名称和属性按 `spec/sites/douyu.md` §8 构造，所有值（DID、LTP0、JWT、acf_* 字段）都是合成的；JWT 的签名部分是随机字节。真实响应里 Set-Cookie 的字段组合和属性写法 [待确认]，拿到登录态后应改为录制样本。
- `vectors.json` 的每一项：`input` 是已保存的 Cookie、Set-Cookie 列表、当前时间和保存时间；`output` 是旧版 `DouyuUtils.mergeSetCookieLines`、`sessionExpiry`、`sessionState`、`cookieHeader` 的结果。合并与否按 `DouyuUtils.refreshSession` 的规则：没有 Set-Cookie 就不合并，也不更新保存时间。
- 输出由 `test/fixtures_expected/douyu_test.dart` 在 `PURELIVE_UPDATE_EXPECTED=1` 时写入，平时用来比对。
