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
/// [AuthCodeClient.authorize]는 **인가 코드만** 돌려준다.
///
/// ## 카카오톡이 있으면 카카오톡으로 간다
///
/// [AuthCodeClient.authorize]는 **브라우저(카카오계정)로만** 간다 — 카카오톡이
/// 깔려 있어도 아이디와 비밀번호를 치게 했다. 앱으로 가는 것은
/// [AuthCodeClient.authorizeWithTalk]이고, 둘 중 어느 쪽을 쓸지는 **부르는
/// 쪽이 정해야 한다.**
///
/// 받는 것은 둘 다 **인가 코드 + PKCE**라 서버가 하는 일은 달라지지 않는다.
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
      final code = await _code(verifier);
      return OauthCode(authorizationCode: code, codeVerifier: verifier);
    } on PlatformException catch (error) {
      // ⚠️ **브라우저를 닫으면 여기로 온다.** 네이티브 `CustomTabsActivity`가
      // `sendError("CANCELED", ...)`를 보내고, pigeon이 그것을 그대로 넘긴다.
      //
      // `KakaoClientException`이 아니다 — 그것은 Dart 쪽에서 던지는 경우다
      // (리다이렉트 주소 불일치 등). 에뮬레이터에서 실제로 눌러보고 알았다.
      _log('platform', '${error.code} · ${error.message}');
      throw AuthException(_failureOf(error));
    } on KakaoClientException catch (error) {
      // SDK가 Dart에서 막은 경우. 취소도 이 형태로 올 수 있어 함께 본다.
      _log('client', '${error.reason} · ${error.msg}');
      throw AuthException(_failureOf(error));
    } on KakaoAuthException catch (error) {
      // 카카오 동의 화면에서 "취소"를 눌렀다. 위와 예외 타입이 다르다 —
      // **둘 다 취소이므로 둘 다 잡아야 한다.**
      _log('auth', '${error.error} · ${error.errorDescription}');
      throw AuthException(_failureOf(error));
    } on Exception catch (error) {
      // SDK가 던지는 것이 이 둘만은 아니다. 무엇이 오든 화면은 같은 말을 한다.
      //
      // ⚠️ **취소가 여기로 떨어지면 사용자가 오류 문구를 본다.** 로그를 남기는
      // 이유가 이것이다 — 어떤 예외가 오는지 모르면 고칠 수도 없다.
      _log('기타', '${error.runtimeType} · $error');
      throw const AuthException(AuthFailure.oauthFailed);
    }
  }

  /// 인가 코드를 받아 온다. **카카오톡이 먼저다.**
  Future<String> _code(String verifier) async {
    if (await _talkAvailable()) {
      try {
        return await AuthCodeClient.instance.authorizeWithTalk(
          redirectUri: KakaoSdk.redirectUri,
          codeVerifier: verifier,
        );
      } on Exception catch (error) {
        // ⚠️ **취소면 여기서 끝낸다.** 카카오톡에서 "취소"를 누른 사람에게
        // 브라우저를 다시 띄우면, 끈 창이 다른 모습으로 또 열린다.
        if (cancelledBy(error)) rethrow;

        // 카카오톡으로 못 했다. 앱 버전이 낮거나, 방금 로그아웃됐거나,
        // 인텐트가 막힌 경우다. **로그인을 막지 않고** 브라우저로 간다.
        _log('talk', '카카오톡으로 못 했다 — 브라우저로 간다 · $error');
      }
    }

    return AuthCodeClient.instance.authorize(
      redirectUri: KakaoSdk.redirectUri,
      codeVerifier: verifier,
    );
  }

  /// 카카오톡으로 갈 수 있는가.
  ///
  /// ## ⚠️ "깔려 있는가"보다 좁다
  ///
  /// SDK는 카카오톡의 `CAPRI_LOGGED_IN_ACTIVITY`가 응답하는지 본다 — **카카오톡에
  /// 로그인해 둔 상태**여야 `true`다. 깔려만 있고 로그아웃이면 `false`이고,
  /// 그때 브라우저로 가는 것이 맞다. 앱으로 보내도 로그인 화면이 뜬다.
  ///
  /// 안드로이드 11+에서 다른 앱이 보이려면 `<queries>` 선언이 필요한데,
  /// **SDK가 자기 매니페스트에 넣어 둔다**(`kakao_flutter_sdk_common`의
  /// `com.kakao.talk`). 앱 매니페스트에 또 쓰지 않는다.
  Future<bool> _talkAvailable() async {
    try {
      return await isKakaoTalkInstalled();
    } on Exception catch (error) {
      // 못 물어봤다. **없는 것으로 보고 브라우저로 간다** — 여기서 멈추면
      // 로그인할 길이 아예 없어진다.
      _log('talk', '설치 여부를 못 물어봤다 · ${error.runtimeType} · $error');
      return false;
    }
  }

  static AuthFailure _failureOf(Object error) =>
      cancelledBy(error) ? AuthFailure.oauthCancelled : AuthFailure.oauthFailed;

  /// 사용자가 **취소한 것**인가.
  ///
  /// 세 가지 모습으로 온다. 카카오톡·브라우저·동의 화면이 각각 다른 예외를
  /// 던지는데 셋 다 "사용자가 그만두었다"는 같은 뜻이다 —
  /// [AuthFailure.oauthCancelled]는 화면에 오류 문구를 띄우지 않는다.
  @visibleForTesting
  static bool cancelledBy(Object error) => switch (error) {
    // 네이티브가 창을 닫으며 보내는 코드.
    PlatformException(:final code) => code == 'CANCELED',
    KakaoClientException(:final reason) => reason == ClientErrorCause.cancelled,
    KakaoAuthException(:final error) => error == AuthErrorCause.accessDenied,
    _ => false,
  };
}
