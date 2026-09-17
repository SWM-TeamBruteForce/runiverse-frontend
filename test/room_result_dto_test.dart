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
  }) => {
    'userId': id,
    'nickname': name,
    'profileImageUrl': null,
    'status': 'COMPLETED',
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
