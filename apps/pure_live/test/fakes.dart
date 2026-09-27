import 'package:live_core/live_core.dart';

/// An adapter with canned pages, for widget and provider tests.
final class FakeSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  new(this.id, {List<Page<RoomCard>>? pages, this.failFirst = false}) : pages = pages ?? [];

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
  Future<RoomDetail> detail(RoomRef ref) async =>
      RoomDetail(card: card(ref.roomId), link: Uri.parse('https://example.com/${ref.roomId}'));

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) => throw StreamUnavailable(id);

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
