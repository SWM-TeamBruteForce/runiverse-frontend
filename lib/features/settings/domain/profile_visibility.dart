/// 내 프로필을 누가 볼 수 있는가. `GET·PATCH /api/v1/users/me/settings`.
///
/// ## "친구"라고 쓴다
///
/// 2026-10-28에 앱 어휘를 **친구**로 통일했다. 그 전에는 팔로우 모델을 따라
/// [friends]가 `followers`였고 화면에도 "팔로워에게만"으로 적었다. 백엔드가
/// 양방향 친구(요청→수락)로 가면서 서버·앱·시안이 한 말을 쓰게 됐다.
///
/// 자세한 경위는 `docs/specs/2026-10-28-friend-design.md` §1.
///
/// ## ⚠️ 정본은 3단이지만 둘뿐이다
///
/// 정본 와이어프레임 S22.2는 전체공개·친구공개·나만보기 셋인데
/// 서버 enum에 "나만보기"가 없다. 칸을 만들어 두면 저장할 데가 없다.
enum ProfileVisibility {
  public,
  friends;

  /// 서버가 받는 값.
  ///
  /// ⚠️ **enum 이름에서 뽑지 않는다.** 지금은 [friends]와 `FRIENDS`가 우연히
  /// 겹치지만, 이름은 앱 사정이고 전송값은 서버와의 약속이라 따로 둔다.
  /// 이름을 또 바꾸는 날 전송값이 따라 바뀌면 설정이 저장되지 않는다.
  String get wireValue => switch (this) {
    ProfileVisibility.public => 'PUBLIC',
    ProfileVisibility.friends => 'FRIENDS',
  };

  /// 모르는 값이면 `null`. 서버가 단계를 늘려도 앱이 죽지 않아야 한다.
  static ProfileVisibility? fromWire(String? value) => switch (value) {
    'PUBLIC' => ProfileVisibility.public,
    'FRIENDS' => ProfileVisibility.friends,
    _ => null,
  };
}
