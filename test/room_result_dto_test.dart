import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record/data/room_result_dto.dart';
import 'package:runiverse/features/record/domain/run_detail.dart';

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
    // ⚠️ **한 겹이 더 있다**(1.1.1). 끊긴 곳이 없어도 바깥 배열은 있다.
    'routes': [
      [
        [37.5, 127.0],
        [37.5001, 127.0001],
      ],
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

  group('경로 조각', () {
    /// ⚠️ **서버가 나눠 준 대로 쓴다.** 1.1.0까지는 앱이 30m 넘게 벌어진 자리를
    /// 찾아 끊었는데, 이제 일시정지·관측 공백·GPS 튐을 **서버가 경계로 보고
    /// 나눠 준다.** 앱이 또 끊으면 서버가 이어도 된다고 판단한 자리까지
    /// 갈라진다.
    RunDetail parsed(Object? routes) => RoomResultDto.merge(
      results: {...results, 'routes': routes},
      splitResults: splitResults,
    );

    test('⚠️ 조각 수와 점을 그대로 가져온다', () {
      final detail = parsed([
        [
          [37.5, 127.0],
          [37.50009, 127.0],
        ],
        [
          [37.5010, 127.0],
          [37.50109, 127.0],
        ],
      ]);

      expect(detail.track, hasLength(2));
      expect(detail.track.first, hasLength(2));
      expect(detail.track.last, hasLength(2));
    });

    test('⚠️ 앱이 더 끊지 않는다 — 멀리 떨어진 점도 한 조각이다', () {
      // 100m 넘게 벌어져 있어도 서버가 한 조각으로 줬으면 한 조각이다.
      // 고치기 전에는 여기서 둘로 갈라졌다.
      final detail = parsed([
        [
          [37.5, 127.0],
          [37.5010, 127.0],
        ],
      ]);

      expect(detail.track, hasLength(1));
      expect(detail.track.single, hasLength(2));
    });

    test('⚠️ 점이 하나인 조각도 버리지 않는다', () {
      // 끊긴 경계에 걸린 구간이 그렇게 온다. 버리면 그 자리가 통째로 빈다.
      // 그리는 쪽이 선을 긋지 않을 뿐이다.
      final detail = parsed([
        [
          [37.5, 127.0],
        ],
        [
          [37.5010, 127.0],
          [37.50109, 127.0],
        ],
      ]);

      expect(detail.track, hasLength(2));
      expect(detail.track.first, hasLength(1));
    });

    test('⚠️ 옛 모양(점 목록 하나)이 오면 빈 경로다', () {
      // 조용히 틀리지 않게 한다. 한 겹을 덜 벗기면 `point[0]`이 숫자라
      // 좌표로 읽히지 않는다 — 엉뚱한 곳에 그려지는 것보다 비는 편이 낫다.
      final detail = parsed([
        [37.5, 127.0],
        [37.5001, 127.0001],
      ]);

      expect(detail.track.expand((segment) => segment), isEmpty);
    });

    test('경로가 없으면 빈 목록이다', () {
      expect(parsed(null).track, isEmpty);
      expect(parsed(const []).track, isEmpty);
    });
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
