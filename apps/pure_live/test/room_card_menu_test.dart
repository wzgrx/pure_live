import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live_app/features/rooms/room_card_menu.dart';

void main() {
  test('principles §4.2: one menu for every card', () {
    expect(roomCardActions(followed: false, newWindow: false), [
      RoomCardAction.follow,
      RoomCardAction.multiview,
      RoomCardAction.share,
      RoomCardAction.copyLink,
      RoomCardAction.openSite,
    ]);
    expect(roomCardActions(followed: true, newWindow: true), [
      RoomCardAction.unfollow,
      RoomCardAction.groups,
      RoomCardAction.multiview,
      RoomCardAction.share,
      RoomCardAction.copyLink,
      RoomCardAction.newWindow,
      RoomCardAction.openSite,
    ]);
  });
}
