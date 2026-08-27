import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/database/database_provider.dart';
import 'package:runiverse/features/session/data/geolocator_location_repository.dart';
import 'package:runiverse/features/session/data/sqflite_track_repository.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/location_repository.dart';
import 'package:runiverse/features/session/domain/location_smoother.dart';
import 'package:runiverse/features/session/domain/pace_calculator.dart';
import 'package:runiverse/features/session/domain/run_metrics.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/domain/track_recorder.dart';
import 'package:runiverse/features/session/domain/track_repository.dart';

/// 위치를 누가 줄 것인가. 지금은 실제 GPS다.
///
/// 테스트는 `FakeLocationRepository`로 갈아 끼운다. **바꾸는 자리는 이 한 줄이다.**
///
/// ⚠️ `presentation`에 있으면서 `data`를 import한다. 의존 방향의 예외인데,
/// 구현체를 고르는 일은 어딘가에서 해야 하고 그 자리가 여기다
/// (`auth_provider.dart`와 같은 판단). 화면 파일은 여전히 `data`를 모른다.
final locationRepositoryProvider = Provider<LocationRepository>(
  (ref) => const GeolocatorLocationRepository(),
);

/// 지금 몇 시인가. 테스트가 시간을 돌리기 위해 갈아 끼운다.
final runClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 좌표를 담는 곳. 기기 SQLite다.
final trackRepositoryProvider = Provider<TrackRepository>(
  (ref) => SqfliteTrackRepository(() => ref.read(databaseProvider.future)),
);

/// 좌표를 어디에 쌓나.
///
/// **테스트는 가짜 저장소를 끼운다.** 진짜를 쓰면 위젯 테스트가 기기 DB를
/// 열려 하고, `sqflite`는 기기가 있어야 돌아서 죽는다.
final trackRecorderProvider = Provider<TrackRecorder>(
  (ref) => TrackRecorder(ref.watch(trackRepositoryProvider)),
);

/// 1인 러닝 세션.
///
/// [NotifierProvider]는 Riverpod 3에서 기본이 `isAutoDispose = false`다.
/// 그래서 화면이 사라져도 살아 있다 — 러닝 중에 다른 화면이 위로 올라와도
/// 기록이 통째로 사라지지 않는다(`docs/implementation-notes.md` §5-1).
final runSessionControllerProvider =
    NotifierProvider<RunSessionController, RunSessionState>(
      RunSessionController.new,
    );

/// 준비 → 진행 → 일시정지 → 종료.
///
/// ## 시간을 좌표에서 세지 않는다
///
/// 경과 시간은 시계로 잰다. 좌표가 끊겨도 시간은 흘러야 하기 때문이다.
/// 터널에 들어가 GPS가 30초간 안 잡혀도 "30초 동안 멈춰 있었다"가 되면 안 된다.
///
/// ## 일시정지 중에는 아무것도 쌓이지 않는다
///
/// 시간은 [_accumulated]에 얼려두고, 들어온 좌표는 버린다.
/// 재개할 때 [_points]를 비우므로 **멈춘 사이에 이동한 거리도 세지 않는다.**
class RunSessionController extends Notifier<RunSessionState> {
  StreamSubscription<GeoPoint>? _subscription;
  Timer? _ticker;

  /// 좌표의 흔들림을 걷어낸다. **들어온 좌표는 전부 이걸 먼저 지난다.**
  final _smoother = LocationSmoother();

  /// 현재 구간의 좌표. 페이스 계산과 거리 누적의 기준점이다.
  ///
  /// 재개할 때 비우므로 **러닝 전체의 경로가 아니다.** 지도는 [track]을 본다.
  final _points = <GeoPoint>[];

  /// 지도가 그릴 경로. **구간으로 나눠 담는다.**
  ///
  /// 일시정지 사이의 이동을 거리에 넣지 않기로 했으니 선으로도 잇지 않는다.
  /// 하나로 이으면 멈춘 사이에 차로 이동한 것까지 뛴 것처럼 그려진다.
  final _segments = <List<GeoPoint>>[];

  /// 지금까지 달린 경로. 구간마다 선을 따로 그린다.
  ///
  /// 마지막 구간은 아직 달리는 중이라 [_points]에 있다.
  List<List<GeoPoint>> get track => [
    for (final segment in _segments)
      if (segment.length > 1) segment,
    if (_points.length > 1) List.unmodifiable(_points),
  ];

  double _distanceMeters = 0;

  /// 일시정지 이전까지 쌓인 시간.
  Duration _accumulated = Duration.zero;

  /// 현재 구간이 시작된 시각. 일시정지 중에는 `null`이다.
  DateTime? _resumedAt;

  DateTime? _startedAt;

  DateTime Function() get _now => ref.read(runClockProvider);
  LocationRepository get _repository => ref.read(locationRepositoryProvider);

  @override
  RunSessionState build() {
    // 이걸 빠뜨리면 러닝이 끝나도 GPS가 계속 돈다.
    ref.onDispose(_teardown);
    return const RunIdle();
  }

  /// 출발 준비. 권한을 확인하고 위치 구독을 연다.
  ///
  /// 허용되지 않으면 [RunIdle]로 되돌리고 이유를 돌려준다.
  /// 화면마다 `try`/`catch`를 쓰지 않도록 예외 대신 값으로 답한다
  /// (`AuthController`와 같은 방식).
  Future<LocationAccess> prepare() async {
    _reset();
    state = const RunPreparing();

    final access = await _repository.ensureAccess();
    if (!access.isGranted) {
      state = const RunIdle();
      return access;
    }

    _subscription = _repository.watchPosition().listen(_onPoint);
    return access;
  }

  /// 달리기 시작. [RunPreparing]에서 **첫 신호를 받은 뒤에만** 걸린다.
  void start() {
    if (state case RunPreparing(hasFix: true)) {
      final now = _now();
      _startedAt = now;
      _resumedAt = now;
      _accumulated = Duration.zero;

      // 준비하며 서 있는 동안 흔들린 좌표를 거리에 넣지 않는다.
      _points.clear();
      _segments.clear();

      state = RunRunning(_metrics());
      _startTicker();
    }
  }

  void pause() {
    if (state is! RunRunning) return;

    _accumulated = _elapsed();
    _resumedAt = null;
    _stopTicker();

    // 여기까지가 한 구간이다. 재개하면 [_points]가 비워지므로 지금 접어 둔다.
    if (_points.length > 1) _segments.add(List.of(_points));

    state = RunPaused(_metrics());
  }

  void resume() {
    if (state is! RunPaused) return;

    _resumedAt = _now();

    // 멈춘 사이에 이동했더라도 그 구간은 거리에 넣지 않는다.
    _points.clear();

    state = RunRunning(_metrics());
    _startTicker();
  }

  /// 러닝을 끝낸다. 요약 화면이 [RunFinished]를 읽는다.
  void finish() {
    final startedAt = _startedAt;
    if (startedAt == null) return;

    final metrics = _metrics();
    _teardown();

    state = RunFinished(
      metrics: metrics,
      startedAt: startedAt,
      endedAt: _now(),
    );
  }

  /// 요약 화면을 닫고 홈으로 돌아갈 때. 다음 러닝을 위해 비운다.
  void reset() {
    _teardown();
    _reset();
    state = const RunIdle();
  }

  void _onPoint(GeoPoint raw) {
    // ⚠️ **여기가 유일한 보정 지점이다.** 거리 계산과 지도가 같은 좌표를 봐야
    // 화면의 선과 화면의 숫자가 같은 이야기를 한다.
    final point = _smoother.smooth(raw);

    switch (state) {
      // 준비 중에는 "신호를 받았다"만 알린다. 거리는 아직 세지 않는다.
      case RunPreparing(hasFix: false):
        state = const RunPreparing(hasFix: true);

      case RunRunning():
        if (_points.isNotEmpty) {
          _distanceMeters += _points.last.distanceTo(point);
        }
        _points.add(point);
        final metrics = _metrics();
        state = RunRunning(metrics);

        // ⚠️ **기다리지 않는다.** DB 쓰기가 느려도 화면과 거리 계산이 멈추면
        // 안 된다. 실패해도 러닝은 계속된다 — 좌표 하나 때문에 달리기를
        // 멈출 이유가 없다.
        unawaited(
          ref
              .read(trackRecorderProvider)
              .add(point, currentPace: metrics.currentPace)
              .catchError((Object error) {
                debugPrint('[track] 좌표를 쌓지 못했다 · $error');
              }),
        );

      // 일시정지·종료·대기 중에 들어온 좌표는 버린다.
      case RunPreparing() || RunPaused() || RunFinished() || RunIdle():
        break;
    }
  }

  /// 1초마다 화면의 시간을 밀어준다. 좌표가 안 와도 시계는 흘러야 한다.
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state is RunRunning) state = RunRunning(_metrics());
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Duration _elapsed() {
    final resumedAt = _resumedAt;
    if (resumedAt == null) return _accumulated;
    return _accumulated + _now().difference(resumedAt);
  }

  RunMetrics _metrics() => RunMetrics(
    distanceMeters: _distanceMeters,
    elapsed: _elapsed(),
    currentPace: PaceCalculator.recent(_points),
  );

  /// 바깥으로 나가는 것을 끊는다. 상태는 건드리지 않는다.
  void _teardown() {
    _stopTicker();
    _subscription?.cancel();
    _subscription = null;
  }

  void _reset() {
    _points.clear();
    _segments.clear();
    // ⚠️ 안 비우면 다음 러닝의 첫 좌표가 **지난 러닝의 마지막 위치로 끌려온다.**
    _smoother.reset();
    _distanceMeters = 0;
    _accumulated = Duration.zero;
    _resumedAt = null;
    _startedAt = null;
  }
}
