import 'package:runiverse/features/auth/domain/auth_session.dart';
import 'package:runiverse/features/auth/domain/auth_tokens.dart';

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

  /// 실패 시 `AuthException(AuthFailure.emailAlreadyExists)`.
  ///
  /// **가입 결과로 세션까지 돌려준다.** 서버 `POST /auth/signup`은 `userId`만 주지만,
  /// 가입하자마자 로그인 화면으로 되돌리는 것은 사용자에게 같은 일을 두 번 시키는 셈이다.
  /// 실제 구현은 signup 뒤에 login을 이어 부른다.
  Future<AuthSession> signUp({required String email, required String password});

  /// 저장된 리프레시 토큰으로 새 토큰 쌍을 받는다.
  ///
  /// 실패 시 `AuthException(AuthFailure.sessionExpired)` — 다시 로그인해야 한다.
  ///
  /// **돌려받은 두 값을 모두 저장해야 한다.** 서버가 리프레시 토큰을 회전시킨다.
  Future<AuthTokens> refresh(String refreshToken);

  /// 서버 세션을 끊는다. 로컬 토큰을 지우는 것은 호출자 몫이다.
  Future<void> signOut();
}
