import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/data/fake_location_repository.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/run_metrics.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';

/// 버튼 없이 멈춘 구간이 **거리와 움직인 시간에서도 빠지는가** — 1.1.0 가이드 2.3.
///
/// 판정 자체는 `auto_pause_test.dart`가 본다. 여기서 보는 것은 **세션에
/// 닿았는가**다 — 거리와 움직인 시간이 안 늘고, 경과 시간은 흐르고, 다시 가면
/// 둘 다 풀리는가.
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
  /// 움직인 시간이 서고 경과 시간은 흐르는지 보려면 벽시계가 흘러야 한다.
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

  test('⚠️ 서 있으면 움직인 시간은 서고 경과 시간은 흐른다', () async {
    final container = await running();
    for (var i = 1; i <= 10; i++) {
      await emit(container, 6.0 * i);
    }

    await stand(container);
    final stopped = metricsOf(container);

    // 그 자리에서 더 선다. 좌표마다 2초씩, 20초다.
    await stand(container, count: 10);

    final later = metricsOf(container);
    expect(later.elapsed, stopped.elapsed, reason: '움직인 시간은 서 있어야 한다');
    expect(
      later.clockElapsed - stopped.clockElapsed,
      const Duration(seconds: 20),
      reason: '경과 시간은 버튼으로만 선다',
    );
  });

  test('⚠️ 멈춤이 확정돼도 경과 시간은 되돌아가지 않는다', () async {
    // 확정이 10초 넘게 늦어, 시계를 기준점으로 되돌리면 18초에서 2초로
    // 거꾸로 갔다. 워치도 이 값을 그대로 그린다.
    final container = await running();
    for (var i = 1; i <= 10; i++) {
      await emit(container, 6.0 * i);
    }

    var previous = metricsOf(container).clockElapsed;
    for (var i = 1; i <= 16; i++) {
      await emit(container, 60 + (i.isEven ? 2.0 : -2.0));
      final current = metricsOf(container).clockElapsed;
      expect(current, greaterThan(previous), reason: '$i번째 좌표에서 거꾸로 갔다');
      previous = current;
    }

    // 확정은 됐어야 한다 — 안 되면 위 검사가 아무것도 안 본 것이다.
    final metrics = metricsOf(container);
    expect(metrics.elapsed, lessThan(metrics.clockElapsed));
  });

  test('⚠️ 서 있다가 버튼으로 멈추면 그 정지는 거기서 끝난다', () async {
    // 안 끊으면 버튼으로 멈춘 동안에도 정지가 자라, 움직인 시간이 깎인다.
    // [RunPaused]는 멈춘 순간의 값을 들고 있으므로 **다시 계산하는 종료로** 본다.
    final container = await running();
    for (var i = 1; i <= 10; i++) {
      await emit(container, 6.0 * i);
    }
    await stand(container);

    final session = container.read(runSessionControllerProvider.notifier);
    session.pause();
    final paused = metricsOf(container);

    clock = clock.add(const Duration(seconds: 30));
    session.finish();

    final finished = container.read(runSessionControllerProvider);
    expect(finished, isA<RunFinished>());
    final metrics = (finished as RunFinished).metrics;
    expect(metrics.elapsed, paused.elapsed);
    expect(metrics.clockElapsed, paused.clockElapsed);
  });

  test('두 번 서면 두 번 다 움직인 시간에서 빠진다', () async {
    Duration gap(RunMetrics metrics) => metrics.clockElapsed - metrics.elapsed;

    final container = await running();
    for (var i = 1; i <= 10; i++) {
      await emit(container, 6.0 * i);
    }
    await stand(container);
    final first = gap(metricsOf(container));
    expect(first, greaterThan(Duration.zero), reason: '첫 정지가 확정돼야 한다');

    // 반경을 벗어나 달린다. 달리는 동안은 더 빠지지 않는다.
    for (var i = 1; i <= 8; i++) {
      await emit(container, 60 + 20.0 * i);
    }
    final moving = gap(metricsOf(container));
    for (var i = 9; i <= 12; i++) {
      await emit(container, 60 + 20.0 * i);
    }
    expect(gap(metricsOf(container)), moving, reason: '달리는 동안 빠졌다');

    // 다른 자리에서 또 선다.
    for (var i = 1; i <= 16; i++) {
      await emit(container, 300 + (i.isEven ? 2.0 : -2.0));
    }
    expect(gap(metricsOf(container)), greaterThan(moving));
  });

  test('⚠️ 좌표가 늦게 몰려 와도 같은 정지를 두 번 빼지 않는다', () async {
    // 앞 정지가 닫힌 직후 다음 정지가 확정되면, 그 시작점(받은 시각 − 머문
    // 시간)이 앞 정지 안으로 들어가 같은 시간이 두 번 빠졌다. 그만큼이
    // 쌓여 남아 **그 뒤 달린 시간도 움직인 시간에 안 잡혔다.**
    final container = await running();
    for (var i = 1; i <= 10; i++) {
      await emit(container, 6.0 * i);
    }
    await stand(container);
    final stopped = metricsOf(container).elapsed;

    // 위치 콜백이 1분 밀렸다가 한꺼번에 들어온다. 받는 동안 시계는 서 있고
    // 좌표 시각만 2초씩 간다.
    var recordedAt = clock;
    clock = clock.add(const Duration(minutes: 1));
    Future<void> emitLate(double meters) async {
      recordedAt = recordedAt.add(const Duration(seconds: 2));
      location.emit(
        GeoPoint(
          latitude: 37.4979 + meters / 111320,
          longitude: 127.0276,
          recordedAt: recordedAt,
          accuracy: 5,
        ),
      );
      await settle();
    }

    for (var i = 1; i <= 8; i++) {
      await emitLate(60 + 20.0 * i);
    }
    for (var i = 1; i <= 16; i++) {
      await emitLate(300 + (i.isEven ? 2.0 : -2.0));
    }
    // 둘째 정지가 확정됐는지도 본다 — 서 있는 채로 10초가 더 가도 그대로여야 한다.
    await emit(container, 302, after: const Duration(seconds: 10));

    // 앞 정지는 빠져나간 좌표를 **받은 시각**에 닫혀, 밀린 1분이 통째로 정지로
    // 든다. 몰려 온 동안은 시계가 서 있었으니 둘째 정지가 겹쳐 빠지지 않으면
    // 움직인 시간은 처음 섰을 때 그대로다.
    expect(metricsOf(container).elapsed, stopped);
  });

  test('재개 직전에 찍힌 좌표로 멈춰도 재개 전 시간은 빼지 않는다', () async {
    // 재개 전 시간은 이미 버튼 일시정지로 빠져 있다. 기준점 좌표가 재개보다
    // 앞서 찍혔다고 그만큼을 또 빼면 앞 구간의 움직인 시간이 깎인다.
    //
    // ⚠️ **먼저 서서 필터의 속도를 죽인다.** 달리던 채로 멈추면 필터가 그 속도로
    // 앞으로 기어가, 재개 전 기준점이 곧 새 기준점으로 바뀌어 이 갈래에 닿지 않는다.
    final container = await running();
    for (var i = 1; i <= 10; i++) {
      await emit(container, 6.0 * i);
    }
    await stand(container);
    final session = container.read(runSessionControllerProvider.notifier);
    session.pause();
    clock = clock.add(const Duration(seconds: 30));
    session.resume();
    final resumedAt = clock;
    final before = metricsOf(container);

    // 재개 5초 전에 찍힌 좌표가 재개 뒤에 도착한다.
    location.emit(
      GeoPoint(
        latitude: 37.4979 + 60 / 111320,
        longitude: 127.0276,
        recordedAt: resumedAt.subtract(const Duration(seconds: 5)),
        accuracy: 5,
      ),
    );
    await settle();
    await stand(container);

    final after = metricsOf(container);
    final added =
        (after.clockElapsed - after.elapsed) -
        (before.clockElapsed - before.elapsed);
    expect(added, greaterThan(Duration.zero), reason: '정지가 확정돼야 한다');
    expect(added, lessThanOrEqualTo(clock.difference(resumedAt)));
  });

  test('폰 시각이 뒤로 가도 움직인 시간이 경과 시간을 넘지 않는다', () async {
    final container = await running();
    for (var i = 1; i <= 10; i++) {
      await emit(container, 6.0 * i);
    }
    await stand(container);

    // 서 있는 동안 사용자가 폰 시각을 40초 뒤로 돌렸다. 정지가 시작된 시각보다
    // 앞이지만 출발보다는 뒤다 — 출발보다 앞으로 가면 경과 시간부터 음수가 된다.
    clock = clock.subtract(const Duration(seconds: 40));
    await emit(container, 60);
    final standing = metricsOf(container);
    expect(standing.elapsed, lessThanOrEqualTo(standing.clockElapsed));

    for (var i = 1; i <= 8; i++) {
      await emit(container, 60 + 20.0 * i);
    }

    final metrics = metricsOf(container);
    expect(metrics.elapsed, lessThanOrEqualTo(metrics.clockElapsed));
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

  test('⚠️ 다시 걸으면 거리와 움직인 시간이 함께 풀린다', () async {
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
