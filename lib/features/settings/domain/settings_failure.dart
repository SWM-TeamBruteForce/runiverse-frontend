/// 설정을 읽거나 바꾸지 못한 이유.
///
/// 비밀번호 변경만 실패 종류가 많아 따로 뒀다 — `PasswordChangeFailure`.
enum SettingsFailure {
  /// 토큰이 죽었다. 갱신도 실패했다.
  ///
  /// ⚠️ **이 값이 떠도 로그아웃 버튼은 계속 눌려야 한다.** 세션이 이상해서
  /// 조회가 실패하는 경우가 있는데, 그때 로그아웃까지 막히면 사용자가 앱에서
  /// 나갈 방법이 없다(설계 문서 4절).
  sessionExpired,

  /// 서버까지 닿지 못했다.
  network,

  /// 5xx.
  server,

  unknown,
}

class SettingsException implements Exception {
  const SettingsException(this.failure);

  final SettingsFailure failure;

  @override
  String toString() => 'SettingsException($failure)';
}
