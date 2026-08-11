import 'package:runiverse/features/auth/domain/oauth_authorization.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';

/// 소셜 인가 코드를 얻는 곳 — **인터페이스만 있다.**
///
/// ## 왜 `AuthRepository`에 넣지 않는가
///
/// 그것은 **서버를 부르는** 저장소다. 카카오 SDK 호출은 서버와 무관하고,
/// 플랫폼 채널을 쓰므로 `flutter test`에서는 아예 돌지 않는다.
/// 갈아끼울 자리를 따로 둬야 화면과 상태 전이를 테스트할 수 있다.
///
/// ## 앱이 토큰을 받지 않는다
///
/// 카카오 SDK의 흔한 예제(`UserApi.loginWithKakaoTalk`)는 **액세스 토큰을 앱이
/// 받는다.** 이 서비스는 그렇게 하지 않는다 — 토큰 교환도 프로필 조회도 서버가
/// 하고, 앱은 인가 코드만 건넨다.
abstract interface class OauthCodeSource {
  /// 인가 화면을 띄우고 코드를 받아온다.
  ///
  /// 실패는 전부 `AuthException`이다. 특히 **사용자가 취소하면
  /// `AuthFailure.oauthCancelled`** — 취소는 오류가 아니라서 화면이 다르게
  /// 다뤄야 한다.
  Future<OauthAuthorization> authorize(OauthProvider provider);
}
