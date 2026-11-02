import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';
import 'package:runiverse/features/notification/data/notification_dto.dart';
import 'package:runiverse/features/notification/domain/app_notification.dart';

/// 인앱 알림 응답 읽기.
///
/// ## ⚠️ 이벤트 `data`와 목록 항목이 같은 모양이다
///
/// 이벤트는 `type`만 빠져 있고 종류는 **이벤트 이름이** 말한다. 그래서 버퍼에
/// 담은 이벤트를 목록과 `notificationId`로 대조할 수 있다 — 그 대조가 배지
/// 숫자를 목록과 맞추는 유일한 수단이다.
void main() {
  Map<String, Object?> actor({
    String? relationshipType = 'FRIEND',
    bool isDeleted = false,
    String nickname = '철수',
  }) => {
    'userId': '01a0f2d4-6180-7000-8000-446655440013',
    'nickname': nickname,
    'profileImageUrl': 'https://x/photo.jpg',
    'isDeleted': isDeleted,
    'relationshipType': relationshipType,
  };

  Map<String, Object?> invitation({
    int runningRoomId = 130,
    String status = 'PENDING',
  }) => {
    'runningRoomId': runningRoomId,
    'status': status,
    'scheduledStartAt': '2026-10-28T19:30:00',
    'targetDistanceMeters': 7000,
  };

  Map<String, Object?> data({
    int notificationId = 913,
    bool isRead = false,
    Map<String, Object?>? withActor,
    Map<String, Object?>? withInvitation,
  }) => {
    'notificationId': notificationId,
    'isRead': isRead,
    'createdAt': '2026-10-28T12:10:00',
    'actor': withActor ?? actor(),
    'invitation': withInvitation,
  };

  group('이벤트 data를 읽는다', () {
    test('RUNNING_INVITED는 초대를 싣고 온다', () {
      final one = notificationFromEvent(
        'RUNNING_INVITED',
        data(withInvitation: invitation()),
      );

      expect(one!.notificationId, 913);
      expect(one.type, NotificationType.runningInvited);
      expect(one.isRead, isFalse);
      expect(one.actor.nickname, '철수');
      expect(one.actor.relation, FriendRelation.friend);
      expect(one.invitation!.runningRoomId, 130);
      expect(one.invitation!.status, InvitationStatus.pending);
      expect(one.invitation!.targetDistanceMeters, 7000);
    });

    test('친구 알림은 초대가 null이다', () {
      final one = notificationFromEvent(
        'FRIEND_REQUESTED',
        data(
          notificationId: 912,
          withActor: actor(relationshipType: 'FRIEND_REQUEST_RECEIVED'),
        ),
      );

      expect(one!.type, NotificationType.friendRequested);
      expect(one.invitation, isNull);
      expect(one.actor.relation, FriendRelation.requestReceived);
    });

    test('FRIEND_ACCEPTED도 읽는다', () {
      final one = notificationFromEvent('FRIEND_ACCEPTED', data());

      expect(one!.type, NotificationType.friendAccepted);
      expect(one.invitation, isNull);
    });

    test('⚠️ 탈퇴한 사람의 관계는 null이다', () {
      // 친구 버튼을 전부 숨겨야 한다. `none`으로 읽으면 "친구 요청" 버튼이
      // 뜨고 눌러 봐야 아무 데도 가지 않는다.
      final one = notificationFromEvent(
        'FRIEND_REQUESTED',
        data(
          withActor: actor(
            relationshipType: null,
            isDeleted: true,
            nickname: '탈퇴한 사용자',
          ),
        ),
      );

      expect(one!.actor.relation, isNull);
      expect(one.actor.isDeleted, isTrue);
      expect(one.actor.nickname, '탈퇴한 사용자');
    });

    test('⚠️ 모르는 이벤트 이름은 null이다 — 스트림을 끊지 않는다', () {
      expect(notificationFromEvent('SOMETHING_NEW', data()), isNull);
    });

    test('⚠️ invitation 없는 RUNNING_INVITED는 버린다', () {
      // 명세는 "없다"고 하지만 오면 줄을 그릴 수 없다. 그 알림만 버리고
      // 나머지 목록은 살아야 한다.
      expect(notificationFromEvent('RUNNING_INVITED', data()), isNull);
    });

    test('⚠️ notificationId가 숫자가 아니면 버린다', () {
      // `Long`이다. 문자열로 다루면 "913"과 913이 다른 알림이 되어 중복
      // 제거가 깨지고 배지가 어긋난다.
      final broken = data()..['notificationId'] = '913';

      expect(notificationFromEvent('FRIEND_REQUESTED', broken), isNull);
    });

    test('actor가 없으면 버린다', () {
      final broken = data()..['actor'] = null;

      expect(notificationFromEvent('FRIEND_REQUESTED', broken), isNull);
    });

    test('createdAt은 오프셋 없는 KST다', () {
      final one = notificationFromEvent('FRIEND_ACCEPTED', data());

      // 2026-10-28T12:10:00 KST == 03:10 UTC
      expect(one!.createdAt.toUtc(), DateTime.utc(2026, 10, 28, 3, 10));
    });
  });

  group('초대 상태를 읽는다', () {
    test('다섯 값을 읽고 모르는 값은 null이다', () {
      expect(InvitationStatus.of('PENDING'), InvitationStatus.pending);
      expect(InvitationStatus.of('ACCEPTED'), InvitationStatus.accepted);
      expect(InvitationStatus.of('DECLINED'), InvitationStatus.declined);
      expect(InvitationStatus.of('LEFT'), InvitationStatus.left);
      expect(InvitationStatus.of('EXPIRED'), InvitationStatus.expired);
      expect(InvitationStatus.of('CANCELLED'), isNull);
      expect(InvitationStatus.of(null), isNull);
    });

    test('⚠️ 모르는 초대 상태면 알림을 버린다', () {
      // 버튼을 그릴 근거가 없다. `pending`으로 뭉개면 이미 끝난 초대에
      // 수락 버튼이 선다.
      expect(
        notificationFromEvent(
          'RUNNING_INVITED',
          data(withInvitation: invitation(status: 'CANCELLED')),
        ),
        isNull,
      );
    });
  });

  group('목록 한 페이지를 읽는다', () {
    Map<String, Object?> item({
      required String type,
      int notificationId = 913,
      Map<String, Object?>? withInvitation,
    }) => {
      'type': type,
      ...data(notificationId: notificationId, withInvitation: withInvitation),
    };

    test('항목·커서·안 읽은 수를 함께 읽는다', () {
      final page = notificationPageFromJson({
        'items': [
          item(type: 'RUNNING_INVITED', withInvitation: invitation()),
          item(type: 'FRIEND_ACCEPTED', notificationId: 912),
        ],
        'nextCursor': 'c2',
        'unreadCount': 7,
      });

      expect(page.items.map((n) => n.notificationId), [913, 912]);
      expect(page.items.first.type, NotificationType.runningInvited);
      expect(page.nextCursor, 'c2');
      expect(page.unreadCount, 7);
    });

    test('⚠️ items가 비어도 nextCursor가 있으면 마지막 페이지가 아니다', () {
      // 서버가 깨진 행과 초대 행 없는 알림을 건너뛴다. 개수로 판단하면
      // 목록이 중간에 끊긴다.
      final page = notificationPageFromJson({
        'items': <Object?>[],
        'nextCursor': 'c2',
        'unreadCount': 3,
      });

      expect(page.items, isEmpty);
      expect(page.nextCursor, 'c2');
    });

    test('nextCursor가 없으면 마지막 페이지다', () {
      final page = notificationPageFromJson({
        'items': <Object?>[],
        'nextCursor': null,
        'unreadCount': 0,
      });

      expect(page.nextCursor, isNull);
    });

    test('깨진 항목만 건너뛰고 나머지를 준다', () {
      final page = notificationPageFromJson({
        'items': [
          item(type: 'FRIEND_ACCEPTED', notificationId: 1),
          {'type': 'FRIEND_ACCEPTED', 'notificationId': 'nope'},
          'not-a-map',
          item(type: 'FRIEND_ACCEPTED', notificationId: 3),
        ],
        'unreadCount': 2,
      });

      expect(page.items.map((n) => n.notificationId), [1, 3]);
    });

    test('⚠️ 응답이 깨져도 빈 페이지를 준다', () {
      // 알림함이 통째로 못 열리는 것보다 비어 보이는 편이 낫다.
      final page = notificationPageFromJson('nope');

      expect(page.items, isEmpty);
      expect(page.unreadCount, 0);
      expect(page.nextCursor, isNull);
    });

    test('unreadCount가 숫자가 아니면 0이다', () {
      final page = notificationPageFromJson({
        'items': <Object?>[],
        'unreadCount': null,
      });

      expect(page.unreadCount, 0);
    });
  });
}
