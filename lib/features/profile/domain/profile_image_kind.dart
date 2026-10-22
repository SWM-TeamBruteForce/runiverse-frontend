/// 사용자 이미지의 **종류**. 경로와 필드 이름이 여기 모인다.
///
/// ## ⚠️ 두 Key는 서로 못 바꾼다
///
/// 프로필 Key로 배경을 등록하면 서버가 `INVALID_BACKGROUND_IMAGE`로 거절한다.
/// 같은 사진을 둘 다에 쓰더라도 **각각 발급받아 각각 올려야 한다.**
///
/// 그래서 종류를 enum으로 들고, 저장소가 생성자에서 한 번 받아 `final`로 둔다.
/// 메서드 인자로 받으면 한 객체가 두 종류를 오가며 **Key를 섞을 자리**가 생기는데,
/// 그 실수는 서버가 400으로만 알려 준다 — 화면에는 "실패"만 뜬다.
enum ProfileImageKind {
  profile('profile-image', 'profileImageKey', 'profileImageUrl'),
  background('background-image', 'backgroundImageKey', 'backgroundImageUrl');

  const ProfileImageKind(this._segment, this.keyField, this.urlField);

  /// 경로의 마지막 조각. `/users/me/<여기>`.
  final String _segment;

  /// 발급 응답과 등록 요청이 쓰는 이름.
  final String keyField;

  /// 조회 응답이 쓰는 이름.
  final String urlField;

  /// 인증이 필요한 셋(발급·등록·삭제)이 쓰는 경로.
  String get mePath => '/api/v1/users/me/$_segment';

  /// 조회 경로. **인증이 없다** — 남의 것도 같은 API로 본다.
  String userPath(String userId) => '/api/v1/users/$userId/$_segment';
}
