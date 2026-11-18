import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/analytics/run_outcome.dart';

/// `run_finish.run_outcome` 판정. 완주율 차트가 이 값 하나로 그려진다.
void main() {
  RunOutcome judge(int? target, int? distance) =>
      RunOutcome.judge(targetMeters: target, distanceMeters: distance);

  test('목표와 같으면 완주다 — 경계는 완주 쪽에 둔다', () {
    expect(judge(5000, 5000), RunOutcome.completed);
  });

  test('목표를 넘으면 완주다', () {
    expect(judge(5000, 5020), RunOutcome.completed);
  });

  test('1m라도 모자라면 미완주다', () {
    expect(judge(5000, 4999), RunOutcome.incomplete);
  });

  test('목표가 없는 방은 가릴 수 없다', () {
    expect(judge(null, 3000), RunOutcome.unknown);
    // 0을 목표로 읽으면 모든 러닝이 완주가 된다.
    expect(judge(0, 3000), RunOutcome.unknown);
  });

  test('거리를 못 읽으면 미완주가 아니라 모름이다', () {
    // 기록 없는 참가자는 17번이 `totalDistanceMeters: null`을 준다.
    expect(judge(5000, null), RunOutcome.unknown);
  });
}
