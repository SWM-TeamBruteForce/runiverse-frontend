/// 친구 응답을 읽는다.
///
/// ## ⚠️ 던지지 않는다
///
/// 200인데 몸통이 기대와 다를 수 있다. 여기서 던지면 부르는 쪽마다 또 받아내야
/// 하고, 화면에서 "목록이 비었다"와 "못 받았다"는 어차피 같은 그림이다.
/// **못 읽은 것은 조용히 빠진다.**
library;

import 'package:runiverse/features/friend/domain/friend_entry.dart';
import 'package:runiverse/features/friend/domain/friend_page.dart';
import 'package:runiverse/features/friend/domain/friend_recommendation.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';

/// 목록 한 쪽을 읽는다.
///
/// ⚠️ **항목 하나가 깨져도 나머지는 살린다.** 한 사람 때문에 목록이 통째로
/// 비면 쓸 수 없는 화면이 된다.
FriendPage friendPageFromJson(Object? body) {
  if (body is! Map) return const FriendPage.empty();
  final items = body['items'];
  final cursor = body['nextCursor'];

  return FriendPage(
    items: items is List
        ? [for (final item in items) ?_entryOf(item)]
        : const [],
    nextCursor: cursor is String && cursor.isNotEmpty ? cursor : null,
  );
}

/// 추천 목록을 읽는다.
///
/// ⚠️ **이유를 못 읽은 사람은 뺀다.** 추천 줄은 이유를 함께 보여 주는 것이
/// 전부라, 이유가 없으면 그 줄에 쓸 말이 없다. 운영 설정이 바뀌어 기준이 늘면
/// 그 사람들만 조용히 빠진다.
List<FriendRecommendation> recommendationsFromJson(Object? body) {
  if (body is! Map) return const [];
  final list = body['recommendations'];
  if (list is! List) return const [];

  return [
    for (final item in list)
      if (_entryOf(item) case final entry?)
        if (_reasonOf(item) case final reason?)
          FriendRecommendation(
            // 추천은 전부 `none` 이다 — 서버가 나머지를 빼고 준다.
            entry: entry.withRelation(FriendRelation.none),
            reason: reason,
          ),
  ];
}

/// 사람 하나. `userId`와 `nickname`이 있어야 줄을 세울 수 있다.
FriendEntry? _entryOf(Object? item) {
  if (item is! Map) return null;
  final userId = item['userId'];
  final nickname = item['nickname'];
  if (userId is! String || nickname is! String) return null;

  final photo = item['profileImageUrl'];
  return FriendEntry(
    userId: userId,
    nickname: nickname,
    profileImageUrl: photo is String && photo.isNotEmpty ? photo : null,
    relation: friendRelationOf(item['relationshipType']),
  );
}

FriendReason? _reasonOf(Object? item) => switch ((item as Map?)?['reason']) {
  'RAN_TOGETHER' => FriendReason.ranTogether,
  'SIMILAR_PACE' => FriendReason.similarPace,
  _ => null,
};
