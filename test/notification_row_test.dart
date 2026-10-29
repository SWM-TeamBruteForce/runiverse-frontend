import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';
import 'package:runiverse/features/notification/domain/app_notification.dart';
import 'package:runiverse/features/notification/presentation/notification_row.dart';

/// 알림 한 줄의 버튼과 문구.
///
/// ## ⚠️ 버튼은 지금 상태로 그린다
///
/// 알림이 만들어진 때를 기준으로 그리면 **이미 처리한 요청에 버튼이** 서고,
/// 눌러 봐야 409만 돌아온다.
void main() {
  final createdAt = DateTime(2026, 10, 28, 12, 10);

  AppNotification friend({
    required NotificationType type,
    FriendRelation? relation,
    bool isDeleted = false,
    bool isRead = false,
  }) => AppNotification(
    notificationId: 912,
    type: type,
    isRead: isRead,
    createdAt: createdAt,
    actor: NotificationActor(
      userId: 'u1',
      nickname: isDeleted ? '탈퇴한 사용자' : '철수',
      isDeleted: isDeleted,
      relation: relation,
    ),
  );

  AppNotification invite(InvitationStatus status, {int meters = 5000}) =>
      AppNotification(
        notificationId: 913,
        type: NotificationType.runningInvited,
        isRead: false,
        createdAt: createdAt,
        actor: const NotificationActor(
          userId: 'u1',
          nickname: '철수',
          isDeleted: false,
          relation: FriendRelation.friend,
        ),
        invitation: NotificationInvitation(
          runningRoomId: 130,
          status: status,
          // KST 19:30. 화면은 벽시계로 되돌려 그린다.
          scheduledStartAt: DateTime.utc(2026, 10, 28, 10, 30).toLocal(),
          targetDistanceMeters: meters,
        ),
      );

  Future<void> pump(WidgetTester tester, AppNotification one) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: NotificationRow(notification: one)),
        ),
      );

  group('문구는 앱이 만든다', () {
    testWidgets('친구 요청', (tester) async {
      await pump(tester, friend(type: NotificationType.friendRequested));

      expect(
        find.text(AppStrings.notificationFriendRequested('철수')),
        findsOneWidget,
      );
    });

    testWidgets('친구 수락', (tester) async {
      await pump(tester, friend(type: NotificationType.friendAccepted));

      expect(
        find.text(AppStrings.notificationFriendAccepted('철수')),
        findsOneWidget,
      );
    });

    testWidgets('러닝 초대는 시각과 거리를 함께 적는다', (tester) async {
      await pump(tester, invite(InvitationStatus.pending));

      expect(
        find.text(AppStrings.notificationRunningInvited('철수')),
        findsOneWidget,
      );
      expect(find.text('19:30 · 5km'), findsOneWidget);
    });

    testWidgets('하프는 소수 자리가 남는다', (tester) async {
      await pump(tester, invite(InvitationStatus.pending, meters: 21098));

      expect(find.text('19:30 · 21.098km'), findsOneWidget);
    });
  });

  group('러닝 초대 버튼', () {
    testWidgets('⚠️ PENDING일 때만 선다', (tester) async {
      await pump(tester, invite(InvitationStatus.pending));

      expect(find.text(AppStrings.notificationAccept), findsOneWidget);
      expect(find.text(AppStrings.notificationDecline), findsOneWidget);
    });

    testWidgets('ACCEPTED는 버튼이 없다', (tester) async {
      await pump(tester, invite(InvitationStatus.accepted));

      expect(find.text(AppStrings.notificationAccept), findsNothing);
    });

    testWidgets('DECLINED는 상태만 알린다', (tester) async {
      await pump(tester, invite(InvitationStatus.declined));

      expect(find.text(AppStrings.notificationAccept), findsNothing);
      expect(find.text(AppStrings.notificationInviteDeclined), findsOneWidget);
    });

    testWidgets('LEFT는 상태만 알린다', (tester) async {
      await pump(tester, invite(InvitationStatus.left));

      expect(find.text(AppStrings.notificationInviteLeft), findsOneWidget);
    });

    testWidgets('⚠️ EXPIRED는 버튼 없이 마감만 알린다', (tester) async {
      await pump(tester, invite(InvitationStatus.expired));

      expect(find.text(AppStrings.notificationAccept), findsNothing);
      expect(find.text(AppStrings.notificationInviteExpired), findsOneWidget);
    });
  });

  group('친구 요청 버튼', () {
    testWidgets('⚠️ 받은 요청이 아직 처리 전일 때만 선다', (tester) async {
      await pump(
        tester,
        friend(
          type: NotificationType.friendRequested,
          relation: FriendRelation.requestReceived,
        ),
      );

      expect(find.text(AppStrings.notificationAccept), findsOneWidget);
    });

    testWidgets('이미 친구가 됐으면 버튼이 없다', (tester) async {
      // 과거에 받은 요청 알림이라도 지금 상태로 그린다.
      await pump(
        tester,
        friend(
          type: NotificationType.friendRequested,
          relation: FriendRelation.friend,
        ),
      );

      expect(find.text(AppStrings.notificationAccept), findsNothing);
    });

    testWidgets('⚠️ 탈퇴한 사람은 친구 버튼을 모두 숨긴다', (tester) async {
      // 관계가 `null`이다. `none`으로 읽으면 없는 사람에게 버튼이 뜬다.
      await pump(
        tester,
        friend(type: NotificationType.friendRequested, isDeleted: true),
      );

      expect(find.text(AppStrings.notificationAccept), findsNothing);
      expect(find.text('탈퇴한 사용자 님이 친구 요청을 보냈어요'), findsOneWidget);
    });

    testWidgets('친구 수락 알림에는 버튼이 없다', (tester) async {
      await pump(
        tester,
        friend(
          type: NotificationType.friendAccepted,
          relation: FriendRelation.friend,
        ),
      );

      expect(find.text(AppStrings.notificationAccept), findsNothing);
    });
  });

  group('안 읽은 표시', () {
    testWidgets('읽은 줄과 안 읽은 줄의 폭이 같다', (tester) async {
      // 점이 들어오고 나갈 때 아바타가 좌우로 흔들리면 목록이 떨린다.
      await pump(tester, friend(type: NotificationType.friendAccepted));
      final unread = tester.getTopLeft(find.byType(Text).first);

      await pump(
        tester,
        friend(type: NotificationType.friendAccepted, isRead: true),
      );
      final read = tester.getTopLeft(find.byType(Text).first);

      expect(read.dx, unread.dx);
    });
  });

  group('누르는 동안 잠근다', () {
    testWidgets('busy면 버튼이 눌리지 않는다', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: NotificationRow(
              notification: invite(InvitationStatus.pending),
              busy: true,
              onAcceptInvite: () => taps++,
            ),
          ),
        ),
      );

      await tester.tap(find.text(AppStrings.notificationAccept));
      await tester.pump();

      expect(taps, 0);
    });
  });
}
