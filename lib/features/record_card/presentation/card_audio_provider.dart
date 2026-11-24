import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/record_card/data/just_audio_player.dart';
import 'package:runiverse/features/record_card/domain/card_audio_player.dart';
import 'package:runiverse/features/record_card/domain/card_music.dart';

/// 소리가 지금 어떤가. **보고 있는 장 하나**를 말한다.
class CardAudioState {
  const CardAudioState({this.trackId, this.playable = false, this.playing = false});

  /// 플레이어에 물려 있는 곡의 신원([trackIdOf]). 곡이 아예 없으면 `null`이다.
  ///
  /// ⚠️ **주소가 아니다.** 서명 주소는 읽을 때마다 달라져서, 그것으로 견주면
  /// 폴링이 돌 때마다 다시 물어 소리가 끊긴다.
  final String? trackId;

  /// 지금 장의 곡을 틀 수 있나. 만드는 중이거나 실패한 장은 `false`다.
  final bool playable;

  /// 소리가 나고 있나.
  final bool playing;

  CardAudioState copyWith({bool? playing}) => CardAudioState(
    trackId: trackId,
    playable: playable,
    playing: playing ?? this.playing,
  );
}

/// 소리를 내는 것 하나.
///
/// ⚠️ **`isAutoDispose`를 빼면 상세를 떠나도 플레이어가 앱이 끝날 때까지
/// 산다.** 수동 provider는 Riverpod 3에서 기본이 `false`다.
///
/// 테스트는 여기를 `overrideWithValue`로 갈아 끼운다 — 진짜 소리를 내지
/// 않는다.
final cardAudioPlayerProvider = Provider<CardAudioPlayer>((ref) {
  final player = JustAudioPlayer();
  ref.onDispose(player.dispose);
  return player;
}, isAutoDispose: true);

/// 카드 하나의 소리.
///
/// ## ⚠️ 상세 화면만 몬다
///
/// 페이저도 음악 줄도 이것을 부르지 않는다. 두 군데서 몰면 줄은 `재생`인데
/// 소리는 나는 어긋남이 생긴다(설계 6-1).
final cardAudioProvider =
    NotifierProvider.family<CardAudio, CardAudioState, String>(
      CardAudio.new,
      isAutoDispose: true,
    );

class CardAudio extends Notifier<CardAudioState> {
  CardAudio(this.cardId);

  final String cardId;

  var _alive = false;

  /// 틀지 말지를 한 번이라도 정했나.
  ///
  /// ⚠️ **처음 틀 수 있게 된 순간에만 남의 소리를 본다.** 그다음부터는 사람의
  /// 뜻을 이어 간다 — 멈춰 둔 채로 장을 넘기면 멈춘 채로 둔다.
  var _decided = false;

  CardAudioPlayer get _player => ref.read(cardAudioPlayerProvider);

  @override
  CardAudioState build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    return const CardAudioState();
  }

  /// 보고 있는 장이 [page]이고 그 장의 곡이 [music]이라고 알린다.
  ///
  /// 상세 화면이 **장이 바뀌거나 카드가 다시 와서 곡이 달라졌을 때** 부른다.
  /// 신원이 같으면 아무것도 하지 않는다 — 폴링이 돌아도 소리가 안 끊긴다.
  Future<void> show({required int page, required CardMusic? music}) async {
    final id = music == null ? null : trackIdOf(page: page, music: music);
    if (id == state.trackId) return;

    if (music == null || !music.isPlayable) {
      // ⚠️ **나고 있을 때만 멈춘다.** 아무것도 안 물린 플레이어에 멈추라고
      // 하면 플랫폼을 공연히 한 번 부른다.
      if (state.playing) await _player.pause();
      if (!_alive) return;
      state = CardAudioState(trackId: id);
      return;
    }

    final wanted = _decided
        ? state.playing
        : !await _player.otherAudioPlaying();
    _decided = true;
    if (!_alive) return;

    await _player.load(music.url!);
    if (!_alive) return;

    if (wanted) await _player.play();
    if (!_alive) return;
    state = CardAudioState(trackId: id, playable: true, playing: wanted);
  }

  /// 사진을 탭했거나 음악 줄을 눌렀다.
  Future<void> toggle() async {
    if (!state.playable) return;

    final next = !state.playing;
    if (next) {
      await _player.play();
    } else {
      await _player.pause();
    }
    if (!_alive) return;
    state = state.copyWith(playing: next);
  }

  /// 화면이 덮였거나 앱이 배경으로 갔다.
  ///
  /// ⚠️ **돌아와도 저절로 다시 틀지 않는다.** 사용자가 돌아온 이유가 음악이
  /// 아닐 수 있다 — 저절로 나는 소리는 카드를 열 때 한 번이면 족하다.
  Future<void> suspend() async {
    if (!state.playing) return;
    await _player.pause();
    if (!_alive) return;
    state = state.copyWith(playing: false);
  }
}
