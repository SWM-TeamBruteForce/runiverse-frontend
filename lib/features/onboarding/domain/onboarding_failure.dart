/// 프로필 전송이 실패한 이유.
///
/// `AuthFailure`와 같은 규칙이다 — 서버 `message`를 화면에 그대로 쓰지 않고
/// `code`를 계약으로 본다. 서버 문구는 습니다체고 앱은 해요체다.
///
/// **`alreadyOnboarded`가 없는 것은 의도다.** 서버가 409로 "이미 했다"고 하면
/// 그것은 도메인상 성공이므로 저장소가 흡수한다.
enum OnboardingFailure {
  /// 서버가 형식을 거절했다. 서버 `VALIDATION_FAILED` (400)
  ///
  /// **앱이 먼저 막았어야 할 값이 서버까지 갔다는 뜻이다.** 사용자에게 정확한 사유를
  /// 옮길 게 아니라 앱 검증에 구멍이 있다는 신호로 읽어야 한다.
  validation,

  /// 다시 로그인해야 한다. 갱신까지 실패한 경우다.
  sessionExpired,

  /// 네트워크에 닿지 못했다.
  network,

  /// 서버가 5xx를 돌려줬다.
  server,

  /// 그 밖. 앱이 모르는 `code`가 왔을 때를 포함한다.
  unknown,
}

/// 저장소가 실패를 알리는 방법.
///
/// 반환값으로 실패를 돌려주지 않고 던지는 이유는 성공 경로의 타입을 깨끗하게
/// 유지하기 위해서다. 잡는 곳은 화면 하나다.
class OnboardingException implements Exception {
  const OnboardingException(this.failure);

  final OnboardingFailure failure;

  @override
  String toString() => 'OnboardingException($failure)';
}
