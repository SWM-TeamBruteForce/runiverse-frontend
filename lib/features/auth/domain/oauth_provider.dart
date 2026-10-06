/// 어느 소셜로 로그인하는가.
///
/// 문자열을 화면에 흩뿌리지 않는다. 이 값이 서버 경로
/// (`POST /auth/oauth/{provider}`)에 그대로 들어가므로, 오타가 나면
/// `UNSUPPORTED_PROVIDER`가 돌아온다 — 컴파일러가 잡아주는 편이 낫다.
///
/// **`apple`은 없다.** 서버 `Provider` enum에 `KAKAO`·`GOOGLE`뿐이라
/// 지금 넣으면 부를 수 없는 값이 생긴다.
enum OauthProvider {
  kakao;

  /// 서버 경로에 쓰는 값.
  ///
  /// ⚠️ 예전 주석은 "서버가 `toUpperCase` 로 바꿔 읽으므로 소문자로 보낸다"고
  /// 적혀 있었는데 **더는 맞지 않는다.** 서버 경로가 `/oauth/kakao` ·
  /// `/oauth/google` 소문자로 고정돼 있다.
  String get path => name;
}
