/// 닉네임을 못 바꾼 이유.
///
/// [ProfileFailure]와 섞지 않는다. 그쪽은 **읽기가 실패한 이유**라 화면이
/// 저장해 둔 값으로 물러서면 되지만, 이쪽은 사용자가 방금 한 일이 안 된 것이라
/// **무엇을 고쳐야 하는지 말해야 한다.** 물러설 자리가 없다.
enum NicknameChangeFailure {
  /// 409 `NICKNAME_ALREADY_EXISTS`. 다른 사람이 쓰고 있다.
  ///
  /// 고칠 곳이 입력칸이라 화면은 이때 시트를 닫지 않는다.
  taken,

  /// 409 `ONBOARDING_NOT_COMPLETED`.
  ///
  /// 닉네임이 `user_onboardings`에 있어 온보딩을 마쳐야 바꿀 수 있다.
  /// 프로필 탭까지 온 사람에게는 나오지 않아야 하는 값이다.
  notOnboarded,

  /// 400. ⚠️ **앱 규칙이 서버와 어긋났다는 신호다.**
  ///
  /// 앱이 [NicknameRule]로 먼저 막고 있으니 정상 경로에서는 나오지 않는다.
  /// 나온다면 서버가 규칙을 바꾼 것이다.
  invalid,

  /// 토큰이 죽었다. 갱신도 실패했다.
  sessionExpired,

  /// 서버까지 닿지 못했다.
  network,

  unknown,
}

class NicknameChangeException implements Exception {
  const NicknameChangeException(this.failure);

  final NicknameChangeFailure failure;

  @override
  String toString() => 'NicknameChangeException($failure)';
}
