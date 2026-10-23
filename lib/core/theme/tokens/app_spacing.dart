/// 스페이싱 스케일 — 디자인 시스템 v1.1 §3-1. 4pt 베이스.
///
/// 여백은 이 스케일에서만 고른다. `EdgeInsets.all(16)` 대신
/// `EdgeInsets.all(AppSpacing.space4)`를 쓴다.
/// 스케일 밖의 값이 필요하다고 느껴지면 대개 레이아웃 구조가 잘못된 것이다.
abstract final class AppSpacing {
  /// 2 — 헤어라인 간격
  static const space0 = 2.0;

  /// 4 — 아이콘과 라벨 최소 간격
  static const space1 = 4.0;

  /// 8 — 칩 내부, 인접 요소
  static const space2 = 8.0;

  /// 12 — 카드 내부 행 간격
  static const space3 = 12.0;

  /// 16 — 기본 여백. 화면 좌우 패딩과 카드 내부 패딩이 이 값이다.
  static const space4 = 16.0;

  /// 20 — 섹션 내부, 프로필 헤더 좌우
  static const space5 = 20.0;

  /// 24 — 카드 간, 섹션 헤더
  static const space6 = 24.0;

  /// 32 — 블록 간
  static const space7 = 32.0;

  /// 40 — 큰 블록 분리
  static const space8 = 40.0;

  /// 48 — 히어로 여백
  static const space9 = 48.0;

  /// 64 — 화면 상하 특대
  static const space10 = 64.0;
}
