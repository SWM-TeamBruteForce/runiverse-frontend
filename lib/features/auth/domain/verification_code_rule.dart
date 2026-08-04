/// 인증번호 판정 결과.
enum VerificationCodeStatus {
  /// 아직 입력하지 않았다. 오류가 아니라 시작 상태다.
  empty,

  /// 숫자 6자리가 아니다. 덜 쳤거나 숫자가 아닌 것이 섞였다.
  ///
  /// 둘을 나누지 않은 이유는 화면이 할 말이 같기 때문이다 — "숫자 6자리를 입력해주세요".
  incomplete,

  valid;

  bool get isValid => this == VerificationCodeStatus.valid;
}

/// 이메일 인증번호 규칙 — 숫자 6자리, 5분 유효.
///
/// ## 맞는 번호인지는 여기서 모른다
///
/// 이 규칙은 **모양만** 본다. 실제로 그 번호가 발급된 것인지, 만료됐는지는
/// 서버만 안다. 화면이 할 일은 6자리가 차기 전에 `확인` 버튼을 열지 않는 것이다.
///
/// ## ⚠️ [ttl]은 표시용이다
///
/// 화면의 카운트다운을 그리기 위한 값이고, **만료 판정은 저장소(서버)가 한다.**
/// 화면 타이머로 판정하면 앱을 백그라운드에 두거나 기기 시계를 돌렸을 때 어긋난다.
///
/// 서버가 `expiresIn`을 응답에 실어주면 그 값을 쓰도록 바꾼다.
/// 그전까지는 비밀번호 규칙과 같은 이유로 **같은 값이 두 곳에 있다.**
abstract final class VerificationCodeRule {
  static const length = 6;

  static const ttl = Duration(minutes: 5);

  static final _sixDigits = RegExp(r'^\d{6}$');

  static VerificationCodeStatus of(String raw) {
    if (raw.isEmpty) return VerificationCodeStatus.empty;
    return _sixDigits.hasMatch(raw)
        ? VerificationCodeStatus.valid
        : VerificationCodeStatus.incomplete;
  }
}
