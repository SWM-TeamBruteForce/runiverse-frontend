import 'package:runiverse/features/friend/domain/friend_entry.dart';
import 'package:runiverse/features/friend/domain/friend_list.dart';
import 'package:runiverse/features/friend/domain/friend_recommendation.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';
import 'package:runiverse/features/friend/domain/friend_repository.dart';

/// 서버 없이 도는 [FriendRepository]. **상태 전이와 화면 테스트가 쓴다.**
///
/// 심어 둔 값을 돌려주고, **무엇을 어떤 인자로 불렀는지 기록한다** — 검색이
/// 20에서 50으로 올라갔는지, 수락 뒤에 목록을 다시 읽지 않았는지는 그 기록이
/// 아니면 확인할 길이 없다.
class FakeFriendRepository implements FriendRepository {
  FakeFriendRepository({
    this.friendEntries = const [],
    this.recommended = const [],
    this.searchResults = const [],
    this.nextCursor,
    this.failure,
    this.actionFailure,
  });

  /// 내 친구 목록으로 돌려줄 것.
  final List<FriendEntry> friendEntries;
  final List<FriendRecommendation> recommended;
  final List<FriendEntry> searchResults;
  final String? nextCursor;

  /// 심어 두면 **모든 호출**이 이 갈래로 던진다.
  final FriendFailure? failure;

  /// 조회는 되는데 **버튼만** 실패한다. 404·409를 재현하는 데 쓴다 — 목록이
  /// 떠 있어야 누를 줄이 있다.
  final FriendFailure? actionFailure;

  var friendsCalls = 0;

  /// 조회마다 받은 커서. 이어 읽기가 서버 값을 그대로 돌려보내는지 본다.
  final cursors = <String?>[];
  var recommendationsCalls = 0;
  final searchQueries = <String>[];
  final searchLimits = <int>[];
  final requested = <String>[];
  final accepted = <String>[];
  final cancelled = <String>[];
  final removed = <String>[];

  void _maybeThrow() {
    final f = failure;
    if (f != null) throw FriendException(f);
  }

  void _maybeThrowAction() {
    final f = actionFailure;
    if (f != null) throw FriendException(f);
  }

  @override
  Future<FriendList> friends({
    required String userId,
    String? cursor,
    int limit = 20,
  }) async {
    _maybeThrow();
    friendsCalls++;
    cursors.add(cursor);
    // 이어 읽기는 다음 장이라 다른 사람이 와야 한다. 마지막 장이면 커서가
    // 없다.
    if (cursor != null) {
      return FriendList(
        items: [
          for (final entry in friendEntries)
            FriendEntry(
              userId: '${entry.userId}-$cursor',
              nickname: entry.nickname,
              relation: entry.relation,
            ),
        ],
      );
    }
    return FriendList(items: friendEntries, nextCursor: nextCursor);
  }

  @override
  Future<List<FriendRecommendation>> recommendations() async {
    _maybeThrow();
    recommendationsCalls++;
    return recommended;
  }

  @override
  Future<FriendList> search({required String query, int limit = 20}) async {
    _maybeThrow();
    searchQueries.add(query);
    searchLimits.add(limit);
    // 요청한 만큼만 돌려준다 — 20을 물었는데 50이 오면 화면이 더 읽을 이유를
    // 잃는다.
    return FriendList(items: searchResults.take(limit).toList());
  }

  @override
  Future<FriendRelation> request(String userId) async {
    _maybeThrow();
    _maybeThrowAction();
    requested.add(userId);
    return FriendRelation.requestSent;
  }

  @override
  Future<FriendRelation> accept(String userId) async {
    _maybeThrow();
    _maybeThrowAction();
    accepted.add(userId);
    return FriendRelation.friend;
  }

  @override
  Future<void> cancel(String userId) async {
    _maybeThrow();
    _maybeThrowAction();
    cancelled.add(userId);
  }

  @override
  Future<void> remove(String userId) async {
    _maybeThrow();
    _maybeThrowAction();
    removed.add(userId);
  }
}
