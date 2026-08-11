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

  /// 인증번호 확인: 번호가 맞지 않다. 서버 `INVALID_VERIFICATION_CODE` (400)
  invalidCode,

  /// 인증번호 확인: 발급된 번호가 없다 — 만료됐거나 받은 적이 없다.
  /// 서버 `EMAIL_VERIFICATION_NOT_FOUND` (400)
  ///
  /// [invalidCode]와 나눈 이유는 **사용자가 할 행동이 다르기** 때문이다.
  /// 이쪽은 다시 받아야 하고, 저쪽은 메일을 다시 보고 치면 된다.
  codeExpired,

  /// 인증번호 확인: 시도 횟수를 다 썼다. 서버 `TOO_MANY_VERIFICATION_ATTEMPTS` (429)
  ///
  /// 번호를 다시 받아야 풀린다 — 서버가 시도 횟수를 번호에 매달아 두기 때문이다.
  tooManyCodeAttempts,

  /// 발송: 방금 보냈다. 서버 `EMAIL_VERIFICATION_COOLDOWN` (429)
  sendCooldown,

  /// 발송: 하루 한도를 넘겼다. 서버 `EMAIL_VERIFICATION_DAILY_LIMIT_EXCEEDED` (429)
  ///
  /// [sendCooldown]과 달리 **오늘 안에는 풀리지 않는다.** 기다리라고 하면 안 된다.
  sendDailyLimit,

  /// 발송: 메일 서버가 받지 못했다. 서버 `EMAIL_SEND_FAILED` (503)
  ///
  /// ⚠️ 5xx지만 [server]로 흡수하지 않는다. 사용자가 한 일(이메일 입력)은
  /// 멀쩡하고 다시 눌러 볼 수 있다 — 화면이 할 말이 다르다.
  sendFailed,

  /// 가입: 티켓이 없거나 만료됐다. 서버 `EMAIL_NOT_VERIFIED` (403)
  ///
  /// **인증을 마치고 비밀번호를 오래 고민하면 여기 온다.** 티켓에도 유효기간이 있다.
  /// 가입에 한 번 실패한 뒤 같은 티켓으로 다시 눌러도 이것이 나온다 —
  /// 서버가 티켓을 먼저 소비하기 때문이다.
  emailNotVerified,

  /// 소셜: 사용자가 인가 화면에서 그만뒀다.
  ///
  /// ⚠️ **화면은 이 경우 아무 문구도 띄우지 않는다.** 스스로 그만둔 사람에게
  /// 오류를 보여주면 무언가 잘못된 것처럼 읽힌다. 그래서 [oauthFailed]와 나눈다 —
  /// 이유가 하나였다면 취소할 때마다 빨간 글씨가 떴을 것이다.
  oauthCancelled,

  /// 소셜: 인가나 토큰 교환이 실패했다.
  /// 서버 `OAUTH_CODE_EXCHANGE_FAILED`, 또는 앱 쪽 SDK 오류.
  ///
  /// **`redirect_uri`가 서버 설정과 어긋나면 여기로 온다.** 가장 흔한 원인이고,
  /// 증상이 앱이 아니라 서버에서 나므로 찾기 어렵다.
  oauthFailed,

  /// 소셜: 카카오가 이메일을 주지 않았다. 서버 `OAUTH_EMAIL_NOT_PROVIDED` (403)
  ///
  /// 동의항목이 꺼져 있거나 사용자가 이메일 제공에 동의하지 않았다.
  /// **서버가 이메일로 계정을 만들기 때문에** 없으면 가입할 수 없다.
  oauthEmailMissing,

  /// 갱신: 리프레시 토큰이 만료됐거나 무효다. 서버 `INVALID_REFRESH_TOKEN` (401)
  ///
  /// [invalidCredentials]와 나눠 둔다. 화면이 다르게 말해야 한다 —
  /// 하나는 "비밀번호를 확인해 주세요"고, 다른 하나는 "다시 로그인해 주세요"다.
  /// **사용자는 아무것도 틀리지 않았다.**
  sessionExpired,

  /// 서버가 형식을 거절했다. 서버 `VALIDATION_FAILED` (400)
  ///
  /// **앱이 먼저 막았어야 할 값이 서버까지 갔다는 뜻이다.** 서버는 사유를
  /// `message`로만 주는데 그것을 갈라 읽으면 문구가 바뀔 때 조용히 깨진다.
  /// 화면에는 앱이 정한 문구 하나를 쓰고, `message`는 디버그 로그로만 남긴다.
  validation,

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
