import 'package:flutter/foundation.dart';
import 'package:runiverse/features/auth/domain/apple_nonce.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/oauth_authorization.dart';
import 'package:runiverse/features/auth/domain/oauth_code_source.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// 애플 로그인 창을 띄우고 **ID 토큰과 nonce 원본**을 받아온다.
///
/// ## ⚠️ 구글과 다른 점은 nonce 하나다
///
/// 앱이 로그인마다 무작위 값을 만들어 **해시를 애플에, 원본을 서버에** 보낸다.
/// 애플은 받은 해시를 ID 토큰 안에 박아 주고, 서버는 원본을 해시해 그 값과
/// 대조한다(연동 가이드 1절). 가로챈 토큰을 다시 보내도 그때의 원본이 없으니
/// 통과하지 못한다.
///
/// 구글처럼 ID 토큰 교환은 하지 않는다 — 앱이 받은 것을 그대로 넘긴다.
///
/// ## iOS에서만 부른다
///
/// 안드로이드에서는 패키지가 애플 **웹** 흐름(Chrome Custom Tab)을 여는데,
/// 그러려면 `serviceIdentifier`와 `redirectUri`가 있어야 하고 토큰의 발급
/// 대상도 번들 ID가 아니게 된다. 서버는 iOS 번들 ID만 인정하므로
/// (연동 가이드 3절) **토큰은 받아지는데 401이 돌아온다** — 앱에서는
/// 성공처럼 보여 찾기 어려운 실패다.
///
/// 로그인 화면이 애플 타일을 iOS에서만 그리지만, 여기서도 한 번 더 막는다.
/// 딥링크나 테스트가 화면을 지나지 않고 들어올 수 있다.
class AppleCodeSource implements OauthCodeSource {
  const AppleCodeSource();

  /// SDK가 무엇을 던졌는지 남긴다. 화면에는 뭉뚱그린 문구를 쓰므로,
  /// 이 로그가 없으면 **취소인지 오류인지도 구분할 수 없다.**
  ///
  /// ⚠️ **ID 토큰과 nonce 는 절대 남기지 않는다**(연동 가이드 6절).
  void _log(String kind, String detail) {
    if (kDebugMode) debugPrint('[apple] $kind: $detail');
  }

  @override
  Future<OauthAuthorization> authorize(OauthProvider provider) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      // [AuthFailure.oauthFailed]로 뭉뚱그리지 않는다 — "다시 시도해주세요"는
      // 거짓말이다. 다시 눌러도 이 기기에서는 되지 않는다.
      //
      // [AuthFailure.oauthUnavailable](키가 없는 빌드)과도 나눈다. 저쪽은 다음
      // 배포에서 열리지만 이쪽은 기기의 성질이라 기다려도 열리지 않는다.
      _log('건너뜀', 'iOS가 아니다 ($defaultTargetPlatform)');
      throw const AuthException(AuthFailure.oauthNotSupported);
    }

    // ⚠️ **로그인마다 새로 만든다.** 재사용하면 nonce 가 막으려던 재전송을
    // 막지 못한다.
    final nonce = AppleNonce.generate();

    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        // 이메일만 받는다. 서버가 **이메일로 계정을 만들기** 때문이고
        // (없으면 403 `OAUTH_EMAIL_NOT_PROVIDED`), 이름은 쓰는 곳이 없다 —
        // 닉네임은 온보딩에서 따로 받는다.
        //
        // ⚠️ "이메일 숨기기"를 고르면 애플 릴레이 주소가 오는데 그것도 정상
        // 가입이다(연동 가이드 4절).
        scopes: const [AppleIDAuthorizationScopes.email],
        nonce: nonce.hashed, // ⚠️ 애플에는 해시
      );

      final idToken = credential.identityToken;
      // ⚠️ **토큰이 비어 올 수 있다.** 빈 문자열을 보내면 서버가 400
      // `INVALID_REQUEST`를 주는데, 그 화면 문구는 원인을 가린다.
      if (idToken == null || idToken.isEmpty) {
        _log('실패', 'ID 토큰이 비어 있다');
        throw const AuthException(AuthFailure.oauthFailed);
      }

      return OauthIdTokenWithNonce(
        idToken: idToken,
        nonce: nonce.raw, // ⚠️ 서버에는 원본
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      // ⚠️ **취소는 오류가 아니다.** 창을 닫았을 뿐인데 빨간 문구가 뜨면
      // 고장으로 읽힌다.
      if (error.code == AuthorizationErrorCode.canceled) {
        _log('취소', '사용자가 창을 닫았다');
        throw const AuthException(AuthFailure.oauthCancelled);
      }
      _log('실패', '${error.code.name} ${error.message}');
      throw const AuthException(AuthFailure.oauthFailed);
    } on SignInWithAppleNotSupportedException catch (error) {
      // iOS 13 미만. 배포 타깃이 13.0이라 정상적으로는 오지 않지만,
      // 온다면 다시 눌러도 되지 않으므로 [AuthFailure.oauthFailed]와 나눈다.
      _log('건너뜀', '이 기기가 지원하지 않는다: ${error.message}');
      throw const AuthException(AuthFailure.oauthNotSupported);
    } on SignInWithAppleException catch (error) {
      // 위 둘의 부모다. **아래에 둬야 한다** — 위로 올리면 앞의 두 분기가
      // 죽고 취소가 오류로 읽힌다.
      _log('실패', '$error');
      throw const AuthException(AuthFailure.oauthFailed);
    }
  }
}
