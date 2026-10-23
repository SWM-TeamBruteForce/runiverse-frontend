/// 내 프로필을 누가 볼 수 있는가. `GET·PATCH /api/v1/users/me/settings`.
///
/// ## "친구"라고 쓰지 않는다
///
/// 서버 enum은 `FRIENDS`지만 화면에는 **"팔로워에게만"**으로 적는다.
/// `CLAUDE.md`가 "친구"라는 말을 쓰지 않기로 정했다 — 이 서비스는 요청→수락
/// 모델이고, 정본 S18도 "팔로워/팔로잉 목록"이다.
///
/// 그래서 이름이 [followers]다. **전송값만 서버 말을 따른다.**
///
/// ## ⚠️ 정본은 3단이지만 둘뿐이다
///
/// 정본 와이어프레임 S22.2는 전체공개·팔로워공개·나만보기 셋인데
/// 서버 enum에 "나만보기"가 없다. 칸을 만들어 두면 저장할 데가 없다.
enum ProfileVisibility {
  public,
  followers;

  /// 서버가 받는 값.
  ///
  /// enum 이름에서 뽑지 않는다. `followers`를 대문자로 바꾸면 `FOLLOWERS`가
  /// 되는데 서버는 `FRIENDS`를 기다린다 — 이름과 약속은 서로 다른 것이다.
  String get wireValue => switch (this) {
    ProfileVisibility.public => 'PUBLIC',
    ProfileVisibility.followers => 'FRIENDS',
  };

  /// 모르는 값이면 `null`. 서버가 단계를 늘려도 앱이 죽지 않아야 한다.
  static ProfileVisibility? fromWire(String? value) => switch (value) {
    'PUBLIC' => ProfileVisibility.public,
    'FRIENDS' => ProfileVisibility.followers,
    _ => null,
  };
}
