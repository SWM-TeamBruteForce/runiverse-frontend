/// 비밀번호를 바꾸지 못한 이유. `PATCH /api/v1/users/me/password` (명세 56번).
///
/// 설정의 다른 실패와 달리 **화면이 이 값으로 갈라진다.** 어느 칸이 잘못됐는지
/// 알려주려면 이유를 알아야 한다.
enum PasswordChangeFailure {
  /// 현재 비밀번호가 틀렸다. 서버 401 `INVALID_CURRENT_PASSWORD`.
  ///
  /// ## ⚠️ 401이지만 세션 만료가 아니다
  ///
  /// 401을 만나면 토큰을 갱신하고 재시도하는 인터셉터가 이미 있다.
  /// 이 코드가 거기 걸리면 **비밀번호를 틀린 사람이 조용히 재시도되고,
  /// 갱신도 안 되니 결국 로그아웃된다.** `code`를 보고 갈라서 입력 오류로
  /// 다뤄야 한다 — 명세에도 같은 주의가 적혀 있다.
  wrongCurrentPassword,

  /// 소셜 계정이라 비밀번호가 없다. 서버 409 `PASSWORD_NOT_SET`.
  ///
  /// 화면이 `LoginType`으로 이미 메뉴를 숨기므로 **정상적으로는 오지 않는다.**
  /// 딥링크로 바로 들어온 경우를 위해 남겨 둔다.
  notLocalAccount,

  /// 새 비밀번호가 규칙에 안 맞는다. 서버 400 `INVALID_REQUEST`.
  ///
  /// 앱이 먼저 검사하므로 여기까지 오는 것은 규칙이 서버에서 바뀐 경우다.
  invalidNewPassword,

  /// 토큰이 죽었다. **[wrongCurrentPassword]와 반드시 갈라야 한다** — 둘 다 401이다.
  sessionExpired,

  network,

  server,

  unknown,
}

class PasswordChangeException implements Exception {
  const PasswordChangeException(this.failure);

  final PasswordChangeFailure failure;

  @override
  String toString() => 'PasswordChangeException($failure)';
}
