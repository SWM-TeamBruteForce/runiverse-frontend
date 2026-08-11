import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/oauth_authorization.dart';
import 'package:runiverse/features/auth/domain/oauth_code_source.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';

/// 서버와 SDK 없이 소셜 로그인을 돌려보기 위한 가짜.
///
/// 카카오 SDK는 플랫폼 채널을 쓰므로 `flutter test`에서 부를 수 없다.
/// 이것이 없으면 화면과 상태 전이를 전혀 시험할 수 없다.
class FakeOauthCodeSource implements OauthCodeSource {
  FakeOauthCodeSource({this.failure, this.code = 'fake-code'});

  /// 주면 그 이유로 실패한다. **취소 경로를 시험하는 데 쓴다** —
  /// 취소는 화면이 다르게 다뤄야 하는 유일한 실패다.
  final AuthFailure? failure;

  /// 돌려줄 인가 코드. 저장소에 심은 계정과 짝을 맞출 때 바꾼다.
  final String code;

  /// 몇 번 불렸는가.
  ///
  /// **취소했을 때 서버를 부르지 않는지** 확인하는 데 쓴다. 취소인데 서버까지
  /// 가면 쓸모없는 요청이 나간다.
  var callCount = 0;

  @override
  Future<OauthAuthorization> authorize(OauthProvider provider) async {
    callCount++;

    final reason = failure;
    if (reason != null) throw AuthException(reason);

    return OauthAuthorization(
      authorizationCode: code,
      codeVerifier: 'fake-verifier',
    );
  }
}
