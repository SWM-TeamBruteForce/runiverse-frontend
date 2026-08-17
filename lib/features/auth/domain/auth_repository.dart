import 'package:runiverse/features/auth/domain/auth_session.dart';
import 'package:runiverse/features/auth/domain/auth_tokens.dart';
import 'package:runiverse/features/auth/domain/current_user.dart';
import 'package:runiverse/features/auth/domain/oauth_authorization.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';

/// 인증 저장소 — **인터페이스만 있다.**
///
/// 화면은 이 타입에만 기대고, 실제로 누가 답하는지 모른다.
/// 지금 답하는 것은 메모리에 계정을 들고 있는 `FakeAuthRepository`고,
/// 서버가 준비되면 dio로 HTTP를 부르는 구현이 같은 자리에 들어간다.
/// **바꿔 끼우는 곳은 `auth_provider.dart`의 한 줄뿐이다.**
///
/// 실패는 전부 `AuthException`으로 던진다. 구현체는 자기 사정(HTTP 상태 코드,
/// 소켓 예외 등)을 밖으로 흘리지 않는다 — 흘리면 화면이 dio를 알아야 한다.
abstract interface class AuthRepository {
  /// 실패 시 `AuthException(AuthFailure.invalidCredentials)`.
  Future<AuthSession> signIn({required String email, required String password});

  /// 소셜 인가 코드로 로그인한다.
  ///
  /// **계정이 없으면 서버가 만든다** — 이메일 가입과 달리 별도 절차가 없다.
  /// 그래서 이름이 `signIn`이지만 첫 호출은 가입이기도 하다.
  ///
  /// 인가 코드와 검증값은 [OauthAuthorization]으로 묶여 온다. 짝이 어긋나면
  /// 서버의 토큰 교환이 카카오에 거부당한다.
  ///
  /// 실패: `oauthFailed` · `oauthEmailMissing` · `emailAlreadyExists`
  Future<AuthSession> signInWithOauth({
    required OauthProvider provider,
    required OauthAuthorization authorization,
  });

  /// 이메일로 인증번호를 보낸다.
  ///
  /// **이미 가입된 이메일이면 여기서 `emailAlreadyExists`가 난다.** 인증번호를
  /// 치기도 전에 알려주는 것이 중요하다 — 다 치고 나서 알려주면 사용자가 한 일이
  /// 통째로 버려진다.
  ///
  /// 실패: `emailAlreadyExists` · `sendCooldown` · `sendDailyLimit` · `sendFailed`
  Future<void> sendVerificationCode(String email);

  /// 인증번호를 확인하고 **티켓을 받는다.**
  ///
  /// 이 티켓이 "이 사람은 이 이메일을 인증했다"는 증거고, [signUp]에 넘긴다.
  /// **서버는 티켓을 한 번만 받아준다** — 저장하지 말고 그 화면에서만 들고 있는다.
  ///
  /// 티켓은 URL-safe base64 문자열이다. 앱은 **모양을 검사하지 않는다** —
  /// 서버가 형식을 바꿔도 앱이 깨지지 않아야 한다.
  ///
  /// 실패: `invalidCode` · `codeExpired` · `tooManyCodeAttempts`
  Future<String> verifyCode({required String email, required String code});

  /// 인증을 마치고 받은 티켓으로 가입한다.
  ///
  /// **이메일을 받지 않는다** — 티켓 안에 들어 있고 서버가 거기서 꺼내 쓴다.
  ///
  /// ## ⚠️ 티켓은 실패해도 소비된다
  ///
  /// 서버는 티켓을 **먼저** 소비하고 계정을 만든다. `emailAlreadyExists`로
  /// 실패하면 그 티켓은 이미 없다. 화면은 실패를 받으면 티켓을 버리고 인증
  /// 단계를 다시 열어야 한다 — 같은 티켓으로 재시도하면 반드시
  /// `emailNotVerified`가 나온다.
  ///
  /// 실패: `emailNotVerified` · `emailAlreadyExists` · `validation`
  Future<AuthSession> signUp({
    required String verificationTicket,
    required String password,
  });

  /// 지금 로그인한 사람이 누구인지 서버에 묻는다.
  ///
  /// **`isOnboarded`의 유일한 출처다.** 저장소에도 같은 이름의 값이 있지만 그것은
  /// 로그인하던 순간의 사진이라, 다른 기기에서 프로필을 채우면 어긋난다.
  ///
  /// 앱에 들어올 때마다(자동 로그인 · 로그인 · 가입 직후) 부른다.
  ///
  /// 토큰을 **인자로 받는다.** 이 저장소는 토큰이 어디 있는지 모른다 —
  /// 알게 하면 `core/storage`에 기대게 되고, 가짜 구현도 저장소를 흉내 내야 한다.
  ///
  /// 실패: `sessionExpired`(401) · `network` · `server`
  Future<CurrentUser> fetchCurrentUser(String accessToken);

  /// 저장된 리프레시 토큰으로 새 토큰 쌍을 받는다.
  ///
  /// 실패 시 `AuthException(AuthFailure.sessionExpired)` — 다시 로그인해야 한다.
  ///
  /// **돌려받은 두 값을 모두 저장해야 한다.** 서버가 리프레시 토큰을 회전시킨다.
  Future<AuthTokens> refresh(String refreshToken);

  /// 서버 세션을 끊는다. 로컬 토큰을 지우는 것은 호출자 몫이다.
  Future<void> signOut();
}
