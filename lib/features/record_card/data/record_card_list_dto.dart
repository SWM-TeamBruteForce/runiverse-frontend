import 'package:runiverse/features/record_card/domain/record_card_list_item.dart';

/// `GET /api/v1/users/{userId}/record-cards?limit=&cursor=` 응답 (10-3).
///
/// **여기가 서버 형식을 아는 유일한 곳이다.**
///
/// ## ⚠️ 서버가 거른다
///
/// 보는 사람과 작성자의 관계로 서버가 인가를 적용한다(연동 가이드 5절) —
/// 앱은 받은 `items`를 그대로 세운다. 앱이 거르면 "안 보여야 할 카드가 이미
/// 기기에 와 있다"는 뜻이 되고, 내려받은 뒤 가리는 것은 가린 것이 아니다.
///
/// **본인에게는 비공개 카드도 온다**(2026-11-24 결정) — 항목에 `visibility`가
/// 없어 앱이 가려낼 근거도 없다.
abstract final class RecordCardListDto {
  const RecordCardListDto._();

  static RecordCardListPage from(Map<String, dynamic> json) => RecordCardListPage(
    items: [
      if (json['items'] case final List items)
        for (final item in items)
          if (item is Map<String, dynamic>) _item(item),
    ],
    // ⚠️ **빈 문자열을 커서로 쓰지 않는다.** 그대로 다음 요청에 넣으면
    // `400`이고(가이드 5절 3번), "더 있다"로 읽히면 끝나지 않는 목록이 된다.
    nextCursor: switch (json['nextCursor']) {
      final String cursor when cursor.isNotEmpty => cursor,
      _ => null,
    },
  );

  static RecordCardListItem _item(Map<String, dynamic> json) =>
      RecordCardListItem(
        id: json['recordCardId'] as String,
        // ⚠️ **오프셋 없는 KST다.** `.toUtc()`를 붙이면 9시간 밀린다.
        startedAt: DateTime.parse(json['startedAt'] as String),
        distanceMeters: json['totalDistanceMeters'] as int? ?? 0,
        imageCount: json['imageCount'] as int? ?? 0,
        thumbnailUrl: json['thumbnailUrl'] as String?,
      );
}
