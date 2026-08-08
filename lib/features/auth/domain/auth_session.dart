/// 로그인에 성공했을 때 손에 남는 것.
///
/// ## 토큰이 왜 둘인가
///
/// [accessToken]은 API를 부를 때마다 붙이는 짧은 수명의 출입증이고,
/// [refreshToken]은 그 출입증이 만료됐을 때 새로 받아오는 긴 수명의 열쇠다.
/// 출입증이 새어 나가도 금방 만료되고, 열쇠는 서버에 한 번만 보내므로 노출이 적다.
///
/// **[refreshToken]은 탈취되면 계정을 계속 쓸 수 있는 값이다.** 로그로 찍지 않는다.
class AuthSession {
  const AuthSession({
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
    required this.isOnboarded,
  });

  final String userId;
  final String accessToken;
  final String refreshToken;

  /// 프로필 등록(S04)을 마쳤는가. 서버 로그인 응답이 알려준다.
  ///
  /// **갱신 응답(`POST /auth/refresh`)에는 이 값이 없다.** 그래서 로그인할 때
  /// 받은 값을 저장해 두고, 자동 로그인 경로에서는 저장된 값을 읽는다.
  final bool isOnboarded;
}
