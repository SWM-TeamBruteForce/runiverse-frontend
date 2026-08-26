/// 프로필 요약을 못 가져온 이유.
///
/// 화면은 지금 이 값으로 갈라지지 않는다 — 실패하면 **저장해 둔 값을 그대로
/// 쓰기** 때문이다. 그래도 이유를 나누는 것은, 실패가 무엇이었는지 모르면
/// 나중에 "왜 안 뜨지"를 로그 없이 쫓게 되어서다.
enum ProfileFailure {
  /// 그런 사용자가 없다. 서버 404.
  notFound,

  /// 토큰이 죽었다. 갱신도 실패했다.
  sessionExpired,

  /// 서버까지 닿지 못했다.
  network,

  /// 5xx.
  server,

  unknown,
}

class ProfileException implements Exception {
  const ProfileException(this.failure);

  final ProfileFailure failure;

  @override
  String toString() => 'ProfileException($failure)';
}
