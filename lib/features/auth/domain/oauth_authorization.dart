/// 소셜 인가를 마치고 얻은 것. **둘을 함께 서버에 보낸다.**
///
/// ## 왜 묶어 두는가
///
/// 따로 들고 다니면 짝이 어긋난 채로 보낼 수 있다. 인가할 때 쓴 검증값과
/// 서버가 토큰 교환에 보내는 검증값이 다르면 **카카오가 거부하는데,
/// 그 증상은 앱이 아니라 서버에서 난다** — 원인을 찾기 어렵다.
///
/// 한 묶음으로 만들어 두면 둘이 떨어질 자리가 없다.
class OauthAuthorization {
  const OauthAuthorization({
    required this.authorizationCode,
    required this.codeVerifier,
  });

  /// 카카오가 준 1회용 인가 코드.
  final String authorizationCode;

  /// 인가를 시작할 때 쓴 PKCE 검증값. **서버가 이것으로 토큰을 교환한다.**
  final String codeVerifier;
}
