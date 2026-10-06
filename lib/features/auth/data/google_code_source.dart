import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:runiverse/core/config/app_config.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/oauth_authorization.dart';
import 'package:runiverse/features/auth/domain/oauth_code_source.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';

/// 구글 계정 선택 창을 띄우고 **ID 토큰**을 받아온다.
///
/// ## ⚠️ 카카오와 흐름이 다르다
///
/// 카카오는 인가 코드를 받아 **서버가 토큰을 교환**한다. 구글은 그 단계가
/// 없다 — 앱이 받은 ID 토큰을 그대로 넘기면 서버가 구글 공개키로 서명을
/// 확인한다. 인가 코드도 PKCE 검증값도 `redirect_uri` 도 없다
/// (연동 가이드 1절).
///
/// ## `serverClientId` 는 **웹** 클라이언트 ID다
///
/// ID 토큰에는 "이 토큰을 누구에게 발급했는가"가 찍히고, 서버는 그 값이 우리
/// 웹 클라이언트 ID인지 본다. Android 클라이언트 ID를 넣으면 **토큰은 받아지는데
/// 서버가 401을 돌려준다** — 앱에서는 성공처럼 보여서 찾기 어렵다.
///
/// Android 클라이언트(패키지명 + SHA-1)는 콘솔에 등록만 돼 있으면 되고
/// 코드에는 들어가지 않는다.
class GoogleCodeSource implements OauthCodeSource {
  const GoogleCodeSource();

  /// SDK가 무엇을 던졌는지 남긴다. 화면에는 뭉뚱그린 문구를 쓰므로,
  /// 이 로그가 없으면 **취소인지 오류인지도 구분할 수 없다.**
  ///
  /// ⚠️ **ID 토큰은 절대 남기지 않는다.**
  void _log(String kind, String detail) {
    if (kDebugMode) debugPrint('[google] $kind: $detail');
  }

  @override
  Future<OauthAuthorization> authorize(OauthProvider provider) async {
    // ⚠️ **ID가 없으면 SDK를 부르기 전에 돌아선다.** `main.dart` 가 ID 없이는
    // `initialize` 를 건너뛰므로, 그대로 부르면 초기화 전 호출로 죽는다.
    // 카카오에서 겪은 것과 같은 함정이다.
    //
    // 이유를 [AuthFailure.oauthFailed] 로 뭉뚱그리지 않는다 —
    // "다시 시도해주세요"는 거짓말이다. 다시 눌러도 ID는 생기지 않는다.
    if (!AppConfig.hasGoogleServerClientId) {
      _log('건너뜀', '웹 클라이언트 ID가 없다');
      throw const AuthException(AuthFailure.oauthUnavailable);
    }

    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;

      // ⚠️ **토큰이 비어 올 수 있다.** 그때 빈 문자열을 서버에 보내면 400이
      // 돌아오는데, 그 화면 문구는 "다시 시도해주세요"라 원인을 가린다.
      if (idToken == null || idToken.isEmpty) {
        _log('실패', 'ID 토큰이 비어 있다');
        throw const AuthException(AuthFailure.oauthFailed);
      }

      return OauthIdToken(idToken);
    } on GoogleSignInException catch (error) {
      // ⚠️ **취소는 오류가 아니다.** 화면이 다르게 다뤄야 한다 — 창을 닫았을
      // 뿐인데 빨간 문구가 뜨면 고장으로 읽힌다.
      if (error.code == GoogleSignInExceptionCode.canceled) {
        _log('취소', '사용자가 창을 닫았다');
        throw const AuthException(AuthFailure.oauthCancelled);
      }
      _log('실패', '${error.code.name} ${error.description ?? ''}');
      throw const AuthException(AuthFailure.oauthFailed);
    }
  }
}
