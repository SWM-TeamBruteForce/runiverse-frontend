/// 프로필(소개글·신체 정보)을 못 바꾼 이유.
///
/// [NicknameChangeFailure]와 나눠 둔다. 닉네임에는 "이미 누가 쓰고 있다"가
/// 있는데 여기에는 없고, **겹치는 이름이라는 개념 자체가 없는 값들**이라
/// 한 enum에 담으면 절대 나오지 않는 분기를 화면이 계속 다루게 된다.
enum ProfileEditFailure {
  /// 400. ⚠️ **앱 규칙이 서버와 어긋났다는 신호다.**
  ///
  /// 앱이 범위(소개글 100자, 키·몸무게 20~300)를 먼저 막고 있으니 정상
  /// 경로에서는 나오지 않는다. 나온다면 서버가 규칙을 바꾼 것이다.
  invalid,

  /// 409 `ONBOARDING_NOT_COMPLETED`.
  ///
  /// 신체 정보가 `user_onboardings`에 있어 온보딩을 마쳐야 바꿀 수 있다.
  /// 앱 진입이 `isOnboarded`로 갈리므로 정상 경로에서는 닿지 못한다.
  notOnboarded,

  /// 토큰이 죽었다. 갱신도 실패했다.
  sessionExpired,

  /// 서버까지 닿지 못했다.
  network,

  unknown,
}

class ProfileEditException implements Exception {
  const ProfileEditException(this.failure);

  final ProfileEditFailure failure;

  @override
  String toString() => 'ProfileEditException($failure)';
}
