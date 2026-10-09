import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

LiveMessage _from(String user, LiveGift gift) => LiveMessage(
  type: LiveMessageType.gift,
  userName: user,
  userId: user,
  message: gift.plainText,
  color: LiveMessageColor.white,
  data: gift,
);

void main() {
  test('the fallback combo key: the same sender and gift, and the same receiver when one is named', () {
    String key(LiveGift gift, {String user = '主播'}) => giftComboKey(_from(user, gift), gift);
    const plain = LiveGift(id: '1', name: '亲亲');
    expect(key(plain), key(const LiveGift(id: '1', name: '亲亲', count: 3)));
    expect(key(plain), isNot(key(plain, user: '别人')));
    // D07.7: Kugou's streamer sends 亲亲 to ten viewers in turn; each is a combo of its own.
    const toA = LiveGift(id: '1', name: '亲亲', receiverName: '甲');
    const toB = LiveGift(id: '1', name: '亲亲', receiverName: '乙');
    expect(key(toA), isNot(key(toB)));
    expect(key(toA), key(const LiveGift(id: '1', name: '亲亲', count: 2, receiverName: '甲')));
    // A platform's combo key wins over everything else.
    expect(
      key(const LiveGift(id: '1', name: '亲亲', comboKey: 'c', receiverName: '甲')),
      key(const LiveGift(id: '1', name: '亲亲', comboKey: 'c')),
    );
  });
}
