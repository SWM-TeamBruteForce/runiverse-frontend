import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/database/database_provider.dart';
import 'package:runiverse/core/storage/body_profile_provider.dart';
import 'package:runiverse/features/session/domain/calorie_calculator.dart';
import 'package:runiverse/features/session/data/geolocator_location_repository.dart';
import 'package:runiverse/features/session/data/pedometer_step_repository.dart';
import 'package:runiverse/features/session/data/sqflite_track_repository.dart';
import 'package:runiverse/features/session/domain/cadence_calculator.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/location_repository.dart';
import 'package:runiverse/features/session/domain/location_smoother.dart';
import 'package:runiverse/features/session/domain/pace_calculator.dart';
import 'package:runiverse/features/session/domain/run_metrics.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/domain/step_repository.dart';
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

/// 걸음을 누가 셀 것인가. 지금은 기기 센서다.
///
/// ⚠️ **에뮬레이터에는 걸음 센서가 없다.** 테스트는 `FakeStepRepository`를 끼운다.
final stepRepositoryProvider = Provider<StepRepository>(
  (ref) => const PedometerStepRepository(),
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
  /// 방향을 내는 데 쓸 최소 이동 거리.
  ///
  /// GPS 오차 반경이 흔히 5~10미터다. 그보다 짧은 이동으로 각도를 내면
  /// 진행 방향이 아니라 잡음의 방향이 나온다.
  ///
  /// ## ⚠️ 직전 좌표 하나와 비교하는 값이 아니다
  ///
  /// 좌표는 1초 간격이다. 6분/km로 달려도 초당 2.8미터라 **직전 좌표와의
  /// 거리가 10미터를 넘으려면 시속 36km로 달려야 한다.** 그렇게 걸면 방향이
  /// 거의 항상 비게 된다.
  ///
  /// 그래서 **되돌아보는 창**으로 쓴다 — 이만큼 떨어진 가장 최근 좌표에서
  /// 방위를 낸다. 6분/km면 약 4초 전 좌표다.
  static const _headingMinMeters = 10.0;

  /// 방위를 낼 때 최대 몇 점까지 되돌아보나.
  ///
  /// 1초에 하나씩 들어오므로 1분이다. **1분 동안 10미터를 못 갔으면 움직이는
  /// 중이 아니다.** 한도가 없으면 신호등에 서 있는 동안 매 초 러닝 전체를
  /// 훑게 된다.
  static const _headingLookback = 60;

  StreamSubscription<GeoPoint>? _subscription;

  /// 걸음 센서 구독. 권한이 없거나 센서가 없으면 `null`이다.
  StreamSubscription<StepSample>? _steps;

  /// 최근 걸음 표본. 케이던스는 **두 표본의 차이**로만 나온다.
  final _stepSamples = <StepSample>[];

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

    _subscription = _repository.watchPosition().listen(
      _onPoint,
      // ⚠️ **이것이 없으면 예외가 Zone으로 새고 화면이 영원히 멈춘다.**
      // `ensureAccess`를 통과한 뒤에도 스트림이 "위치 서비스가 꺼졌다"를
      // 던지는 일이 있다. 상태에 실어 화면이 이유를 띄우게 한다.
      onError: _onPositionError,
    );

    // ⚠️ **위치와 달리 실패해도 러닝을 막지 않는다.** 케이던스는 있으면 좋은
    // 값이고, 없으면 `--`로 남을 뿐이다. 걸음 권한을 거절했다고 달리지
    // 못하게 하면 안 된다.
    unawaited(_startSteps());
    return access;
  }

  /// 위치 스트림이 죽었다. **준비 중에만 화면에 알린다.**
  ///
  /// 달리는 도중이라면 상태를 건드리지 않는다 — 잠깐 신호가 끊겼다고 기록을
  /// 되돌리면 그때까지 달린 거리가 사라진다. 로그만 남기고 그대로 둔다.
  void _onPositionError(Object error) {
    debugPrint('[run] 위치 스트림이 실패했다 · $error');

    if (state is! RunPreparing) return;

    unawaited(_subscription?.cancel());
    _subscription = null;
    state = RunPreparing(
      failure: error is LocationUnavailable
          ? error.reason
          : LocationAccess.denied,
    );
  }

  /// 걸음 센서를 연다. 권한이 없거나 센서가 없으면 조용히 포기한다.
  ///
  /// 에뮬레이터에는 걸음 센서가 아예 없어 스트림이 곧바로 오류를 낸다.
  Future<void> _startSteps() async {
    try {
      if (!await ref.read(stepRepositoryProvider).ensureAccess()) {
        debugPrint('[cadence] 걸음 권한이 없다. 케이던스를 내지 않는다');
        return;
      }
      _steps = ref
          .read(stepRepositoryProvider)
          .watchSteps()
          .listen(
            _onStep,
            onError: (Object error) {
              debugPrint('[cadence] 걸음 센서를 읽지 못했다 · $error');
            },
          );
    } on Object catch (error) {
      debugPrint('[cadence] 걸음 센서를 열지 못했다 · $error');
    }
  }

  void _onStep(StepSample sample) {
    _stepSamples.add(sample);

    // 안 버리면 30분 러닝에서 표본이 계속 쌓인다. 창 하나만큼만 남긴다.
    final kept = CadenceCalculator.trimmed(_stepSamples);
    if (kept.length != _stepSamples.length) {
      _stepSamples
        ..clear()
        ..addAll(kept);
    }

    // 화면은 1초 티커가 갱신한다. 여기서 상태를 바꾸면 걸음이 몰려 올 때
    // 초당 여러 번 다시 그리게 된다.
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
      // 준비하며 서성인 걸음도 마찬가지다.
      _stepSamples.clear();

      state = RunRunning(_metrics());
      _startTicker();
    }
  }

  void pause() {
    if (state is! RunRunning) return;

    _accumulated = _elapsed();
    _resumedAt = null;
    _stopTicker();

    // ⚠️ **여기서 접지 않는다.** [track]이 이미 [_points]를 마지막 구간으로
    // 내보내므로, 여기서 [_segments]에도 넣으면 **같은 좌표가 두 벌이 된다.**
    // 멈춘 채로 끝내면 구간·거리가 통째로 두 배가 되어 나왔다.
    // 접는 것은 [resume]이 비우기 직전에 한다.

    state = RunPaused(_metrics());
  }

  void resume() {
    if (state is! RunPaused) return;

    _resumedAt = _now();

    // 여기까지가 한 구간이다. **비우기 직전에** 접는다 — 멈춰 있는 동안에는
    // [track]이 [_points]를 그대로 내보내므로 접어 두면 중복이 된다.
    if (_points.length > 1) _segments.add(List.of(_points));

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
        // 진행 방향. **센서 값을 믿을 수 없어 직접 낸다**(`GeoPoint.bearingTo`).
        if (_points.isNotEmpty) {
          _distanceMeters += _points.last.distanceTo(point);
        }
        final heading = _headingAt(point);
        _points.add(point);
        final metrics = _metrics();
        state = RunRunning(metrics);

        // ⚠️ **기다리지 않는다.** DB 쓰기가 느려도 화면과 거리 계산이 멈추면
        // 안 된다. 실패해도 러닝은 계속된다 — 좌표 하나 때문에 달리기를
        // 멈출 이유가 없다.
        unawaited(
          ref
              .read(trackRecorderProvider)
              .add(
                point,
                currentPace: metrics.currentPace,
                headingDegrees: heading,
                // ⚠️ 칼로리와 달리 **케이던스는 서버로 간다.** 페이로드에
                // 자리가 있고, 저장 시점에 박아 둬야 재전송이 읽어서
                // 보내기로 끝난다(설계 문서 6절).
                cadenceSpm: metrics.cadenceSpm,
              )
              .catchError((Object error) {
                debugPrint('[track] 좌표를 쌓지 못했다 · $error');
              }),
        );

      // 일시정지·종료·대기 중에 들어온 좌표는 버린다.
      case RunPreparing() || RunPaused() || RunFinished() || RunIdle():
        break;
    }
  }

  /// [point]의 진행 방향. 낼 수 없으면 `null`이다.
  ///
  /// [_headingMinMeters] 이상 떨어진 **가장 최근** 좌표를 찾아 거기서 낸다.
  /// 가장 최근 것을 쓰므로 조건을 만족하는 가장 짧은 창이 되고, 방향이
  /// 지나간 것이 되지 않는다.
  ///
  /// 러닝 시작 직후나 제자리에 서 있을 때는 `null`이다. 그때는 "모른다"로
  /// 남겨 전송 계층이 0으로 눌러 보낸다.
  double? _headingAt(GeoPoint point) {
    final oldest = _points.length - _headingLookback;
    for (var i = _points.length - 1; i >= 0 && i >= oldest; i--) {
      if (_points[i].distanceTo(point) >= _headingMinMeters) {
        return _points[i].bearingTo(point);
      }
    }
    return null;
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

  RunMetrics _metrics() {
    final elapsed = _elapsed();
    return RunMetrics(
      distanceMeters: _distanceMeters,
      elapsed: elapsed,
      currentPace: PaceCalculator.recent(_points),
      // ⚠️ **화면 표시용이다.** 서버가 종료 시 확정하는 칼로리와 다를 수 있다.
      // 몸무게를 모르면 `null`이고, 화면은 그것을 `--`로 그린다.
      calories: CalorieCalculator.burned(
        meters: _distanceMeters,
        elapsed: elapsed,
        weightKg: ref.read(bodyProfileProvider).weightKg,
      ),
      // 걸음 센서가 없거나 권한이 없으면 `null`이다. 화면은 `--`로 그린다.
      cadenceSpm: CadenceCalculator.recent(_stepSamples),
    );
  }

  /// 바깥으로 나가는 것을 끊는다. 상태는 건드리지 않는다.
  void _teardown() {
    _stopTicker();
    _subscription?.cancel();
    _subscription = null;
    // 이걸 빠뜨리면 러닝이 끝나도 걸음 센서가 계속 돈다.
    _steps?.cancel();
    _steps = null;
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
