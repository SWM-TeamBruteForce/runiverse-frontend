import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/record_card/data/just_audio_player.dart';
import 'package:runiverse/features/record_card/domain/card_audio_player.dart';
import 'package:runiverse/features/record_card/domain/card_music.dart';
import 'package:runiverse/features/record_card/presentation/card_detail_provider.dart';

/// 소리가 지금 어떤가. **보고 있는 장 하나**를 말한다.
class CardAudioState {
  const CardAudioState({this.playable = false, this.playing = false});

  /// 지금 장의 곡이 **물려 있나.** 만드는 중이거나 못 물린 장은 `false`다.
  final bool playable;

  /// 소리가 나고 있나.
  final bool playing;

  CardAudioState copyWith({bool? playing}) =>
      CardAudioState(playable: playable, playing: playing ?? this.playing);
}

/// 소리를 내는 것 하나.
///
/// ## ⚠️ `ref.read`로 가져다 쓰면 안 된다
///
/// `autoDispose`라 **듣는 사람이 없으면 읽은 직후 버려진다.** `ref.read`는
/// 듣는 사람을 만들지 않으므로 읽을 때마다 새 플레이어가 선다 — `load`와
/// `play`가 서로 다른 플레이어로 가 **소리가 영영 안 난다.** 2026-11-25에
/// 실제로 세 번 세워졌다. 반드시 [CardAudio.build]에서 `ref.watch`로 잡는다.
///
/// 테스트는 여기를 갈아 끼운다 — 진짜 소리를 내지 않는다.
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

  /// ⚠️ **`late final`이 아니다.** 플레이어가 다시 서면 `build`가 또 돈다.
  late CardAudioPlayer _player;

  var _alive = false;

  /// 지금 **물려 있는** 곡의 신원. 못 물었으면 `null`이라 다시 물어 본다.
  String? _loaded;

  /// 못 물어서 상세를 다시 읽어 본 곡.
  ///
  /// ⚠️ **곡마다 한 번이다.** 새 주소도 못 물면 조용히 접는다 — 안 그러면
  /// 다시 읽기와 다시 물기가 서로를 부르는 고리가 된다.
  String? _retriedFor;

  /// 지금 보고 있는 장과 그 곡. [toggle]이 다시 물어 볼 때 쓴다.
  var _page = 0;
  CardMusic? _music;

  /// 틀 뜻이 있나.
  ///
  /// ⚠️ **[state]가 아니라 이것으로 판단한다.** `state.playing`은 기다린 뒤에야
  /// 바뀌어서, 물리는 동안 들어온 [suspend]나 두 번째 [toggle]을 놓친다.
  var _wantPlaying = false;

  /// [_wantPlaying]을 한 번이라도 정했나. 처음 틀 수 있게 된 순간에만 남의
  /// 소리를 본다 — 그다음부터는 사람의 뜻을 이어 간다.
  var _decided = false;

  /// 몇 번째 요청인가.
  ///
  /// ⚠️ **빠르게 밀면 [show]가 겹친다.** 뒤늦게 끝난 앞 장의 결과가 상태를
  /// 덮어쓰면 줄이 지금 장과 어긋나 **눌러도 아무 일 없는 버튼**이 된다.
  var _generation = 0;

  @override
  CardAudioState build() {
    _alive = true;
    _player = ref.watch(cardAudioPlayerProvider);
    ref.onDispose(() => _alive = false);
    return const CardAudioState();
  }

  /// 보고 있는 장이 [page]이고 그 장의 곡이 [music]이라고 알린다.
  ///
  /// 상세 화면이 **들어올 때, 장을 넘길 때, 카드가 다시 왔을 때** 부른다.
  /// 이미 물려 있는 곡이면 아무것도 하지 않는다 — 폴링이 새 서명 주소를 줘도
  /// 소리가 안 끊긴다.
  Future<void> show({required int page, required CardMusic? music}) async {
    _page = page;
    _music = music;

    final id = music == null ? null : trackIdOf(page: page, music: music);
    if (id != null && id == _loaded) return;
    await _open(id, music);
  }

  /// 사진을 탭했거나 음악 줄을 눌렀다.
  Future<void> toggle() async {
    // ⚠️ **못 물린 장이면 한 번 더 물어 본다.** 줄은 카드가 든 곡을 보고
    // 버튼을 세우므로, 못 물린 뒤에도 `재생`이 서 있다. 눌러도 아무 일이
    // 없으면 안 된다.
    if (!state.playable) {
      final music = _music;
      if (music == null || !music.isPlayable) return;
      _wantPlaying = true;
      _decided = true;
      await _open(trackIdOf(page: _page, music: music), music);
      return;
    }

    final next = !_wantPlaying;
    _wantPlaying = next;
    _decided = true;
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
  ///
  /// ⚠️ **아직 안 물린 동안에도 받는다.** 뜻을 먼저 꺾어 두지 않으면, 다 물린
  /// 뒤에 가려진 앱에서 소리가 난다.
  Future<void> suspend() async {
    _wantPlaying = false;
    _decided = true;
    if (!state.playing) return;
    await _player.pause();
    if (!_alive) return;
    state = state.copyWith(playing: false);
  }

  /// [music]을 물리고, 틀 뜻이 있으면 튼다.
  Future<void> _open(String? id, CardMusic? music) async {
    final mine = ++_generation;
    bool stale() => !_alive || mine != _generation;

    if (music == null || !music.isPlayable) {
      _loaded = null;
      // 나고 있을 때만 멈춘다 — 아무것도 안 물린 플레이어를 공연히 부르지
      // 않는다.
      if (state.playing) await _player.pause();
      if (stale()) return;
      state = const CardAudioState();
      return;
    }

    if (!_decided) {
      final others = await _player.otherAudioPlaying();
      if (stale()) return;
      _decided = true;
      _wantPlaying = !others;
    }

    try {
      await _player.load(music.url!);
    } catch (_) {
      // ⚠️ **무엇 때문인지 가르지 않는다.** 안드로이드에서 올라오는 것은
      // ExoPlayer 오류라 403을 믿고 가려낼 수 없다(설계 7-3). 주소도 적지
      // 않는다 — 서명이 붙어 있다.
      if (stale()) return;
      // ⚠️ **[_loaded]를 세우지 않는다.** 세우면 새 주소를 받아 와도 "같은
      // 곡"으로 걸러져 다시 읽은 것이 헛일이 된다.
      _loaded = null;
      state = const CardAudioState();
      if (_retriedFor != id) {
        _retriedFor = id;
        // 만료였다면 새 주소를 받아 온다. 아니면 이 장은 소리 없이 선다.
        ref.invalidate(cardDetailProvider(cardId));
      }
      return;
    }
    if (stale()) return;
    _loaded = id;

    if (_wantPlaying) await _player.play();
    if (stale()) return;
    state = CardAudioState(playable: true, playing: _wantPlaying);
  }
}
