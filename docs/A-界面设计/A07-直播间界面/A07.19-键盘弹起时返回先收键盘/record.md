# A07.19 直播间里键盘弹起时，返回先收键盘：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区 `ai/A07.19`（从 master `8ccb5a053` 开始）
- 设计或说明：[README.md](README.md)

## 做了什么

- `apps/pure_live/lib/features/live_play/logic/predictive_back.dart`：`_handle` 先看 `_keyboardUp()`（任一窗口底部有键盘，且主焦点在 `EditableText` 里），是就 `unfocus()` 后返回，不调直播间的返回。

## 根因

见 README：直播间的原生返回回调是 overlay 优先级，排在输入法前面。

## 测试

- `room_extras_test.dart`“A07.19 back with the keyboard up only closes the keyboard…”：改之前失败（第一次返回就交给了直播间）；改后 `room_extras_test.dart` 14 个全过。

## 真机

待 K90：见 README“验证”。

## K90 复查（2026-10-08，master a3b799737）

- 本地弹幕框输入 hello，返回一次：键盘收起，还在直播间 ✓。
- 切换直播间 → 筛选框弹键盘，手势返回一次：只收键盘，面板还在 ✓；再返回一次关面板，还在直播间 ✓。
