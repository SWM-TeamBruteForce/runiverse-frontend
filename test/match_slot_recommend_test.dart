import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/utils/kst_time.dart';
import 'package:runiverse/features/matching/domain/match_slot.dart';
import 'package:runiverse/features/matching/presentation/match_slot_sheet.dart';

/// 시간 시트의 `추천` — **고른 거리에 아무도 없을 때, 이른 쪽·늦은 쪽에 한
/// 줄씩** 붙는다.
void main() {
  MatchSlot slot(
    int hour, {
    int minute = 0,
    int waiting = 0,
    bool selectable = true,
  }) {
    final raw = '2026-11-12T$hour:${'$minute'.padLeft(2, '0')}:00';
    return MatchSlot(
      raw: raw,
      // ⚠️ **KST로 읽는다.** `DateTime.parse`는 기기 시간대로 읽어, 다른
      // 시간대에서 돌리면 시각이 어긋난다.
      startAt: KstTime.parse(raw)!,
      waitingCount: waiting,
      selectable: selectable,
    );
  }

  /// 18:00~22:00 한 거리의 줄.
  List<MatchSlot> day({
    Map<int, int> waiting = const {},
    Set<int> closed = const {},
  }) => [
    for (final hour in [18, 19, 20, 21, 22])
      slot(
        hour,
        waiting: waiting[hour] ?? 0,
        selectable: !closed.contains(hour),
      ),
  ];

  /// 추천이 붙은 줄의 시각.
  List<String> picked(List<MatchSlot> slots) => [
    for (final slot in recommendedSlots(slots)) slot.raw,
  ];

  test('아무도 없으면 18:00과 22:00이다', () {
    expect(picked(day()), ['2026-11-12T18:00:00', '2026-11-12T22:00:00']);
  });

  test('18:00이 마감되면 19:00으로 넘어간다', () {
    expect(picked(day(closed: {18})), [
      '2026-11-12T19:00:00',
      '2026-11-12T22:00:00',
    ]);
  });

  test('⚠️ 누가 신청해 둔 줄이 있으면 붙이지 않는다', () {
    // 21:00의 `1명 대기`가 가장 확실한 추천이다. 빈 18:00·22:00에 붙이면
    // 추천을 믿고 고른 사람과 21:00의 사람이 각자 혼자 남는다.
    expect(picked(day(waiting: {21: 1})), isEmpty);
  });

  test('⚠️ 30분 간격이어도 18:00 다음은 19:00이다', () {
    // 시(hour)만 보면 18:30도 18시라 거기 붙는다. 간격은 서버 설정값이다.
    final slots = [slot(18, selectable: false), slot(18, minute: 30), slot(19)];
    expect(picked(slots), ['2026-11-12T19:00:00']);
  });

  test('⚠️ 18:00·19:00이 둘 다 마감이면 22:00만 남는다', () {
    // 이른 쪽은 19:00에서 끝나고 20:00으로 넘어가지 않는다.
    expect(picked(day(closed: {18, 19})), ['2026-11-12T22:00:00']);
  });

  test('22:00까지 마감이면 붙이지 않는다', () {
    expect(picked(day(closed: {18, 19, 20, 21, 22})), isEmpty);
  });

  test('⚠️ 마감된 줄의 대기자는 세지 않는다', () {
    // 이제 들어갈 수 없는 사람이다. 세면 19:00 이후를 고를 사람에게 아무
    // 말도 못 한다.
    expect(picked(day(closed: {18}, waiting: {18: 2})), [
      '2026-11-12T19:00:00',
      '2026-11-12T22:00:00',
    ]);
  });
}
