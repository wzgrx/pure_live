import 'package:dio/dio.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/common/models/live_room.dart';

/// Optional native-page contract. Row count is NOT pagination evidence: a
/// server may inject recommendations or the adapter may exclude closed rooms.
class LiveDirectoryPage {
  LiveDirectoryPage({required Iterable<LiveRoom> rooms, required this.page, required this.hasMore})
    : rooms = List.unmodifiable(rooms);
  final List<LiveRoom> rooms;
  final int page;
  final bool hasMore;
}

abstract interface class LiveSiteDirectoryPager {
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel});
}

/// Optional, persistent explanation of a platform's visible directory scope.
abstract interface class LiveDirectoryNotice {
  String get directoryNoticeKey;
}
