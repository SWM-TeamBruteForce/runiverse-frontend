import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/matching/domain/match_slot.dart';
import 'package:runiverse/features/matching/domain/slot_board.dart';

/// 거리 × 시간의 판(명세 No 16) — **한 칸을 어떻게 집고, 시각을 어떻게 접나.**
///
/// ## ⚠️ 시간 선택기는 고른 거리의 줄을 읽는다
///
/// 서버는 거리별로 시간대 목록을 준다. 시간 선택기는 그중 고른 거리의 줄을
/// 그대로 그린다(`slotsOf`). 거리를 접어 시각 하나로 만드는 `times`는 "오늘
/// 아직 열린 시각이 있나"를 가릴 때만 쓰고, 인원을 더하지 않는다.
void main() {
  MatchSlot slot(String raw, {int waiting = 0, bool selectable = true}) =>
      MatchSlot(
        raw: raw,
        startAt: DateTime.parse(raw),
        waitingCount: waiting,
        selectable: selectable,
      );

  test('시각은 오름차순 합집합이다', () {
    // ⚠️ **거리마다 목록이 같다고 믿지 않는다.** 명세는 같다고 했지만, 하나만
    // 빠진 응답이 오면 그 시각이 통째로 사라진다 — 합집합이라 남는다.
    final board = SlotBoard([
      DistanceSlots(meters: 3000, slots: [slot('2026-07-25T19:00:00')]),
      DistanceSlots(
        meters: 5000,
        slots: [slot('2026-07-25T18:00:00'), slot('2026-07-25T19:00:00')],
      ),
    ]);

    expect(board.times.map((t) => t.raw), [
      '2026-07-25T18:00:00',
      '2026-07-25T19:00:00',
    ]);
  });

  test('⚠️ 시간 시트의 줄은 그 거리의 칸이다', () {
    // 거리가 다르면 같은 방에 매칭되지 않는다. 다른 거리의 3명이 섞이면
    // 10km 시트에 `5명 대기`가 서고, 들어가 보면 2명이다.
    final board = SlotBoard([
      DistanceSlots(
        meters: 3000,
        slots: [slot('2026-07-25T18:30:00', waiting: 3)],
      ),
      DistanceSlots(
        meters: 10000,
        slots: [slot('2026-07-25T18:30:00', waiting: 2)],
      ),
    ]);

    expect(board.slotsOf(10000).single.waitingCount, 2);
  });

  test('⚠️ 시간 시트의 줄은 시각 순이다', () {
    // 명세는 오름차순으로 준다고 했지만 믿지 않는다. 전에는 시트가 `times`를
    // 읽어 여기서 정렬됐는데, 거리의 줄을 그대로 넘기면 그 방어가 사라진다.
    final board = SlotBoard([
      DistanceSlots(
        meters: 3000,
        slots: [slot('2026-07-25T19:00:00'), slot('2026-07-25T18:00:00')],
      ),
    ]);

    expect(board.slotsOf(3000).map((s) => s.raw), [
      '2026-07-25T18:00:00',
      '2026-07-25T19:00:00',
    ]);
  });

  test('없는 거리의 줄은 비어 있다', () {
    final board = SlotBoard([
      DistanceSlots(meters: 3000, slots: [slot('2026-07-25T18:30:00')]),
    ]);

    expect(board.slotsOf(9999), isEmpty);
  });

  test('⚠️ 하나라도 고를 수 있으면 그 시각은 열려 있다', () {
    // 명세는 시작 시각이 같으면 거리가 달라도 `selectable`이 같다고 한다.
    // 그래도 **합집합으로 읽는다** — 서버가 그 전제를 깨도 고를 수 있는 것을
    // 막지는 않게 된다. 막는 쪽으로 틀리면 사람이 할 수 있는 일이 없다.
    final board = SlotBoard([
      DistanceSlots(
        meters: 3000,
        slots: [slot('2026-07-25T18:30:00', selectable: false)],
      ),
      DistanceSlots(
        meters: 5000,
        slots: [slot('2026-07-25T18:30:00', selectable: true)],
      ),
    ]);

    expect(board.times.single.selectable, isTrue);
  });

  test('전부 마감이면 그 시각도 마감이다', () {
    final board = SlotBoard([
      DistanceSlots(
        meters: 3000,
        slots: [slot('2026-07-25T18:30:00', selectable: false)],
      ),
      DistanceSlots(
        meters: 5000,
        slots: [slot('2026-07-25T18:30:00', selectable: false)],
      ),
    ]);

    expect(board.times.single.selectable, isFalse);
  });

  test('시각 × 거리로 한 칸을 집는다', () {
    final board = SlotBoard([
      DistanceSlots(
        meters: 3000,
        slots: [slot('2026-07-25T18:30:00', waiting: 3)],
      ),
      DistanceSlots(
        meters: 5000,
        slots: [slot('2026-07-25T18:30:00', waiting: 7)],
      ),
    ]);

    expect(board.at(raw: '2026-07-25T18:30:00', meters: 5000)?.waitingCount, 7);
  });

  test('없는 칸은 null이다', () {
    // ⚠️ **0으로 뭉개지 않는다.** 등록 버튼이 이 값을 읽는데, 없는 조합을 0명
    // 대기로 그리면 고를 수 없는 자리를 고를 수 있는 것처럼 말하게 된다.
    final board = SlotBoard([
      DistanceSlots(meters: 3000, slots: [slot('2026-07-25T18:30:00')]),
    ]);

    expect(board.at(raw: '2026-07-25T18:30:00', meters: 9999), isNull);
    expect(board.at(raw: '2026-07-25T21:00:00', meters: 3000), isNull);
  });

  test('거리 순서는 받은 그대로다', () {
    // ⚠️ **앱이 다시 정렬하지 않는다.** 명세가 오름차순으로 준다고 했고,
    // 칩의 순서는 **서버가 정하는 것**이다 — 앱이 끼어들면 서버가 순서를
    // 바꿔도 화면이 안 따라간다.
    final board = SlotBoard([
      DistanceSlots(meters: 3000, slots: const []),
      DistanceSlots(meters: 5000, slots: const []),
      DistanceSlots(meters: 10000, slots: const []),
    ]);

    expect(board.distances.map((d) => d.meters), [3000, 5000, 10000]);
  });

  test('빈 판도 만들어진다', () {
    const board = SlotBoard([]);

    expect(board.times, isEmpty);
    expect(board.at(raw: '어쩌구', meters: 3000), isNull);
  });
}
