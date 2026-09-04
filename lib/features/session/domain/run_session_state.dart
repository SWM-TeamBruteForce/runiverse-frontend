import 'package:runiverse/features/session/domain/location_repository.dart';
import 'package:runiverse/features/session/domain/run_metrics.dart';

/// 1인 러닝 세션의 상태.
///
/// 화면은 이 다섯 중 무엇인지로 갈린다. `bool isRunning`과 `bool isPaused`를
/// 따로 들면 "달리는 중이면서 일시정지"라는 없는 상태가 표현된다.
///
/// freezed 대신 Dart 3의 `sealed`를 쓴다. 상태가 다섯뿐이라
/// `build_runner` 파이프라인을 통째로 들이는 비용이 더 크다고 봤다
/// (인증에서 `AuthState`를 만들 때와 같은 판단).
sealed class RunSessionState {
  const RunSessionState();
}

/// 아무것도 시작하지 않았다. 홈에서 들어오기 전.
class RunIdle extends RunSessionState {
  const RunIdle();
}

/// 출발 준비 — GPS 첫 신호를 기다린다.
///
/// 신호를 잡기 전에 출발하면 초반 거리가 통째로 빠진다.
/// 그래서 [hasFix]가 `false`인 동안 시작 버튼을 잠근다.
class RunPreparing extends RunSessionState {
  const RunPreparing({this.hasFix = false, this.failure});

  /// 쓸 만한 좌표를 한 번이라도 받았는가.
  final bool hasFix;

  /// 구독을 연 **뒤에** 위치를 못 쓰게 된 이유. `null`이면 아직 기다리는 중이다.
  ///
  /// ⚠️ **권한 확인을 통과해도 스트림이 뒤늦게 실패한다.** `ensureAccess`는
  /// `isLocationServiceEnabled`가 `true`라고 답했는데, 그다음 열린 스트림이
  /// `LocationServiceDisabledException`을 던지는 일이 실제로 있다(안드로이드
  /// 에뮬레이터에서 재현). 이 값이 없으면 화면은 실패를 "아직 신호를 못 잡음"과
  /// 구분하지 못해 **영원히 기다린다.**
  final LocationAccess? failure;
}

/// 달리는 중.
class RunRunning extends RunSessionState {
  const RunRunning(this.metrics);

  final RunMetrics metrics;
}

/// 일시정지.
///
/// 이 동안 **시간도 거리도 늘지 않는다.** 들어온 좌표는 버린다.
class RunPaused extends RunSessionState {
  const RunPaused(this.metrics);

  final RunMetrics metrics;
}

/// 끝났다. 요약 화면이 이 값을 읽는다.
class RunFinished extends RunSessionState {
  const RunFinished({
    required this.metrics,
    required this.startedAt,
    required this.endedAt,
  });

  final RunMetrics metrics;

  /// 출발 시각. 일시정지를 포함한 벽시계 구간이다.
  final DateTime startedAt;
  final DateTime endedAt;
}
