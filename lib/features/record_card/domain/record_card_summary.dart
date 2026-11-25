import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';

/// 달력 칸과 그날 시트가 쓰는 **카드 한 장의 요약.** 상세가 아니다.
///
/// ## ⚠️ 상세와 다른 타입인 이유
///
/// 서버가 세 자리에 **다른 필드**를 준다(연동 가이드). 달력(7-1)의
/// `recordCard`에는 번호·썸네일·경로(최대 50점)·유형뿐이고, 회고·사진·파티원·
/// 음악은 상세(8-1)에만 있다. 하나로 합치면 달력이 **모르는 값을 지어 넣어야**
/// 한다 — 그러면 "받아 온 것"과 "채워 넣은 것"을 화면이 구별할 수 없다.
///
/// ## ⚠️ [startedAt]과 [distanceMeters]는 **그 러닝의 값**이다
///
/// `recordCard` 안이 아니라 7-1 행의 바깥에 있다. 같은 행에서 함께 읽으므로
/// `ComposableRecord.record.startedAt`과 **늘 같다** — 한 DTO가 둘을 짓는다.
/// 여기 들고 있는 이유는 그날 시트가 카드만 받아 날짜와 거리를 적기 때문이다.
class RecordCardSummary {
  const RecordCardSummary({
    required this.id,
    required this.startedAt,
    required this.distanceMeters,
    this.thumbnailUrl,
    this.route = RouteArt.empty,
    this.activity,
  });

  /// `recordCardId`. UUID 문자열이다.
  final String id;

  /// 그 러닝의 시작 시각. **오프셋 없는 KST다.**
  final DateTime startedAt;

  /// 그 러닝의 총 이동 거리(m).
  final int distanceMeters;

  /// 칸에 깔 그림. **없으면 `null`이다** — 그때 [route]로 선을 긋고, 경로도
  /// 비어 있으면 점 하나를 남긴다(가이드 1절 표).
  final String? thumbnailUrl;

  /// 배경 없이 그릴 달린 모양. 달력은 **최대 50점**을 받는다.
  final RouteArt route;

  /// 활동 유형. **모르는 값이면 `null`이다.**
  ///
  /// ⚠️ 일상으로 뭉개지 않는다 — 대회에서 뛴 카드가 일상 필터에 걸리면
  /// 필터가 거짓말을 한다. `null`인 카드는 유형 필터 결과에서 빠진다.
  final RecordCardActivity? activity;

  /// [startedAt]에서 시·분을 자른 날짜. **달력이 이것으로 묶는다.**
  DateTime get day => DateTime(startedAt.year, startedAt.month, startedAt.day);
}
