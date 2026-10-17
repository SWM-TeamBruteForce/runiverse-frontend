/// 어느 소셜로 로그인하는가.
///
/// 문자열을 화면에 흩뿌리지 않는다. 이 값이 서버 경로
/// (`POST /auth/oauth/{provider}`)에 그대로 들어가므로, 오타가 나면
/// `UNSUPPORTED_PROVIDER`가 돌아온다 — 컴파일러가 잡아주는 편이 낫다.
///
/// ## ⚠️ `apple`은 iOS에서만 부를 수 있다
///
/// 서버는 **iOS 번들 ID로 발급된 ID 토큰만** 받는다(연동 가이드 3절). 안드로이드는
/// 애플 웹 흐름을 거쳐야 하는데 그쪽 등록이 없어서, 값이 아니라 **버튼이** 없다
/// (`sign_in_page.dart`). 여기서 플랫폼을 가르지 않는 이유는, enum 이 "서버가
/// 무엇을 받는가"만 말하고 "지금 눌릴 수 있는가"는 화면이 정하기 때문이다.
enum OauthProvider {
  kakao,
  google,
  apple;

  /// 서버 경로에 쓰는 값.
  ///
  /// ⚠️ 예전 주석은 "서버가 `toUpperCase` 로 바꿔 읽으므로 소문자로 보낸다"고
  /// 적혀 있었는데 **더는 맞지 않는다.** 서버 경로가 `/oauth/kakao` ·
  /// `/oauth/google` · `/oauth/apple` 소문자로 고정돼 있다.
  String get path => name;
}
