import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';

/// 쓰다 만 기록카드 한 장.
///
/// 작성이 세 화면이라(기록·유형·회고 → 사진 → 공개범위·음악) 라우트를
/// 넘나든다. 그 사이를 이것 하나가 따라간다 — 들고 있는 쪽은
/// `CardDraftController`다.
///
/// ## ⚠️ 러닝 기록은 **고르는** 것이고, 경로는 **딸려 오는** 것이다
///
/// [record]는 사용자가 목록에서 고른다. [route]는 그 기록의 상세를 받아 와야
/// 알 수 있어, 고른 뒤에 채워지고 **못 받으면 비어 있다.** 그래서 경로는
/// [canProceed]의 조건이 아니다 — 트레드밀 러닝은 경로가 아예 없다.
class CardDraft {
  const CardDraft({
    this.record,
    this.route,
    this.activity,
    this.reviewText = '',
  });

  /// 이 카드가 붙을 러닝 기록. 고르기 전에는 `null`이다.
  final RunRecord? record;

  /// [record]의 경로 선 아트. **못 받았거나 경로가 없는 러닝이면 `null`이다.**
  final RouteArt? route;

  /// 일상 · 대회 · 여행. 고르기 전에는 `null`이다.
  final RecordCardActivity? activity;

  /// 회고. **설계가 필수로 못 박았다**(6-2). 빈 문자열이 "아직 안 썼다"다.
  final String reviewText;

  /// 회고 상한. 서버 `review_text`가 받는 길이이고, 입력 칸도 여기서 멈춘다.
  static const reviewMaxLength = 1000;

  /// 다음 화면으로 갈 수 있나 — **기록 · 유형 · 회고가 다 차야 한다**(설계 6-2).
  ///
  /// 공백뿐인 회고는 쓴 것으로 세지 않는다. 띄어쓰기 한 칸으로 필수 항목을
  /// 통과하면 회고를 필수로 둔 뜻이 없어진다.
  bool get canProceed =>
      record != null && activity != null && reviewText.trim().isNotEmpty;

  /// 버리기 전에 사용자에게 물어야 하나.
  ///
  /// ## ⚠️ [record]와 [route]는 세지 않는다
  ///
  /// 둘은 **앱이 꽂아 준 것**이다 — 달력의 운동화를 누르거나 러닝 요약에서
  /// 들어오면 고르지 않아도 차 있다. 그것만 보고 확인을 받으면 잘못 들어온
  /// 사람이 나갈 때마다 막힌다. 사용자가 손으로 넣은 것은 유형과 회고다.
  bool get isDirty => activity != null || reviewText.trim().isNotEmpty;

  /// ⚠️ **비우려면 `clear*`를 쓴다.** `record: null`은 "안 바꾼다"와 구별되지
  /// 않는다. `RecordCardData.copyWith(clearFilter:)`와 같은 꼴이다.
  CardDraft copyWith({
    RunRecord? record,
    bool clearRecord = false,
    RouteArt? route,
    bool clearRoute = false,
    RecordCardActivity? activity,
    String? reviewText,
  }) => CardDraft(
    record: clearRecord ? null : (record ?? this.record),
    route: clearRoute ? null : (route ?? this.route),
    activity: activity ?? this.activity,
    reviewText: reviewText ?? this.reviewText,
  );
}
