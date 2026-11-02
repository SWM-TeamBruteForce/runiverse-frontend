import 'package:flutter/foundation.dart';
import 'package:runiverse/core/utils/kst_time.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';
import 'package:runiverse/features/notification/domain/app_notification.dart';
import 'package:runiverse/features/notification/domain/notification_page_result.dart';

/// 알림 응답을 읽는다. **여기가 그 형식을 아는 유일한 곳이다.**
///
/// ## ⚠️ 깨진 한 줄이 목록을 통째로 버리게 하지 않는다
///
/// 알림 하나를 못 읽어서 알림함이 비어 보이면, 사용자는 받은 초대를 영영 못
/// 본다. 못 읽는 원소만 건너뛴다 — `slot_board_dto.dart`와 같은 판단이다.

/// 목록 한 페이지(`GET /users/me/notifications`).
NotificationPageResult notificationPageFromJson(Object? body) {
  if (body is! Map) return const NotificationPageResult.empty();

  final rows = body['items'];
  final unread = body['unreadCount'];
  final cursor = body['nextCursor'];

  return NotificationPageResult(
    items: rows is List ? [for (final row in rows) ?_itemOf(row)] : const [],
    // 못 읽으면 0이다. 지어낸 숫자를 배지에 세우는 것보다 낫다 — 다음 진입
    // 때 재보정된다.
    unreadCount: unread is int && unread > 0 ? unread : 0,
    nextCursor: cursor is String && cursor.isNotEmpty ? cursor : null,
  );
}

/// 목록 항목 하나. **`type`이 안에 실려 있다.**
AppNotification? _itemOf(Object? wire) {
  if (wire is! Map) return null;
  return _notificationOf(NotificationType.of(wire['type']), wire);
}

/// 앱 스트림 이벤트의 `data`.
///
/// ⚠️ **종류는 이벤트 이름이 말한다.** `data`는 목록 항목에서 `type`만 뺀
/// 모양이라, 이름을 붙이면 그대로 목록 항목이 된다.
///
/// 모르는 이벤트 이름이면 `null`이다 — **스트림을 끊지 않는다.** 지원하지 않는
/// 이벤트를 받았다고 알림 처리 전체가 실패하면 안 된다.
AppNotification? notificationFromEvent(String eventName, Object? data) {
  final type = NotificationType.of(eventName);
  if (type == null) {
    debugPrint('[app-stream] 모르는 이벤트를 버렸다 · $eventName');
    return null;
  }
  if (data is! Map) return null;
  return _notificationOf(type, data);
}

AppNotification? _notificationOf(
  NotificationType? type,
  Map<Object?, Object?> wire,
) {
  if (type == null) return null;

  // ⚠️ **`Long`이다.** 문자열로 오면 버린다 — 숫자로 비교해야 중복 제거가
  // 돈다. 뭉개서 파싱하면 `"913"`과 `913`이 다른 알림이 되어 배지가 어긋난다.
  final id = wire['notificationId'];
  if (id is! int) return null;

  final createdAt = KstTime.parse(wire['createdAt']);
  if (createdAt == null) return null;

  final actor = _actorOf(wire['actor']);
  if (actor == null) return null;

  final invitation = _invitationOf(wire['invitation']);
  // ⚠️ **초대 알림에 초대가 없으면 버린다.** 명세는 그런 경우가 없다고 하지만
  // 오면 줄을 그릴 수 없다 — 시각도 거리도 방 번호도 거기 있다. 그 알림만
  // 버리고 나머지 목록은 산다.
  if (type == NotificationType.runningInvited && invitation == null) {
    debugPrint('[notification] 초대 없는 초대 알림을 버렸다 · $id');
    return null;
  }

  return AppNotification(
    notificationId: id,
    type: type,
    // 없으면 안 읽은 것으로 본다. 읽은 것을 안 읽었다고 하는 편이 그 반대보다
    // 낫다 — 강조가 한 번 더 뜰 뿐이고, 놓치지는 않는다.
    isRead: wire['isRead'] == true,
    createdAt: createdAt,
    actor: actor,
    invitation: invitation,
  );
}

NotificationActor? _actorOf(Object? wire) {
  if (wire is! Map) return null;
  final id = wire['userId'];
  final nickname = wire['nickname'];
  if (id is! String || nickname is! String) return null;

  return NotificationActor(
    userId: id,
    nickname: nickname,
    isDeleted: wire['isDeleted'] == true,
    profileImageUrl: _stringOrNull(wire['profileImageUrl']),
    // ⚠️ 탈퇴했으면 서버가 `null`을 주고, 모르는 값도 `null`이 된다. 둘 다
    // 화면에서 하는 일이 같다 — **친구 버튼을 세우지 않는다.**
    relation: friendRelationOf(wire['relationshipType']),
  );
}

NotificationInvitation? _invitationOf(Object? wire) {
  if (wire is! Map) return null;

  final roomId = wire['runningRoomId'];
  final status = InvitationStatus.of(wire['status']);
  final startAt = KstTime.parse(wire['scheduledStartAt']);
  final meters = wire['targetDistanceMeters'];

  // ⚠️ **`status`를 뭉개지 않는다.** `pending`으로 읽으면 이미 끝난 초대에
  // 수락 버튼이 서고, 눌러 봐야 409만 돌아온다. 넷 중 하나라도 없으면
  // 그릴 수 없는 줄이다.
  if (roomId is! int || status == null || startAt == null || meters is! int) {
    return null;
  }

  return NotificationInvitation(
    runningRoomId: roomId,
    status: status,
    scheduledStartAt: startAt,
    targetDistanceMeters: meters,
  );
}

String? _stringOrNull(Object? value) =>
    value is String && value.isNotEmpty ? value : null;
