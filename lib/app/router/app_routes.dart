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
  // ── 온보딩 — 탭 셸 밖이다 ────────────────────────────────────
  //
  // 하단 탭이 없는 화면들이다. 셸 안에 넣으면 탭 바가 같이 뜬다.

  /// 스플래시 (S01). 앱의 첫 화면.
  static const splash = '/splash';

  /// 온보딩 소개 3장 (S02)
  static const onboardingIntro = '/onboarding';

  /// 시작 방식 선택 (S02.5) — 카카오 · 애플 · 이메일
  static const authIntro = '/auth';

  /// 이메일 로그인
  ///
  /// **정본 와이어프레임에 없는 화면이다.** 백엔드가 이메일·비밀번호 방식을 요구해
  /// 새로 만들었다 (`docs/implementation-notes.md`).
  static const signIn = '/auth/sign-in';

  /// 이메일 회원가입
  ///
  /// 가입에 성공한 사람은 **신규**다. 약관(S03) → 프로필(S04)을 거쳐 홈으로 간다.
  /// 로그인한 사람은 기존이므로 곧장 홈으로 간다.
  ///
  /// ⚠️ 서버가 "이 사람이 온보딩을 마쳤는가"를 알려주지 않아서 쓰는 방법이다.
  /// 앱을 지웠다 깔면 기존 사용자도 프로필 화면을 다시 본다.
  static const signUp = '/auth/sign-up';

  /// 약관 동의 (S03)
  ///
  /// 가입한 사람만 지나간다. 이미 계정이 있는 사람은 로그인에서 곧장 홈으로 간다.
  static const terms = '/onboarding/terms';

  /// 프로필 등록 (S04)
  ///
  /// 다음은 시그니처 컬러 리빌(S04.5)이다. 그 화면이 생기기 전까지 홈으로 간다.
  static const profileSetup = '/onboarding/profile';

  // ── 탭 셸 안 ────────────────────────────────────────────────

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
