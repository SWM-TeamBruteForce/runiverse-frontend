/// 마지막으로 **성공한** 로그인 방법.
///
/// 실패한 시도는 남기지 않는다. 눌러봤다가 안 된 것을 "최근 사용"이라고 하면
/// 잘못된 힌트가 된다.
///
/// ## 무엇을 풀고 무엇을 못 푸는가
///
/// 같은 이메일로 이미 계정이 있으면 서버가 409를 주는데, **어느 방법으로
/// 가입했는지는 알려주지 않는다.** 그 자리를 이 기록이 조금 메운다 — 이 기기에서
/// 로그인한 적이 있으면 무엇을 눌러야 할지 보인다.
///
/// ⚠️ **앱을 지웠다 깔거나 기기를 바꾸면 기록이 없다.** "내가 뭘로 가입했더라"가
/// 떠오르는 순간이 대개 그때라서, 이것만으로는 부족하다. 서버가 409에 `provider`를
/// 실어 주는 것이 진짜 해법이다.
enum SignInMethod {
  email,
  kakao;

  // ⚠️ Apple은 아직 없다. `OauthProvider`에도 `kakao`뿐이고, 로그인 화면의
  // Apple 버튼은 자리만 잡아 둔 것이다. 붙을 때 여기에 더한다.

  /// 저장할 때 쓰는 값. **enum 이름을 그대로 쓰지 않는다** —
  /// 이름을 바꾸면 기기에 남아 있던 값이 읽히지 않는다.
  String get storageKey => switch (this) {
    SignInMethod.email => 'email',
    SignInMethod.kakao => 'kakao',
  };

  /// 저장된 값에서 되살린다. 모르는 값이면 `null` — 예전 버전이 남긴 값일 수 있다.
  static SignInMethod? fromStorage(String? value) => switch (value) {
    'email' => SignInMethod.email,
    'kakao' => SignInMethod.kakao,
    _ => null,
  };
}
