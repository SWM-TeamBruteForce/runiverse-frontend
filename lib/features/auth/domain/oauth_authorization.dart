/// 소셜 인가를 마치고 얻은 것. **서버에 그대로 넘긴다.**
///
/// ## ⚠️ 제공자마다 모양이 다르다
///
/// 카카오는 **인가 코드 + PKCE 검증값**을, 구글은 **ID 토큰** 하나를 준다.
/// 둘을 한 클래스에 담으면 "구글인데 `codeVerifier`가 뭐지" 같은 빈 자리가
/// 생기고, 그 자리를 채우거나 비우는 판단이 코드 여기저기로 흩어진다.
///
/// sealed 로 가르면 **서버 본문을 만드는 자리에서 컴파일러가 빠짐을 잡는다**
/// (`http_auth_repository.signInWithOauth`). 제공자가 늘 때도 같다.
sealed class OauthAuthorization {
  const OauthAuthorization();
}

/// 카카오 — 인가 코드와 검증값. **둘을 함께 보낸다.**
///
/// ## 왜 묶어 두는가
///
/// 따로 들고 다니면 짝이 어긋난 채로 보낼 수 있다. 인가할 때 쓴 검증값과
/// 서버가 토큰 교환에 보내는 검증값이 다르면 **카카오가 거부하는데,
/// 그 증상은 앱이 아니라 서버에서 난다** — 원인을 찾기 어렵다.
///
/// 한 묶음으로 만들어 두면 둘이 떨어질 자리가 없다.
class OauthCode extends OauthAuthorization {
  const OauthCode({
    required this.authorizationCode,
    required this.codeVerifier,
  });

  /// 카카오가 준 1회용 인가 코드.
  final String authorizationCode;

  /// 인가를 시작할 때 쓴 PKCE 검증값. **서버가 이것으로 토큰을 교환한다.**
  final String codeVerifier;
}

/// 구글 — ID 토큰 하나.
///
/// 구글이 서명한 "이 사람이 누구인지"의 증명서다. 서버가 구글 공개키로 서명을
/// 확인하므로 **앱이 토큰을 교환하지 않는다** — 인가 코드도 PKCE 검증값도
/// `redirect_uri` 도 없다(연동 가이드 1절).
class OauthIdToken extends OauthAuthorization {
  const OauthIdToken(this.idToken);

  final String idToken;
}
