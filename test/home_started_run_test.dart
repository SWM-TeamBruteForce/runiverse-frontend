import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/app_update/data/fake_app_version_repository.dart';
import 'package:runiverse/features/app_update/presentation/app_version_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/matching/data/fake_match_repository.dart';
import 'package:runiverse/features/notification/data/fake_app_stream.dart';
import 'package:runiverse/features/notification/data/fake_notification_repository.dart';
import 'package:runiverse/features/notification/domain/push_messaging.dart';
import 'package:runiverse/features/notification/presentation/notification_provider.dart';
import 'package:runiverse/features/notification/presentation/push_provider.dart';
import 'package:runiverse/features/profile/presentation/user_profile_page.dart';
import 'package:runiverse/features/matching/presentation/match_register_provider.dart';
import 'package:runiverse/features/session/data/fake_location_repository.dart';
import 'package:runiverse/features/session/data/fake_step_repository.dart';
import 'package:runiverse/features/session/data/fake_track_repository.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/domain/finish_outcome.dart';
import 'package:runiverse/features/session/domain/run_numbers.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
import 'package:runiverse/features/session/domain/run_snapshot.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/domain/user_status_repository.dart';
import 'package:runiverse/features/session/presentation/run_session_page.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 홈의 **"러닝 화면으로 가기"** — 들어가기 전에 상태를 다시 읽는가.
///
/// 히어로가 들고 있는 방은 마지막으로 읽은 상태에서 나온 것이다. 그사이에
/// 러닝이 끝났으면 **이미 끝난 방**으로 들어가려 하고 서버가
/// `NOT_ROOM_PLAYER`로 거절한다(2026-09-19 00:44 실주행).
void main() {
  final startAt = DateTime(2026, 9, 19, 0, 40);

  late FakeUserStatusRepository status;
  late _CountingChannel channel;
  late _TapPushes pushes;

  UserStatusRunning running({int room = 29}) => UserStatusRunning(
    runningRoomId: room,
    type: RoomType.match,
    scheduledStartAt: startAt,
    targetDistanceMeters: 3000,
  );

  Future<ProviderContainer> pumpHome(WidgetTester tester) async {
    status = FakeUserStatusRepository(status: running());
    channel = _CountingChannel();
    pushes = _TapPushes();

    final tokens = InMemoryTokenStore();
    await tokens.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );

    final container = ProviderContainer.test(
      overrides: [
        // 스플래시가 **토큰 복원보다 먼저** 앱 버전을 확인한다. 진짜를 두면
        // dio가 서버 주소를 찾다 죽고, 판정을 못 받은 화면은 넘어가지 않는다.
        appVersionRepositoryProvider.overrideWithValue(
          FakeAppVersionRepository(),
        ),
        tokenStoreProvider.overrideWithValue(tokens),
        matchRepositoryProvider.overrideWithValue(FakeMatchRepository()),
        // ⚠️ **셸이 앱 스트림을 연다**(알림). 가짜를 안 끼우면 진짜가 붙으려
        // 하고, 실패 후 백오프 타이머가 남아 `pumpAndSettle`이 영영 안 끝난다.
        appStreamProvider.overrideWithValue(FakeAppStream()),
        notificationRepositoryProvider.overrideWithValue(
          FakeNotificationRepository(),
        ),
        userStatusRepositoryProvider.overrideWithValue(status),
        locationRepositoryProvider.overrideWithValue(FakeLocationRepository()),
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
        stepRepositoryProvider.overrideWithValue(FakeStepRepository()),
        runningChannelFactoryProvider.overrideWithValue((_) => channel),
        pushMessagingProvider.overrideWithValue(pushes),
        // ⚠️ 로그인 상태가 아니면 셸이 유저 상태를 **묻지도 않는다**
        // (`AppShell._refreshStatus`). 그러면 히어로가 기본 화면으로 떨어져
        // 이 테스트가 무의미해진다.
        authControllerProvider.overrideWith(
          () => _SignedIn(const AuthSignedIn('u-1', isOnboarded: true)),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const RuniverseApp(initialLocation: AppRoutes.home),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// 들어간 러닝을 정리한다.
  ///
  /// ⚠️ **위젯만 걷어내면 안 된다.** 컨테이너를 테스트가 들고 있어
  /// `UncontrolledProviderScope`가 버리지 않는다 — `TrackSender`의 10초
  /// 타이머가 그대로 돌고, 그것 하나로 flutter_test가 죽는다.
  Future<void> leave(WidgetTester tester, ProviderContainer container) async {
    container.read(runSessionControllerProvider.notifier).reset();
    await container.read(runningConnectionProvider.notifier).close();
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('달리는 중이면 들어가는 문이 보인다', (tester) async {
    await pumpHome(tester);

    expect(find.text(AppStrings.homeRunStarted), findsOneWidget);
    expect(find.text(AppStrings.homeRunToSession), findsOneWidget);
  });

  testWidgets('⚠️ 방금 끝낸 방은 문을 내놓지 않는다', (tester) async {
    // 종료 확인을 받은 뒤에도 서버 상태가 잠시 `RUNNING`을 돌려준다. 그 값만
    // 믿으면 "러닝 화면으로 가기"가 뜨고 눌러도 `NOT_ROOM_PLAYER`만 받는다.
    final container = await pumpHome(tester);
    expect(find.text(AppStrings.homeRunToSession), findsOneWidget);

    // 그 방을 끝낸다. 상태는 여전히 RUNNING이라고 답한다.
    final connection = container.read(runningConnectionProvider.notifier);
    await connection.reopen(29);
    await connection.finish();
    await tester.pumpAndSettle();

    expect(
      container.read(runningConnectionProvider).finishedRoomId,
      29,
      reason: '끝냈다는 사실을 기억해야 한다',
    );
    expect(find.text(AppStrings.homeRunToSession), findsNothing);
    await leave(tester, container);
  });

  testWidgets('⚠️ 다른 방이면 문이 그대로 있다', (tester) async {
    // 끝낸 방만 가린다. 새로 배정된 방까지 가리면 들어갈 길이 사라진다.
    final container = await pumpHome(tester);

    final connection = container.read(runningConnectionProvider.notifier);
    await connection.reopen(99);
    await connection.finish();
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.homeRunToSession), findsOneWidget);
    await leave(tester, container);
  });

  testWidgets('⚠️ 들어가기 전에 상태를 다시 읽는다', (tester) async {
    final container = await pumpHome(tester);
    final before = status.calls;

    await tester.tap(find.text(AppStrings.homeRunToSession));
    await tester.pumpAndSettle();

    expect(status.calls, greaterThan(before), reason: '낡은 값을 믿으면 안 된다');
    expect(container.read(runningConnectionProvider).room?.id, 29);
    await leave(tester, container);
  });

  testWidgets('⚠️ 그사이 러닝이 끝났으면 들어가지 않는다', (tester) async {
    // 이것이 없으면 이미 끝난 방에 `RUNNING_START`를 보내고 서버가
    // `NOT_ROOM_PLAYER`로 거절한다.
    final container = await pumpHome(tester);
    status.status = const UserStatusIdle();

    await tester.tap(find.text(AppStrings.homeRunToSession));
    await tester.pumpAndSettle();

    expect(container.read(runningConnectionProvider).room, isNull);
    expect(channel.starts, 0, reason: '끝난 방에 시작을 보내면 안 된다');
    // 히어로가 새 상태로 다시 그려진다.
    expect(find.text(AppStrings.homeRunStarted), findsNothing);
    expect(find.text(AppStrings.homeMatchCta), findsOneWidget);
  });

  testWidgets('⚠️ 그사이 다른 방이면 새 방으로 들어간다', (tester) async {
    // 방 번호까지 새로 읽은 값을 쓴다. 화면이 들고 있던 번호는 낡았다.
    final container = await pumpHome(tester);
    status.status = running(room: 31);

    await tester.tap(find.text(AppStrings.homeRunToSession));
    await tester.pumpAndSettle();

    expect(container.read(runningConnectionProvider).room?.id, 31);
    await leave(tester, container);
  });

  testWidgets('⚠️ 상태를 못 읽으면 그래도 들어간다', (tester) async {
    // 판정에 실패했다고 막으면 신호가 나쁜 곳에서 자기 러닝으로 못 돌아간다.
    // 틀렸을 때의 값은 `NOT_ROOM_PLAYER` 한 번이고 그 길은 안내와 함께 홈으로
    // 돌아온다.
    final container = await pumpHome(tester);
    status.failure = UserStatusFailure.network;

    await tester.tap(find.text(AppStrings.homeRunToSession));
    await tester.pumpAndSettle();

    expect(container.read(runningConnectionProvider).room?.id, 29);
    await leave(tester, container);
  });

  testWidgets('⚠️ 달리는 중에 누른 푸시는 러닝 화면을 가리지 않는다', (tester) async {
    // 홈에서 들어간 러닝은 셸 위에 얹혀 셸이 살아 있다. 그대로 두면 친구
    // 프로필이 러닝 화면 위로 열린다. 알림함에는 남아 있다.
    final container = await pumpHome(tester);
    await tester.tap(find.text(AppStrings.homeRunToSession));
    await tester.pumpAndSettle();
    expect(find.byType(RunSessionPage), findsOneWidget);

    pushes.taps.add(
      const OpenedPush(
        messageId: 'm-1',
        data: {'type': 'FRIEND_REQUESTED', 'actorId': 'u-9'},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(UserProfilePage), findsNothing);
    expect(find.byType(RunSessionPage), findsOneWidget);
    await leave(tester, container);
  });
}

/// 눌린 푸시만 흘려보낸다. 토큰이 없어 기기 등록은 하지 않는다
/// ([NoopPushMessaging]과 같다).
class _TapPushes extends NoopPushMessaging {
  final taps = StreamController<OpenedPush>.broadcast();

  @override
  Stream<OpenedPush> get opened => taps.stream;
}

/// 로그인 상태를 고정한다. `signIn()`으로 만들면 가짜 시간 위에서 멈춘다.
class _SignedIn extends AuthController {
  _SignedIn(this.initial);

  final AuthState initial;

  @override
  AuthState build() => initial;
}

/// `RUNNING_START`가 몇 번 나갔는지 센다.
class _CountingChannel implements RunningChannel {
  var starts = 0;

  @override
  Stream<WsConnectionState> get states => const Stream.empty();

  @override
  WsConnectionState get state => WsConnectionState.connected;

  @override
  Stream<WsErrorCode> get errors => const Stream.empty();

  @override
  Stream<RunProgress> get progress => const Stream.empty();

  @override
  Stream<RunCombo> get combos => const Stream.empty();

  @override
  Stream<void> get finished => const Stream.empty();

  @override
  Stream<RunSnapshot> get snapshots => const Stream.empty();

  @override
  Stream<RunNumbers> get serverNumbers => const Stream.empty();

  @override
  Future<void> start(int runningRoomId) async {
    starts++;
  }

  @override
  bool sendLocations(List<TrackPoint> points) => true;

  @override
  bool pause() => true;

  @override
  bool resume() => true;

  @override
  Future<FinishOutcome> finish({bool forced = false}) async =>
      const FinishConfirmed();

  @override
  Future<void> close() async {}
}
