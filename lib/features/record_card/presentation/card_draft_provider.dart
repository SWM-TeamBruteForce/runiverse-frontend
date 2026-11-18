import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/domain/card_draft.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';

/// 쓰다 만 기록카드. **인자는 카드 번호이고, `null`이 새 카드다.**
///
/// ## ⚠️ 수정은 카드별로 따로 둔다
///
/// 새 카드를 쓰던 중에 남의 카드 수정으로 들어가도 섞이지 않아야 한다
/// (설계 7절). family 인자가 그것을 가른다.
///
/// ## ⚠️ `autoDispose`를 붙이지 않는다
///
/// 작성이 세 화면이라 라우트를 넘나든다. 붙이면 **사진 화면으로 가는 순간
/// 작성 1의 구독이 끊겨 쓴 것이 사라진다**(`docs/implementation-notes.md`
/// §5-1). 이 저장소의 수동 provider는 기본이 keepAlive라, 붙이지 않는 것이
/// 곧 명시다.
///
/// 수명(설계 7절):
///
/// | 언제 | 어떻게 |
/// |---|---|
/// | 저장 성공 | [CardDraftController.clear] |
/// | 작성 1에서 뒤로 | 쓴 것이 있으면 확인을 받고 [CardDraftController.clear] |
/// | 앱을 죽였다 켬 | **사라진다.** 영속화하지 않는다 |
final cardDraftProvider =
    NotifierProvider.family<CardDraftController, CardDraft, int?>(
      CardDraftController.new,
    );

class CardDraftController extends Notifier<CardDraft> {
  CardDraftController(this.cardId);

  /// 수정 중인 카드의 번호. **`null`이면 새 카드다.**
  final int? cardId;

  @override
  CardDraft build() => const CardDraft();

  /// 러닝 기록을 고른다.
  ///
  /// ⚠️ **다른 기록을 고르면 경로를 비운다.** 안 비우면 앞 기록의 선 아트가
  /// 이 카드에 그려진다. 같은 기록을 다시 누른 것은 비울 이유가 없다 —
  /// 버리면 상세 조회가 또 나간다.
  void pickRecord(RunRecord record) {
    final sameRecord = state.record?.id == record.id;
    state = state.copyWith(record: record, clearRoute: !sameRecord);
  }

  /// 고른 기록의 경로. **못 받았으면 `null`을 넣는다.**
  void setRoute(RouteArt? route) => state = route == null
      ? state.copyWith(clearRoute: true)
      : state.copyWith(route: route);

  void setActivity(RecordCardActivity activity) =>
      state = state.copyWith(activity: activity);

  /// 회고. **[CardDraft.reviewMaxLength]에서 자른다.**
  ///
  /// 입력 칸도 같은 수에서 막지만, 여기서 한 번 더 자른다 — 붙여넣기나 다른
  /// 경로로 긴 글이 들어오면 저장에서 거절당하고 쓴 글을 잃는다.
  void setReview(String text) => state = state.copyWith(
    reviewText: text.length > CardDraft.reviewMaxLength
        ? text.substring(0, CardDraft.reviewMaxLength)
        : text,
  );

  void clear() => state = const CardDraft();
}
