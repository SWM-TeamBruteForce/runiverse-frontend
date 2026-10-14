import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/data/fake_location_repository.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/run_metrics.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';

/// 버튼 없이 멈춘 구간이 **화면에서도 빠지는가** — 1.1.0 가이드 2.3.
///
/// 판정 자체는 `auto_pause_test.dart`가 본다. 여기서 보는 것은 **세션에
/// 닿았는가**다 — 거리가 안 늘고, 시계가 서고, 다시 가면 둘 다 풀리는가.
///
/// ## ⚠️ 상태는 [RunRunning]에 남는다
///
/// 사용자가 누른 것이 아니다. [RunPaused]로 바꾸면 **일시정지 버튼이 제멋대로
/// 재개 버튼이 되고**, 서버에도 `RUNNING_PAUSE`가 나간다 — 가이드가 "PAUSE를
/// 보내지 말아 주세요"라고 적은 그 자리다.
void main() {
  late DateTime clock;
  late FakeLocationRepository location;

  ProviderContainer makeContainer() {
    clock = DateTime(2026, 10, 14, 7);
    location = FakeLocationRepository();
    return ProviderContainer.test(
      overrides: [
        locationRepositoryProvider.overrideWithValue(location),
        runClockProvider.overrideWithValue(() => clock),
      ],
    );
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// 북쪽으로 [meters] 간 자리의 좌표를 흘린다. **시계도 함께 간다** —
  /// 경과 시간이 멈추는지 보려면 벽시계가 흘러야 한다.
  Future<void> emit(
    ProviderContainer container,
    double meters, {
    Duration after = const Duration(seconds: 2),
    double accuracy = 5,
  }) async {
    clock = clock.add(after);
    location.emit(
      GeoPoint(
        latitude: 37.4979 + meters / 111320,
        longitude: 127.0276,
        recordedAt: clock,
        accuracy: accuracy,
      ),
    );
    await settle();
  }

  /// 그 자리에서 [count]번 흔들린다.
  ///
  /// ⚠️ **넉넉히 넣어야 한다.** 좌표가 칼만 필터를 거쳐 들어오는데, 필터는
  /// 좌표 하나에 벌어진 간격의 1/3쯤만 따라간다. 그래서 달리는 동안 추정이
  /// **실제 위치보다 몇 미터 뒤에** 있고, 선 뒤에도 그 간격만큼 **앞으로
  /// 기어간다** — 그동안은 기준점이 매번 새로 서므로 10초가 안 쌓인다.
  /// 실제로 11번째 좌표에서야 멈춤이 확정됐다. 그만큼 판정이 늦지만, 서버도
  /// **같은 좌표를 받아**(전송도 보정 좌표다) 같은 지연을 겪으므로 둘은
  /// 어긋나지 않는다.
  Future<void> stand(ProviderContainer container, {int count = 16}) async {
    for (var i = 1; i <= count; i++) {
      await emit(container, 60 + (i.isEven ? 2.0 : -2.0));
    }
  }

  RunMetrics metricsOf(ProviderContainer container) =>
      switch (container.read(runSessionControllerProvider)) {
        RunRunning(:final metrics) || RunPaused(:final metrics) => metrics,
        _ => const RunMetrics(distanceMeters: 0, elapsed: Duration.zero),
      };

  /// 달리는 중인 세션을 만든다.
  Future<ProviderContainer> running() async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final session = container.read(runSessionControllerProvider.notifier);
    await session.prepare();
    await emit(container, 0, after: Duration.zero);
    session.start();
    return container;
  }

  test('⚠️ 서 있으면 거리가 더는 늘지 않는다', () async {
    // ⚠️ **이것이 안 되면 36분 서 있던 러닝이 3km에 76분으로 찍힌다.**
    //
    // ⚠️ 재는 것은 **확정된 뒤로 더 늘지 않는가**다. 확정 전,
    // 필터가 따라붙는 동안 쌓인 몇 미터는 되돌려지지 않는다 — 가이드가
    // 되돌리라고 한 것은 **기준점부터**이고, 그동안은 기준점이 매번 새로
    // 섰기 때문이다. 36분짜리 정지에서 앞의 20초는 문제가 아니다.
    final container = await running();

    for (var i = 1; i <= 10; i++) {
      await emit(container, 6.0 * i);
    }
    expect(
      metricsOf(container).distanceMeters,
      greaterThan(40),
      reason: '먼저 달려야 멈춘 것이 의미가 있다',
    );

    await stand(container);
    final frozen = metricsOf(container).distanceMeters;

    await stand(container, count: 10);

    expect(metricsOf(container).distanceMeters, frozen);
  });

  test('⚠️ 서 있으면 시계도 선다', () async {
    final container = await running();
    for (var i = 1; i <= 10; i++) {
      await emit(container, 6.0 * i);
    }

    await stand(container);
    final frozen = metricsOf(container).elapsed;

    // 그 자리에서 더 선다. 시계가 서 있어야 한다.
    await stand(container, count: 10);

    expect(metricsOf(container).elapsed, frozen, reason: '시계가 서 있어야 한다');
  });

  test('⚠️ 상태는 달리는 중으로 남는다', () async {
    // [RunPaused]로 바꾸면 **버튼이 제멋대로 재개로 바뀌고**, 연결이
    // `RUNNING_PAUSE`를 보낸다 — 가이드가 금지한 바로 그것이다.
    final container = await running();
    for (var i = 1; i <= 10; i++) {
      await emit(container, 6.0 * i);
    }
    await stand(container);

    expect(container.read(runSessionControllerProvider), isA<RunRunning>());
  });

  test('⚠️ 다시 걸으면 거리와 시계가 함께 풀린다', () async {
    final container = await running();
    for (var i = 1; i <= 10; i++) {
      await emit(container, 6.0 * i);
    }
    await stand(container);
    final stopped = metricsOf(container);

    // 반경을 벗어난다. 빠져나가는 이동은 정상 이동이다.
    for (var i = 1; i <= 8; i++) {
      await emit(container, 60 + 20.0 * i);
    }

    final back = metricsOf(container);
    expect(back.distanceMeters, greaterThan(stopped.distanceMeters));
    expect(back.elapsed, greaterThan(stopped.elapsed));
  });

  test('⚠️ 느리게 달리는 사람을 멈춘 것으로 보지 않는다', () async {
    // 반경(5~8m)보다 큰 걸음이면 매번 기준점이 새로 선다. 10초를 채울 일이
    // 없어야 한다 — 걸어가는 사람의 거리가 사라지면 안 된다.
    final container = await running();

    for (var i = 1; i <= 20; i++) {
      await emit(container, 10.0 * i);
    }

    expect(
      metricsOf(container).distanceMeters,
      greaterThan(150),
      reason: '10m씩 20번이면 200m 가까이 나와야 한다',
    );
  });
}
