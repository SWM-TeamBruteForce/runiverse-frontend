import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/presentation/card_detail_provider.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';

/// 음악 줄이 보는 **곁 상태.** 곡 자체는 카드가 들고 있다.
///
/// `record_card_state.dart`와 같은 방식이다 — freezed 미도입이라 손으로 쓴다.
sealed class CardMusicState {
  const CardMusicState();
}

/// 평소. 줄은 카드가 든 곡을 그대로 보여 준다.
class CardMusicIdle extends CardMusicState {
  const CardMusicIdle();
}

/// 다시 만들어 달라고 보내는 중. **버튼이 다시 눌리지 않아야 한다.**
class CardMusicRetrying extends CardMusicState {
  const CardMusicRetrying();
}

/// 재요청을 못 보냈다. **카드와 곡은 그대로 보인다** — 음악과 카드는 따로다.
class CardMusicRetryFailed extends CardMusicState {
  const CardMusicRetryFailed(this.failure);

  final RecordCardFailure failure;
}

/// 음악이 만들어지는 동안 상세를 다시 읽고, 재요청을 보낸다.
///
/// ## ⚠️ 상태를 직접 받아 오지 않는다
///
/// 곡이 **상세(8-1) 응답에 실려 온다**(연동 가이드 2절). 따로 묻는
/// 엔드포인트가 없으므로, 다시 읽는다는 것은 [cardDetailProvider]를 버리는
/// 것이다. 묶음 5까지 있던 `musicOf`는 사라졌다.
///
/// ## ⚠️ `autoDispose`다
///
/// 상세는 열고 닫는 화면이고 카드마다 인자가 다르다. 안 켜면 **카드를 열어 본
/// 만큼 타이머가 쌓인다.** 수동 `NotifierProvider`는 Riverpod 3에서 기본이
/// `isAutoDispose = false`다(`chat_provider.dart`가 같은 함정을 적어 두었다).
///
/// 화면을 떠나면 provider가 버려지고 **타이머도 함께 멈춘다** — 가이드가
/// "화면 이탈 시 중지"라고 적은 것이 그것이다.
final cardMusicProvider =
    NotifierProvider.family<CardMusicController, CardMusicState, String>(
      CardMusicController.new,
      isAutoDispose: true,
    );

class CardMusicController extends Notifier<CardMusicState> {
  CardMusicController(this.cardId);

  /// 처음 다시 묻는 간격.
  ///
  /// ⚠️ **3초가 아니다.** 큐에서 오래 기다릴 수 있어(설계 3절) 짧은 간격은
  /// 배터리만 쓴다. 가이드 7절이 "10초부터 최대 1분까지" 늘리라고 적었다.
  static const firstInterval = Duration(seconds: 10);

  /// 더 늘리지 않는 한도.
  static const maxInterval = Duration(minutes: 1);

  final String cardId;

  Timer? _poll;

  /// 다음에 기다릴 시간. 물을 때마다 두 배가 되고 [maxInterval]에서 멈춘다.
  var _interval = firstInterval;

  /// 재요청이 날아가는 중.
  ///
  /// ⚠️ **[state]의 모양으로 가리면 안 된다.** 상태를 바꾸기 전에 두 번째
  /// 누름이 들어올 수 있다 — 연타가 요청을 둘 보낸다.
  var _retrying = false;

  var _alive = false;

  @override
  CardMusicState build() {
    _alive = true;
    ref.onDispose(() {
      _alive = false;
      _poll?.cancel();
    });

    // ⚠️ **카드를 듣는다.** 곡이 상세 응답에 실려 오므로, 만들고 있는 곡이
    // 있는지는 그 응답만 보면 안다. `fireImmediately`로 이미 받아 둔 카드도
    // 본다 — 안 하면 상세가 먼저 뜬 뒤에는 폴링이 영영 안 걸린다.
    ref.listen(cardDetailProvider(cardId), (_, next) {
      _scheduleFrom(next.value);
    }, fireImmediately: true);

    return const CardMusicIdle();
  }

  /// 못 만든 곡을 다시 만들어 달라고 한다 (9-6).
  Future<void> retry() async {
    if (_retrying) return;
    _retrying = true;
    state = const CardMusicRetrying();

    try {
      await ref.read(recordCardRepositoryProvider).retryMusic(cardId);
      if (!_alive) return;
      state = const CardMusicIdle();
      // ⚠️ **바로 다시 읽는다.** `204`는 상태를 주지 않는다(가이드 4절) —
      // 상세를 다시 읽어야 `GENERATING`으로 바뀐 줄이 보인다.
      _interval = firstInterval;
      ref.invalidate(cardDetailProvider(cardId));
    } on RecordCardException catch (error) {
      if (!_alive) return;
      state = CardMusicRetryFailed(error.failure);
    } finally {
      _retrying = false;
    }
  }

  /// 만들고 있는 곡이 있으면 다음 조회를 건다.
  void _scheduleFrom(RecordCard? card) {
    _poll?.cancel();
    if (card == null) return;

    if (!card.isMusicWorking) {
      // 끝났으면 간격을 되돌린다 — 다음 재요청이 다시 10초에서 시작한다.
      _interval = firstInterval;
      return;
    }

    final wait = _interval;
    // 다음 간격은 두 배, 1분에서 멈춘다.
    _interval = wait * 2 > maxInterval ? maxInterval : wait * 2;
    _poll = Timer(wait, () {
      if (!_alive) return;
      ref.invalidate(cardDetailProvider(cardId));
    });
  }
}
