import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
import 'package:runiverse/core/config/app_config.dart';
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

  /// SDK가 무엇을 던졌는지 남긴다.
  ///
  /// 화면에는 뭉뚱그린 문구를 쓰므로, 이 로그가 없으면 **취소인지 오류인지도
  /// 구분할 수 없다.** 서버 `code`를 디버그로만 남기는 것과 같은 이유다.
  void _log(String kind, String detail) {
    if (kDebugMode) debugPrint('[kakao] $kind: $detail');
  }

  @override
  Future<OauthAuthorization> authorize(OauthProvider provider) async {
    // ⚠️ **키가 없으면 SDK를 부르기 전에 돌아선다.** `main.dart`가 키 없이는
    // `KakaoSdk.init`을 건너뛰므로, 그대로 부르면 `LateInitializationError`가
    // 난다. 그것은 `Exception`이 아니라 **`Error`**라 아래 `on Exception`을
    // 포함해 어떤 catch에도 걸리지 않고 화면까지 그대로 올라간다.
    //
    // 이유를 [AuthFailure.oauthFailed]로 뭉뚱그리지 않는다 —
    // "다시 시도해주세요"는 거짓말이다. 다시 눌러도 키는 생기지 않는다.
    if (!AppConfig.hasKakaoNativeAppKey) {
      _log('설정', '앱 키가 주입되지 않았다 — SDK를 부르지 않는다');
      throw const AuthException(AuthFailure.oauthUnavailable);
    }

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
    } on PlatformException catch (error) {
      // ⚠️ **브라우저를 닫으면 여기로 온다.** 네이티브 `CustomTabsActivity`가
      // `sendError("CANCELED", ...)`를 보내고, pigeon이 그것을 그대로 넘긴다.
      //
      // `KakaoClientException`이 아니다 — 그것은 Dart 쪽에서 던지는 경우다
      // (리다이렉트 주소 불일치 등). 에뮬레이터에서 실제로 눌러보고 알았다.
      _log('platform', '${error.code} · ${error.message}');
      throw AuthException(
        error.code == 'CANCELED'
            ? AuthFailure.oauthCancelled
            : AuthFailure.oauthFailed,
      );
    } on KakaoClientException catch (error) {
      // SDK가 Dart에서 막은 경우. 취소도 이 형태로 올 수 있어 함께 본다.
      _log('client', '${error.reason} · ${error.msg}');
      throw AuthException(
        error.reason == ClientErrorCause.cancelled
            ? AuthFailure.oauthCancelled
            : AuthFailure.oauthFailed,
      );
    } on KakaoAuthException catch (error) {
      // 카카오 동의 화면에서 "취소"를 눌렀다. 위와 예외 타입이 다르다 —
      // **둘 다 취소이므로 둘 다 잡아야 한다.**
      _log('auth', '${error.error} · ${error.errorDescription}');
      throw AuthException(
        error.error == AuthErrorCause.accessDenied
            ? AuthFailure.oauthCancelled
            : AuthFailure.oauthFailed,
      );
    } on Exception catch (error) {
      // SDK가 던지는 것이 이 둘만은 아니다. 무엇이 오든 화면은 같은 말을 한다.
      //
      // ⚠️ **취소가 여기로 떨어지면 사용자가 오류 문구를 본다.** 로그를 남기는
      // 이유가 이것이다 — 어떤 예외가 오는지 모르면 고칠 수도 없다.
      _log('기타', '${error.runtimeType} · $error');
      throw const AuthException(AuthFailure.oauthFailed);
    }
  }
}
