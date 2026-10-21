import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record/data/room_result_dto.dart';

/// 결과 두 API를 합칠 때 **파티원을 버리지 않는가.**
///
/// 서버 응답에는 방 전원이 섞여 온다. 본인만 골라내던 파서가 나머지를 잃으면
/// 결과 화면의 파티원 비교가 그릴 것이 없다.
void main() {
  Map<String, dynamic> player(
    String id,
    String name, {
    bool isMe = false,
    bool deleted = false,
    int? distance = 5000,
    int? seconds = 1800,
    int? pace = 360,
    String status = 'COMPLETED',
  }) => {
    'userId': id,
    'nickname': name,
    'profileImageUrl': null,
    'status': status,
    'isDeleted': deleted,
    'isMe': isMe,
    'totalDistanceMeters': distance,
    'totalDurationSeconds': seconds,
    'totalCaloriesKcal': distance == null ? null : 320,
    'averagePaceSecondsPerKm': pace,
    'averageCadenceSpm': distance == null ? null : 172,
    'totalElevationGainMeters': distance == null ? null : 12,
  };

  Map<String, dynamic> split(int number, Map<String, int> secondsOf) => {
    'splitNumber': number,
    'startDistanceMeters': (number - 1) * 10,
    'endDistanceMeters': number * 10,
    'distanceMeters': 10,
    'routes': null,
    'players': [
      for (final entry in secondsOf.entries)
        {
          'userId': entry.key,
          'durationSeconds': entry.value,
          'averagePaceSecondsPerKm': entry.value * 100,
          'averageCadenceSpm': 170,
          'caloriesKcal': 1,
          'elevationChangeMeters': null,
        },
    ],
  };

  final results = <String, dynamic>{
    'runningRoomId': 125,
    'startedAt': '2026-09-17T19:00:00',
    'finishedAt': '2026-09-17T19:30:00',
    'routes': [
      [37.5, 127.0],
      [37.5001, 127.0001],
    ],
    'players': [
      player('u-2', '이서연'),
      player('me-1', '러너42', isMe: true),
      player('u-3', '박지훈', distance: null, seconds: null, pace: null),
      player('u-4', '탈퇴한 사용자', deleted: true),
    ],
  };

  final splitResults = <String, dynamic>{
    'runningRoomId': 125,
    'splitDistanceMeters': 10,
    'totalDistanceMeters': 30,
    'totalElevationGainMeters': 12,
    'players': [player('u-2', '이서연'), player('me-1', '러너42', isMe: true)],
    'splits': [
      split(1, {'me-1': 4, 'u-2': 3}),
      split(2, {'me-1': 4, 'u-2': 3}),
      split(3, {'me-1': 4}),
    ],
  };

  test('방 전원이 서버 순서대로 남는다', () {
    final detail = RoomResultDto.merge(
      results: results,
      splitResults: splitResults,
    );

    expect(detail.players.map((p) => p.userId), ['u-2', 'me-1', 'u-3', 'u-4']);
    expect(detail.players[1].isMe, isTrue);
    expect(detail.party.map((p) => p.userId), ['u-2', 'u-3', 'u-4']);
  });

  test('⚠️ 기록 없는 사람은 0이 아니라 모른다', () {
    // 짧게 달렸거나 출발하지 않은 사람. 0km로 그리면 거짓말이다.
    final detail = RoomResultDto.merge(
      results: results,
      splitResults: splitResults,
    );
    final none = detail.players.firstWhere((p) => p.userId == 'u-3');

    expect(none.hasRecord, isFalse);
    expect(none.distanceMeters, isNull);
    expect(none.averagePace, isNull);
  });

  test('⚠️ 아직 달리는 사람은 기록이 확정된 것이 아니다', () {
    // 먼저 끝낸 사람이 결과를 열면 아직 뛰는 사람의 **중간값**이 실려 온다.
    // 그것을 최종 기록처럼 그리면 나중에 열었을 때 숫자가 달라져 있다.
    final detail = RoomResultDto.merge(
      results: {
        'runningRoomId': 125,
        'routes': null,
        'players': [
          player('u-1', '나', isMe: true),
          player('u-2', '김도윤', status: 'RUNNING'),
        ],
      },
      splitResults: const {'splits': []},
    );

    final running = detail.players.last;
    expect(running.isRunning, isTrue);
    // 수치는 실려 왔지만 확정이 아니다.
    expect(running.duration, isNotNull);
    expect(running.hasRecord, isFalse);
  });

  test('끝낸 사람은 기록이 있다', () {
    final detail = RoomResultDto.merge(
      results: results,
      splitResults: splitResults,
    );

    expect(detail.players.first.isRunning, isFalse);
    expect(detail.players.first.hasRecord, isTrue);
  });

  test('탈퇴한 사람은 표시만 남는다', () {
    final detail = RoomResultDto.merge(
      results: results,
      splitResults: splitResults,
    );

    expect(detail.players.last.isDeleted, isTrue);
    expect(detail.players.last.nickname, '탈퇴한 사용자');
  });

  test('구간은 사람별로 갈리고 내 것은 rawSplits다', () {
    final detail = RoomResultDto.merge(
      results: results,
      splitResults: splitResults,
    );

    expect(detail.rawSplits, hasLength(3));
    expect(detail.rawSplits.first.duration, const Duration(seconds: 4));
    // 파티원 것은 따로. 늦게 끝난 사람(나)의 목록이 더 길다.
    expect(detail.splitsByPlayer.keys, ['u-2']);
    expect(detail.splitsByPlayer['u-2'], hasLength(2));
    expect(detail.splitsByPlayer.containsKey('me-1'), isFalse);
  });

  test('파티원 묶음도 같은 경계로 묶인다', () {
    final detail = RoomResultDto.merge(
      results: results,
      splitResults: splitResults,
    );

    expect(detail.tableSplitsOf('u-2'), hasLength(1));
    expect(
      detail.tableSplitsOf('u-2').single.duration,
      const Duration(seconds: 6),
    );
    // 기록 없는 사람은 빈 목록. 던지지 않는다.
    expect(detail.tableSplitsOf('u-3'), isEmpty);
  });

  /// 경로의 두 가지 모양 — 1.1.1 4절.
  ///
  /// ## ⚠️ 여기가 기기에서 터진 자리다
  ///
  /// 서버가 경로를 **조각으로 묶어** 주기 시작했는데 앱은 점이 한 줄로 오는
  /// 줄 알고 읽었다. 점 자리에 배열이 들어와 캐스트가 터졌고, 그 예외가 화면
  /// 까지 올라가 **끝낸 러닝의 상세가 하나도 안 열렸다** — 서버는 200을
  /// 주는데 화면은 "기록을 불러오지 못했어요"였다(2026-10-21 확인).
  group('⚠️ 조각으로 묶여 온 경로', () {
    test('조각마다 한 토막으로 읽는다', () {
      final detail = RoomResultDto.merge(
        results: {
          ...results,
          'routes': [
            [
              [37.5, 127.0],
              [37.50009, 127.0],
            ],
            [
              [37.6, 127.1],
              [37.60009, 127.1],
            ],
          ],
        },
        splitResults: splitResults,
      );

      expect(detail.track, hasLength(2));
      expect(detail.track.first.first.latitude, 37.5);
      expect(detail.track.last.first.latitude, 37.6);
    });

    test('⚠️ 붙어 있는 조각이라도 잇지 않는다', () {
      // 서버가 나눠 준 경계가 정본이다. 가까워 보인다고 이으면 **멈춰 있던
      // 자리를 가로질러** 선이 그려진다.
      final detail = RoomResultDto.merge(
        results: {
          ...results,
          'routes': [
            [
              [37.5, 127.0],
              [37.50009, 127.0],
            ],
            [
              [37.50018, 127.0],
              [37.50027, 127.0],
            ],
          ],
        },
        splitResults: splitResults,
      );

      expect(detail.track, hasLength(2));
    });

    test('⚠️ 조각 안에서 벌어진 자리는 그대로 끊는다', () {
      // 조각 안에도 빠진 자리가 남을 수 있다(가이드 4.2).
      final detail = RoomResultDto.merge(
        results: {
          ...results,
          'routes': [
            [
              [37.5, 127.0],
              [37.50009, 127.0],
              [37.5010, 127.0], // 약 100m 점프
              [37.50109, 127.0],
            ],
          ],
        },
        splitResults: splitResults,
      );

      expect(detail.track, hasLength(2));
    });

    test('⚠️ 읽을 수 없는 점은 버리고 나머지를 그린다', () {
      // 하나가 이상하다고 던지면 **기록 전체가 안 열린다.** 선 한 토막이
      // 비는 편이 낫다.
      final detail = RoomResultDto.merge(
        results: {
          ...results,
          'routes': [
            [37.5, 127.0],
            ['이상한 값', 127.0],
            [37.50009, 127.0],
          ],
        },
        splitResults: splitResults,
      );

      expect(detail.track.single, hasLength(2));
    });
  });

  test('⚠️ 한 줄로 온 경로를 벌어진 자리에서 끊는다', () {
    // ⚠️ 서버는 정지 구간·오염 좌표를 **뺀** 경로를 한 줄로 준다. 그대로
    // 한 토막으로 넘기면 빠진 자리가 직선으로 이어져 **가 본 적 없는 길이
    // 그려진다**(가이드 4.2).
    final detail = RoomResultDto.merge(
      results: {
        ...results,
        'routes': [
          [37.5, 127.0],
          [37.50009, 127.0], // 약 10m
          [37.5010, 127.0], // 약 100m 점프 — 여기서 끊긴다
          [37.50109, 127.0],
        ],
      },
      splitResults: splitResults,
    );

    expect(detail.track, hasLength(2));
    expect(detail.track.first, hasLength(2));
    expect(detail.track.last, hasLength(2));
  });

  test('솔로는 나 하나뿐이고 파티원은 없다', () {
    final detail = RoomResultDto.merge(
      results: {
        ...results,
        'players': [player('me-1', '러너42', isMe: true)],
      },
      splitResults: {
        ...splitResults,
        'splits': [
          split(1, {'me-1': 4}),
        ],
      },
    );

    expect(detail.party, isEmpty);
    expect(detail.rawSplits, hasLength(1));
  });
}
