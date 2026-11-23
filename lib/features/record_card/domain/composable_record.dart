import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/domain/record_card_summary.dart';

/// 7-1 응답의 한 줄 — 러닝 기록 하나와 **그 기록에 쓴 카드**.
///
/// 달력·그날 시트·작성 화면·러닝 요약이 모두 이것을 본다. 한 조회가 둘을 함께
/// 주므로(연동 가이드 1절) **맞춰 붙이는 일이 없다** — 묶음 6까지 있었던
/// `joinCards`가 그 일을 했고, 서버가 깃발을 주면서 사라졌다.
class ComposableRecord {
  const ComposableRecord({required this.record, this.existingCard});

  final RunRecord record;

  /// 이 기록으로 **이미 쓴 카드**. 없으면 `null`이다.
  ///
  /// 작성 목록은 이 줄에 `카드`를 붙이고, 누르면 그 카드의 수정으로 보낸다.
  /// **회색으로 죽이지 않는다** — 왜 못 고르는지 알 수 없다(설계 6-2).
  ///
  /// ## ⚠️ 요약이다. 상세가 아니다
  ///
  /// 7-1이 싣는 것은 번호·썸네일·경로·유형뿐이다. 회고·사진·파티원·음악은
  /// 상세(8-1)로 따로 받는다 — 상세 화면이 **번호로** 읽는다.
  ///
  /// 묶음 6까지는 여기에 **카드 전부**를 들고 있었다. 상세 라우트가 카드를
  /// `extra`로 요구했기 때문인데, 지금은 번호 하나로 열린다.
  final RecordCardSummary? existingCard;

  String? get existingCardId => existingCard?.id;

  bool get hasCard => existingCard != null;

  /// 이 기록이 뛰어진 날. 시·분이 잘려 있다. **달력이 이것으로 묶는다.**
  DateTime get day => record.day;
}
