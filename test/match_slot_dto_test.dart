import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/matching/data/slot_dto.dart';

/// 슬롯 응답을 읽는다(명세 No 16).
///
/// ## ⚠️ 한 줄이 깨져도 목록을 버리지 않는다
///
/// 서버가 예상 밖의 값을 한 줄 섞어 보냈다고 매칭 등록 화면이 통째로 멈추면
/// 안 된다. 못 읽는 줄만 건너뛰고 나머지를 준다.
void main() {
  test('세 필드를 읽는다', () {
    final slots = matchSlotsFromJson({
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
    });

    expect(slots, hasLength(2));
    expect(slots.first.raw, '2026-07-25T18:00:00');
    expect(slots.first.waitingCount, 0);
    expect(slots.first.selectable, isFalse);
    expect(slots[1].waitingCount, 3);
    expect(slots[1].selectable, isTrue);
  });

  test('⚠️ 시각을 KST로 읽는다 — 기기 시간대와 무관하다', () {
    // `DateTime.parse`로 읽으면 화면이 `KstTime.wallOf`로 +9시간을 한 번 더
    // 해, UTC 기기에서 18:00 슬롯이 03:00으로 뜬다(설계 8-5).
    final slot = matchSlotsFromJson({
      'slots': [
        {
          'scheduledStartAt': '2026-07-25T18:00:00',
          'waitingCount': 1,
          'selectable': true,
        },
      ],
    }).single;

    expect(AppStrings.matchSlotTime(slot.startAt), '18:00');
  });

  test('⚠️ 못 읽는 줄은 건너뛰고 나머지를 준다', () {
    final slots = matchSlotsFromJson({
      'slots': [
        {'scheduledStartAt': '어쩌구', 'waitingCount': 1, 'selectable': true},
        {
          'scheduledStartAt': '2026-07-25T18:30:00',
          'waitingCount': 3,
          'selectable': true,
        },
        {'waitingCount': 2, 'selectable': true},
      ],
    });

    expect(slots, hasLength(1));
    expect(slots.single.raw, '2026-07-25T18:30:00');
  });

  test('⚠️ 같은 시각이 두 번 오면 한 번만 남긴다', () {
    // 그대로 두면 합계가 두 배가 되고 시트에 같은 시각이 두 줄 선다.
    final slots = matchSlotsFromJson({
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
    });

    expect(slots, hasLength(1));
    expect(slots.single.waitingCount, 3, reason: '먼저 온 줄을 쓴다');
  });

  test('⚠️ 음수 대기 인원은 0으로 본다', () {
    // 음수를 그대로 쓰면 합계가 줄어들어 "사람이 적다"로 잘못 읽힌다.
    final slots = matchSlotsFromJson({
      'slots': [
        {
          'scheduledStartAt': '2026-07-25T18:00:00',
          'waitingCount': -1,
          'selectable': true,
        },
      ],
    });

    expect(slots.single.waitingCount, 0);
  });

  test('⚠️ 빠지거나 타입이 틀린 값은 안전한 쪽으로 읽는다', () {
    // 대기 인원은 0(없다고 말하는 쪽), 선택 가능은 거짓(막는 쪽).
    final slots = matchSlotsFromJson({
      'slots': [
        {'scheduledStartAt': '2026-07-25T18:00:00'},
        {
          'scheduledStartAt': '2026-07-25T18:30:00',
          'waitingCount': '셋',
          'selectable': 'yes',
        },
      ],
    });

    expect(slots, hasLength(2));
    expect(slots.first.waitingCount, 0);
    expect(slots.first.selectable, isFalse);
    expect(slots[1].waitingCount, 0);
    expect(slots[1].selectable, isFalse);
  });

  test('빈 목록도 실패가 아니다', () {
    expect(matchSlotsFromJson({'slots': <Object>[]}), isEmpty);
    expect(matchSlotsFromJson(null), isEmpty);
    expect(matchSlotsFromJson({'slots': '어쩌구'}), isEmpty);
  });
}
