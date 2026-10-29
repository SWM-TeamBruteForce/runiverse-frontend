import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';
import 'package:runiverse/features/notification/data/fake_app_stream.dart';
import 'package:runiverse/features/notification/data/fake_notification_repository.dart';
import 'package:runiverse/features/notification/domain/app_notification.dart';
import 'package:runiverse/features/notification/domain/app_stream.dart';
import 'package:runiverse/features/notification/domain/notification_page_result.dart';
import 'package:runiverse/features/notification/domain/notification_repository.dart';
import 'package:runiverse/features/notification/presentation/notification_provider.dart';

/// 알림 목록과 배지.
///
/// ## ⚠️ 배지가 목록과 어긋나면 사용자는 앱을 믿지 않는다
///
/// 앱 스트림을 먼저 열고 목록을 받는 사이에 알림이 도착한다. 그것을 바로
/// 화면에 넣으면 목록 응답이 같은 알림을 한 번 더 싣고 와서 **두 번 세어진다.**
/// 버퍼에 담아 두고 `notificationId`로 대조하는 것이 그 유일한 해법이다.
void main() {
  final createdAt = DateTime(2026, 10, 28, 12, 10);

  AppNotification friendRequest(int id) => AppNotification(
    notificationId: id,
    type: NotificationType.friendRequested,
    isRead: false,
    createdAt: createdAt,
    actor: NotificationActor(
      userId: 'u-$id',
      nickname: '러너$id',
      isDeleted: false,
      relation: FriendRelation.requestReceived,
    ),
  );

  AppNotification invite(
    int id, {
    int roomId = 130,
    InvitationStatus status = InvitationStatus.pending,
  }) => AppNotification(
    notificationId: id,
    type: NotificationType.runningInvited,
    isRead: false,
    createdAt: createdAt,
    actor: NotificationActor(
      userId: 'u-$id',
      nickname: '러너$id',
      isDeleted: false,
      relation: FriendRelation.friend,
    ),
    invitation: NotificationInvitation(
      runningRoomId: roomId,
      status: status,
      scheduledStartAt: DateTime(2026, 10, 28, 19, 30),
      targetDistanceMeters: 7000,
    ),
  );

  NotificationPageResult page(
    List<AppNotification> items, {
    int unreadCount = 0,
    String? nextCursor,
  }) => NotificationPageResult(
    items: items,
    unreadCount: unreadCount,
    nextCursor: nextCursor,
  );

  ({
    ProviderContainer container,
    FakeAppStream stream,
    FakeNotificationRepository repo,
  })
  build() {
    final stream = FakeAppStream();
    final repo = FakeNotificationRepository();
    final container = ProviderContainer(
      overrides: [
        appStreamProvider.overrideWithValue(stream),
        notificationRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, stream: stream, repo: repo);
  }

  NotificationState read(ProviderContainer c) => c.read(notificationProvider);

  group('앱 시작 순서', () {
    test('⚠️ 스트림을 먼저 열고 그다음 목록을 받는다', () async {
      // 목록을 먼저 받으면 그사이 생긴 알림을 실시간으로도 못 받고 목록에도
      // 없다 — 영영 사라진다.
      final app = build();
      app.repo.pages[null] = page([friendRequest(912)], unreadCount: 1);

      await app.container.read(notificationProvider.notifier).start();

      expect(app.stream.connects, 1);
      expect(app.repo.listCalls, 1);
      expect(read(app.container).items, hasLength(1));
      expect(read(app.container).unreadCount, 1);
    });
  });

  group('버퍼와 병합', () {
    test('목록 응답 전에 온 알림은 버퍼에 담겼다가 맨 위에 붙는다', () async {
      final app = build();
      app.repo.pages[null] = page([friendRequest(912)], unreadCount: 1);
      app.repo.defer = true;

      final started = app.container.read(notificationProvider.notifier).start();
      await Future<void>.delayed(Duration.zero);

      // 목록을 기다리는 동안 새 알림이 왔다.
      app.stream.emit(invite(913));
      await Future<void>.delayed(Duration.zero);
      // 아직 화면에 넣지 않는다.
      expect(read(app.container).items, isEmpty);

      app.repo.release();
      await started;

      expect(read(app.container).items.map((n) => n.notificationId), [
        913,
        912,
      ]);
      // 목록의 1 + 버퍼에서 새로 더한 1.
      expect(read(app.container).unreadCount, 2);
    });

    test('⚠️ 목록에 이미 있는 알림은 배지에 다시 더하지 않는다', () async {
      final app = build();
      app.repo.pages[null] = page([friendRequest(912)], unreadCount: 1);
      app.repo.defer = true;

      final started = app.container.read(notificationProvider.notifier).start();
      await Future<void>.delayed(Duration.zero);

      // 목록이 싣고 올 그 알림이 이벤트로도 왔다.
      app.stream.emit(friendRequest(912));
      await Future<void>.delayed(Duration.zero);

      app.repo.release();
      await started;

      expect(read(app.container).items, hasLength(1));
      expect(read(app.container).unreadCount, 1);
    });

    test('버퍼 안에서도 같은 id는 하나만 남는다', () async {
      final app = build();
      app.repo.pages[null] = page([], unreadCount: 0);
      app.repo.defer = true;

      final started = app.container.read(notificationProvider.notifier).start();
      await Future<void>.delayed(Duration.zero);

      app.stream.emit(invite(913));
      app.stream.emit(invite(913));
      await Future<void>.delayed(Duration.zero);

      app.repo.release();
      await started;

      expect(read(app.container).items, hasLength(1));
      expect(read(app.container).unreadCount, 1);
    });

    test('실시간 모드에서 같은 알림이 두 번 와도 한 번만 반영된다', () async {
      final app = build();
      app.repo.pages[null] = page([], unreadCount: 0);
      await app.container.read(notificationProvider.notifier).start();

      app.stream.emit(invite(913));
      await Future<void>.delayed(Duration.zero);
      app.stream.emit(invite(913));
      await Future<void>.delayed(Duration.zero);

      expect(read(app.container).items, hasLength(1));
      expect(read(app.container).unreadCount, 1);
    });

    test('⚠️ 목록 조회가 실패해도 버퍼를 지우지 않는다', () async {
      // 지우면 그동안 받은 알림이 사라진다.
      final app = build();
      app.repo.pages[null] = page([friendRequest(912)], unreadCount: 1);
      app.repo.listFailure = NotificationFailure.network;

      await app.container.read(notificationProvider.notifier).start();
      app.stream.emit(invite(913));
      await Future<void>.delayed(Duration.zero);

      expect(read(app.container).failure, NotificationFailure.network);

      // 재시도에서 합쳐진다.
      await app.container.read(notificationProvider.notifier).refresh();

      expect(read(app.container).items.map((n) => n.notificationId), [
        913,
        912,
      ]);
      expect(read(app.container).failure, isNull);
    });
  });

  group('재조회', () {
    test('⚠️ 첫 페이지부터 다시 받고 뒤쪽 페이지와 커서를 버린다', () async {
      final app = build();
      app.repo.pages[null] = page(
        [friendRequest(1)],
        unreadCount: 1,
        nextCursor: 'c2',
      );
      app.repo.pages['c2'] = page([friendRequest(2)]);

      final notifier = app.container.read(notificationProvider.notifier);
      await notifier.start();
      await notifier.loadMore();
      expect(read(app.container).items, hasLength(2));

      // 포그라운드 복귀. 첫 페이지가 달라졌다.
      app.repo.pages[null] = page(
        [friendRequest(3)],
        unreadCount: 1,
        nextCursor: 'c9',
      );
      await notifier.refresh();

      expect(read(app.container).items.map((n) => n.notificationId), [3]);
      expect(read(app.container).nextCursor, 'c9');
      expect(app.repo.cursors.last, isNull);
    });

    test('⚠️ items가 비어도 nextCursor가 있으면 더 받는다', () async {
      // 서버가 깨진 행을 건너뛴다. 개수로 끝을 판단하면 목록이 중간에 끊긴다.
      final app = build();
      app.repo.pages[null] = page([], nextCursor: 'c2');
      app.repo.pages['c2'] = page([friendRequest(5)]);

      final notifier = app.container.read(notificationProvider.notifier);
      await notifier.start();
      await notifier.loadMore();

      expect(read(app.container).items.map((n) => n.notificationId), [5]);
      expect(read(app.container).nextCursor, isNull);
    });

    test('nextCursor가 null이면 더 받지 않는다', () async {
      final app = build();
      app.repo.pages[null] = page([friendRequest(1)]);

      final notifier = app.container.read(notificationProvider.notifier);
      await notifier.start();
      final before = app.repo.listCalls;
      await notifier.loadMore();

      expect(app.repo.listCalls, before);
    });
  });

  group('같은 방의 알림을 함께 갱신한다', () {
    test('⚠️ 받아 둔 모든 페이지를 훑는다', () async {
      // A와 C가 각각 나를 같은 방에 초대하면 알림은 둘이고 actor도 다르지만
      // 초대는 하나다. 첫 페이지만 고치면 스크롤하면 낡은 버튼이 나온다.
      final app = build();
      app.repo.pages[null] = page([invite(913, roomId: 130)], nextCursor: 'c2');
      app.repo.pages['c2'] = page([
        invite(900, roomId: 130),
        invite(800, roomId: 999),
      ]);

      final notifier = app.container.read(notificationProvider.notifier);
      await notifier.start();
      await notifier.loadMore();

      notifier.updateRoom(130, InvitationStatus.accepted);

      final items = read(app.container).items;
      expect(
        items
            .where((n) => n.invitation?.runningRoomId == 130)
            .every((n) => n.invitation!.status == InvitationStatus.accepted),
        isTrue,
      );
      // 다른 방은 건드리지 않는다.
      expect(
        items
            .firstWhere((n) => n.invitation?.runningRoomId == 999)
            .invitation!
            .status,
        InvitationStatus.pending,
      );
    });
  });

  group('모두 읽음', () {
    test('⚠️ 성공하면 배지는 0이고 안 읽은 강조는 남는다', () async {
      // 의도된 동작이다 — 화면은 조회 당시 안 읽은 것을 강조하고, 서버의
      // 읽음 결과는 배지에만 반영한다.
      final app = build();
      app.repo.pages[null] = page([
        friendRequest(1),
        friendRequest(2),
      ], unreadCount: 2);

      final notifier = app.container.read(notificationProvider.notifier);
      await notifier.start();
      await notifier.markAllRead();

      expect(read(app.container).unreadCount, 0);
      expect(read(app.container).items.where((n) => !n.isRead), hasLength(2));
    });

    test('실패하면 배지를 내리지 않는다', () async {
      final app = build();
      app.repo.pages[null] = page([friendRequest(1)], unreadCount: 1);
      final notifier = app.container.read(notificationProvider.notifier);
      await notifier.start();

      app.repo.readAllFailure = NotificationFailure.network;
      await notifier.markAllRead();

      expect(read(app.container).unreadCount, 1);
    });

    test('모두 읽음 뒤에 온 알림은 배지를 다시 올린다', () async {
      final app = build();
      app.repo.pages[null] = page([], unreadCount: 0);
      final notifier = app.container.read(notificationProvider.notifier);
      await notifier.start();
      await notifier.markAllRead();

      app.stream.emit(invite(913));
      await Future<void>.delayed(Duration.zero);

      expect(read(app.container).unreadCount, 1);
    });
  });

  group('배지는 숫자가 아니라 있다/없다로 쓴다', () {
    test('안 읽은 것이 있으면 참이다', () async {
      final app = build();
      app.repo.pages[null] = page([friendRequest(1)], unreadCount: 1);
      await app.container.read(notificationProvider.notifier).start();

      expect(app.container.read(hasUnreadProvider), isTrue);
    });

    test('없으면 거짓이다', () async {
      final app = build();
      app.repo.pages[null] = page([], unreadCount: 0);
      await app.container.read(notificationProvider.notifier).start();

      expect(app.container.read(hasUnreadProvider), isFalse);
    });
  });

  group('끊기면 다시 붙는다', () {
    test('⚠️ 끊김을 받으면 재연결을 예약한다', () async {
      final app = build();
      app.repo.pages[null] = page([], unreadCount: 0);
      await app.container.read(notificationProvider.notifier).start();

      app.stream.breakConnection();
      await Future<void>.delayed(Duration.zero);

      expect(read(app.container).connected, isFalse);
    });

    test('업데이트가 필요하면 재연결하지 않는다', () async {
      // 구버전 앱이다. 다시 붙어도 같은 403이고, 화면이 업데이트를 안내한다.
      final app = build();
      app.repo.pages[null] = page([], unreadCount: 0);
      await app.container.read(notificationProvider.notifier).start();

      app.stream.breakConnection(
        const AppStreamException(AppStreamFailure.updateRequired),
      );
      await Future<void>.delayed(Duration.zero);

      expect(read(app.container).updateRequired, isTrue);
    });
  });
}
