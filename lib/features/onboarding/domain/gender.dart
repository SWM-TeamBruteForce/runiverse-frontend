/// 성별 — 서버가 받는 두 값.
///
/// 화면은 한국어로 보여주고 서버는 대문자 영문을 받는다. 그 변환을 화면이 하게 두면
/// **표시 문구를 고칠 때 전송값까지 같이 깨진다.** 여기서 한 번만 옮긴다.
///
/// 한국어 라벨은 여기 두지 않는다 — `AppStrings`가 문구를 갖고 화면이 둘을 잇는다.
/// domain이 `AppStrings`를 import하면 도메인이 화면 문구에 묶인다.
///
/// 남성·여성 둘뿐인 이유는 칼로리·페이스 계산식이 이분법을 전제해서다.
/// **그 계산이 필요 없는 곳(프로필 공개 정보 등)까지 이 값을 끌어다 쓰면 안 된다.**
enum Gender {
  male,
  female;

  /// 서버 `OnboardRequest.gender`가 받는 값.
  String get wireValue => switch (this) {
    Gender.male => 'MALE',
    Gender.female => 'FEMALE',
  };
}
