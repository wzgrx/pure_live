import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';

/// An adapter with canned pages, for widget and provider tests.
final class FakeSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  new(this.id, {List<Page<RoomCard>>? pages, this.failFirst = false, this.offline = const {}}) : pages = pages ?? [];

  /// Room ids whose detail reports offline.
  final Set<String> offline;

  /// Detail requests, in order, so tests can see which rooms were asked for.
  final details = <String>[];

  /// Stream requests, in order.
  final streamRequests = <String>[];

  @override
  final String id;

  @override
  String get name => id;

  /// Pages returned in order by [recommended], [areaRooms] and [search].
  final List<Page<RoomCard>> pages;

  /// Throws a [NetworkFailure] on the first request.
  bool failFirst;

  /// Cursors received, in order.
  final cursors = <PageCursor?>[];

  Future<Page<RoomCard>> _page(PageCursor? cursor) async {
    cursors.add(cursor);
    if (failFirst) {
      failFirst = false;
      throw NetworkFailure(id, 'offline');
    }
    final index = cursor == null ? 0 : int.parse(cursor.value);
    return index < pages.length ? pages[index] : const Page.empty();
  }

  @override
  Future<List<Category>> categories() async => [
    const Category(
      id: 'c1',
      name: '网游',
      areas: [Area(id: 'a1', name: '英雄联盟', categoryId: 'c1')],
    ),
  ];

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) => _page(cursor);

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) => _page(cursor);

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) => _page(cursor);

  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    details.add(ref.roomId);
    final state = offline.contains(ref.roomId) ? LiveState.offline : LiveState.live;
    return RoomDetail(
      card: card(ref.roomId, state: state),
      link: Uri.parse('https://example.com/${ref.roomId}'),
    );
  }

  /// Qualities every room offers, best first.
  static const qualities = [
    Quality(id: 'hd', label: '原画', rank: 3),
    Quality(id: 'sd', label: '高清', rank: 2),
    Quality(id: 'ld', label: '流畅', rank: 1),
  ];

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    streamRequests.add(room.ref.roomId);
    final chosen = quality ?? qualities.first;
    return StreamSet(
      qualities: qualities,
      selected: chosen,
      lines: [
        StreamLine(
          url: Uri.parse('https://cdn.example.com/${room.ref.roomId}/${chosen.id}.m3u8'),
          format: StreamFormat.hls,
          lineId: 'a',
          requested: chosen,
        ),
      ],
    );
  }

  @override
  Future<RoomRef?> resolve(String input) async =>
      input.contains('$id.example') ? RoomRef(id, input.split('/').last) : null;

  /// A live card for [roomId].
  RoomCard card(String roomId, {LiveState state = LiveState.live}) => RoomCard(
    ref: RoomRef(id, roomId),
    title: '标题$roomId',
    anchorName: '主播$roomId',
    state: state,
    audience: const Audience(online: 35512),
  );
}

/// A recorder that never touches the disk or the network.
RecordManager fakeRecordManager() => RecordManager(
  rooms: SiteRecordRooms((_) => null),
  store: MemoryRecordTaskStore(),
  root: '/nonexistent',
  opener: httpRecordOpener(),
);
