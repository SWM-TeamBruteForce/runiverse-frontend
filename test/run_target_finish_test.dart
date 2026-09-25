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

/// 목표 거리에 닿으면 **스스로 끝내는가.**
///
/// 명세가 정한 순서는 `RUNNING_FINISH` → `RUNNING_FINISHED` ack → 로컬 트랙
/// 삭제 → 결과 조회다. 예전에는 그 첫 줄이 **사용자가 중지를 누를 때만**
/// 나갔다 — 목표를 채우고도 안 누르면 서버는 그 러닝을 계속 들고 있다.
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

  testWidgets('⚠️ 목표에 닿으면 스스로 종료를 보낸다', (tester) async {
    final container = await pumpRunning(tester);

    // 목표(200m)를 넘을 때까지 60m씩 나아간다.
    for (var i = 1; i <= 6 && channel.finishes.isEmpty; i++) {
      await emit(tester, north(60.0 * i));
    }

    expect(
      distanceOf(container),
      greaterThanOrEqualTo(target),
      reason: '목표를 넘겨야 판정이 의미가 있다',
    );
    await settleFinish(tester);
    expect(channel.finishes, hasLength(1));
    await unmount(tester, container);
  });

  testWidgets('⚠️ forced는 거짓이다', (tester) async {
    // 명세가 `forced`를 **"목표 거리 달성 전 사용자의 종료 의사"** 로 정의한다.
    // 목표를 채우고 끝나는 것은 의사 표시가 아니라 완주다 — 참이면 서버가
    // 조기 종료로 읽는다.
    final container = await pumpRunning(tester);

    for (var i = 1; i <= 6 && channel.finishes.isEmpty; i++) {
      await emit(tester, north(60.0 * i));
    }

    await settleFinish(tester);
    expect(channel.finishes.single, isFalse);
    await unmount(tester, container);
  });

  testWidgets('⚠️ 목표를 넘어도 한 번만 보낸다', (tester) async {
    // 좌표는 1초마다 온다. 매번 보내면 같은 방에 종료가 쏟아진다.
    final container = await pumpRunning(tester);

    for (var i = 1; i <= 10; i++) {
      await emit(tester, north(60.0 * i));
    }

    await settleFinish(tester);
    expect(channel.finishes, hasLength(1));
    await unmount(tester, container);
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

  @override
  Stream<RunSnapshot> get snapshots => const Stream.empty();

  @override
  Future<void> start(int runningRoomId) async {}

  @override
  bool sendLocations(List<TrackPoint> points) => true;

  @override
  Future<bool> finish({bool forced = false}) async {
    finishes.add(forced);
    return true;
  }

  @override
  Future<void> close() async {}
}
