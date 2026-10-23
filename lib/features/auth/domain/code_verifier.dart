import 'dart:math';

/// PKCE의 `code_verifier`를 만든다 (RFC 7636).
///
/// ## 무엇을 막는가
///
/// 앱이 비밀값을 만들어 두고, 인가를 시작할 때는 그것의 **해시**만 카카오에 보낸다.
/// 나중에 토큰으로 바꿀 때 원본 비밀값을 함께 내야 하므로, **인가 코드만 가로챈
/// 쪽은 토큰을 얻지 못한다.** 커스텀 URL 스킴은 같은 기기의 다른 앱이 가로챌 수
/// 있어서 이 보호가 필요하다.
///
/// ## 해시는 SDK가 계산한다
///
/// 카카오 SDK의 `PKCE(codeVerifier)`가 SHA-256으로 `code_challenge`를 만든다.
/// 앱이 만들 것은 검증값뿐이라 **해시 패키지가 필요 없다.**
///
/// ## ⚠️ 이 값을 서버에도 보낸다
///
/// 토큰 교환은 서버가 한다. 그래서 검증값이 **앱 → 서버 → 카카오** 로 흘러간다.
/// 인가를 시작할 때 쓴 값과 서버가 보내는 값이 같아야 하므로, 한 번 만든 것을
/// 그 로그인이 끝날 때까지 들고 있어야 한다.
abstract final class CodeVerifier {
  /// RFC 7636이 정한 범위는 43~128자다. 넉넉한 쪽을 쓴다.
  static const length = 64;

  /// RFC 7636의 `unreserved` 집합. 다른 문자가 섞이면 URL 인코딩 단계에서
  /// 값이 달라져, 카카오가 기억하는 해시와 어긋난다.
  static const _allowed =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  /// ⚠️ **`Random.secure()`를 쓴다.** 기본 `Random()`은 예측 가능해서
  /// 이 값이 막으려던 것을 막지 못한다.
  static final _random = Random.secure();

  static String generate() => String.fromCharCodes(
    Iterable.generate(
      length,
      (_) => _allowed.codeUnitAt(_random.nextInt(_allowed.length)),
    ),
  );
}
