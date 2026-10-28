import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/matching/data/slot_board_dto.dart';

/// 슬롯 조회 응답을 읽는다(명세 No 16, 2026-10-26 변경).
///
/// ## ⚠️ 응답 모양이 통째로 바뀌었다
///
/// 전에는 `{ slots: [...] }` 한 겹이었다. 이제 `{ distances: [ {
/// targetDistanceMeters, slots: [...] } ] }` 두 겹이다. 그래서 **같은 시각이
/// 거리마다 한 번씩, 정상적으로 여러 번 온다** — 옛 코드가 중복으로 보고
/// 버렸던 것이 지금은 버려선 안 되는 값이다.
///
/// ## ⚠️ 한 줄이 깨져도 판을 버리지 않는다
///
/// 서버가 예상 밖의 값을 한 줄 섞어 보냈다고 매칭 등록 화면이 통째로 멈추면
/// 안 된다. 못 읽는 줄만 건너뛰고 나머지를 준다.
void main() {
  test('두 겹을 읽는다', () {
    final board = slotBoardFromJson({
      'distances': [
        {
          'targetDistanceMeters': 3000,
          'slots': [
            {
              'scheduledStartAt': '2026-07-25T18:00:00',
              'waitingCount': 0,
              'selectable': false,
            },
            {
              'scheduledStartAt': '2026-07-25T18:30:00',
              'waitingCount': 3,
              'selectable': true,
            },
          ],
        },
        {
          'targetDistanceMeters': 5000,
          'slots': [
            {
              'scheduledStartAt': '2026-07-25T18:30:00',
              'waitingCount': 7,
              'selectable': true,
            },
          ],
        },
      ],
    });

    expect(board.distances.map((d) => d.meters), [3000, 5000]);
    expect(board.distances.first.slots, hasLength(2));
    expect(board.distances.first.slots.first.raw, '2026-07-25T18:00:00');
    expect(board.distances.first.slots.first.waitingCount, 0);
    expect(board.distances.first.slots.first.selectable, isFalse);
    expect(board.distances.first.slots[1].waitingCount, 3);
    expect(board.distances[1].slots.single.waitingCount, 7);
  });

  test('⚠️ 같은 시각이 거리마다 오는 것은 중복이 아니다', () {
    // 옛 DTO는 `scheduledStartAt`이 같으면 뒤에 온 줄을 버렸다. 그 규칙을
    // 그대로 들고 오면 **두 번째 거리의 시간대가 전부 사라진다.**
    final board = slotBoardFromJson({
      'distances': [
        {
          'targetDistanceMeters': 3000,
          'slots': [
            {
              'scheduledStartAt': '2026-07-25T18:00:00',
              'waitingCount': 1,
              'selectable': true,
            },
          ],
        },
        {
          'targetDistanceMeters': 5000,
          'slots': [
            {
              'scheduledStartAt': '2026-07-25T18:00:00',
              'waitingCount': 2,
              'selectable': true,
            },
          ],
        },
      ],
    });

    expect(board.at(raw: '2026-07-25T18:00:00', meters: 3000)?.waitingCount, 1);
    expect(board.at(raw: '2026-07-25T18:00:00', meters: 5000)?.waitingCount, 2);
  });

  test('⚠️ 한 거리 안에서 같은 시각이 두 번 오면 한 번만 남긴다', () {
    // 이쪽은 진짜 중복이다. 그대로 두면 그 거리의 합계가 두 배가 된다.
    final board = slotBoardFromJson({
      'distances': [
        {
          'targetDistanceMeters': 3000,
          'slots': [
            {
              'scheduledStartAt': '2026-07-25T18:00:00',
              'waitingCount': 3,
              'selectable': true,
            },
            {
              'scheduledStartAt': '2026-07-25T18:00:00',
              'waitingCount': 5,
              'selectable': true,
            },
          ],
        },
      ],
    });

    expect(board.distances.single.slots, hasLength(1));
    expect(
      board.distances.single.slots.single.waitingCount,
      3,
      reason: '먼저 온 줄을 쓴다',
    );
  });

  test('⚠️ 시각을 KST로 읽는다 — 기기 시간대와 무관하다', () {
    // `DateTime.parse`로 읽으면 화면이 `KstTime.wallOf`로 +9시간을 한 번 더
    // 해, UTC 기기에서 18:00 슬롯이 03:00으로 뜬다.
    final board = slotBoardFromJson({
      'distances': [
        {
          'targetDistanceMeters': 3000,
          'slots': [
            {
              'scheduledStartAt': '2026-07-25T18:00:00',
              'waitingCount': 1,
              'selectable': true,
            },
          ],
        },
      ],
    });

    expect(
      AppStrings.matchSlotTime(board.distances.single.slots.single.startAt),
      '18:00',
    );
  });

  test('⚠️ 못 읽는 줄은 건너뛰고 나머지를 준다', () {
    final board = slotBoardFromJson({
      'distances': [
        {
          'targetDistanceMeters': 3000,
          'slots': [
            {'scheduledStartAt': '어쩌구', 'waitingCount': 1, 'selectable': true},
            {
              'scheduledStartAt': '2026-07-25T18:30:00',
              'waitingCount': 3,
              'selectable': true,
            },
            {'waitingCount': 2, 'selectable': true},
            '어쩌구',
          ],
        },
      ],
    });

    expect(board.distances.single.slots, hasLength(1));
    expect(board.distances.single.slots.single.raw, '2026-07-25T18:30:00');
  });

  test('⚠️ 거리를 못 읽으면 그 거리를 통째로 버린다', () {
    // 미터값이 **칩의 이름이자 신청에 실리는 값**이다. 모르는 채로 세우면
    // 누를 수는 있는데 무엇을 신청하는지 알 수 없는 칩이 생긴다.
    final board = slotBoardFromJson({
      'distances': [
        {
          'slots': [
            {
              'scheduledStartAt': '2026-07-25T18:00:00',
              'waitingCount': 1,
              'selectable': true,
            },
          ],
        },
        {
          'targetDistanceMeters': 0,
          'slots': [
            {
              'scheduledStartAt': '2026-07-25T18:00:00',
              'waitingCount': 1,
              'selectable': true,
            },
          ],
        },
        {
          'targetDistanceMeters': '5km',
          'slots': [
            {
              'scheduledStartAt': '2026-07-25T18:00:00',
              'waitingCount': 1,
              'selectable': true,
            },
          ],
        },
        {
          'targetDistanceMeters': 5000,
          'slots': [
            {
              'scheduledStartAt': '2026-07-25T18:00:00',
              'waitingCount': 1,
              'selectable': true,
            },
          ],
        },
      ],
    });

    expect(board.distances.map((d) => d.meters), [5000]);
  });

  test('⚠️ 거리가 두 번 오면 한 번만 남긴다', () {
    // 그대로 두면 칩이 두 개 서고, 시간 시트의 합계가 그 거리만 두 배가 된다.
    final board = slotBoardFromJson({
      'distances': [
        {
          'targetDistanceMeters': 3000,
          'slots': [
            {
              'scheduledStartAt': '2026-07-25T18:00:00',
              'waitingCount': 3,
              'selectable': true,
            },
          ],
        },
        {
          'targetDistanceMeters': 3000,
          'slots': [
            {
              'scheduledStartAt': '2026-07-25T18:00:00',
              'waitingCount': 5,
              'selectable': true,
            },
          ],
        },
      ],
    });

    expect(board.distances, hasLength(1));
    expect(board.times.single.waitingTotal, 3, reason: '먼저 온 거리를 쓴다');
  });

  test('시간대가 빈 거리도 남긴다', () {
    // ⚠️ **서버가 내놓은 선택지다.** 읽을 수 있는 시간대가 없다고 칩을 빼면
    // 신청할 수 있는 거리를 앱이 감추는 꼴이 된다. 칩은 서고, 그 거리에
    // 해당하는 칸이 없으니 등록 버튼이 저절로 막는다(`at`이 `null`).
    final board = slotBoardFromJson({
      'distances': [
        {'targetDistanceMeters': 3000, 'slots': <Object>[]},
        {
          'targetDistanceMeters': 5000,
          'slots': [
            {
              'scheduledStartAt': '2026-07-25T18:00:00',
              'waitingCount': 1,
              'selectable': true,
            },
          ],
        },
      ],
    });

    expect(board.distances.map((d) => d.meters), [3000, 5000]);
    expect(board.distances.first.slots, isEmpty);
    expect(board.at(raw: '2026-07-25T18:00:00', meters: 3000), isNull);
  });

  test('⚠️ 음수 대기 인원은 0으로 본다', () {
    // 음수를 그대로 쓰면 합계가 줄어들어 "사람이 적다"로 잘못 읽힌다.
    final board = slotBoardFromJson({
      'distances': [
        {
          'targetDistanceMeters': 3000,
          'slots': [
            {
              'scheduledStartAt': '2026-07-25T18:00:00',
              'waitingCount': -1,
              'selectable': true,
            },
          ],
        },
      ],
    });

    expect(board.distances.single.slots.single.waitingCount, 0);
  });

  test('⚠️ 빠지거나 타입이 틀린 값은 안전한 쪽으로 읽는다', () {
    // 대기 인원은 0(없다고 말하는 쪽), 선택 가능은 거짓(막는 쪽).
    final board = slotBoardFromJson({
      'distances': [
        {
          'targetDistanceMeters': 3000,
          'slots': [
            {'scheduledStartAt': '2026-07-25T18:00:00'},
            {
              'scheduledStartAt': '2026-07-25T18:30:00',
              'waitingCount': '셋',
              'selectable': 'yes',
            },
          ],
        },
      ],
    });

    final slots = board.distances.single.slots;
    expect(slots, hasLength(2));
    expect(slots.first.waitingCount, 0);
    expect(slots.first.selectable, isFalse);
    expect(slots[1].waitingCount, 0);
    expect(slots[1].selectable, isFalse);
  });

  test('빈 판도 실패가 아니다', () {
    expect(slotBoardFromJson({'distances': <Object>[]}).distances, isEmpty);
    expect(slotBoardFromJson(null).distances, isEmpty);
    expect(slotBoardFromJson({'distances': '어쩌구'}).distances, isEmpty);
    expect(slotBoardFromJson({'slots': <Object>[]}).distances, isEmpty);
  });
}
