import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live_app/features/rooms/room_card_menu.dart';

void main() {
  test('principles §4.2: one menu for every card', () {
    expect(roomCardActions(followed: false, newWindow: false), [
      RoomCardAction.follow,
      RoomCardAction.multiview,
      RoomCardAction.share,
      RoomCardAction.copyLink,
      RoomCardAction.streamLink,
      RoomCardAction.openSite,
    ]);
    expect(roomCardActions(followed: true, newWindow: true), [
      RoomCardAction.unfollow,
      RoomCardAction.groups,
      RoomCardAction.multiview,
      RoomCardAction.share,
      RoomCardAction.copyLink,
      RoomCardAction.streamLink,
      RoomCardAction.newWindow,
      RoomCardAction.openSite,
    ]);
  });

  test('F-FAV-09: the follows page adds 多选 first; the rest stays as on every card', () {
    expect(roomCardActions(followed: true, newWindow: false, select: true), [
      RoomCardAction.select,
      ...roomCardActions(followed: true, newWindow: false),
    ]);
  });

  test('F-FAV-08: a platform without an adapter keeps only following and groups', () {
    expect(roomCardActions(followed: true, newWindow: true, supported: false), [
      RoomCardAction.unfollow,
      RoomCardAction.groups,
    ]);
  });
}
