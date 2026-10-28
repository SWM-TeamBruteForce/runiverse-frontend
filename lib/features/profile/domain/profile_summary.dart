import 'package:runiverse/features/friend/domain/friend_relation.dart';

/// 프로필 화면이 그리는 한 사람의 요약. `GET /api/v1/users/{userId}` (명세 37번).
///
/// ## 본인과 타인이 같은 것을 쓴다
///
/// 서버가 한 엔드포인트로 둘을 다 답한다. 그래서 이 화면도 하나로 두고,
/// **누구를 보는지는 `userId`가 정한다.**
///
/// ## 응답의 일부만 담는다
///
/// 서버가 주는 것 중 화면이 그리는 것만 담는다. 쓰지 않는 필드를 미리
/// 담아두면 "이건 왜 있지"가 되고, 서버 규격이 바뀌어도 아무도 눈치채지
/// 못한다.
///
/// [isMe]와 [relation]은 2026-10-28에 들어왔다 — 타인 프로필을 만들면서다.
class ProfileSummary {
  const ProfileSummary({
    required this.userId,
    required this.friendCount,
    this.nickname,
    this.profileImageUrl,
    this.introduction,
    this.isMe = false,
    this.relation,
  });

  final String userId;

  /// 온보딩 전에는 셋 다 `null`일 수 있다.
  final String? nickname;

  /// ⚠️ **만료되는 주소다.** 화면은 실패했을 때 기본 아이콘으로 물러설 줄 알아야 한다.
  final String? profileImageUrl;

  final String? introduction;

  /// 서로 수락한 사람 수. 화면에는 **"친구"**로 적는다.
  final int friendCount;

  /// 내 프로필인가.
  ///
  /// ⚠️ **없으면 거짓으로 둔다.** 못 읽었다고 내 것으로 읽으면 남의 화면에
  /// "프로필 편집"이 뜬다.
  final bool isMe;

  /// 나와 이 사람의 관계. **[isMe]면 `null`이다.**
  ///
  /// ⚠️ **서버가 이 값을 `friendStatus`로 부르고 값도 다르다**(`ACCEPTED` 대
  /// `FRIEND`). 읽는 일은 `friendRelationOf`가 두 어휘를 모두 받아서 한다.
  final FriendRelation? relation;
}
