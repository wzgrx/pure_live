// E05.5: the shared gift every platform's gift message holds
// (E05.5; design in docs/V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md §6.1).
import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

final class _PlatformGift extends LiveGift {
  const new({required super.name, this.extra = 0}) : super(unit: LiveGiftUnit.goldSeed);

  final int extra;

  @override
  bool operator ==(Object other) => super == other && other is _PlatformGift && other.extra == extra;

  @override
  int get hashCode => Object.hash(super.hashCode, extra);
}

void main() {
  group('LiveGift', () {
    test('defaults: one gift, no combo, no value, unit other, not free, normal', () {
      const gift = LiveGift(name: '小心心');
      expect(
        (gift.id, gift.count, gift.kind, gift.comboKey, gift.comboTotal, gift.unitPrice, gift.totalValue),
        ('', 1, LiveGiftKind.gift, '', null, null, null),
      );
      expect((gift.unit, gift.free, gift.iconUrl, gift.receiverName), (LiveGiftUnit.other, false, null, ''));
      expect(gift.tier, LiveGiftTier.normal);
    });

    test('a count below 1 counts as 1', () {
      for (final count in [0, -3]) {
        expect(
          LiveGift(name: 'a', count: count).count,
          1,
          reason: '$count',
        );
      }
      expect(const LiveGift(name: 'a', count: 7).count, 7);
    });

    test('the shared text: name and count, the id when there is no name', () {
      expect(const LiveGift(name: '小心心', count: 3).plainText, '小心心 ×3');
      expect(const LiveGift(name: '', id: 'nicoko').plainText, 'nicoko ×1');
      expect(const LiveGift(name: '', id: 'nicoko').displayName, 'nicoko');
      expect(
        const LiveGift(name: '舰长', count: 2, kind: LiveGiftKind.membership).plainText,
        '舰长 ×2',
        reason: 'one text for every kind; the months are the count',
      );
    });

    test('the tier comes from giftTierOf', () {
      expect(const LiveGift(name: 'a', totalValue: 10000, unit: LiveGiftUnit.goldSeed).tier, LiveGiftTier.valuable);
      expect(
        const LiveGift(name: 'a', totalValue: 10000, unit: LiveGiftUnit.goldSeed, free: true).tier,
        LiveGiftTier.normal,
      );
    });

    test('equality: same class and same shared fields; a subclass adds its own', () {
      final icon = Uri.parse('https://example.com/gift.png');
      LiveGift full({int count = 2}) => LiveGift(
        id: '1',
        name: 'a',
        count: count,
        kind: LiveGiftKind.tip,
        comboKey: 'k',
        comboTotal: 3,
        unitPrice: 5,
        totalValue: 10,
        unit: LiveGiftUnit.bits,
        free: true,
        iconUrl: icon,
        receiverName: 'r',
      );
      expect(full(), full());
      expect(full().hashCode, full().hashCode);
      expect(full(), isNot(full(count: 3)));
      expect(const _PlatformGift(name: 'a'), const _PlatformGift(name: 'a'));
      expect(const _PlatformGift(name: 'a'), isNot(const _PlatformGift(name: 'a', extra: 1)));
      expect(
        const LiveGift(name: 'a', unit: LiveGiftUnit.goldSeed),
        isNot(const _PlatformGift(name: 'a')),
        reason: 'a platform class is not the plain gift',
      );
      expect(const _PlatformGift(name: 'a'), isNot(const LiveGift(name: 'a', unit: LiveGiftUnit.goldSeed)));
      expect('${full()}', 'LiveGift(tip a ×2, 10 bits, free)');
    });

    test('LiveMessage.gift is the data when it is a gift', () {
      const gift = LiveGift(name: 'a');
      const message = LiveMessage(
        type: LiveMessageType.gift,
        userName: 'u',
        message: 'a ×1',
        color: LiveMessageColor.white,
        data: gift,
      );
      expect(message.gift, same(gift));
      const local = LiveMessage(
        type: LiveMessageType.gift,
        userName: 'u',
        message: 'a ×1',
        color: LiveMessageColor.white,
        data: {'giftName': 'a'},
      );
      expect(local.gift, isNull);
    });
  });

  group('giftTierOf', () {
    test('the yuan thresholds: below 10 normal, below 100 valuable, from 100 precious', () {
      for (final (unit, perYuan) in [
        (LiveGiftUnit.fen, 100),
        (LiveGiftUnit.goldSeed, 1000),
        (LiveGiftUnit.diamond, 10),
        (LiveGiftUnit.douyinCoin, 10),
        (LiveGiftUnit.acCoin, 10),
      ]) {
        expect(giftUnitsPerYuan[unit], perYuan, reason: unit.name);
        LiveGiftTier tierAt(double yuan) => giftTierOf(unit, (yuan * perYuan).round());
        expect(tierAt(9.9), LiveGiftTier.normal, reason: '${unit.name} 9.9');
        expect(tierAt(10), LiveGiftTier.valuable, reason: '${unit.name} 10');
        expect(tierAt(99.9), LiveGiftTier.valuable, reason: '${unit.name} 99.9');
        expect(tierAt(100), LiveGiftTier.precious, reason: '${unit.name} 100');
      }
      expect(giftTierOf(LiveGiftUnit.fen, 999), LiveGiftTier.normal, reason: '9.99 yuan');
    });

    test('free, no value, or a unit without a rate is normal', () {
      expect(giftTierOf(LiveGiftUnit.goldSeed, 1000000, free: true), LiveGiftTier.normal);
      expect(giftTierOf(LiveGiftUnit.goldSeed, null), LiveGiftTier.normal);
      expect(giftTierOf(LiveGiftUnit.goldSeed, 0), LiveGiftTier.normal);
      expect(giftTierOf(LiveGiftUnit.goldSeed, -5), LiveGiftTier.normal);
      for (final unit in [LiveGiftUnit.other, LiveGiftUnit.redBean, LiveGiftUnit.silverSeed, LiveGiftUnit.banana]) {
        expect(giftUnitsPerYuan.containsKey(unit), isFalse, reason: unit.name);
        expect(giftTierOf(unit, 1 << 40), LiveGiftTier.normal, reason: unit.name);
      }
    });

    test('the overseas units have rough rates: about a US dollar, a won, a yen', () {
      expect(giftTierOf(LiveGiftUnit.bits, 100), LiveGiftTier.normal, reason: 'about a dollar');
      expect(giftTierOf(LiveGiftUnit.bits, 1000), LiveGiftTier.valuable, reason: 'about 10 dollars, 70 yuan');
      expect(giftTierOf(LiveGiftUnit.bits, 10000), LiveGiftTier.precious, reason: 'about 100 dollars');
      expect(giftTierOf(LiveGiftUnit.kicks, 500), LiveGiftTier.valuable, reason: '5 dollars');
      expect(giftTierOf(LiveGiftUnit.cheese, 10000), LiveGiftTier.valuable, reason: '10,000 won');
      expect(giftTierOf(LiveGiftUnit.starBalloon, 100), LiveGiftTier.valuable, reason: '100 balloons');
      expect(giftTierOf(LiveGiftUnit.point, 500), LiveGiftTier.valuable, reason: '500 points, about 500 yen');
      expect(giftTierOf(LiveGiftUnit.point, 5000), LiveGiftTier.precious);
    });
  });
}
