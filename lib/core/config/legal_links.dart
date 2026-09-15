/// 고지 문서 주소.
///
/// ## 링크마다 따로 본다
///
/// 예전에는 `isReady` 하나로 묶여 있었다. 그때는 문서가 하나도 없어서 그걸로
/// 충분했지만, 지금은 **방침과 계정삭제는 있고 이용약관만 없다.** 묶어 두면
/// 있는 문서까지 함께 잠긴다.
///
/// ## 이용약관은 아직 없다
///
/// 법정 필수가 아니라 신고·제재 기능을 붙일 때 만든다. 그때까지 설정의
/// 이용약관 행은 눌러도 "준비 중"이 뜬다. **행을 감추지 않는 이유는, 약관을
/// 볼 수 있어야 한다는 사실 자체가 약속**이라 자리를 비워두면 나중에 붙이는
/// 것을 잊기 때문이다.
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

  /// 개인정보처리방침 전문. **구글 플레이 심사가 요구한다.**
  static const privacy =
      'https://swm-teambruteforce.github.io/runiverse-legal/privacy.html';

  /// 계정·데이터 삭제 안내. **구글 플레이 심사가 요구한다** — 앱에서 탈퇴할 수
  /// 있어도 웹에서 절차를 볼 수 있어야 한다.
  static const accountDeletion =
      'https://swm-teambruteforce.github.io/runiverse-legal/account-deletion.html';

  /// 이용약관 전문. 아직 문서가 없다.
  static const terms = '';

  /// 열 수 있는 주소인가.
  static bool isReady(String url) => url.isNotEmpty;
}
