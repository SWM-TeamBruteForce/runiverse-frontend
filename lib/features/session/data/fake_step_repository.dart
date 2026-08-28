import 'dart:async';

import 'package:runiverse/features/session/domain/step_repository.dart';

/// 걸음 센서 없이 케이던스를 돌려보기 위한 가짜.
///
/// **에뮬레이터에는 걸음 센서가 없다.** 그리고 위젯 테스트는 플랫폼 채널을
/// 부를 수 없다. 손으로 표본을 먹인다.
class FakeStepRepository implements StepRepository {
  FakeStepRepository({this.granted = true});

  /// 권한을 줄 것인가. 거절했을 때 케이던스가 `--`로 남는지 보는 데 쓴다.
  final bool granted;

  final _controller = StreamController<StepSample>.broadcast();

  /// [ensureAccess]가 몇 번 불렸나. 러닝마다 한 번이어야 한다.
  var accessCalls = 0;

  @override
  Future<bool> ensureAccess() async {
    accessCalls++;
    return granted;
  }

  @override
  Stream<StepSample> watchSteps() => _controller.stream;

  /// 센서가 값을 준 척한다.
  void emit(int steps, DateTime at) =>
      _controller.add(StepSample(steps: steps, at: at));

  Future<void> dispose() => _controller.close();
}
