import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/domain/party_board.dart';
import 'package:runiverse/features/session/domain/run_metrics.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/domain/runner_status.dart';
import 'package:runiverse/features/session/domain/running_room.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/domain/watch_payload.dart';

/// 폰이 워치에 보내는 값 한 벌.
///
/// 모양은 워치 레포 `docs/phone-communication.md` 「상태」가 정본이다. 워치는
/// 이 값을 그대로 그리므로, 폰 화면과 다른 값이 실리면 두 화면이 다른 말을 한다.
void main() {
  final now = DateTime(2026, 11, 4, 9);

  const metrics = RunMetrics(
    distanceMeters: 3421.9,
    elapsed: Duration(minutes: 24, seconds: 10),
    currentPace: Duration(minutes: 5, seconds: 32),
    calories: 210,
    cadenceSpm: 172,
  );

  const matched = RunningRoom(
    812,
    targetDistanceMeters: 5000,
    isMatched: true,
    type: RoomType.match,
    playerCount: 2,
  );

  const members = [
    PartyMember(userId: 'me', nickname: '나'),
    PartyMember(userId: 'u-1', nickname: '콩나물'),
  ];

  Map<String, Object?> stateOf(
    RunSessionState session, {
    RunningRoom? room = matched,
    PartyBoard board = const PartyBoard(),
    bool finishing = false,
    int? goalPendingMeters,
    String? lastRequestId,
    WatchResult result = const WatchResultMeasured(),
  }) => WatchPayload.state(
    phoneInstanceId: '3f2a9c1e',
    stateSequence: 7,
    statusVersion: 2,
    lastRequestId: lastRequestId,
    session: session,
    room: room,
    board: board,
    isServerConnected: true,
    finishing: finishing,
    goalPendingMeters: goalPendingMeters,
    result: result,
    unknownNickname: '함께 달리는 사람',
    now: now,
  );

  Map<String, Object?> runOf(Map<String, Object?> state) =>
      state['run']! as Map<String, Object?>;

  test('출발 전에는 러닝이 없다', () {
    expect(stateOf(const RunIdle())['run'], isNull);
    expect(stateOf(const RunPreparing(hasFix: true))['run'], isNull);
  });

  test('내 값은 폰 화면 값 그대로, 거리는 버린다', () {
    final run = runOf(stateOf(const RunRunning(metrics)));

    expect(run['runningRoomId'], 812);
    expect(run['type'], 'MATCH');
    expect(run['status'], 'RUNNING');
    expect(run['targetDistanceMeters'], 5000);
    expect(run['isPenaltyApplicable'], isTrue);
    // 완주 전에 반올림으로 올라가면 워치가 폰보다 먼저 목표에 닿는다.
    expect(run['me'], {
      'distanceMeters': 3421,
      'elapsedSeconds': 1450,
      'currentPaceSecondsPerKm': 332,
      'caloriesKcal': 210,
      'cadenceSpm': 172,
    });
    expect(run['finish'], isNull);
    expect(run['result'], isNull);
  });

  test('⚠️ 러닝 중 시간은 경과 시간, 결과는 움직인 시간', () {
    // 서 있던 시간이 둘을 가른다. 같은 값으로 시험하면 바뀐 쪽을 못 잡는다.
    const split = RunMetrics(
      distanceMeters: 3421.9,
      elapsed: Duration(seconds: 20),
      clockElapsed: Duration(seconds: 50),
    );

    final running = runOf(stateOf(const RunRunning(split)));
    expect((running['me']! as Map)['elapsedSeconds'], 50);

    final finished = runOf(
      stateOf(RunFinished(metrics: split, startedAt: now, endedAt: now)),
    );
    expect((finished['result']! as Map)['elapsedSeconds'], 20);
  });

  test('폰 시각이 출발 전으로 돌아가 경과 시간이 음수면 0을 보낸다', () {
    const rewound = RunMetrics(
      distanceMeters: 3421.9,
      elapsed: Duration.zero,
      clockElapsed: Duration(minutes: -57),
    );

    final running = runOf(stateOf(const RunRunning(rewound)));
    expect((running['me']! as Map)['elapsedSeconds'], 0);
  });

  test('파티원은 나를 빼고 색 번호·격차·콤보를 싣는다', () {
    final board = const PartyBoard()
        .withRoster(members, myUserId: 'me')
        .withMyDistance(3421)
        .withProgress(
          RunProgress(
            userId: 'u-1',
            distanceMeters: 3541,
            targetDistanceMeters: 5000,
            currentPaceSecondsPerKm: 318,
            receivedAt: now.subtract(const Duration(seconds: 3)),
          ),
        )
        .withCombos(
          const RunCombo([
            ComboPeer(
              userId: 'u-1',
              gapMeters: 120,
              comboCount: 12,
              maxComboCount: 20,
            ),
          ]),
        );

    final run = runOf(stateOf(const RunRunning(metrics), board: board));

    expect(run['players'], [
      {
        'userId': 'u-1',
        'nickname': '콩나물',
        'colorSlot': 1,
        'distanceMeters': 3541,
        'currentPaceSecondsPerKm': 318,
        'status': 'RUNNING',
        'gapMeters': 120,
        'comboCount': 12,
        'maxComboCount': 20,
        'isStale': false,
      },
    ]);
  });

  test('통지가 아직 없는 파티원은 폰 화면이 그리는 값으로 보낸다', () {
    // 출발 직후 첫 통지(최대 10초) 전이다. 폰도 0m·달리는 중으로 그린다.
    final board = const PartyBoard().withRoster(members, myUserId: 'me');

    final run = runOf(stateOf(const RunRunning(metrics), board: board));
    final player = (run['players']! as List).single as Map;

    expect(player['distanceMeters'], 0);
    expect(player['status'], 'RUNNING');
    // 격차는 폰도 비워 둔다. 대신 그릴 숫자가 없다.
    expect(player['gapMeters'], isNull);
    expect(player['comboCount'], 0);
    expect(player['isStale'], isFalse);
  });

  test('색 번호는 폰 팔레트처럼 0~3 안에 있다', () {
    // 내 번호를 모르면 내 진행 통지가 낯선 파티원으로 하나 더 잡혀 넷이 된다.
    final board = const PartyBoard()
        .withRoster(const [
          PartyMember(userId: 'u-1', nickname: '콩나물'),
          PartyMember(userId: 'u-2', nickname: '두부'),
          PartyMember(userId: 'u-3', nickname: '숙주'),
        ])
        .withProgress(const RunProgress(userId: 'me', distanceMeters: 10));

    final run = runOf(stateOf(const RunRunning(metrics), board: board));

    // 넷째는 폰 화면처럼 0번(파랑)으로 감긴다.
    expect(
      [
        for (final player in run['players']! as List)
          (player as Map)['colorSlot'],
      ],
      [1, 2, 3, 0],
    );
  });

  test('파티원 상태를 워치가 읽는 값으로 옮긴다', () {
    // 워치는 모르는 값이 든 메시지를 통째로 버린다.
    const wire = {
      RunnerStatus.running: 'RUNNING',
      RunnerStatus.paused: 'PAUSED',
      RunnerStatus.disconnected: 'DISCONNECTED',
      RunnerStatus.finished: 'FINISHED',
    };

    wire.forEach((status, expected) {
      final board = const PartyBoard()
          .withRoster(members, myUserId: 'me')
          .withProgress(
            RunProgress(userId: 'u-1', distanceMeters: 10, status: status),
          );

      final run = runOf(stateOf(const RunRunning(metrics), board: board));
      final player = (run['players']! as List).single as Map;

      expect(player['status'], expected);
    });
  });

  test('방에 목표가 없으면 파티원 통지의 목표를 쓴다', () {
    // 러닝 화면과 같은 순서다. 앱을 다시 켜고 방이 세워지기 전 구간이다.
    final board = const PartyBoard()
        .withRoster(members, myUserId: 'me')
        .withProgress(
          const RunProgress(
            userId: 'u-1',
            distanceMeters: 10,
            targetDistanceMeters: 5000,
          ),
        );

    final run = runOf(
      stateOf(const RunRunning(metrics), room: null, board: board),
    );

    expect(run['targetDistanceMeters'], 5000);
    expect(run['isPenaltyApplicable'], isTrue);
  });

  test('이름을 모르면 폰 문구를 싣는다', () {
    // 앱을 다시 켜면 명단 없이 통지만 온다.
    final board = const PartyBoard()
        .withRoster(const [], myUserId: 'me')
        .withProgress(const RunProgress(userId: 'u-1', distanceMeters: 10));

    final run = runOf(stateOf(const RunRunning(metrics), board: board));
    final player = (run['players']! as List).single as Map;

    expect(player['nickname'], '함께 달리는 사람');
  });

  test('통지가 19초 넘게 끊긴 사람만 흐리게 한다', () {
    // 폰 파티원 화면처럼 사람마다 따로 본다. 한 사람이 끊겨도 다른 사람은 선명하다.
    final board = const PartyBoard()
        .withRoster(const [
          PartyMember(userId: 'me', nickname: '나'),
          PartyMember(userId: 'u-1', nickname: '콩나물'),
          PartyMember(userId: 'u-2', nickname: '두부'),
        ], myUserId: 'me')
        .withProgress(
          RunProgress(
            userId: 'u-1',
            distanceMeters: 10,
            receivedAt: now.subtract(const Duration(seconds: 20)),
          ),
        )
        .withProgress(
          RunProgress(
            userId: 'u-2',
            distanceMeters: 10,
            receivedAt: now.subtract(const Duration(seconds: 19)),
          ),
        );

    final run = runOf(stateOf(const RunRunning(metrics), board: board));

    expect(
      [
        for (final player in run['players']! as List)
          (player as Map)['isStale'],
      ],
      [true, false],
    );
  });

  test('방 종류를 가른다 — 솔로·초대·매칭', () {
    String? typeOf(RunningRoom room) =>
        runOf(stateOf(const RunRunning(metrics), room: room))['type']
            as String?;

    expect(typeOf(const RunningRoom(1)), 'SOLO');
    expect(
      typeOf(const RunningRoom(1, isMatched: true, type: RoomType.invite)),
      'INVITE',
    );
    // 옛 서버가 종류를 안 보내면 모른다. 매칭 방이면 매칭으로 본다.
    expect(typeOf(const RunningRoom(1, isMatched: true)), 'MATCH');
  });

  test('방이 안 세워졌고 명단이 없으면 솔로로 보낸다', () {
    // 솔로는 카운트다운 동안 방을 열고, 답을 기다리지 않고 출발한다.
    final run = runOf(stateOf(const RunRunning(metrics), room: null));

    expect(run['status'], 'RUNNING');
    expect(run['runningRoomId'], isNull);
    expect(run['type'], 'SOLO');
    // 목표가 없어 매칭 제한 안내를 띄우지 않는다 — 폰 러닝 화면과 같다.
    expect(run['isPenaltyApplicable'], isFalse);
  });

  test('방이 안 세워졌어도 명단이 있으면 매칭으로 보낸다', () {
    // 매칭도 출발 직후엔 방이 없다. 폰 러닝 화면도 명단을 보고 파티원 장을 띄운다.
    final board = const PartyBoard().withRoster(members, myUserId: 'me');

    final run = runOf(
      stateOf(const RunRunning(metrics), room: null, board: board),
    );

    expect(run['runningRoomId'], isNull);
    expect(run['type'], 'MATCH');
  });

  test('목표가 있는 방은 종류를 몰라도 매칭 제한 방으로 본다', () {
    // 옛 서버 응답으로 붙은 매칭 방은 종류·인원을 모를 수 있다. 모르면서 "제한 없다"고 하지 않는다.
    final run = runOf(
      stateOf(
        const RunRunning(metrics),
        room: const RunningRoom(
          812,
          targetDistanceMeters: 5000,
          isMatched: true,
        ),
      ),
    );

    expect(run['isPenaltyApplicable'], isTrue);
  });

  test('초대 방은 목표가 있어도 매칭 제한이 없다', () {
    final run = runOf(
      stateOf(
        const RunRunning(metrics),
        room: const RunningRoom(
          812,
          targetDistanceMeters: 5000,
          isMatched: true,
          type: RoomType.invite,
        ),
      ),
    );

    expect(run['isPenaltyApplicable'], isFalse);
  });

  test('종료 답을 기다리는 중이면 종료 단계를 싣는다', () {
    final run = runOf(stateOf(const RunPaused(metrics), finishing: true));

    expect(run['status'], 'PAUSED');
    expect(run['finish'], {'stage': 'FINISHING'});
  });

  test('보류 중이면 남은 거리를 싣는다', () {
    final run = runOf(
      stateOf(const RunRunning(metrics), goalPendingMeters: 420),
    );

    expect(run['finish'], {'stage': 'GOAL_PENDING', 'remainingMeters': 420});
  });

  test('다시 종료해 답을 기다리는 동안은 보류보다 종료 중이 먼저다', () {
    final run = runOf(
      stateOf(
        const RunRunning(metrics),
        finishing: true,
        goalPendingMeters: 420,
      ),
    );

    expect(run['finish'], {'stage': 'FINISHING'});
  });

  test('끝났으면 종료 단계를 싣지 않는다', () {
    final run = runOf(
      stateOf(
        RunFinished(
          metrics: metrics,
          startedAt: DateTime(2026, 11, 4, 8),
          endedAt: DateTime(2026, 11, 4, 9),
        ),
        finishing: true,
        goalPendingMeters: 420,
      ),
    );

    expect(run['finish'], isNull);
  });

  test('마지막으로 처리한 워치 명령을 싣는다', () {
    expect(stateOf(const RunIdle())['lastRequestId'], isNull);
    expect(stateOf(const RunIdle(), lastRequestId: 'a')['lastRequestId'], 'a');
  });

  group('끝난 결과는 폰 요약(S15)과 같은 숫자다', () {
    final finished = RunFinished(
      metrics: metrics,
      startedAt: now.subtract(const Duration(minutes: 30)),
      endedAt: now,
    );

    test('서버 기록을 받았으면 서버 숫자', () {
      final run = runOf(
        stateOf(
          finished,
          result: const WatchResultConfirmed(
            distanceMeters: 3410,
            duration: Duration(minutes: 23, seconds: 50),
            averagePace: Duration(minutes: 6, seconds: 59),
          ),
        ),
      );

      expect(run['status'], 'FINISHED');
      expect(run['finish'], isNull);
      expect(run['result'], {
        'isServerConfirmed': true,
        'totalDistanceMeters': 3410,
        'averagePaceSecondsPerKm': 419,
        'elapsedSeconds': 1430,
      });
    });

    test('받는 중이면 결과를 비운다', () {
      // 폰 요약이 `--` 를 띄우는 동안이다.
      final run = runOf(stateOf(finished, result: const WatchResultLoading()));

      expect(run['status'], 'FINISHED');
      expect(run['result'], isNull);
    });

    test('서버 기록이 없으면 폰이 잰 숫자', () {
      final run = runOf(stateOf(finished));

      expect(run['result'], {
        'isServerConfirmed': false,
        'totalDistanceMeters': 3421,
        'averagePaceSecondsPerKm': metrics.averagePace!.inSeconds,
        // 멈춘 시간을 뺀 값이다. 벽시계(30분)가 아니다.
        'elapsedSeconds': 1450,
      });
    });
  });

  test('SYNCED 는 상태에 syncId·생일·사진을 더한다', () {
    final synced = WatchPayload.synced(
      stateOf(const RunIdle()),
      syncId: 'a1',
      birthday: DateTime(1998, 3, 7),
      board: const PartyBoard(),
      photos: const {},
    );

    expect(synced['phoneInstanceId'], '3f2a9c1e');
    expect(synced['syncId'], 'a1');
    expect(synced['birthday'], '1998-03-07');
    expect(synced['photos'], isEmpty);
  });

  test('SYNCED 사진은 파티원 중 사진이 있는 사람만 싣는다', () {
    final board = const PartyBoard().withRoster(const [
      ...members,
      PartyMember(userId: 'u-2', nickname: '두부'),
    ], myUserId: 'me');

    final synced = WatchPayload.synced(
      stateOf(const RunRunning(metrics), board: board),
      syncId: 'a1',
      birthday: null,
      board: board,
      // 내 사진이 섞여 와도 싣지 않는다. 두부는 못 만들었다.
      photos: const {'me': 'mine', 'u-1': '/9j/kong'},
    );

    expect(synced['photos'], [
      {'userId': 'u-1', 'jpegBase64': '/9j/kong'},
    ]);
  });

  group('콤보 순간', () {
    ComboPeer peer(String userId, int count) => ComboPeer(
      userId: userId,
      gapMeters: 0,
      comboCount: count,
      maxComboCount: count,
    );

    List<(String, int, WatchComboKind)> momentsOf(
      Map<String, ComboPeer> before,
      Map<String, ComboPeer> after,
    ) => [
      for (final moment in WatchPayload.comboMoments(
        before: before,
        after: after,
      ))
        (moment.userId, moment.comboCount, moment.kind),
    ];

    test('처음 붙으면 0으로 틱이다', () {
      expect(momentsOf({}, {'u-1': peer('u-1', 0)}), [
        ('u-1', 0, WatchComboKind.tick),
      ]);
    });

    test('눈금에 닿으면 틱이 아니라 눈금이다', () {
      expect(momentsOf({'u-1': peer('u-1', 2)}, {'u-1': peer('u-1', 3)}), [
        ('u-1', 3, WatchComboKind.milestone),
      ]);
    });

    test('목록에서 빠지면 끊김이다', () {
      expect(momentsOf({'u-1': peer('u-1', 7)}, {}), [
        ('u-1', 0, WatchComboKind.broken),
      ]);
    });

    test('값이 그대로면 아무것도 없다', () {
      // 같은 관계를 두고 양쪽 배치가 통지를 따로 만들 수 있다.
      expect(momentsOf({'u-1': peer('u-1', 4)}, {'u-1': peer('u-1', 4)}), []);
    });

    test('사람마다 따로 알린다', () {
      expect(
        momentsOf(
          {'u-1': peer('u-1', 4), 'u-2': peer('u-2', 1)},
          {'u-1': peer('u-1', 5)},
        ),
        [
          ('u-2', 0, WatchComboKind.broken),
          ('u-1', 5, WatchComboKind.milestone),
        ],
      );
    });
  });
}
