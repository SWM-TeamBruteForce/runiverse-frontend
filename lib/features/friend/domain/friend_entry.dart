import 'package:runiverse/features/friend/domain/friend_relation.dart';

/// 목록에 서는 사람 하나.
///
/// 친구 목록 · 검색 결과 · 추천이 모두 이 네 값을 준다. 화면이 그릴 수 있는
/// 것도 이것뿐이다 — **페이스도, 접속 상태도, 언제 함께 뛰었는지도 서버가
/// 주지 않는다**(`docs/specs/2026-10-28-friend-design.md` §8-1).
class FriendEntry {
  const FriendEntry({
    required this.userId,
    required this.nickname,
    this.profileImageUrl,
    this.relation,
  });

  final String userId;
  final String nickname;

  /// 사진이 없으면 `null`. 서명된 URL이라 운영값(현재 1시간) 동안만 산다.
  final String? profileImageUrl;

  /// **나와 이 사람의 관계.** 목록 주인과의 관계가 아니다.
  ///
  /// ⚠️ **이 사람이 나 자신이면 `null`이다.** 타인의 친구 목록에는 내가 들어
  /// 있을 수 있다. `null`인 줄에는 버튼을 그리지 않는다.
  final FriendRelation? relation;

  FriendEntry withRelation(FriendRelation? next) => FriendEntry(
    userId: userId,
    nickname: nickname,
    profileImageUrl: profileImageUrl,
    relation: next,
  );
}
