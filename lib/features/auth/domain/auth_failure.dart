/// 인증이 실패한 이유.
///
/// 서버 `message`를 화면에 그대로 쓰지 않기 위해 존재한다.
/// 서버 문구는 습니다체(`"이미 가입된 이메일입니다."`)고 앱은 해요체다. 그대로 쓰면 톤이 깨진다.
/// **서버가 주는 `code`를 계약으로 보고, 문구는 앱이 정한다.**
///
/// 서버 `code` → 이 값으로 옮기는 변환은 실제 API가 붙을 때 `data/`에 만든다.
/// 지금은 가짜 저장소가 이 값을 직접 던진다.
enum AuthFailure {
  /// 가입: 이미 있는 이메일. 서버 `EMAIL_ALREADY_EXISTS` (409)
  emailAlreadyExists,

  /// 로그인: 이메일 또는 비밀번호가 틀렸다. 서버 `INVALID_CREDENTIALS` (401)
  ///
  /// **어느 쪽이 틀렸는지 나누지 않는다.** 나누면 "이 이메일은 가입돼 있다"는 사실이
  /// 새어 나간다. 서버도 같은 이유로 두 코드를 노출 목록에서 빼놨다.
  invalidCredentials,

  /// 이메일 인증: 번호가 발급된 것과 다르다. 받은 적 없는 이메일도 여기 들어온다.
  invalidCode,

  /// 이메일 인증: 번호가 만료됐다(5분).
  ///
  /// [invalidCode]와 나눈 이유는 사용자가 할 행동이 다르기 때문이다 —
  /// 이쪽은 **다시 받아야** 하고, 저쪽은 다시 보고 치면 된다.
  codeExpired,

  /// 가입: 인증하지 않은 이메일로 가입을 시도했다.
  ///
  /// 앱은 인증 전에 가입 버튼을 열지 않으므로 화면에서 볼 일이 없다.
  /// **서버가 막아야 하는 것**이라 가짜 저장소도 같이 막는다 — 앱만 막으면
  /// curl로 인증 없이 가입된다.
  emailNotVerified,

  /// 네트워크에 닿지 못했다.
  network,

  /// 서버가 5xx를 돌려줬다.
  server,

  /// 그 밖. 앱이 모르는 `code`가 왔을 때를 포함한다.
  unknown,
}

/// 저장소가 실패를 알리는 방법.
///
/// 반환값으로 실패를 돌려주지 않고 던지는 이유는, 성공 경로의 타입을 깨끗하게
/// 유지하기 위해서다 — `signIn`은 `AuthSession`을 주거나 던지거나 둘 중 하나다.
/// 이것을 잡아 `AuthFailure`로 되돌리는 곳은 `AuthController` 한 군데다.
class AuthException implements Exception {
  const AuthException(this.failure);

  final AuthFailure failure;

  @override
  String toString() => 'AuthException($failure)';
}
