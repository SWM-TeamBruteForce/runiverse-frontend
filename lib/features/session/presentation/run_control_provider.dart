import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/features/session/domain/finish_outcome.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';

final runControlProvider =
    NotifierProvider<RunControlController, RunControlState>(
      RunControlController.new,
    );

/// 일시정지·종료 조작의 진행 상태. 러닝 화면이 이 값을 보고 그린다.
final class RunControlState {
  const RunControlState({
    this.finishing = false,
    this.goalPendingMeters,
    this.rejected,
  });

  /// 종료를 보내고 서버 답을 기다리는 중인가. 목표 도달과 중지가 겹쳐 두 번
  /// 보내는 것을 막는다.
  final bool finishing;

  /// 서버가 종료를 미뤘다. 서버 기준 남은 거리(m)이고, 고를 때까지 남는다.
  final int? goalPendingMeters;

  /// 서버가 종료를 거절했다. 다음 종료를 보낼 때 비운다.
  final WsErrorCode? rejected;
}

/// 폰 버튼과 워치 명령이 같이 타는 조작의 길.
///
/// 화면에 두면 워치 명령이 같은 길을 탈 수 없어 앱이 켜져 있는 동안 산다. 러닝
/// 화면은 이 상태를 보고 로딩 원·보류 창·거절 알림·요약 이동만 맡는다.
class RunControlController extends Notifier<RunControlState> {
  @override
  RunControlState build() {
    // 앱이 켜져 있는 동안 살아서, 안 비우면 값이 다음 러닝에 남는다.
    ref.listen(runSessionControllerProvider, (_, next) {
      if (!_isRunning(next)) state = const RunControlState();
    });
    return const RunControlState();
  }

  /// 멈춘다. **되돌릴 수 있는 것이라 길게 누르지 않는다.**
  ///
  /// ## ⚠️ 서버에도 알린다
  ///
  /// 1.1.0 전까지 일시정지는 **이 화면 안에만 있었다.** 상대 화면에서는 내가
  /// 계속 달리는 것으로 보였고, 서버는 멈춘 구간을 알 길이 없었다(가이드 2.1).
  ///
  /// 순서가 양쪽으로 다르다.
  ///
  /// - **멈출 때는 세션이 먼저다.** 세션이 멈춰야 들어오는 좌표를 버리고,
  ///   그래야 [RunningConnectionController.pause] 가 **다 흘려보낸 뒤** 알릴
  ///   수 있다. 거꾸로 하면 `PAUSE` 뒤에 좌표가 닿아 서버가 일시정지를 푼다.
  /// - **다시 갈 때는 알리는 것이 먼저다.** 좌표만으로도 서버는 돌아오지만
  ///   배치까지 최대 10초가 걸린다 — 그동안 상대 화면에는 멈춰 보인다.
  void pause() {
    if (ref.read(runSessionControllerProvider) is! RunRunning) return;
    if (state.finishing) return;
    ref.read(runSessionControllerProvider.notifier).pause();
    unawaited(ref.read(runningConnectionProvider.notifier).pause());
  }

  /// 다시 간다. 순서는 [pause] 참조.
  void resume() {
    if (ref.read(runSessionControllerProvider) is! RunPaused) return;
    if (state.finishing) return;
    ref.read(runningConnectionProvider.notifier).resume();
    ref.read(runSessionControllerProvider.notifier).resume();
  }

  /// 러닝을 끝낸다. **손으로 멈출 때와 목표에 닿을 때가 같은 길이다.**
  ///
  /// ## 순서가 명세로 정해져 있다
  ///
  /// `RUNNING_FINISH` → `RUNNING_FINISHED` ack → 로컬 트랙 삭제 → 결과 조회.
  /// 앞의 셋은 [RunningConnectionController.finish]가 맡고, 결과 조회는 요약
  /// 화면이 [RunningConnectionState.settling]이 풀린 뒤에만 연다.
  ///
  /// ## ⚠️ 이제 답을 기다린다
  ///
  /// 예전에는 요청만 던지고 **곧바로** 요약으로 넘어갔다. 1.1.0 서버는
  /// `RUNNING_GOAL_PENDING` 으로 **"확정 거리가 모자라다"** 고 답할 수 있는데,
  /// 그때는 러닝이 끝나지 않는다 — 먼저 넘어가 버리면 **러닝이 뒤에서 계속
  /// 도는 채로 요약 화면이 뜬다.**
  ///
  /// 기다리는 시간은 채널의 ack 타임아웃(15초)이 윗선이다. 못 받으면
  /// [FinishUnconfirmed] 로 떨어져 예전처럼 요약으로 간다 — 신호가 나쁜 곳에서
  /// 요약조차 못 보는 일은 그대로 막는다.
  Future<void> finish({required bool forced}) async {
    if (state.finishing) return;
    if (!_isRunning(ref.read(runSessionControllerProvider))) return;
    // 서버 종료·구간 거부가 이미 끝내는 중이다. 또 보내면 채널이 먼저 보낸 쪽의
    // 답 기다리기를 덮어써, 그쪽이 타임아웃까지 매달린다.
    if (ref.read(runningConnectionProvider).settling) return;

    state = const RunControlState(finishing: true);

    final FinishOutcome outcome;
    try {
      // 끝나면 소켓도 함께 닫힌다 — 안 닫으면 다음 러닝에서 서버가 중복 연결로
      // 보고 이쪽을 4001로 끊는다.
      outcome = await ref
          .read(runningConnectionProvider.notifier)
          .finish(forced: forced);
    } on Object catch (error) {
      // 못 받은 것과 같다. 안 풀면 로딩 원에 갇힌다.
      debugPrint('[running] 종료 정리가 어긋났다 · $error');
      _foldSession();
      return;
    }

    // 기다리는 사이 강퇴·서버 종료로 세션을 이미 비웠다.
    if (!_isRunning(ref.read(runSessionControllerProvider))) return;

    switch (outcome) {
      // ⚠️ **러닝이 이어진다.** 세션을 접지도, 화면을 옮기지도 않는다.
      case FinishGoalPending(:final remainingMeters):
        state = RunControlState(goalPendingMeters: remainingMeters);
      // ⚠️ **러닝이 이어진다.** 서버가 종료를 거절했다 — 알리고 다시 누르게 한다.
      case FinishRejected(:final code):
        state = RunControlState(rejected: code);
      case FinishConfirmed() || FinishUnconfirmed():
        _foldSession();
    }
  }

  /// 보류 창에서 `계속 달리기` 를 골랐다.
  void keepRunning() {
    if (state.finishing) return;
    state = const RunControlState();
  }

  /// ⚠️ **세션은 여기서 접는다.** 보류일 수 있으므로 답을 받기 전에 접으면
  /// 멀쩡한 러닝의 시계가 멈춘다. 접히면 [build] 의 듣기가 상태를 비운다.
  void _foldSession() =>
      ref.read(runSessionControllerProvider.notifier).finish();

  static bool _isRunning(RunSessionState session) =>
      session is RunRunning || session is RunPaused;
}
