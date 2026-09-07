import 'package:flutter/services.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/modules/toolbox/toolbox_action_scope.dart';

class ToolBoxDirectLinkFlow {
  ToolBoxDirectLinkFlow({LiveSite Function(String)? siteFor, Future<void> Function(String)? copyText})
    : _siteFor = siteFor ?? ((platform) => Sites.of(platform).liveSite),
      _copyText = copyText ?? ((text) => Clipboard.setData(ClipboardData(text: text)));

  final LiveSite Function(String) _siteFor;
  final Future<void> Function(String) _copyText;

  Future<void> run({
    required LiveRoom room,
    required ToolBoxActionScope scope,
    required Future<LivePlayQuality?> Function(List<LivePlayQuality>) chooseQuality,
    required Future<String?> Function(List<String>) chooseLine,
    required void Function(String) notify,
    Future<void> Function(String)? useUrl,
  }) async {
    scope.checkActive();
    final site = _siteFor(room.platform!);
    final detail = await scope.wait(() => site.getRoomDetail(roomId: room.roomId!, platform: room.platform!));
    final qualities = await scope.wait(() => site.getPlayQualites(detail: detail));
    if (qualities.isEmpty) {
      notify('toolbox_quality_failed');
      return;
    }
    // User choices have no timer. Only network/platform operations are timed.
    final quality = await scope.wait(() => chooseQuality(qualities), timed: false);
    if (quality == null || !qualities.contains(quality)) return;
    final urls = normalizeResolvedPlayUrls(await scope.wait(() => site.getPlayUrls(detail: detail, quality: quality)));
    if (urls.isEmpty) {
      notify('toolbox_get_url_failed');
      return;
    }
    final selected = await scope.wait(() => chooseLine(urls), timed: false);
    if (selected == null || !urls.contains(selected)) return;
    if (useUrl != null) {
      await scope.wait(() => useUrl(selected), timed: false);
      return;
    }
    try {
      await scope.wait(() => _copyText(selected));
    } on ToolBoxActionCancelled {
      rethrow;
    } catch (_) {
      if (scope.isActive) notify('toolbox_copy_failed');
      return;
    }
    notify('toolbox_copy_success');
  }
}
