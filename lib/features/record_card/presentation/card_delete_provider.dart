import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/profile/presentation/profile_cards_provider.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';

/// 삭제가 어디까지 갔나.
///
/// `cardSaveProvider`와 같은 꼴의 sealed union이다 — freezed 미도입이라
/// 손으로 쓴다.
sealed class CardDeleteState {
  const CardDeleteState();
}

/// 아직 안 눌렀거나, 눌러서 끝났다.
class CardDeleteIdle extends CardDeleteState {
  const CardDeleteIdle();
}

/// 도는 중. **버튼이 다시 눌리지 않아야 한다.**
class CardDeleting extends CardDeleteState {
  const CardDeleting();
}

/// 못 지웠다. 카드는 그대로 있다.
class CardDeleteFailed extends CardDeleteState {
  const CardDeleteFailed(this.failure);

  final RecordCardFailure failure;
}

/// 카드를 지운다.
///
/// ## ⚠️ family가 아니다
///
/// 한 번에 한 장만 지운다 — 상세 화면에서 누르는 것이 유일한 길이다. 번호로
/// 가르면 지우고 떠난 화면의 상태가 남는다.
final cardDeleteProvider =
    NotifierProvider<CardDeleteController, CardDeleteState>(
      CardDeleteController.new,
    );

class CardDeleteController extends Notifier<CardDeleteState> {
  @override
  CardDeleteState build() => const CardDeleteIdle();

  /// 지웠으면 `true`.
  ///
  /// ## ⚠️ 되돌릴 수 없다
  ///
  /// 서버에 논리 삭제 컬럼이 없다(설계 3절). **확인은 화면이 먼저 받는다** —
  /// 여기까지 왔으면 사용자가 이미 "지우기"를 골랐다는 뜻이다.
  Future<bool> delete(String cardId) async {
    // ⚠️ **두 번 가면 두 번째는 404를 받는다.** 첫 번째가 이미 지웠다 —
    // 아래에서 그것을 성공으로 받는다.
    if (state is CardDeleting) return false;

    state = const CardDeleting();
    try {
      await ref.read(recordCardRepositoryProvider).delete(cardId);
      // ⚠️ **달력을 무효화한다.** 안 하면 지운 카드가 달력에 남는다 — 저장
      // 때와 같은 결함이다(2026-11-18 에뮬레이터).
      //
      // `read(...notifier)`가 아니라 `invalidate`다. 직접 부르면 달력이 안 떠
      // 있어도 여기서 새로 세우고, 달력은 인증·dio를 거쳐 서버 주소를 찾다
      // 죽는다.
      ref.invalidate(recordCardControllerProvider);
      // ⚠️ **프로필 그리드도 버린다 — 묶음째다.** 키에 `limit`이 들어 있어
      // (그리드는 7장, 전체 보기는 전부) 하나만 버리면 **한쪽이 옛 목록을 들고
      // 남는다.** 프로필에 지운 카드가 그대로 서 있는 것이 그 모습이다.
      //
      // ⚠️ **`profile`의 provider를 부른다.** CLAUDE.md가 막은 것은 다른
      // feature의 **화면·위젯**이고 provider는 예외로 적혀 있다. `invalidate`는
      // 듣는 것이 아니라 버리는 것이라 순환 의존도 생기지 않는다.
      ref.invalidate(profileCardsProvider);
      state = const CardDeleteIdle();
      return true;
    } on RecordCardException catch (error) {
      // ⚠️ **이미 지워진 카드는 지워진 것이다.** 가이드 4절: "같은 카드의
      // 삭제를 재시도해 404가 와도 삭제 흐름을 마쳐 주세요." 실패로 다루면
      // 사용자가 **없는 카드를 못 지웠다는 말**을 듣고 화면에 남는다 — 다시
      // 눌러도 같은 답이다.
      if (error.failure == RecordCardFailure.notFound) {
        ref.invalidate(recordCardControllerProvider);
        ref.invalidate(profileCardsProvider);
        state = const CardDeleteIdle();
        return true;
      }
      state = CardDeleteFailed(error.failure);
      return false;
    } on Object {
      // 생각 못 한 실패다. **삼키지 않는다** — 삼키면 버튼이 영원히 도는
      // 것으로 보인다.
      state = const CardDeleteFailed(RecordCardFailure.server);
      return false;
    }
  }
}
