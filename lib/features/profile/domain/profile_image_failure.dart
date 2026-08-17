/// 프로필 사진 작업이 실패한 이유.
///
/// `OnboardingFailure`와 같은 규칙이다 — 서버 `message`를 화면에 그대로 옮기지
/// 않고, **상태 코드를 1차 근거**로 삼는다.
///
/// ## 앞의 둘은 서버에 가기 전에 난다
///
/// [unsupportedFormat] · [tooLarge]는 앱이 파일을 보고 판단한다. 서버도 같은 것을
/// 검사하지만(`ProfileImageUploadUrlRequest`), 거기까지 보내면 **왕복 한 번을 버리고
/// 400 하나로 뭉뚱그려진 답**을 받는다. 어느 쪽이 문제였는지 사용자에게 말해줄 수 없다.
enum ProfileImageFailure {
  /// jpeg · png · webp가 아니다.
  ///
  /// 서버가 `^(?i)(image/jpeg|image/png|image/webp)$`로 막는다. heic(아이폰 기본)와
  /// gif가 여기 걸린다.
  unsupportedFormat,

  /// 10MB를 넘는다. 서버 상한(`@Max(10_485_760)`)과 같은 값을 쓴다.
  tooLarge,

  /// S3에 올리는 단계에서 실패했다.
  ///
  /// **서버 실패와 구분한다.** 이 단계는 우리 서버를 거치지 않으므로 서버 로그에
  /// 아무것도 남지 않는다. 뭉뚱그리면 "서버가 죽었다"로 읽고 엉뚱한 데를 뒤지게 된다.
  ///
  /// 대부분 원인은 하나다 — 서명에 들어간 `Content-Type`·`Content-Length`가
  /// 실제로 보낸 것과 다르면 S3가 403을 준다.
  upload,

  /// 다시 로그인해야 한다. 갱신까지 실패한 경우다.
  sessionExpired,

  /// 네트워크에 닿지 못했다.
  network,

  /// 서버가 5xx를 돌려줬다.
  server,

  /// 그 밖.
  unknown,
}

/// 저장소가 실패를 알리는 방법. 던지는 이유는 `OnboardingException`과 같다 —
/// 성공 경로의 타입을 깨끗하게 두고, 잡는 곳을 한 군데로 모은다.
class ProfileImageException implements Exception {
  const ProfileImageException(this.failure);

  final ProfileImageFailure failure;

  @override
  String toString() => 'ProfileImageException($failure)';
}
