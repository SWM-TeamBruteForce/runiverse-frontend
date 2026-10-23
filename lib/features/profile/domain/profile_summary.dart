/// 프로필 화면이 그리는 한 사람의 요약. `GET /api/v1/users/{userId}` (명세 37번).
///
/// ## 본인과 타인이 같은 것을 쓴다
///
/// 서버가 한 엔드포인트로 둘을 다 답한다. 그래서 이 화면도 하나로 두고,
/// **누구를 보는지는 `userId`가 정한다.**
///
/// ## 응답의 일부만 담는다
///
/// 서버는 마일리지·최고 페이스·러닝 횟수·`isMe`·`friendStatus`도 함께 준다.
/// **지금 화면이 그리지 않으므로 담지 않는다** — 대시보드나 타인 프로필을 만들 때
/// 그 화면과 함께 넣는 것이 맞다. 쓰지 않는 필드를 미리 담아두면 "이건 왜 있지"가
/// 되고, 서버 규격이 바뀌어도 아무도 눈치채지 못한다.
class ProfileSummary {
  const ProfileSummary({
    required this.userId,
    required this.friendCount,
    this.nickname,
    this.profileImageUrl,
    this.introduction,
  });

  final String userId;

  /// 온보딩 전에는 셋 다 `null`일 수 있다.
  final String? nickname;

  /// ⚠️ **만료되는 주소다.** 화면은 실패했을 때 기본 아이콘으로 물러설 줄 알아야 한다.
  final String? profileImageUrl;

  final String? introduction;

  /// 서로 수락한 사람 수. 화면에는 **"블렌드 러너"**로 적는다 —
  /// `CLAUDE.md`가 "친구"라는 말을 쓰지 않기로 정했다.
  final int friendCount;
}
