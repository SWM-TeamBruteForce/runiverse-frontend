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

  /// 프로필 등록(S04)을 마쳤는가.
  ///
  /// ## ⚠️ `null`은 "안 했다"가 아니라 **"서버가 말하지 않았다"**
  ///
  /// 서버가 2026-08-17 로그인·가입·소셜 응답에서 이 값을 **뺐다**. 대신
  /// `GET /users/me`를 보라고 하는데 **그 엔드포인트는 아직 없다.**
  /// 그래서 지금은 모든 인증 응답이 `null`로 온다.
  ///
  /// `false`로 떨어뜨리면 **이미 프로필을 채운 사람이 로그인할 때마다 폼으로
  /// 끌려간다.** 모르는 것은 모르는 채로 두고, 판단은 저장된 값에 맡긴다.
  ///
  /// **갱신 응답(`POST /auth/refresh`)에도 이 값이 없다.**
  final bool? isOnboarded;
}
