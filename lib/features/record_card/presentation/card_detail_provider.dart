import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';

/// 카드 한 장 전부 (8-1).
///
/// ## ⚠️ `retry`를 끈다
///
/// Riverpod 3은 실패한 provider를 **열 번쯤, 38초에 걸쳐** 다시 부른다. 그
/// 동안 상태가 `loading`에 머물러 **화면이 오류 갈래에 닿지 못한다** — 사용자는
/// 영원히 도는 표시를 본다. `composeRecordsProvider`가 같은 이유로 끈다.
///
/// 404는 특히 그렇다. 삭제된 카드를 열 번 더 물어도 같은 답이다.
///
/// ## ⚠️ 듣는 사람이 없으면 버려진다
///
/// `autoDispose`라 `read`만 하면 그 직후 버려지고 다음 `read`가 **처음부터
/// 다시** 세운다. 화면에서는 위젯이 듣고 있어 그 일이 없지만, 테스트는
/// `container.listen`을 걸어 둬야 한다.
///
/// 버려지는 것이 여기서는 이득이다 — 카드를 닫으면 들고 있을 이유가 없고,
/// 다시 들어오면 **새로 받는다.** 가이드가 "상세에 다시 들어올 때도 8-1을
/// 호출"하라고 적은 것이 그대로 지켜진다(수정·재요청 뒤 기본곡이 바뀐다).
final cardDetailProvider = FutureProvider.autoDispose
    .family<RecordCard, String>(
      retry: (_, _) => null,
      (ref, cardId) => ref.read(recordCardRepositoryProvider).detailOf(cardId),
    );
