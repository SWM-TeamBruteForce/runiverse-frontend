import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';

/// 작성 화면의 기록 목록 한 줄 — 러닝 기록 하나와 **그 기록에 이미 쓴 카드**.
class ComposableRecord {
  const ComposableRecord({required this.record, this.existingCard});

  final RunRecord record;

  /// 이 기록으로 **이미 쓴 카드**. 없으면 `null`이다.
  ///
  /// 목록은 이 줄에 `카드`를 붙이고, 누르면 그 카드로 보낸다. **회색으로
  /// 죽이지 않는다** — 왜 못 고르는지 알 수 없다(설계 6-2).
  ///
  /// ⚠️ **번호가 아니라 카드를 들고 있는 이유**: 상세 라우트가 카드를
  /// `extra`로 요구하고, 없으면 탭으로 돌려보낸다(`app_router.dart`). 카드
  /// 단건 조회 API도 없다. 그날 카드는 [joinCards]가 이미 받아 왔으므로
  /// 들고 있는 값이고, 번호만 남기면 열 수 없는 번호가 된다.
  final RecordCard? existingCard;

  String? get existingCardId => existingCard?.id;

  bool get hasCard => existingCard != null;
}

/// 그날 러닝 기록에 그날 카드를 맞춰 붙인다.
///
/// ## ⚠️ 서버가 "카드 있음"을 알려 주지 않는다
///
/// 설계 10절 질문 3이 러닝 기록 목록 응답에 그 값을 실어 달라는 것인데, 아직
/// 없다. 대신 **내 카드를 그날치만 받아 [RecordCard.runningRecordId]로 맞춘다**
/// — 왕복이 하나 늘지만 백엔드를 기다리지 않아도 되고, 조회가 그날로 좁혀져
/// 비용이 작다. 서버가 깃발을 주는 날 이 함수는 사라진다.
///
/// 결과는 **[records]의 순서를 그대로 유지한다** — 화면에 뜨는 차례다.
List<ComposableRecord> joinCards({
  required List<RunRecord> records,
  required List<RecordCard> cards,
}) {
  // ⚠️ 한 기록에 카드가 둘로 와도 터지지 않는다. 서버에
  // `unique(running_record_id)`가 있지만 앱이 그것을 믿을 이유는 없다 —
  // 늘 **첫 카드**를 쓴다. 아무거나 고르면 화면이 조회마다 달라진다.
  final byRecord = <int, RecordCard>{};
  for (final card in cards) {
    byRecord.putIfAbsent(card.runningRecordId, () => card);
  }

  return [
    for (final record in records)
      ComposableRecord(record: record, existingCard: byRecord[record.id]),
  ];
}
