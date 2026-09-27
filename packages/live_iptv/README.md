# live_iptv

v4 的 IPTV 包（纯 Dart，不依赖 Flutter）：M3U / TXT / JSON 播放列表和 XMLTV / JSON 节目单的解析、频道与节目单匹配、回看地址规则、下载器，以及把频道当作“网络电视”平台的 `IptvSite`。行为规格见 [spec/modules/iptv.md](../../spec/modules/iptv.md)，决策见 [docs/adr/draft-iptv.md](../../docs/adr/draft-iptv.md)。

依赖方向：`live_iptv → live_core → live_net`（`tools/gate/check_deps.py` 检查）。存储不在这里：`IptvSite` 通过 `IptvRepository` 读数据，应用把 `live_store` 的 `IptvStore` 接到这个接口上。

## 用法（应用）

```dart
final parsed = parsePlaylistBytes(bytes);          // 按内容识别格式；gzip、BOM、UTF-16 自动处理
store.iptv.replaceEntries(id, [...], syncedAt: now);

final guide = parseGuideBytes(bytes, now: now);    // XMLTV / JSON，只保留前后 2 天
store.iptv.replaceGuide(sourceId, [...], [...], syncedAt: now);

final site = IptvSite(repository, userAgent: () => settings.get(Settings.iptvUserAgent));
site.recommended();                                 // 全部频道，卡片标题是当前节目
site.streams(detail);                               // 每个同名条目一条线路，画质只有“原画”
final channel = await site.channel(ref);
final programmes = await site.guide(channel);       // 前 2 天到后 1 天
site.catchupStreams(channel, programme);            // 回看线路，以非连续直播打开
```

`IptvFetcher` 用 `live_net` 下载播放列表和节目单（平台键 `iptv`，超时 2 分钟，可带自定义 UA）。
