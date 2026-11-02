import 'package:runiverse/features/friend/domain/friend_list.dart';
import 'package:runiverse/features/friend/domain/friend_recommendation.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';

/// 친구를 맺고 끊고 찾는 길.
abstract class FriendRepository {
  /// [userId]의 친구 목록. 내 목록이면 주고받은 요청도 함께 온다.
  ///
  /// 타인 목록에는 **친구만** 담긴다 — 누구에게 요청했는지는 본인만 안다.
  Future<FriendList> friends({
    required String userId,
    String? cursor,
    int limit = 20,
  });

  /// 추천. 최대 30명이고 **페이지가 없다.**
  Future<List<FriendRecommendation>> recommendations();

  /// 닉네임으로 전체 사용자를 찾는다.
  ///
  /// ⚠️ **커서를 받지 않는다.** 처음 20, 더 보면 같은 [query]로 50을 다시
  /// 받는다(설계 §5). 커서로 이어 읽으면 그 사이 닉네임을 바꾼 사람이 빠지거나
  /// 두 번 올 수 있다.
  Future<FriendList> search({required String query, int limit = 20});

  /// 친구 요청을 보낸다.
  ///
  /// ⚠️ **돌려주는 관계를 그대로 믿는다.** 상대가 먼저 요청해 뒀으면 서버가
  /// `201`이 아니라 `200` + `FRIEND`를 준다. 상태 코드로 갈라서는 안 된다.
  Future<FriendRelation> request(String userId);

  /// 받은 요청을 수락한다. 멱등이라 이미 친구여도 같은 값이 온다.
  Future<FriendRelation> accept(String userId);

  /// 보낸 요청을 취소하거나 받은 요청을 거절한다. **하는 일이 같아 하나다.**
  ///
  /// ⚠️ 멱등이 아니다. 이미 취소·거절된 요청에 다시 부르면 `404`다.
  Future<void> cancel(String userId);

  /// 친구를 끊는다. 친구가 된 뒤로는 누가 요청했었는지 상관없어 양쪽 다 부를
  /// 수 있다.
  ///
  /// ⚠️ 멱등이 아니다. 이미 끊은 사이에 다시 부르면 `404`다.
  Future<void> remove(String userId);
}

/// 친구 쪽에서 일이 틀어지는 갈래.
enum FriendFailure {
  network,
  sessionExpired,

  /// 이미 처리됐거나 상대가 없다. **경합에서 진 경우도 여기다** — 내가 수락을
  /// 누르는 사이 상대가 요청을 취소했다.
  notFound,

  /// 이미 요청했거나 이미 친구다.
  alreadyExists,

  /// 나 자신에게 요청했다. **일어나면 앱 버그다** — 검색·추천·목록 모두 나를
  /// 빼고 준다.
  cannotFriendSelf,

  unknown,
}

class FriendException implements Exception {
  const FriendException(this.failure);

  final FriendFailure failure;

  @override
  String toString() => 'FriendException(${failure.name})';
}
