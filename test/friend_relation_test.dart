import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';

/// 나와 상대의 관계를 읽는다.
///
/// ## ⚠️ 서버가 같은 뜻을 두 말로 준다
///
/// 친구 엔드포인트는 `relationshipType`, 프로필 요약(No 38)은 `friendStatus`
/// 인데 **값까지 다르다.** 한쪽만 읽으면 **친구인 사람에게 "친구 요청"
/// 버튼이 뜬다** — 눌러 봐야 `409`만 돌아온다.
///
/// 앱의 값은 하나다. 읽는 쪽에서 두 어휘를 같은 값으로 접는다.
/// 표는 `docs/specs/2026-10-28-friend-design.md` §2-1.
void main() {
  test('친구 API 어휘를 읽는다', () {
    expect(friendRelationOf('NONE'), FriendRelation.none);
    expect(friendRelationOf('FRIEND_REQUEST_SENT'), FriendRelation.requestSent);
    expect(
      friendRelationOf('FRIEND_REQUEST_RECEIVED'),
      FriendRelation.requestReceived,
    );
    expect(friendRelationOf('FRIEND'), FriendRelation.friend);
  });

  test('⚠️ 프로필 API 어휘도 같은 값으로 접는다', () {
    expect(friendRelationOf('PENDING_SENT'), FriendRelation.requestSent);
    expect(
      friendRelationOf('PENDING_RECEIVED'),
      FriendRelation.requestReceived,
    );
    expect(friendRelationOf('ACCEPTED'), FriendRelation.friend);
  });

  test('⚠️ 모르는 값과 null 은 null 이다', () {
    // 항목이 나 자신이면 서버가 `null` 을 준다. 아무 값으로 뭉개면 내 줄에
    // 버튼이 선다.
    expect(friendRelationOf(null), isNull);
    expect(friendRelationOf('BLOCKED'), isNull);
    expect(friendRelationOf(7), isNull);
    expect(friendRelationOf(''), isNull);
  });
}
