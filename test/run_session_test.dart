import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/data/fake_location_repository.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/location_repository.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';

/// 러닝 세션 상태 전이 — 무엇을 하면 상태가 어디로 가는가.
///
/// 화면은 보지 않는다. 실기기도 필요 없다. 좌표는 손으로 먹이고,
/// **시계는 갈아 끼운다** — 5분을 실제로 기다리지 않는다.
void main() {
  final start = DateTime(2026, 8, 5, 19);
  late DateTime clock;
  late FakeLocationRepository location;

  setUp(() {
    clock = start;
    location = FakeLocationRepository();
  });

  ProviderContainer makeContainer({
    LocationAccess access = LocationAccess.granted,
  }) {
    location = FakeLocationRepository(access: access);
    return ProviderContainer.test(
      overrides: [
        locationRepositoryProvider.overrideWithValue(location),
        runClockProvider.overrideWithValue(() => clock),
      ],
    );
  }

  /// 좌표가 스트림을 타고 컨트롤러에 닿을 때까지 기다린다.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  GeoPoint point(double lat, double lon) =>
      GeoPoint(latitude: lat, longitude: lon, recordedAt: clock);

  /// 시계를 앞으로 돌린다.
  void advance(Duration by) => clock = clock.add(by);

  group('권한', () {
    test('처음에는 아무것도 시작하지 않은 상태다', () {
      final container = makeContainer();

      expect(container.read(runSessionControllerProvider), isA<RunIdle>());
    });

    test('허용하면 준비 상태로 간다', () async {
      final container = makeContainer();

      final access = await container
          .read(runSessionControllerProvider.notifier)
          .prepare();

      expect(access, LocationAccess.granted);
      expect(container.read(runSessionControllerProvider), isA<RunPreparing>());
    });

    test('거절하면 시작하지 않고 이유를 돌려준다', () async {
      final container = makeContainer(access: LocationAccess.deniedForever);

      final access = await container
          .read(runSessionControllerProvider.notifier)
          .prepare();

      // 예외를 던지지 않는다. 화면이 문구를 고를 수 있게 값으로 답한다.
      expect(access, LocationAccess.deniedForever);
      expect(container.read(runSessionControllerProvider), isA<RunIdle>());
    });

    test('위치 기능이 꺼져 있으면 권한과 다른 이유를 돌려준다', () async {
      final container = makeContainer(access: LocationAccess.serviceDisabled);

      final access = await container
          .read(runSessionControllerProvider.notifier)
          .prepare();

      expect(access, LocationAccess.serviceDisabled);
    });
  });

  group('출발 준비', () {
    test('첫 신호를 받기 전에는 출발하지 못한다', () async {
      final container = makeContainer();
      final controller = container.read(runSessionControllerProvider.notifier);
      await controller.prepare();

      controller.start();

      // 여기서 출발하면 초반 거리가 통째로 빠진다.
      expect(container.read(runSessionControllerProvider), isA<RunPreparing>());
    });

    test('좌표가 들어오면 출발할 수 있다', () async {
      final container = makeContainer();
      final controller = container.read(runSessionControllerProvider.notifier);
      await controller.prepare();

      location.emit(point(37.5, 127));
      await settle();

      final state = container.read(runSessionControllerProvider);
      expect(state, isA<RunPreparing>());
      expect((state as RunPreparing).hasFix, isTrue);
    });

    test('출발하면 진행 상태가 되고 수치는 0이다', () async {
      final container = makeContainer();
      final controller = container.read(runSessionControllerProvider.notifier);
      await controller.prepare();
      location.emit(point(37.5, 127));
      await settle();

      controller.start();

      final state = container.read(runSessionControllerProvider) as RunRunning;
      expect(state.metrics.distanceMeters, 0);
      expect(state.metrics.elapsed, Duration.zero);
    });
  });

  group('진행', () {
    /// 준비를 마치고 출발한 상태를 만든다.
    Future<ProviderContainer> running() async {
      final container = makeContainer();
      final controller = container.read(runSessionControllerProvider.notifier);
      await controller.prepare();
      location.emit(point(37.5, 127));
      await settle();
      controller.start();
      return container;
    }

    test('좌표가 쌓이면 거리가 는다', () async {
      final container = await running();

      location.emit(point(37.5, 127));
      await settle();
      location.emit(point(37.501, 127));
      await settle();

      final state = container.read(runSessionControllerProvider) as RunRunning;

      // ⚠️ 정확히 111m를 기대하지 않는다. 좌표가 **보정을 거쳐** 들어오기
      // 때문이다(`LocationSmoother`) — 한 점만으로는 필터가 아직 새 위치를
      // 다 따라가지 못해 실제보다 짧게 잡힌다. 그게 이 필터의 목적이다.
      //
      // 하버사인의 정확도는 `geo_point_test`가 본다. 여기서 볼 것은
      // "좌표가 쌓이면 거리가 는가"뿐이다.
      expect(state.metrics.distanceMeters, greaterThan(0));
      expect(state.metrics.distanceMeters, lessThan(111));
    });

    test('출발 직전에 서 있던 좌표는 거리에 들어가지 않는다', () async {
      final container = makeContainer();
      final controller = container.read(runSessionControllerProvider.notifier);
      await controller.prepare();

      // 준비하며 서 있는 동안 신호가 흔들렸다.
      location.emit(point(37.5, 127));
      await settle();
      location.emit(point(37.501, 127));
      await settle();

      controller.start();
      location.emit(point(37.501, 127));
      await settle();

      final state = container.read(runSessionControllerProvider) as RunRunning;
      expect(state.metrics.distanceMeters, 0);
    });

    test('시간은 좌표가 아니라 시계로 잰다', () async {
      final container = await running();

      // 터널에 들어가 좌표가 하나도 안 들어왔다.
      advance(const Duration(minutes: 3));
      location.emit(point(37.5, 127));
      await settle();

      final state = container.read(runSessionControllerProvider) as RunRunning;
      expect(state.metrics.elapsed, const Duration(minutes: 3));
    });
  });

  group('일시정지', () {
    Future<ProviderContainer> runningWithDistance() async {
      final container = makeContainer();
      final controller = container.read(runSessionControllerProvider.notifier);
      await controller.prepare();
      location.emit(point(37.5, 127));
      await settle();
      controller.start();

      location.emit(point(37.5, 127));
      await settle();
      advance(const Duration(minutes: 1));
      location.emit(point(37.501, 127));
      await settle();
      return container;
    }

    test('멈추면 시간이 늘지 않는다', () async {
      final container = await runningWithDistance();
      final controller = container.read(runSessionControllerProvider.notifier);

      controller.pause();
      final paused = container.read(runSessionControllerProvider) as RunPaused;

      advance(const Duration(minutes: 5));

      // 5분이 흘렀지만 멈춰 있었으므로 그대로다.
      final still = container.read(runSessionControllerProvider) as RunPaused;
      expect(still.metrics.elapsed, paused.metrics.elapsed);
      expect(still.metrics.elapsed, const Duration(minutes: 1));
    });

    test('멈춘 동안 들어온 좌표는 거리에 더하지 않는다', () async {
      final container = await runningWithDistance();
      final controller = container.read(runSessionControllerProvider.notifier);
      final before =
          (container.read(runSessionControllerProvider) as RunRunning)
              .metrics
              .distanceMeters;

      controller.pause();
      location.emit(point(37.51, 127));
      await settle();

      final state = container.read(runSessionControllerProvider) as RunPaused;
      expect(state.metrics.distanceMeters, before);
    });

    test('재개하면 멈춘 사이에 이동한 거리를 세지 않는다', () async {
      final container = await runningWithDistance();
      final controller = container.read(runSessionControllerProvider.notifier);
      final before =
          (container.read(runSessionControllerProvider) as RunRunning)
              .metrics
              .distanceMeters;

      controller.pause();
      // 차를 타고 1km를 이동했다고 치자.
      controller.resume();
      location.emit(point(37.51, 127));
      await settle();

      final state = container.read(runSessionControllerProvider) as RunRunning;
      expect(state.metrics.distanceMeters, before);
    });

    test('재개하면 시간이 다시 흐른다', () async {
      final container = await runningWithDistance();
      final controller = container.read(runSessionControllerProvider.notifier);

      controller.pause();
      advance(const Duration(minutes: 5));
      controller.resume();
      advance(const Duration(seconds: 30));
      location.emit(point(37.5, 127));
      await settle();

      final state = container.read(runSessionControllerProvider) as RunRunning;
      // 달린 1분 + 재개 후 30초. 멈춘 5분은 빠진다.
      expect(state.metrics.elapsed, const Duration(minutes: 1, seconds: 30));
    });
  });

  group('종료', () {
    Future<ProviderContainer> running() async {
      final container = makeContainer();
      final controller = container.read(runSessionControllerProvider.notifier);
      await controller.prepare();
      location.emit(point(37.5, 127));
      await settle();
      controller.start();
      return container;
    }

    test('끝내면 결과를 들고 종료 상태가 된다', () async {
      final container = await running();
      final controller = container.read(runSessionControllerProvider.notifier);

      advance(const Duration(minutes: 27));
      controller.finish();

      final state = container.read(runSessionControllerProvider) as RunFinished;
      expect(state.startedAt, start);
      expect(state.endedAt, start.add(const Duration(minutes: 27)));
      expect(state.metrics.elapsed, const Duration(minutes: 27));
    });

    test('끝내면 위치를 더 듣지 않는다', () async {
      final container = await running();
      final controller = container.read(runSessionControllerProvider.notifier);
      controller.finish();

      location.emit(point(37.6, 127));
      await settle();

      // 구독을 끊지 않으면 GPS가 계속 돌아 배터리를 먹는다.
      expect(container.read(runSessionControllerProvider), isA<RunFinished>());
    });

    test('되돌리면 처음 상태가 된다', () async {
      final container = await running();
      final controller = container.read(runSessionControllerProvider.notifier);
      controller.finish();

      controller.reset();

      expect(container.read(runSessionControllerProvider), isA<RunIdle>());
    });

    test('시작하지 않았으면 끝낼 것도 없다', () async {
      final container = makeContainer();
      final controller = container.read(runSessionControllerProvider.notifier);

      controller.finish();

      expect(container.read(runSessionControllerProvider), isA<RunIdle>());
    });
  });
}
