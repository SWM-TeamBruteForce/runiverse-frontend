/// 경로 상수 — 화면 이동은 전부 이 상수를 거친다.
///
/// `context.go('/record')`처럼 문자열을 직접 쓰면 오타를 컴파일러가 못 잡는다.
/// `context.go(AppRoutes.record)`는 잡는다.
///
/// ## 딥링크
///
/// 여기 있는 경로가 곧 알림 딥링크의 대상이다.
/// 매핑은 **이 파일 한 곳에서만** 관리하고, 대상이 없으면 [home]으로 폴백한다.
/// 화면마다 자기 링크를 파싱하기 시작하면 규칙이 흩어진다.
///
/// ## `/`를 쓰지 않는 이유
///
/// 홈을 `/`로 두면 딥링크가 `runiverse://`처럼 끝나서 어느 화면인지 안 보인다.
/// 모든 탭을 `/이름` 형태로 맞췄다. 플랫폼이 넘겨주는 기본 경로 `/`는
/// go_router가 `initialLocation`([home])으로 대체한다.
abstract final class AppRoutes {
  /// 홈 (S05)
  static const home = '/home';

  /// 기록 (S21)
  static const record = '/record';

  /// 피드 — 준비 중
  static const feed = '/feed';

  /// 대회일정 — 준비 중
  static const competition = '/competition';

  /// 본인 프로필 (S20)
  static const profile = '/profile';
}
