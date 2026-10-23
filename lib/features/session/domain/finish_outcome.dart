/// `RUNNING_FINISH` 를 보낸 뒤 돌아온 답.
///
/// ## ⚠️ 예전에는 `bool` 이었다
///
/// `true` 는 종료 확인, `false` 는 "못 받았다"였다. 1.1.0 서버가 **세 번째
/// 답**을 보낸다 — `RUNNING_GOAL_PENDING`. 서버가 확정한 거리가 목표에
/// 모자라다는 뜻이고, **러닝은 끝나지 않았다.**
///
/// `bool` 로 두면 그것이 [unconfirmed] 와 섞인다. 둘은 정반대로 다뤄야 한다 —
/// 못 받았을 때는 요약으로 보내고, 모자랄 때는 **화면에 남겨 계속 뛰게** 한다.
sealed class FinishOutcome {
  const FinishOutcome();
}

/// 종료가 확정됐다(`RUNNING_FINISHED`).
///
/// **로컬 트랙을 지워도 되는 유일한 근거다.**
final class FinishConfirmed extends FinishOutcome {
  const FinishConfirmed();
}

/// 서버가 확정한 거리가 목표에 모자라다(`RUNNING_GOAL_PENDING`).
///
/// ⚠️ **종료 정리를 하지 않는다.** 좌표 수집·전송과 로컬 트랙을 그대로 두고
/// 러닝을 이어 간다(1.1.0 가이드 3.2).
///
/// ⚠️ **종료를 요청한 본인에게만 온다.** 참가자 상태는 바뀌지 않고 다른
/// 참가자에게도 전달되지 않는다.
final class FinishGoalPending extends FinishOutcome {
  const FinishGoalPending(this.remainingMeters);

  /// 서버 기준으로 목표까지 남은 거리(m).
  ///
  /// ⚠️ **서버가 계산한 시점의 값이다.** 받은 뒤의 로컬 이동량을 빼서 보일
  /// 때는 추정값이라고 말하고 **0 미만으로 내리지 않는다**(가이드 3.3).
  final int remainingMeters;
}

/// 답을 못 받았다. 타임아웃이거나 소켓에 넘기지 못했다.
///
/// ⚠️ **로컬 트랙을 남긴다.** 지우는 것보다 남기는 쪽이 되돌릴 수 있다.
final class FinishUnconfirmed extends FinishOutcome {
  const FinishUnconfirmed();
}
