/// 갱신에 성공했을 때 손에 남는 것.
///
/// `AuthSession`과 달리 **`userId`가 없다.** 서버 `ReissueResponse`가 토큰 둘만
/// 돌려주기 때문이다. 누구인지는 저장소에 이미 있으므로 다시 받을 필요가 없다.
///
/// ⚠️ **두 값을 모두 저장해야 한다.** 서버가 리프레시 토큰을 회전시키므로,
/// [refreshToken]을 덮어쓰지 않으면 다음 갱신이 401로 죽는다 — 유효기간이 남아 있어도.
class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}
