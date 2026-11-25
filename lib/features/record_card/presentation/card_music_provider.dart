import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/record_card/domain/music_generation.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';

/// 음악 줄이 보는 상태. loading / data / error 세 갈래다.
///
/// `record_card_state.dart`와 같은 방식이다 — freezed 미도입이라 손으로 쓴다.
sealed class CardMusicState {
  const CardMusicState();
}

/// 처음 받아 오는 중. **한 프레임짜리가 아니다** — 망이 느리면 길다.
class CardMusicLoading extends CardMusicState {
  const CardMusicLoading();
}

/// 상태를 못 읽었다. **카드는 그대로 보인다** — 음악과 카드는 따로다(설계 2절).
class CardMusicError extends CardMusicState {
  const CardMusicError(this.failure);

  final RecordCardFailure failure;
}

class CardMusicData extends CardMusicState {
  const CardMusicData({required this.generation, this.requesting = false});

  final MusicGeneration generation;

  /// 만들어 달라고 보내는 중. **버튼이 다시 눌리지 않아야 한다.**
  final bool requesting;
}

/// 카드 한 장의 음악. **인자는 카드 번호다.**
///
/// ## ⚠️ `autoDispose`다
///
/// 상세는 열고 닫는 화면이고 카드마다 인자가 다르다. 안 켜면 **카드를 열어 본
/// 만큼 상태와 타이머가 쌓인다.** 수동 `NotifierProvider`는 Riverpod 3에서
/// 기본이 `isAutoDispose = false`다(`chat_provider.dart`가 같은 함정을 적어
/// 두었다).
final cardMusicProvider =
    NotifierProvider.family<CardMusicController, CardMusicState, int>(
      CardMusicController.new,
      isAutoDispose: true,
    );

/// 음악 상태를 들고, **만드는 중일 때만** 다시 묻는다.
///
/// ## ⚠️ 왜 폴링인가
///
/// 완료를 앱에 알리는 방법이 **아직 정해지지 않았다** — FCM · 조회 · 폴링 중
/// 무엇인지 물어 두었다(`docs/notes/2026-11-16-record-card-backend-questions.md`
/// 10번). 셋 중 앱만으로 되는 것은 폴링이다.
///
/// 정해지면 **이 클래스 한 곳만** 바꾼다. 화면은 상태만 본다.
///
/// ## ⚠️ 끝나면 멈춘다
///
/// `SUCCEEDED`·`FAILED`·`none`에서는 다시 묻지 않는다. 오류에서도 멈춘다 —
/// 끊긴 망을 [pollInterval]마다 두드리면 배터리만 쓰고, 사용자가 `다시`를
/// 누르는 길이 따로 있다.
class CardMusicController extends Notifier<CardMusicState> {
  CardMusicController(this.cardId);

  /// 만드는 중일 때 다시 묻는 간격.
  ///
  /// ⚠️ **서버가 큐에서 6시간까지 기다릴 수 있다**(설계 3절). 그 동안 3초마다
  /// 묻는 것은 통지 방식이 정해지면 바꿀 임시 값이다.
  static const pollInterval = Duration(seconds: 3);

  final int cardId;

  Timer? _poll;

  /// 만들어 달라고 보내는 중.
  ///
  /// ⚠️ **[state]의 모양으로 가리면 안 된다.** 처음 받아 오는 동안에도 누를 수
  /// 있어(줄이 서 있다) 그때 상태는 [CardMusicLoading]이고, 그러면 가드가
  /// 통째로 빠진다 — 연타가 요청을 둘 보낸다.
  var _requesting = false;

  /// 아직 살아 있나. **`await` 뒤에 상태를 쓰기 전에 본다** — `autoDispose`라
  /// 실제로 죽는다.
  var _alive = false;

  @override
  CardMusicState build() {
    _alive = true;
    ref.onDispose(() {
      _alive = false;
      _poll?.cancel();
    });
    // ⚠️ `build` 안에서 상태를 쓰지 않는다. 먼저 `loading`을 돌려주고, 받아 온
    // 뒤에 바꾼다.
    Future.microtask(load);
    return const CardMusicLoading();
  }

  /// 지금 상태를 받아 온다.
  Future<void> load() async {
    try {
      final music = await ref
          .read(recordCardRepositoryProvider)
          .musicOf(cardId);
      if (!_alive) return;
      // ⚠️ **요청이 날아가는 중이면 덮지 않는다.** 처음 받아 오던 답이나
      // 폴링의 답이 요청 뒤에 도착하면, 방금 건 생성이 `없음`으로 되돌아
      // 보인다.
      if (_requesting) return;
      state = CardMusicData(generation: music);
      _schedule(music);
    } on RecordCardException catch (error) {
      if (!_alive) return;
      _poll?.cancel();
      state = CardMusicError(error.failure);
    }
  }

  /// 전곡을 만들어 달라고 한다. 처음 만드는 것과 다시 만드는 것이 같다.
  Future<void> request() async {
    // ⚠️ **두 번 누르면 요청이 둘 나간다.** 서버가 활성 요청을 둘 들게 되고,
    // 앞의 것이 무효화되는지는 모른다.
    if (_requesting) return;
    _requesting = true;

    final before = state;
    if (before is CardMusicData) {
      state = CardMusicData(generation: before.generation, requesting: true);
    }

    try {
      final music = await ref
          .read(recordCardRepositoryProvider)
          .requestMusic(cardId);
      if (!_alive) return;
      state = CardMusicData(generation: music);
      _schedule(music);
    } on RecordCardException catch (error) {
      if (!_alive) return;
      _poll?.cancel();
      state = CardMusicError(error.failure);
    } finally {
      _requesting = false;
    }
  }

  /// 만드는 중이면 [pollInterval] 뒤에 다시 묻게 건다.
  void _schedule(MusicGeneration music) {
    _poll?.cancel();
    if (!music.isWorking) return;
    _poll = Timer(pollInterval, load);
  }
}
