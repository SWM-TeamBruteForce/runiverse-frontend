import 'package:runiverse/features/session/domain/combo_milestone.dart';
import 'package:runiverse/features/session/domain/party_board.dart';
import 'package:runiverse/features/session/domain/party_color.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/domain/runner_status.dart';
import 'package:runiverse/features/session/domain/running_room.dart';
import 'package:runiverse/features/session/domain/user_status.dart';

/// 폰이 워치에 보내는 값을 만든다. 모양은 워치 레포 `docs/phone-communication.md`
/// 「상태」가 정본이라, 필드를 바꾸면 그 문서와 워치 앱을 함께 고친다.
///
/// 모르는 값은 폰 화면이 그 자리에 그리는 값으로 보낸다 — 워치는 받은 대로 그려
/// 폰과 같아진다. `null` 은 대신 보낼 값이 없을 때만 쓴다(방 번호, 못 잰 페이스).
abstract final class WatchPayload {
  const WatchPayload._();

  /// `WATCH_STATE_UPDATED` 의 data.
  ///
  /// [room] 이 `null` 이면 방이 아직 안 세워진 것이다 — 출발은 방을 기다리지 않는다.
  /// [lastRequestId] 는 마지막으로 처리한 워치 명령, [finishing] 은 종료 답을 기다리는
  /// 중인가, [goalPendingMeters] 는 서버가 종료를 미뤘을 때 남은 거리, [result] 는
  /// 끝난 결과 숫자의 출처, [unknownNickname] 은 이름을 모르는 파티원에게 폰이 붙이는
  /// 문구다.
  static Map<String, Object?> state({
    required String phoneInstanceId,
    required int stateSequence,
    required int statusVersion,
    required String? lastRequestId,
    required RunSessionState session,
    required RunningRoom? room,
    required PartyBoard board,
    required bool isServerConnected,
    required bool finishing,
    required int? goalPendingMeters,
    required WatchResult result,
    required String unknownNickname,
    required DateTime now,
  }) => {
    'phoneInstanceId': phoneInstanceId,
    'stateSequence': stateSequence,
    'statusVersion': statusVersion,
    'lastRequestId': lastRequestId,
    'run': _run(
      session,
      room: room,
      board: board,
      isServerConnected: isServerConnected,
      finishing: finishing,
      goalPendingMeters: goalPendingMeters,
      result: result,
      unknownNickname: unknownNickname,
      now: now,
    ),
  };

  /// `WATCH_SYNCED` 의 data. 상태에 [syncId]·생일·사진을 더한다. 사진은 아직 비운다.
  static Map<String, Object?> synced(
    Map<String, Object?> state, {
    required String syncId,
    required DateTime? birthday,
  }) => {
    ...state,
    'syncId': syncId,
    // 기기에 저장할 때와 같은 모양(`yyyy-MM-dd`)이다.
    'birthday': birthday?.toIso8601String().split('T').first,
    'photos': const <Object>[],
  };

  /// 콤보 목록이 [before] 에서 [after] 로 바뀌며 생긴 순간들. 보낼 때 `eventId` 를 붙인다.
  ///
  /// 기준은 폰 진동(`PartyController`)과 같다. 폰은 한 통지에 한 번 울리지만 워치는
  /// 그 사람 사진을 띄우므로 사람마다 알린다.
  static List<({String userId, int comboCount, WatchComboKind kind})>
  comboMoments({
    required Map<String, ComboPeer> before,
    required Map<String, ComboPeer> after,
  }) => [
    for (final userId in before.keys)
      if (!after.containsKey(userId))
        (userId: userId, comboCount: 0, kind: WatchComboKind.broken),
    for (final MapEntry(key: userId, value: peer) in after.entries)
      if (comboMilestonePassed(
        before: before[userId]?.comboCount ?? 0,
        after: peer.comboCount,
      ))
        (
          userId: userId,
          comboCount: peer.comboCount,
          kind: WatchComboKind.milestone,
        )
      // 처음 붙은 상대는 0으로 온다. -1과 견줘야 "올랐다"가 된다.
      else if (peer.comboCount > (before[userId]?.comboCount ?? -1))
        (
          userId: userId,
          comboCount: peer.comboCount,
          kind: WatchComboKind.tick,
        ),
  ];

  static Map<String, Object?>? _run(
    RunSessionState session, {
    required RunningRoom? room,
    required PartyBoard board,
    required bool isServerConnected,
    required bool finishing,
    required int? goalPendingMeters,
    required WatchResult result,
    required String unknownNickname,
    required DateTime now,
  }) {
    final (metrics, status) = switch (session) {
      RunRunning(:final metrics) => (metrics, 'RUNNING'),
      RunPaused(:final metrics) => (metrics, 'PAUSED'),
      RunFinished(:final metrics) => (metrics, 'FINISHED'),
      // 출발 전에는 보일 러닝이 없다.
      RunIdle() || RunPreparing() => (null, null),
    };
    if (metrics == null) return null;

    final rows = board.rows;
    final finished = session is RunFinished;
    // 버린다 — 완주 전에 5.00km가 뜨지 않게, 폰 화면과 같다.
    final distance = metrics.distanceMeters.floor();
    // 러닝 화면 `_targetDistanceMeters` 와 같은 순서(방, 없으면 파티원 통지).
    final target =
        room?.targetDistanceMeters ??
        rows
            .map((row) => row.progress?.targetDistanceMeters)
            .firstWhere((value) => value != null, orElse: () => null);

    return {
      'runningRoomId': room?.id,
      'type': _type(room, rows),
      'status': status,
      'targetDistanceMeters': target,
      'isServerConnected': isServerConnected,
      // 러닝 화면이 매칭 제한 안내를 띄우는 조건과 같다 — 목표가 있고, 제한 방(모르면
      // 제한 방으로 본다). 방이 안 세워진 솔로는 목표가 없어 거짓이다.
      'isPenaltyApplicable': target != null && (room?.canPenalize ?? true),
      'me': {
        'distanceMeters': distance,
        'elapsedSeconds': metrics.elapsed.inSeconds,
        'currentPaceSecondsPerKm': metrics.currentPace?.inSeconds,
        'caloriesKcal': metrics.calories,
        'cadenceSpm': metrics.cadenceSpm,
      },
      'players': [
        for (final row in rows)
          {
            'userId': row.userId,
            'nickname': row.member?.nickname ?? unknownNickname,
            // 폰 팔레트처럼 색 수로 나눈 나머지다(`RunPaletteV2.lane`) — 내 번호를 몰라
            // 파티원이 넷으로 잡혀도 워치가 색 목록 밖을 가리키지 않는다.
            'colorSlot': board.colorSlotOf(row.userId) % partyColorSlots,
            // 통지 전 값은 폰 파티원 화면과 같다 — 거리 0, 달리는 중.
            'distanceMeters': row.progress?.distanceMeters ?? 0,
            'currentPaceSecondsPerKm': row.progress?.currentPaceSecondsPerKm,
            'status': switch (row.progress?.status ?? RunnerStatus.running) {
              RunnerStatus.running => 'RUNNING',
              RunnerStatus.paused => 'PAUSED',
              RunnerStatus.disconnected => 'DISCONNECTED',
              RunnerStatus.finished => 'FINISHED',
            },
            'gapMeters': row.gapMeters,
            'comboCount': row.combo?.comboCount ?? 0,
            'maxComboCount': board.bestComboOf(row.userId),
            'isStale': _stale(row, now),
          },
      ],
      'finish': switch ((finished, finishing, goalPendingMeters)) {
        (true, _, _) => null,
        (false, true, _) => {'stage': 'FINISHING'},
        (false, false, final int meters) => {
          'stage': 'GOAL_PENDING',
          'remainingMeters': meters,
        },
        (false, false, null) => null,
      },
      'result': finished
          ? switch (result) {
              WatchResultConfirmed() => {
                'isServerConfirmed': true,
                'totalDistanceMeters': result.distanceMeters,
                'averagePaceSecondsPerKm': result.averagePace?.inSeconds,
                'elapsedSeconds': result.duration.inSeconds,
              },
              // 폰 요약이 `--` 를 띄우는 동안이다.
              WatchResultLoading() => null,
              WatchResultMeasured() => {
                'isServerConfirmed': false,
                'totalDistanceMeters': distance,
                'averagePaceSecondsPerKm': metrics.averagePace?.inSeconds,
                'elapsedSeconds': metrics.elapsed.inSeconds,
              },
            }
          : null,
    };
  }

  /// 방이 아직 안 세워졌으면 폰 러닝 화면처럼 명단으로 가른다(`hasParty`) — 매칭도
  /// 출발 직후엔 방이 없고, 명단은 출발 전에 들어와 있다. 솔로는 종류가 비어 올 수
  /// 있어 매칭 여부를 먼저 본다.
  static String _type(RunningRoom? room, List<PartyRow> rows) {
    if (room == null) return rows.isEmpty ? 'SOLO' : 'MATCH';
    if (!room.isMatched || room.type == RoomType.solo) return 'SOLO';
    if (room.type == RoomType.invite) return 'INVITE';
    return 'MATCH';
  }

  /// 폰 파티원 화면이 그 사람 카드를 흐리게 그리는 기준과 같다(`RunPartyView._stale`).
  static bool _stale(PartyRow row, DateTime now) {
    final at = row.progress?.receivedAt;
    return at != null && now.difference(at) > PartyBoard.staleAfter;
  }
}

/// `WATCH_COMBO_TRIGGERED` 의 `kind`.
enum WatchComboKind {
  /// 1 올랐다.
  tick,

  /// 눈금(1·3·5·10·20…)에 닿았다.
  milestone,

  /// 끊겼다.
  broken;

  String get wire => switch (this) {
    tick => 'TICK',
    milestone => 'MILESTONE',
    broken => 'BREAK',
  };
}

/// 끝난 결과 숫자의 출처. 폰 요약(S15)과 같다 — 서버 기록, 받는 중, 폰이 잰 값.
sealed class WatchResult {
  const WatchResult();
}

/// 서버 기록이 없다(종료 확인 실패·조회 실패·내 기록 없음). 폰이 잰 값을 쓴다.
final class WatchResultMeasured extends WatchResult {
  const WatchResultMeasured();
}

/// 서버 기록을 받는 중이다.
final class WatchResultLoading extends WatchResult {
  const WatchResultLoading();
}

/// 서버가 확정한 내 기록.
final class WatchResultConfirmed extends WatchResult {
  const WatchResultConfirmed({
    required this.distanceMeters,
    required this.duration,
    this.averagePace,
  });

  final int distanceMeters;

  /// 움직인 시간. 멈춘 구간을 서버가 뺐다.
  final Duration duration;

  final Duration? averagePace;
}
