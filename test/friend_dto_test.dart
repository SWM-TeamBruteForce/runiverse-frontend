import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/friend/data/friend_dto.dart';
import 'package:runiverse/features/friend/domain/friend_recommendation.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';

/// 친구 응답을 읽는다.
///
/// ## ⚠️ 한 항목이 깨졌다고 목록을 잃지 않는다
///
/// 200인데 몸통이 기대와 다를 수 있다. 읽지 못한 항목만 버리고 나머지는
/// 살린다 — 한 사람 때문에 친구 목록이 통째로 비면 쓸 수 없는 화면이 된다.
void main() {
  group('목록', () {
    test('목록과 커서를 읽는다', () {
      final page = friendPageFromJson({
        'items': [
          {
            'userId': 'u1',
            'nickname': '철수',
            'profileImageUrl': 'https://x',
            'relationshipType': 'FRIEND_REQUEST_RECEIVED',
          },
        ],
        'nextCursor': 'abc',
      });

      expect(page.items.single.nickname, '철수');
      expect(page.items.single.profileImageUrl, 'https://x');
      expect(page.items.single.relation, FriendRelation.requestReceived);
      expect(page.nextCursor, 'abc');
    });

    test('마지막 페이지면 커서가 null 이다', () {
      final page = friendPageFromJson({
        'items': <Object>[],
        'nextCursor': null,
      });

      expect(page.items, isEmpty);
      expect(page.nextCursor, isNull);
    });

    test('⚠️ 읽지 못한 항목은 버리고 나머지는 살린다', () {
      final page = friendPageFromJson({
        'items': [
          {'nickname': '이름만'},
          {'userId': 'u2', 'nickname': '영희', 'relationshipType': 'FRIEND'},
        ],
      });

      expect(page.items, hasLength(1));
      expect(page.items.single.userId, 'u2');
    });

    test('⚠️ 몸통을 못 읽으면 빈 목록이다', () {
      // 던지지 않는다. 목록이 비는 것과 못 받는 것은 화면에서 같은 그림이고,
      // 여기서 던지면 호출하는 쪽마다 또 받아내야 한다.
      expect(friendPageFromJson(null).items, isEmpty);
      expect(friendPageFromJson({'items': 'oops'}).items, isEmpty);
    });

    test('관계가 없는 항목도 자리는 지킨다', () {
      // 목록 주인이 나 자신이면 서버가 `null` 을 준다.
      final page = friendPageFromJson({
        'items': [
          {'userId': 'me', 'nickname': '나', 'relationshipType': null},
        ],
      });

      expect(page.items.single.relation, isNull);
    });
  });

  group('추천', () {
    test('추천 이유를 읽는다', () {
      final list = recommendationsFromJson({
        'recommendations': [
          {'userId': 'u1', 'nickname': '철수', 'reason': 'RAN_TOGETHER'},
          {'userId': 'u2', 'nickname': '민수', 'reason': 'SIMILAR_PACE'},
        ],
      });

      expect(list.map((r) => r.reason), [
        FriendReason.ranTogether,
        FriendReason.similarPace,
      ]);
      expect(list.first.entry.nickname, '철수');
    });

    test('⚠️ 추천은 전부 NONE 이다', () {
      // 서버가 친구·요청이 오간 사람을 빼고 준다. 화면이 버튼을 하나로 두는
      // 근거다.
      final list = recommendationsFromJson({
        'recommendations': [
          {'userId': 'u1', 'nickname': '철수', 'reason': 'RAN_TOGETHER'},
        ],
      });

      expect(list.single.entry.relation, FriendRelation.none);
    });

    test('⚠️ 모르는 reason 은 버린다', () {
      // 운영 설정이 바뀌어 기준이 늘 수 있다. 이유를 못 읽으면 줄에 쓸 말이
      // 없어서, 빈 자리를 남기느니 뺀다.
      final list = recommendationsFromJson({
        'recommendations': [
          {'userId': 'u1', 'nickname': '철수', 'reason': 'LIVES_NEARBY'},
        ],
      });

      expect(list, isEmpty);
    });

    test('후보가 없으면 빈 목록이다', () {
      expect(recommendationsFromJson({'recommendations': <Object>[]}), isEmpty);
      expect(recommendationsFromJson(null), isEmpty);
    });
  });
}
