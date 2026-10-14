import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/core/storage/body_profile_provider.dart';
import 'package:runiverse/core/storage/body_profile_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/session/data/fake_location_repository.dart';
import 'package:runiverse/features/session/data/fake_step_repository.dart';
import 'package:runiverse/features/session/data/fake_track_repository.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/domain/run_snapshot.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';
import 'package:runiverse/features/session/domain/finish_outcome.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/session/presentation/run_session_page.dart';

/// 목표에 닿았을 때 **누가 끝내는가.**
///
/// ## ⚠️ 1.1.0 에서 주인이 바뀌었다
///
/// 예전에는 앱이 잰 거리가 목표를 넘으면 **앱이** `RUNNING_FINISH` 를 보냈다.
/// 이제는 **서버**가 끝낸다(가이드 3.1) — 서버는 정지 구간과 오염 좌표를 뺀
/// 확정 거리로 판단하므로, **앱 기준으로 넘었어도 아직 모자랄 수 있다.**
///
/// 그래서 둘을 함께 봐야 한다. 앱이 안 보내는 것만 확인하고 끝내면, 서버가
/// 보낸 종료를 받을 길이 없어 **러닝이 끝났는데 화면이 영영 남는다.**
void main() {
  const target = 200;

  late _FinishChannel channel;
  late FakeLocationRepository location;
  late DateTime clock;

  Future<ProviderContainer> makeContainer() async {
    clock = DateTime(2026, 9, 19, 7);
    channel = _FinishChannel();
    location = FakeLocationRepository();

    final tokens = InMemoryTokenStore();
    await tokens.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );

    return ProviderContainer.test(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        locationRepositoryProvider.overrideWithValue(location),
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
        bodyProfileStoreProvider.overrideWithValue(InMemoryBodyProfileStore()),
        stepRepositoryProvider.overrideWithValue(FakeStepRepository()),
        userStatusRepositoryProvider.overrideWithValue(
          FakeUserStatusRepository(),
        ),
        runningChannelFactoryProvider.overrideWithValue((_) => channel),
      ],
    );
  }

  /// 좌표 하나. 북쪽으로 [meters]만큼 간 자리다.
  GeoPoint north(double meters) {
    clock = clock.add(const Duration(seconds: 10));
    return GeoPoint(
      latitude: 37.4979 + meters / 111320,
      longitude: 127.0276,
      recordedAt: clock,
      accuracy: 5,
    );
  }

  /// 좌표를 흘리고 화면까지 반영시킨다. 스트림이 컨트롤러에 닿는 데 한 번,
  /// 다시 그리는 데 한 번이 필요하다.
  Future<void> emit(WidgetTester tester, GeoPoint p) async {
    location.emit(p);
    await tester.pump();
    await tester.pump();
  }

  /// 세션이 아는 거리. **끝난 뒤에도 읽어야 한다** — 목표에 닿으면 상태가
  /// `RunFinished`로 넘어가므로, 달리는 중만 보면 0이 나온다.
  int distanceOf(ProviderContainer container) =>
      switch (container.read(runSessionControllerProvider)) {
        RunRunning(:final metrics) ||
        RunPaused(:final metrics) ||
        RunFinished(:final metrics) => metrics.distanceMeters.round(),
        _ => 0,
      };

  /// 목표가 있는 매칭 방에서 달리는 화면을 세운다.
  Future<ProviderContainer> pumpRunning(
    WidgetTester tester, {
    int? targetMeters = target,
  }) async {
    final container = await makeContainer();
    addTearDown(container.dispose);

    await container
        .read(runningConnectionProvider.notifier)
        .openMatched(1, targetDistanceMeters: targetMeters);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const RuniverseApp(initialLocation: AppRoutes.runSession),
      ),
    );
    await tester.pump();

    final session = container.read(runSessionControllerProvider.notifier);
    await session.prepare();
    await emit(tester, north(0));
    session.start();
    await tester.pump();

    return container;
  }

  /// 종료가 채널까지 닿기를 기다린다.
  ///
  /// ⚠️ `RunningConnectionController.finish`는 **남은 좌표를 먼저 보내고**
  /// 채널을 부른다(`drain` → `RUNNING_FINISH`). 둘 다 비동기라 프레임 두 번으로는
  /// 아직 안 닿는다.
  Future<void> settleFinish(WidgetTester tester) async {
    // `drain`이 배치 사이에 300ms를 쉬므로 여러 박자가 필요하다.
    for (var i = 0; i < 12 && channel.finishes.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  /// 달리는 중에 끝내면 1초 타이머가 남아 flutter_test가 죽는다.
  ///
  /// ⚠️ **위젯만 걷어내는 것으로는 부족하다.** 컨테이너를 테스트가 들고 있어
  /// `UncontrolledProviderScope`가 그것을 버리지 않는다 — 세션 타이머가 그대로
  /// 돌고, 정리는 `addTearDown`이라 검사보다 늦다. 세션을 직접 접는다.
  Future<void> unmount(WidgetTester tester, ProviderContainer container) async {
    container.read(runSessionControllerProvider.notifier).reset();
    // ⚠️ 연결도 닫는다. 끝나지 않은 러닝에는 **좌표 전송 10초 타이머**가
    // 살아 있고, 그것 하나로도 flutter_test가 죽는다.
    await container.read(runningConnectionProvider.notifier).close();
    await tester.pumpWidget(const SizedBox());
  }

  /// 종료 버튼을 끝까지 길게 누른다.
  ///
  /// ⚠️ **1.1.0부터 종료는 사용자만 보낸다.** 예전에는 목표를 넘기면 앱이
  /// 알아서 보냈고 이 그물도 그것에 기댔다.
  Future<void> holdFinish(WidgetTester tester) async {
    // ⚠️ **요약 화면이 기본 뷰포트(600×800)에서 2px 넘친다.** 이 PR 과 무관한
    // 레이아웃 문제인데, 렌더 예외는 테스트를 죽인다. 세로만 늘려 둔다.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final button = find.bySemanticsLabel(AppStrings.runFinishHold);
    final gesture = await tester.startGesture(tester.getCenter(button));
    // 길게 누르기가 끝까지 차도록 넉넉히 민다.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await gesture.up();
    await settleFinish(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('⚠️ 목표에 닿아도 앱은 보내지 않는다', (tester) async {
    // ⚠️ **1.1.0 에서 뒤집힌 약속이다.** 서버가 확정 거리로 판단하므로
    // 앱 기준으로 넘었다고 끝내면 **모자란 러닝이 완주로 올라간다.**
    final container = await pumpRunning(tester);

    for (var i = 1; i <= 10; i++) {
      await emit(tester, north(60.0 * i));
    }

    expect(
      distanceOf(container),
      greaterThanOrEqualTo(target),
      reason: '목표를 넘겨야 판정이 의미가 있다',
    );
    await settleFinish(tester);
    expect(channel.finishes, isEmpty);
    await unmount(tester, container);
  });

  testWidgets('⚠️ 목표를 넘어도 좌표를 계속 보낸다', (tester) async {
    // 가이드 3.1 — 로컬 거리가 목표를 넘었어도 수집·전송을 이어 가며 종료
    // 확정을 기다린다. 멈추면 **서버가 확정할 거리가 모자란 채로 남는다.**
    final container = await pumpRunning(tester);

    for (var i = 1; i <= 10; i++) {
      await emit(tester, north(60.0 * i));
    }
    await settleFinish(tester);

    final state = container.read(runSessionControllerProvider);
    expect(state, isA<RunRunning>(), reason: '세션이 살아 있어야 좌표가 쌓인다');
    await unmount(tester, container);
  });

  group('⚠️ 서버가 끝내면 따라간다 — 1.1.0 가이드 3.1', () {
    // ⚠️ **앱이 안 보내는 것만 고치면 반쪽이다.** 서버가 보낸 종료를 받을
    // 길이 없으면 러닝이 끝났는데 화면이 영영 남는다.

    testWidgets('요약으로 간다', (tester) async {
      final container = await pumpRunning(tester);

      channel.finished_.add(null);
      await tester.pumpAndSettle();

      expect(find.byType(RunSessionPage), findsNothing);
      await unmount(tester, container);
    });

    testWidgets('⚠️ 종료를 되받아 보내지 않는다', (tester) async {
      // 서버가 이미 끝냈다. 또 보내면 같은 방에 종료가 두 번 간다.
      final container = await pumpRunning(tester);

      channel.finished_.add(null);
      await tester.pumpAndSettle();

      expect(channel.finishes, isEmpty);
      await unmount(tester, container);
    });

    testWidgets('⚠️ 세션의 시계를 멈춘다', (tester) async {
      // 화면만 옮기고 세션을 두면 **1초 타이머가 계속 돈다.**
      final container = await pumpRunning(tester);

      channel.finished_.add(null);
      await tester.pumpAndSettle();

      expect(
        container.read(runSessionControllerProvider),
        isNot(isA<RunRunning>()),
      );
      await unmount(tester, container);
    });
  });

  testWidgets('목표가 없는 솔로는 스스로 끝내지 않는다', (tester) async {
    // 솔로에는 목표가 없다. 끝내는 것은 사용자의 몫이다.
    final container = await pumpRunning(tester, targetMeters: null);

    for (var i = 1; i <= 10; i++) {
      await emit(tester, north(60.0 * i));
    }

    await settleFinish(tester);
    expect(distanceOf(container), greaterThan(target));
    expect(channel.finishes, isEmpty);
    await unmount(tester, container);
  });
  group('⚠️ 종료가 보류되면 러닝이 이어진다 — 1.1.0 가이드 3.2', () {
    // ⚠️ **예전에는 요청만 던지고 곧바로 요약으로 넘어갔다.**
    //
    // 1.1.0 서버는 `RUNNING_GOAL_PENDING` 으로 "확정 거리가 모자라다"고 답할
    // 수 있다. 앱이 잰 거리는 목표를 넘었어도 서버는 정지 구간과 오염 좌표를
    // 뺀 값으로 센다 — 먼저 넘어가 버리면 **러닝이 뒤에서 계속 도는 채로
    // 요약 화면이 뜬다.**

    testWidgets('화면이 러닝에 남는다', (tester) async {
      final container = await pumpRunning(tester);
      channel.outcome = const FinishGoalPending(40);

      await holdFinish(tester);

      expect(find.byType(RunSessionPage), findsOneWidget);
      await unmount(tester, container);
    });

    testWidgets('⚠️ 남은 거리를 말해 준다', (tester) async {
      final container = await pumpRunning(tester);
      channel.outcome = const FinishGoalPending(40);

      await holdFinish(tester);

      expect(find.text(AppStrings.runGoalPending(40)), findsOneWidget);
      await unmount(tester, container);
    });

    testWidgets('⚠️ 세션의 시계가 멈추지 않는다', (tester) async {
      // 답을 받기 전에 세션을 접으면 **멀쩡한 러닝의 시간이 멈춘다.**
      final container = await pumpRunning(tester);
      channel.outcome = const FinishGoalPending(40);

      await holdFinish(tester);

      final state = container.read(runSessionControllerProvider);
      expect(state, isA<RunRunning>());
      await unmount(tester, container);
    });

    testWidgets('확정이면 요약으로 간다', (tester) async {
      // 보류를 넣는 쪽만 보면 **확정 경로가 깨져도 모른다.**
      final container = await pumpRunning(tester);

      await holdFinish(tester);

      expect(find.byType(RunSessionPage), findsNothing);
      await unmount(tester, container);
    });
  });
}

/// `RUNNING_FINISH`가 몇 번, 어떤 `forced`로 나갔는지 센다.
class _FinishChannel implements RunningChannel {
  final finishes = <bool>[];

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

  final finished_ = StreamController<void>.broadcast();

  @override
  Stream<void> get finished => finished_.stream;

  @override
  Stream<RunSnapshot> get snapshots => const Stream.empty();

  @override
  Future<void> start(int runningRoomId) async {}

  @override
  bool sendLocations(List<TrackPoint> points) => true;

  /// 무엇으로 답할지. 보류를 흉내 내려면 [FinishGoalPending] 을 넣는다.
  FinishOutcome outcome = const FinishConfirmed();

  @override
  Future<FinishOutcome> finish({bool forced = false}) async {
    finishes.add(forced);
    return outcome;
  }

  @override
  Future<void> close() async {}
}
