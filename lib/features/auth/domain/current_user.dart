/// 지금 로그인한 사람. `GET /api/v1/users/me`의 답이다.
///
/// ## 왜 auth에 있는가
///
/// "나는 누구인가"는 인증이 답하는 질문이다. 닉네임·소개글이 함께 오지만 그것은
/// **같은 답의 일부**고, 프로필 화면(S22)도 이 값을 읽는다.
///
/// ## ⚠️ [isOnboarded]의 유일한 출처다
///
/// 저장소에도 같은 이름의 값이 있지만 그것은 **로그인하던 순간의 사진**이다.
/// 다른 기기에서 프로필을 채우면 어긋난다. 앱에 들어올 때마다 서버에 다시 묻고,
/// 홈의 유도 카드는 여기서 온 값만 본다.
class CurrentUser {
  const CurrentUser({
    required this.userId,
    required this.email,
    required this.isOnboarded,
    this.nickname,
    this.profileImageUrl,
    this.introduction,
  });

  final String userId;
  final String email;

  /// 프로필을 채웠는가. 홈의 유도 카드를 켜고 끄는 값이다.
  final bool isOnboarded;

  /// 온보딩 전에는 없다. **`isOnboarded`가 `false`면 셋 다 `null`일 수 있다.**
  final String? nickname;
  final String? profileImageUrl;
  final String? introduction;
}
