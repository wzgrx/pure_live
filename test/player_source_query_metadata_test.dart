import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/common/hls_source_query_policy.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/modules/live_play/states/player_state.dart';
import 'package:pure_live/player/core/player_manager.dart';

void main() {
  const first = 'https://cdn.example/one/master.m3u8?token=first';
  const second = 'https://cdn.example/two/master.m3u8?token=second';
  final firstPolicy = HlsSourceQueryPolicy.fromSource(Uri.parse(first));
  final secondPolicy = HlsSourceQueryPolicy.fromSource(Uri.parse(second));

  test('source cohort copies policies and validates exact source keys without leaking them', () {
    final policies = {first: firstPolicy};
    final selection = PlaybackSourceQualitySelection(
      qualities: [LivePlayQuality(quality: 'Original')],
      currentQuality: 9,
      sourceQueryPolicies: policies,
    );
    policies.clear();
    expect(selection.currentQuality, 0);
    expect(selection.sourceQueryPolicies, {first: firstPolicy});
    expect(() => selection.sourceQueryPolicies.clear(), throwsUnsupportedError);
    expect(
      () => PlaybackSourceQualitySelection(
        qualities: [LivePlayQuality(quality: 'Original')],
        currentQuality: 0,
        sourceQueryPolicies: {second: firstPolicy},
      ),
      throwsA(isA<FormatException>().having((error) => error.toString(), 'no signed URL', isNot(contains('token=')))),
    );
  });

  test('player presentation updates retain policies but a new legacy URL cohort clears them', () {
    final policies = {first: firstPolicy};
    final state = const PlayerState().copyWith(playUrls: [first], sourceQueryPolicies: policies);
    policies.clear();
    expect(state.sourceQueryPolicies, {first: firstPolicy});
    expect(state.copyWith(isCurrentRoomAudioOnly: true).sourceQueryPolicies, {first: firstPolicy});
    expect(state.copyWith(currentLineIndex: 1).sourceQueryPolicies, {first: firstPolicy});
    expect(state.copyWith(playUrls: [second]).sourceQueryPolicies, isEmpty);
    expect(() => state.sourceQueryPolicies.clear(), throwsUnsupportedError);
    expect(state.toString(), isNot(contains('token=')));
  });

  test('policy-only updates participate in state equality and use order independent hashing', () {
    final state = PlayerState(
      playUrls: const [first, second],
      sourceQueryPolicies: {first: firstPolicy, second: secondPolicy},
    );
    final reordered = state.copyWith(sourceQueryPolicies: {second: secondPolicy, first: firstPolicy});
    expect(reordered, state);
    expect(reordered.hashCode, state.hashCode);
    expect(state.copyWith(sourceQueryPolicies: const {}), isNot(state));
  });

  test('floating snapshot preserves policy on audio changes and clears it for a direct replacement', () {
    final room = LiveRoom(roomId: 'metadata', platform: 'test');
    final snapshot = RoomSessionSnapshot(
      room: room,
      qualities: [LivePlayQuality(quality: 'Original')],
      currentQuality: 0,
      playUrls: const [first],
      sourceQueryPolicies: {first: firstPolicy},
      currentLineIndex: 0,
      headers: const {},
      isAudioOnly: false,
      isLiving: true,
    );
    expect(snapshot.copyWith(isAudioOnly: true).sourceQueryPolicies, {first: firstPolicy});
    expect(snapshot.copyWith(playUrls: const [second]).sourceQueryPolicies, isEmpty);
    final restored = snapshot.copyWith(playUrls: const [second], sourceQueryPolicies: {second: secondPolicy});
    expect(restored.sourceQueryPolicies, {second: secondPolicy});
    expect(() => restored.sourceQueryPolicies.clear(), throwsUnsupportedError);
  });
}
