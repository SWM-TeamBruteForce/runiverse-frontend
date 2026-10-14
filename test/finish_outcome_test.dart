import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/domain/finish_outcome.dart';

/// 종료 요청의 답이 **셋으로 갈린다.**
///
/// ## ⚠️ `bool` 로는 둘이 섞였다
///
/// 1.1.0 서버가 `RUNNING_GOAL_PENDING` 을 보낸다 — 확정 거리가 목표에
/// 모자라다는 뜻이고 **러닝은 끝나지 않았다.** `false`(못 받았다)와 같은
/// 값으로 두면 정반대로 다뤄야 할 둘이 한 갈래가 된다.
void main() {
  test('⚠️ 세 답을 switch 가 빠짐없이 가른다', () {
    // sealed 라 갈래를 빠뜨리면 컴파일러가 잡는다. 이 테스트는 **셋이 서로
    // 다른 타입**이라는 것을 고정한다 — 하나로 합치려는 수정을 막는다.
    String name(FinishOutcome outcome) => switch (outcome) {
      FinishConfirmed() => '확정',
      FinishGoalPending() => '모자람',
      FinishUnconfirmed() => '못 받음',
    };

    expect(name(const FinishConfirmed()), '확정');
    expect(name(const FinishGoalPending(40)), '모자람');
    expect(name(const FinishUnconfirmed()), '못 받음');
  });

  test('남은 거리를 들고 온다', () {
    expect(const FinishGoalPending(40).remainingMeters, 40);
  });
}
