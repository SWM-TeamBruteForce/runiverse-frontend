import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/analytics/match_slot_params.dart';

/// 매칭 이벤트의 `slot_time`·`slot_weekday`·`distance_group`. 시간대별
/// 성사율 차트가 이 값으로 나뉜다.
void main() {
  test('예약 순간을 KST 벽시계로 적는다', () {
    // 2026-11-20(금) 19:00 KST = 10:00 UTC
    final params = MatchSlotParams.of(
      startAt: DateTime.utc(2026, 11, 20, 10),
      meters: 5000,
    );

    expect(params['slot_time'], '19:00');
    expect(params['slot_weekday'], 'fri');
    expect(params['distance_group'], '5km');
  });

  test('⚠️ KST 자정을 넘으면 요일도 KST를 따른다', () {
    // 2026-11-20(금) 15:30 UTC = 2026-11-21(토) 00:30 KST
    final params = MatchSlotParams.of(
      startAt: DateTime.utc(2026, 11, 20, 15, 30),
    );

    expect(params['slot_time'], '00:30');
    expect(params['slot_weekday'], 'sat');
  });

  test('1km 단위가 아닌 거리는 소수로 적는다', () {
    expect(MatchSlotParams.distanceGroup(10000), '10km');
    expect(MatchSlotParams.distanceGroup(7500), '7.5km');
  });

  test('모르는 값은 빼고 낸다', () {
    // 빈 문자열이나 0을 실으면 그런 분류가 차트에 생긴다.
    expect(MatchSlotParams.of(), isEmpty);
    expect(MatchSlotParams.of(meters: 0), isEmpty);
  });
}
