import 'package:meta/meta.dart';

/// What a platform says about a chat message's sender besides the name and
/// the fan badge (task B06: Bilibili's `user.base.face`). A chat carries it
/// in `LiveMessage.data`; a platform that says nothing more leaves `data`
/// null.
@immutable
final class DanmakuSender {
  /// Creates the sender.
  const new({this.avatar = ''});

  /// The avatar's address (https), empty when there is none.
  final String avatar;

  @override
  bool operator ==(Object other) => other is DanmakuSender && other.avatar == avatar;

  @override
  int get hashCode => avatar.hashCode;

  @override
  String toString() => 'DanmakuSender($avatar)';
}
