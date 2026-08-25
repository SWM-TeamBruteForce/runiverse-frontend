/// 이 계정이 어떻게 만들어졌는가. `GET /api/v1/users/me/account` (명세 55번).
///
/// **비밀번호 변경 메뉴를 보일지 정하는 값이다.** 소셜 계정에는 비밀번호가 없어서
/// 서버가 409 `PASSWORD_NOT_SET`으로 거절한다. 그 거절을 사용자가 눌러 보고서야
/// 알게 하는 것보다, 메뉴를 아예 보이지 않는 편이 낫다.
///
/// ## ⚠️ `SignInMethod`와 다른 것이다
///
/// 로그인 화면이 기억하는 `SignInMethod`는 **이 기기에서 마지막으로 성공한 방법**이고,
/// 앱을 지우면 사라진다. 이것은 **서버가 아는 계정의 성질**이라 기기가 바뀌어도 같다.
///
/// 둘이 어긋날 수 있다 — 같은 이메일로 로컬 계정과 카카오 계정이 따로 있을 수 있는
/// 것이 서비스 정책이라서다. 설정 화면은 반드시 이쪽을 쓴다.
enum LoginType {
  local,
  google,
  kakao;

  /// 서버가 준 값에서 되살린다. 모르는 값이면 `null`.
  ///
  /// 서버가 제공자를 늘려도 앱이 죽지 않아야 해서 예외를 던지지 않는다.
  /// 받는 쪽이 `null`을 "알 수 없는 계정"으로 다룬다.
  static LoginType? fromWire(String? value) => switch (value) {
    'LOCAL' => LoginType.local,
    'GOOGLE' => LoginType.google,
    'KAKAO' => LoginType.kakao,
    _ => null,
  };

  /// 비밀번호를 바꿀 수 있는가.
  ///
  /// 이 판단을 화면에 두지 않는 이유는, 화면이 늘 때마다 `== LoginType.local`이
  /// 흩어지고 제공자가 추가될 때 한 곳을 빠뜨리게 되어서다.
  bool get canChangePassword => this == LoginType.local;
}
