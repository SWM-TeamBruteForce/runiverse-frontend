import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/friend/domain/friend_entry.dart';
import 'package:runiverse/features/friend/domain/friend_group.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';

/// 목록을 관계별로 묶는다.
///
/// ## ⚠️ 묶는 것은 앱이다
///
/// 검색은 서버가 **닉네임 오름차순으로만** 준다. 관계별 묶음은 받은 결과를
/// 앱이 다시 세워 만든다. 친구 목록은 서버가 이미 묶어 주지만, 머리글을
/// 얹으려면 같은 함수를 거친다.
void main() {
  FriendEntry e(String id, FriendRelation? r) =>
      FriendEntry(userId: id, nickname: id, relation: r);

  test('검색 순서는 친구 · 받은 요청 · 보낸 요청 · 그 밖이다', () {
    final groups = groupFriends([
      e('a', FriendRelation.none),
      e('b', FriendRelation.friend),
      e('c', FriendRelation.requestSent),
      e('d', FriendRelation.requestReceived),
    ], friendOrderSearch);

    expect(groups.map((g) => g.relation), [
      FriendRelation.friend,
      FriendRelation.requestReceived,
      FriendRelation.requestSent,
      FriendRelation.none,
    ]);
  });

  test('내 목록 순서는 받은 요청 · 보낸 요청 · 친구다', () {
    // 내가 답해야 할 것이 먼저다. 서버 정렬과 같은 순서라 그대로 편다.
    final groups = groupFriends([
      e('a', FriendRelation.friend),
      e('b', FriendRelation.requestSent),
      e('c', FriendRelation.requestReceived),
    ], friendOrderMine);

    expect(groups.map((g) => g.relation), [
      FriendRelation.requestReceived,
      FriendRelation.requestSent,
      FriendRelation.friend,
    ]);
  });

  test('⚠️ 묶음 안에서는 받은 순서를 지킨다', () {
    // 서버가 닉네임 오름차순으로 준다. 이 순서를 지켜야 다음에 받은 사람이
    // 묶음 **끝**에만 붙고, 이미 그려진 행 사이로 끼어들지 않는다. 끼어들면
    // 스크롤 중에 목록이 튄다.
    final groups = groupFriends([
      e('가', FriendRelation.none),
      e('나', FriendRelation.none),
      e('다', FriendRelation.none),
    ], friendOrderSearch);

    expect(groups.single.entries.map((x) => x.userId), ['가', '나', '다']);
  });

  test('빈 묶음은 빠진다', () {
    final groups = groupFriends([
      e('a', FriendRelation.friend),
    ], friendOrderSearch);

    expect(groups, hasLength(1));
    expect(groups.single.relation, FriendRelation.friend);
  });

  test('⚠️ order 에 없는 관계는 버린다', () {
    // 내 목록 순서에는 `none` 이 없다. 서버가 실수로 끼워 보내도 머리글 없는
    // 줄이 생기지 않는다.
    expect(
      groupFriends([e('a', FriendRelation.none)], friendOrderMine),
      isEmpty,
    );
  });

  test('⚠️ 관계가 null 인 항목(나 자신)은 버린다', () {
    expect(groupFriends([e('me', null)], friendOrderSearch), isEmpty);
  });

  test('빈 목록은 빈 묶음이다', () {
    expect(groupFriends(const [], friendOrderSearch), isEmpty);
  });
}
