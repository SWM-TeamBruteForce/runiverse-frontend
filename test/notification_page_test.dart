import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';
import 'package:runiverse/features/matching/data/fake_match_repository.dart';
import 'package:runiverse/features/matching/domain/invite_failure.dart';
import 'package:runiverse/features/matching/presentation/match_register_provider.dart';
import 'package:runiverse/features/notification/data/fake_app_stream.dart';
import 'package:runiverse/features/notification/data/fake_notification_repository.dart';
import 'package:runiverse/features/notification/domain/app_notification.dart';
import 'package:runiverse/features/notification/domain/notification_page_result.dart';
import 'package:runiverse/features/notification/presentation/notification_page.dart';
import 'package:runiverse/features/notification/presentation/notification_provider.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/notification/domain/notification_repository.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 알림함 화면.
///
/// ## ⚠️ 열면 목록 → 모두 읽음 순서다
///
/// 바꾸면 목록 응답에서 안 읽은 표시가 사라져 **새 알림을 강조할 수 없다.**
void main() {
  final createdAt = DateTime(2026, 10, 28, 12, 10);

  AppNotification invite(
    int id, {
    int roomId = 130,
    InvitationStatus status = InvitationStatus.pending,
  }) => AppNotification(
    notificationId: id,
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
      runningRoomId: roomId,
      status: status,
      scheduledStartAt: DateTime.utc(2026, 10, 28, 10, 30).toLocal(),
      targetDistanceMeters: 5000,
    ),
  );

  ({
    FakeNotificationRepository repo,
    FakeMatchRepository matches,
    FakeAppStream stream,
  })
  fakes() => (
    repo: FakeNotificationRepository(),
    matches: FakeMatchRepository(),
    stream: FakeAppStream(),
  );

  /// 줄을 누르면 라우트를 미는 화면이라 `GoRouter`가 있어야 한다.
  /// 목적지는 눌렸는지만 보면 되므로 빈 화면이다.
  Future<void> pump(
    WidgetTester tester, {
    required FakeNotificationRepository repo,
    required FakeMatchRepository matches,
    required FakeAppStream stream,
  }) async {
    Widget stub(String name) => Scaffold(body: Text('→ $name'));

    final router = GoRouter(
      initialLocation: AppRoutes.notifications,
      routes: [
        GoRoute(
          path: AppRoutes.notifications,
          builder: (_, _) => const NotificationPage(),
        ),
        GoRoute(path: AppRoutes.matchRoom, builder: (_, _) => stub('방')),
        GoRoute(path: AppRoutes.userProfile, builder: (_, _) => stub('프로필')),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(repo),
          appStreamProvider.overrideWithValue(stream),
          matchRepositoryProvider.overrideWithValue(matches),
          userStatusRepositoryProvider.overrideWithValue(
            FakeUserStatusRepository(),
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('열 때', () {
    testWidgets('⚠️ 목록을 받은 뒤에 모두 읽음을 부른다', (tester) async {
      final f = fakes();
      f.repo.pages[null] = NotificationPageResult(
        items: [invite(913)],
        unreadCount: 1,
      );

      await pump(tester, repo: f.repo, matches: f.matches, stream: f.stream);

      expect(f.repo.callOrder, ['list', 'readAll']);
    });

    testWidgets('안 읽은 것이 없으면 모두 읽음을 부르지 않는다', (tester) async {
      final f = fakes();
      f.repo.pages[null] = const NotificationPageResult.empty();

      await pump(tester, repo: f.repo, matches: f.matches, stream: f.stream);

      expect(f.repo.readAllCalls, 0);
    });

    testWidgets('⚠️ 못 받았으면 빈 상태가 아니라 실패를 말한다', (tester) async {
      // 알림이 쌓인 사람에게 "아직 알림이 없어요"라고 하면 안 된다.
      final f = fakes();
      f.repo.listFailure = NotificationFailure.network;

      await pump(tester, repo: f.repo, matches: f.matches, stream: f.stream);

      expect(find.text(AppStrings.notificationLoadFailed), findsOneWidget);
      expect(find.text(AppStrings.notificationEmpty), findsNothing);
    });

    testWidgets('정말 없으면 빈 상태를 그린다', (tester) async {
      final f = fakes();
      f.repo.pages[null] = const NotificationPageResult.empty();

      await pump(tester, repo: f.repo, matches: f.matches, stream: f.stream);

      expect(find.text(AppStrings.notificationEmpty), findsOneWidget);
    });
  });

  group('러닝 초대에 답한다', () {
    testWidgets('수락하면 상태를 다시 읽는다', (tester) async {
      final f = fakes();
      f.repo.pages[null] = NotificationPageResult(
        items: [invite(913)],
        unreadCount: 1,
      );
      await pump(tester, repo: f.repo, matches: f.matches, stream: f.stream);

      await tester.tap(find.text(AppStrings.notificationAccept));
      await tester.pumpAndSettle();

      expect(f.matches.acceptCalls, [130]);
    });

    testWidgets('거절하면 그 방의 알림 상태가 바뀐다', (tester) async {
      final f = fakes();
      f.repo.pages[null] = NotificationPageResult(
        items: [invite(913), invite(900)],
        unreadCount: 2,
      );
      await pump(tester, repo: f.repo, matches: f.matches, stream: f.stream);

      await tester.tap(find.text(AppStrings.notificationDecline).first);
      await tester.pumpAndSettle();

      expect(f.matches.declineCalls, [130]);
      // 같은 방의 알림 둘 다 버튼이 사라진다.
      expect(find.text(AppStrings.notificationAccept), findsNothing);
      expect(
        find.text(AppStrings.notificationInviteDeclined),
        findsNWidgets(2),
      );
    });

    testWidgets('⚠️ 꽉 찬 방은 버튼을 남긴다', (tester) async {
      // 초대가 PENDING으로 남아 자리가 생기면 다시 누를 수 있다.
      final f = fakes();
      f.repo.pages[null] = NotificationPageResult(
        items: [invite(913)],
        unreadCount: 1,
      );
      f.matches.acceptFailure = const InviteException(InviteFailure.roomFull);
      await pump(tester, repo: f.repo, matches: f.matches, stream: f.stream);
      final before = f.repo.listCalls;

      await tester.tap(find.text(AppStrings.notificationAccept));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.notificationAccept), findsOneWidget);
      // 목록을 다시 읽지 않는다 — 상태가 그대로다.
      expect(f.repo.listCalls, before);
    });

    testWidgets('⚠️ 이미 처리된 초대면 목록을 다시 읽는다', (tester) async {
      final f = fakes();
      f.repo.pages[null] = NotificationPageResult(
        items: [invite(913)],
        unreadCount: 1,
      );
      f.matches.acceptFailure = const InviteException(InviteFailure.notPending);
      await pump(tester, repo: f.repo, matches: f.matches, stream: f.stream);
      final before = f.repo.listCalls;

      await tester.tap(find.text(AppStrings.notificationAccept));
      await tester.pumpAndSettle();

      expect(f.repo.listCalls, greaterThan(before));
    });

    testWidgets('⚠️ 서버 문구를 그대로 보여준다', (tester) async {
      final f = fakes();
      f.repo.pages[null] = NotificationPageResult(
        items: [invite(913)],
        unreadCount: 1,
      );
      f.matches.acceptFailure = const InviteException(
        InviteFailure.closed,
        message: '모집이 마감되어 참여할 수 없습니다.',
      );
      await pump(tester, repo: f.repo, matches: f.matches, stream: f.stream);

      await tester.tap(find.text(AppStrings.notificationAccept));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('모집이 마감되어 참여할 수 없습니다.'), findsOneWidget);
    });
  });
}
