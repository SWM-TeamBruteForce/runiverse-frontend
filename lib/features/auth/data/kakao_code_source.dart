import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/code_verifier.dart';
import 'package:runiverse/features/auth/domain/oauth_authorization.dart';
import 'package:runiverse/features/auth/domain/oauth_code_source.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';

/// 카카오 SDK로 인가 코드를 받아온다.
///
/// ## `UserApi`를 쓰지 않는다
///
/// 흔한 예제인 `UserApi.instance.loginWithKakaoTalk()`은 **액세스 토큰을 앱이
/// 받는다.** 이 서비스는 서버가 토큰을 교환하므로 그 방식과 맞지 않는다.
/// [AuthCodeClient.authorize]는 **인가 코드만** 돌려주고, 카카오톡 앱이 있으면
/// 앱으로 없으면 웹으로 SDK가 알아서 분기한다.
///
/// ## 리다이렉트 주소를 직접 만들지 않는다
///
/// [KakaoSdk.redirectUri]를 그대로 쓴다. 네이티브에서는 **다른 값을 쓸 방법이
/// 아예 없고**(SDK가 `notSupported`로 거절한다), 직접 조립하면 오타가 생길
/// 자리만 늘어난다.
///
/// ⚠️ 이 값(`kakao<앱키>://oauth`)은 **서버 `oauth.kakao.redirect-uri`와 같아야
/// 한다.** 다르면 서버의 토큰 교환이 카카오에 거부당한다.
class KakaoCodeSource implements OauthCodeSource {
  const KakaoCodeSource();

  @override
  Future<OauthAuthorization> authorize(OauthProvider provider) async {
    // 검증값을 먼저 만들어 둔다. SDK가 이것의 SHA-256을 카카오에 보내고,
    // 원본은 우리가 들고 있다가 서버에 넘긴다.
    final verifier = CodeVerifier.generate();

    try {
      final code = await AuthCodeClient.instance.authorize(
        redirectUri: KakaoSdk.redirectUri,
        codeVerifier: verifier,
      );
      return OauthAuthorization(
        authorizationCode: code,
        codeVerifier: verifier,
      );
    } on KakaoClientException catch (error) {
      // 브라우저를 닫았다.
      throw AuthException(
        error.reason == ClientErrorCause.cancelled
            ? AuthFailure.oauthCancelled
            : AuthFailure.oauthFailed,
      );
    } on KakaoAuthException catch (error) {
      // 카카오 동의 화면에서 "취소"를 눌렀다. 위와 예외 타입이 다르다 —
      // **둘 다 취소이므로 둘 다 잡아야 한다.**
      throw AuthException(
        error.error == AuthErrorCause.accessDenied
            ? AuthFailure.oauthCancelled
            : AuthFailure.oauthFailed,
      );
    } on Exception {
      // SDK가 던지는 것이 이 둘만은 아니다. 무엇이 오든 화면은 같은 말을 한다.
      throw const AuthException(AuthFailure.oauthFailed);
    }
  }
}
