import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/home/domain/home_notice.dart';
import 'package:runiverse/features/home/presentation/home_notice_provider.dart';
import 'package:runiverse/features/notification/data/fake_app_stream.dart';
import 'package:runiverse/features/notification/data/fake_notification_repository.dart';
import 'package:runiverse/features/notification/domain/app_stream.dart';
import 'package:runiverse/features/notification/domain/notification_page_result.dart';
import 'package:runiverse/features/notification/presentation/notification_provider.dart';

/// 앱 스트림으로 온 홈 공지를 홈이 받는다.
///
/// ## ⚠️ 90초 동안 새 값이 없으면 내린다 — 이벤트마다 따로
///
/// 대기 수는 10초, 띠는 30초마다 온다. 대기 수가 계속 와도 띠 값이 끊겼으면
/// 띠는 내려야 한다.
///
/// 90초 타이머가 남은 채 테스트가 끝나면 `testWidgets`가 실패로 본다.
/// `addTearDown`은 그 검사 뒤에 돌아서, 테스트 끝에서 직접 버린다.
void main() {
  const activity = HomeActivity(
    runningNowCount: 3,
    todayFinishedRuns: [],
    todayFinishedCount: 20,
    yesterdayFinishedCount: 12,
  );

  ({
    ProviderContainer container,
    FakeAppStream stream,
    FakeNotificationRepository repo,
  })
  build() {
    final stream = FakeAppStream();
    final repo = FakeNotificationRepository()
      ..pages[null] = const NotificationPageResult.empty();
    final container = ProviderContainer(
      overrides: [
        appStreamProvider.overrideWithValue(stream),
        notificationRepositoryProvider.overrideWithValue(repo),
      ],
    );
    return (container: container, stream: stream, repo: repo);
  }

  HomeNoticeState read(ProviderContainer c) => c.read(homeNoticeProvider);

  testWidgets('앱 스트림의 두 값을 홈으로 넘긴다', (tester) async {
    final app = build();
    await app.container.read(notificationProvider.notifier).start();

    app.stream
      ..emitEvent(const HomeWaitingArrived(4))
      ..emitEvent(const HomeActivityArrived(activity));
    await tester.pump();

    expect(read(app.container).waitingCount, 4);
    expect(read(app.container).activity?.todayFinishedCount, 20);
    app.container.dispose();
  });

  testWidgets('⚠️ 알림 목록을 기다리는 동안에도 바로 넘긴다', (tester) async {
    // 알림은 목록과 맞춰 보려고 버퍼에 담지만, 홈 공지는 맞춰 볼 것이 없다.
    final app = build();
    app.repo.defer = true;
    final starting = app.container.read(notificationProvider.notifier).start();

    app.stream.emitEvent(const HomeWaitingArrived(4));
    await tester.pump();

    expect(read(app.container).waitingCount, 4);
    app.repo.release();
    await starting;
    app.container.dispose();
  });

  testWidgets('90초 동안 새 값이 없으면 내린다', (tester) async {
    final app = build();
    app.container.read(homeNoticeProvider.notifier).receiveWaiting(4);

    await tester.pump(const Duration(seconds: 89));
    expect(read(app.container).waitingCount, 4);

    await tester.pump(const Duration(seconds: 1));
    expect(read(app.container).waitingCount, isNull);
    app.container.dispose();
  });

  testWidgets('새 값이 오면 90초를 처음부터 다시 센다', (tester) async {
    final app = build();
    final notice = app.container.read(homeNoticeProvider.notifier)
      ..receiveWaiting(4);

    await tester.pump(const Duration(seconds: 60));
    notice.receiveWaiting(5);
    await tester.pump(const Duration(seconds: 60));

    expect(read(app.container).waitingCount, 5);
    app.container.dispose();
  });

  testWidgets('⚠️ 이벤트마다 따로 센다', (tester) async {
    final app = build();
    final notice = app.container.read(homeNoticeProvider.notifier)
      ..receiveActivity(activity)
      ..receiveWaiting(4);

    // 대기 수만 10초마다 온다. 띠 값은 처음 한 번뿐이다.
    for (var i = 0; i < 9; i++) {
      await tester.pump(const Duration(seconds: 10));
      notice.receiveWaiting(4);
    }

    expect(read(app.container).waitingCount, 4);
    expect(read(app.container).activity, isNull);
    app.container.dispose();
  });

  testWidgets('로그아웃하면 바로 내린다', (tester) async {
    final app = build();
    app.container.read(homeNoticeProvider.notifier)
      ..receiveWaiting(4)
      ..receiveActivity(activity);

    await app.container.read(notificationProvider.notifier).signOut();

    expect(read(app.container).waitingCount, isNull);
    expect(read(app.container).activity, isNull);
    app.container.dispose();
  });
}
