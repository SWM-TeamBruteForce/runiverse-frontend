/// 고지 문서 주소.
///
/// ## 링크마다 따로 본다
///
/// 아직 게시하지 않은 문서는 주소를 `''`로 둔다. [isReady]가 링크마다
/// 판정해서 빈 문서만 "준비 중"을 띄우고, 있는 문서는 그대로 열린다.
///
/// ## ⚠️ 주소를 옮기면 앱을 다시 내야 한다
///
/// 지금은 GitHub Pages다. 나중에 랜딩페이지로 옮기면 **상수 변경 = 릴리스**다.
/// 서버에서 받아오는 구조가 아니다.
///
/// ## `AppConfig`에 두지 않은 이유
///
/// 시크릿이 아니고 빌드마다 달라지지도 않는다. `--dart-define`으로 넘기면
/// 넘기는 것을 잊었을 때 링크가 조용히 사라진다 — 그 편이 더 나쁘다.
abstract final class LegalLinks {
  const LegalLinks._();

  /// 개인정보처리방침 전문. **두 스토어 심사가 모두 요구한다.**
  static const privacy =
      'https://swm-teambruteforce.github.io/runiverse-legal/privacy.html';

  /// 계정·데이터 삭제 안내. **구글 플레이 심사가 요구한다** — 앱에서 탈퇴할 수
  /// 있어도 웹에서 절차를 볼 수 있어야 한다.
  static const accountDeletion =
      'https://swm-teambruteforce.github.io/runiverse-legal/account-deletion.html';

  /// 이용약관 전문. 가입 화면이 필수 동의로 받는다.
  static const terms =
      'https://swm-teambruteforce.github.io/runiverse-legal/terms.html';

  /// 열 수 있는 주소인가.
  static bool isReady(String url) => url.isNotEmpty;
}
