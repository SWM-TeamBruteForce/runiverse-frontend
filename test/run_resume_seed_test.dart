import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/data/fake_location_repository.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/run_metrics.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';

/// 앱을 껐다 켜서 이어 달릴 때 **서버가 아는 값이 화면에 돌아오는가.**
///
/// ## ⚠️ 두 길이 같은 틱에 나란히 출발한다
///
/// 스플래시(`splash_page.dart`)는 `reopen()`과 `startWhenReady(since:)`를
/// `unawaited`로 **나란히** 쏜다. 앞은 소켓 왕복을 기다려 스냅샷을 받고, 뒤는
/// **GPS 첫 신호**를 기다려 `start`를 부른다. 둘 중 무엇이 먼저 끝나는지는
/// 망 지연과 위성이 정하므로 **어느 쪽이 이겨도 결과가 같아야 한다.**
///
/// 스냅샷은 `RUNNING_STARTED` 한 번뿐이라, 놓치면 두 번째 기회가 없다.
void main() {
  late DateTime clock;
  late FakeLocationRepository location;

  /// 예약 시각. 복구는 상태 조회가 주는 이 값으로 경과를 재기 시작한다.
  final scheduled = DateTime(2026, 10, 28, 18);

  /// 서버가 아는 **실제 출발 시각.** 예약보다 1분 늦게 떴다.
  final startedAt = DateTime(2026, 10, 28, 18, 1);

  ProviderContainer makeContainer() {
    clock = DateTime(2026, 10, 28, 19);
    location = FakeLocationRepository();
    return ProviderContainer.test(
      overrides: [
        locationRepositoryProvider.overrideWithValue(location),
        runClockProvider.overrideWithValue(() => clock),
      ],
    );
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// 첫 신호를 흘린다. 이것이 와야 [RunSessionController.start]가 선다.
  Future<void> fix(double meters) async {
    location.emit(
      GeoPoint(
        latitude: 37.4979 + meters / 111320,
        longitude: 127.0276,
        recordedAt: clock,
        accuracy: 5,
      ),
    );
    await settle();
  }

  RunMetrics metricsOf(ProviderContainer container) =>
      switch (container.read(runSessionControllerProvider)) {
        RunRunning(:final metrics) || RunPaused(:final metrics) => metrics,
        _ => const RunMetrics(distanceMeters: 0, elapsed: Duration.zero),
      };

  group('신호가 스냅샷보다 먼저 올 때', () {
    test('거리가 돌아온다', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final session = container.read(runSessionControllerProvider.notifier);

      await session.prepare();
      await fix(0);
      await session.startWhenReady(since: scheduled);
      await settle();

      session.seedDistance(3841);

      expect(metricsOf(container).distanceMeters, closeTo(3841, 1));
    });

    test('시작 시각이 돌아온다', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final session = container.read(runSessionControllerProvider.notifier);

      await session.prepare();
      await fix(0);
      await session.startWhenReady(since: scheduled);
      await settle();

      session.seedStartedAt(startedAt);

      expect(metricsOf(container).elapsed, const Duration(minutes: 59));
    });
  });

  group('⚠️ 스냅샷이 신호보다 먼저 올 때', () {
    /// 신호를 기다리는 동안 스냅샷이 먼저 닿은 세션.
    Future<ProviderContainer> snapshotFirst({
      int? meters = 3841,
      DateTime? at,
    }) async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final session = container.read(runSessionControllerProvider.notifier);

      // 아직 첫 신호가 없다 — `start`가 밀려 있다.
      await session.prepare();
      await session.startWhenReady(since: scheduled);
      await settle();

      // 소켓이 먼저 닿았다.
      if (meters != null) session.seedDistance(meters);
      if (at != null) session.seedStartedAt(at);

      // 그 뒤에 첫 신호가 와서 비로소 달리기 시작한다.
      await fix(0);
      await settle();
      return container;
    }

    test('거리가 돌아온다', () async {
      // ⚠️ 이것이 안 되면 3.8km를 뛴 사람의 화면이 `0.00 km`로 남는다.
      final container = await snapshotFirst();

      expect(metricsOf(container).distanceMeters, closeTo(3841, 1));
    });

    test('시작 시각이 돌아온다', () async {
      // ⚠️ 이것이 안 되면 예약 시각으로 세어 **안 뛴 시간이 얹힌다.**
      final container = await snapshotFirst(meters: null, at: startedAt);

      expect(metricsOf(container).elapsed, const Duration(minutes: 59));
    });

    test('⚠️ 거리를 받기 전에는 아직 모른다고 답한다', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final session = container.read(runSessionControllerProvider.notifier);

      await session.prepare();
      await session.startWhenReady(since: scheduled);
      await settle();

      // 스냅샷이 아직 안 왔다. 이 창에서 종료를 누르면 거리가 0이다.
      expect(session.awaitingDistanceSeed, isTrue);

      session.seedDistance(3841);
      await fix(0);
      await settle();

      expect(session.awaitingDistanceSeed, isFalse);
    });
  });

  group('새로 시작한 러닝', () {
    test('⚠️ 스냅샷이 와도 거리를 올리지 않는다', () async {
      // 명세가 "화면 표시는 로컬 계산값 우선, 스냅샷은 복구용"으로 정했다.
      // 연결만 끊겼다 붙은 경우까지 맞추면 화면의 숫자가 툭 뛴다.
      final container = makeContainer();
      addTearDown(container.dispose);
      final session = container.read(runSessionControllerProvider.notifier);

      await session.prepare();
      await fix(0);
      session.start();
      await settle();

      session.seedDistance(3841);

      expect(metricsOf(container).distanceMeters, lessThan(1));
    });

    test('⚠️ 이어 달리는 것이 아니므로 기다릴 것도 없다', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final session = container.read(runSessionControllerProvider.notifier);

      await session.prepare();
      await fix(0);
      session.start();
      await settle();

      expect(session.awaitingDistanceSeed, isFalse);
    });
  });
}
