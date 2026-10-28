import 'package:runiverse/features/friend/domain/friend_entry.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';

/// 같은 관계인 사람들의 묶음. 화면은 이 하나마다 머리글을 얹는다.
class FriendGroup {
  const FriendGroup({required this.relation, required this.entries});

  final FriendRelation relation;
  final List<FriendEntry> entries;
}

/// 내 친구 목록의 묶음 순서 — **내가 답해야 할 것이 먼저다.**
///
/// 서버가 `GET /users/{userId}/friends`를 이 순서로 주므로, 받은 그대로 펴면
/// 맞는다. `none`은 들어 있지 않다 — 내 목록에 올 수 없는 관계다.
const friendOrderMine = [
  FriendRelation.requestReceived,
  FriendRelation.requestSent,
  FriendRelation.friend,
];

/// 검색 결과의 묶음 순서 — **이미 맺은 것이 위다.**
///
/// 검색은 네 관계가 섞여 온다. 찾던 사람이 이미 친구이거나 요청이 오간
/// 사이라면 그 사실이 먼저 보여야 한다.
const friendOrderSearch = [
  FriendRelation.friend,
  FriendRelation.requestReceived,
  FriendRelation.requestSent,
  FriendRelation.none,
];

/// [entries]를 [order]대로 묶는다. 비어 있는 묶음은 넣지 않는다.
///
/// ## ⚠️ 묶음 안에서는 받은 순서를 지킨다
///
/// 서버는 검색 결과를 **닉네임 오름차순으로만** 준다. 그 순서를 묶음 안에서
/// 지켜야, 두 번째로 받은 목록의 사람이 자기 묶음 **끝**에만 붙는다. 다시
/// 정렬하면 이미 그려진 행 사이로 끼어들어 **스크롤 중에 목록이 튄다.**
///
/// ⚠️ **[order]에 없는 관계와 `null`은 버린다.** `null`은 그 줄이 나 자신이라는
/// 뜻이고, 내 목록에 `none`이 오는 일은 서버 쪽 실수다. 어느 쪽이든 머리글
/// 없는 줄을 만드는 것보다 안 그리는 편이 낫다.
List<FriendGroup> groupFriends(
  List<FriendEntry> entries,
  List<FriendRelation> order,
) => [
  for (final relation in order)
    if (entries.where((e) => e.relation == relation).toList() case final picked
        when picked.isNotEmpty)
      FriendGroup(relation: relation, entries: picked),
];
