# 0003 平台分批与去留标准

- 状态：已接受
- 日期：2026-09-27

## 背景

v3.2.11 有 33 个直播站点加 IPTV。诊断（[diagnosis/01-sites.md](../rewrite/diagnosis/01-sites.md)）显示两代代码并存：老 9 站从上游移植，依赖 GetX 和界面层；新 24 站是 2026-09 自研，已按 `*_api / *_link / *_site` 拆分，只剩 i18n 一处依赖。维护热点集中在 B 站、斗鱼、虎牙、抖音、快手、CC、Twitch；15 个站两个月内只有 1–2 次提交。所有签名算法都是纯 Dart，只有 Twitch 依赖 WebView 和原生 TLS 通道。

## 决定

| 批次 | 平台 | 时间 | 前提 |
|---|---|---|---|
| 第一批 | bilibili、douyu、huya、douyin、kuaishou | 第 4 阶段 | 录制样本和冻结的期望值 |
| 第二批 | cc、yy、soop、acfun、twitch | 第 7 阶段前段 | Twitch 需要 `live_net` 提供平台 TLS 接口和可选的浏览器校验接口 |
| 第三批 | chzzk、missevan、kilakila、inke、picarto、twitcasting、showroom、pandalive、17live、liveme、steambroadcast、sixroom、kugoulive、jdlive、baidulive、looklive、weibo | 第 7 阶段 | 以新一代结构为模板批量迁移 |
| 会话型 | niconico | `live_media` 完成后 | 会话输入经本地中继 |
| 候选下线 | tiktok、youtube、bigo、fc2live | 第 7 阶段评估 | 见下方标准 |
| 仅链接 | xiaohongshu | 第 7 阶段 | 保留分享链接打开，不做目录 |
| 不再算站点 | iptv | 第 6 阶段 | 移出 `live_core`，作为独立的本地数据源模块，沿用现有数据库 |

**下线标准**：第 7 阶段起每日探针连续运行 14 天，满足任一条即下线：
1. 取流成功率低于 50%；
2. 需要应用不支持的登录才能观看；
3. 没有公开目录，且只能靠链接进入、链接又不稳定。

下线沿用 3.2.8 的做法：关注和历史保留并标记“已下线”，分享链接提示已下线。

**数据原则**：迁移进度落后的平台，关注和历史原样保留，标记为“暂不支持”，随备份导出；首批只做 5 个平台，不能成为删除数据的理由。

## 备选方案与放弃理由

- 33 个平台同时迁移：验证工作集中在后期，架构问题暴露太晚。
- 按用户量排序：应用不收集使用数据，没有可靠依据；改用维护成本和探针结果。

## 影响

- 第 4 阶段只需要为 5 个平台录制样本。
- 第 7 阶段需要每日探针，这也是 CI nightly 的一部分。
