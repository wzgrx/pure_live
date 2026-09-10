import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/site/niconico/niconico_input_recipe.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/modules/live_play/states/player_state.dart';
import 'package:pure_live/player/core/live_input_playback_binding.dart';

void main() {
  test('owned resolution normalization preserves public recipe and quality without media URLs', () async {
    final input = NiconicoInputRecipe(programId: 'lv123', resolution: '800x450', bandwidth: 1080800);
    final site = _OwnedSite(input);
    final result = await site.resolvePlayUrls(
      detail: LiveRoom(roomId: '123'),
      quality: LivePlayQuality(quality: '450p'),
    );
    expect(result.inputRecipe, same(input));
    expect(result.urls, isEmpty);
    expect(result.sourceQueryPolicies, isEmpty);
    expect(result.lineCount, 1);
    expect(result.hasSources, true);
    expect(result.appliedQualityData, 'ack');
    expect(result.qualityUnconfirmed, true);
    final again = await site.resolvePlayUrlsForRecovery(
      detail: LiveRoom(roomId: '123'),
      quality: LivePlayQuality(quality: '450p'),
    );
    expect(again.inputRecipe, same(input));
  });

  test('empty and multi-line direct resolutions keep existing semantics', () {
    expect(const LivePlayUrlResolution(urls: []).normalized().hasSources, false);
    final result = const LivePlayUrlResolution(urls: [' a ', 'a', 'b']).normalized();
    expect(result.urls, ['a', 'b']);
    expect(result.lineCount, 2);
    expect(result.inputRecipe, isNull);
  });

  test('production niconico binding is lazy and does not export the watch or local URI', () {
    final recipe = NiconicoInputRecipe(programId: 'lv123', resolution: '800x450', bandwidth: 1080800);
    final source = bindLiveInputForPlayback(recipe);
    expect(source.identity, recipe.identity);
    expect(source.url, isNull);
    expect(bindLiveInputForPlayback(recipe), isNot(same(source)));
  });

  for (final args in [(null, 1), ('800x450', 0), ('800x450', -1)]) {
    test('recipe rejects invalid quality selector $args', () {
      expect(
        () => NiconicoInputRecipe(programId: 'lv123', resolution: args.$1, bandwidth: args.$2),
        throwsArgumentError,
      );
    });
  }

  test('owned UI state keeps one logical line but clears capability on ordinary replacement', () {
    final recipe = NiconicoInputRecipe(programId: 'lv123', resolution: null);
    final source = bindLiveInputForPlayback(recipe);
    final state = const PlayerState().copyWith(playUrls: const [], ownedSource: source);
    expect(state.hasPlaybackSource, true);
    expect(state.lineCount, 1);
    expect(state.playUrlSafe, isEmpty);
    expect(state.copyWith(isCurrentRoomAudioOnly: true).ownedSource, same(source));
    expect(state.copyWith(currentLineIndex: 0).ownedSource, same(source));
    expect(state.copyWith(playUrls: ['https://fixture/real.m3u8']).ownedSource, isNull);
    expect(state.copyWith(clearOwnedSource: true).ownedSource, isNull);
    expect(state.copyWith(), state);
    expect(state.copyWith().hashCode, state.hashCode);
    expect(state.copyWith(ownedSource: bindLiveInputForPlayback(recipe)), isNot(state));
    expect(state.toString(), isNot(contains('lv123')));
    // Even malformed presentation state must not export stale remote media.
    expect(PlayerState(ownedSource: source, playUrls: const ['https://fixture/stale']).playUrlSafe, isEmpty);
  });
}

class _OwnedSite extends LiveSite implements LivePlayUrlResolver {
  _OwnedSite(this.input);
  final NiconicoInputRecipe input;
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => LivePlayUrlResolution.owned(input: input, appliedQualityData: 'ack', qualityUnconfirmed: true);
}
