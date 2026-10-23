import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/domain/calorie_calculator.dart';

/// 칼로리 — **모르는 것을 지어내지 않는가.**
///
/// 이 값은 기록이 아니라 화면 표시용이다(서버가 종료 시 확정한다). 그래서
/// 정확도보다 중요한 것이 **틀린 값을 그럴듯하게 내놓지 않는 것**이다.
/// 몸무게를 모르는데 기본 체중으로 때우면 그 사람의 칼로리가 조용히 틀린다.
void main() {
  /// 시속 [kph]로 [minutes]분 달렸을 때.
  int? burnedAt({
    required double kph,
    required double minutes,
    int? weightKg = 70,
  }) => CalorieCalculator.burned(
    meters: kph * 1000 * minutes / 60,
    elapsed: Duration(milliseconds: (minutes * 60000).round()),
    weightKg: weightKg,
  );

  group('모를 때', () {
    test('⚠️ 몸무게를 모르면 null이다', () {
      // 기본 체중으로 때우면 그 사람의 칼로리가 조용히 틀린다.
      expect(burnedAt(kph: 10, minutes: 30, weightKg: null), isNull);
    });

    test('몸무게가 0 이하여도 null이다', () {
      // 저장소가 깨졌거나 잘못 들어온 값이다. 0으로 나눠 이상한 수를 내지 않는다.
      expect(burnedAt(kph: 10, minutes: 30, weightKg: 0), isNull);
      expect(burnedAt(kph: 10, minutes: 30, weightKg: -5), isNull);
    });
  });

  group('아직 아무것도 안 했을 때', () {
    test('시작 직후는 0이다', () {
      expect(
        CalorieCalculator.burned(
          meters: 0,
          elapsed: Duration.zero,
          weightKg: 70,
        ),
        0,
      );
    });

    test('⚠️ 제자리에 서 있으면 0이다', () {
      // 신호를 기다리는 동안 GPS가 흔들린 것을 달린 것으로 세지 않는다.
      // 10분 동안 100m는 시속 0.6km다.
      expect(burnedAt(kph: 0.6, minutes: 10), 0);
    });
  });

  group('값의 크기', () {
    test('⚠️ 시속 10km로 30분이면 350kcal 근처다', () {
      // ACSM 식이 맞게 들어갔는지 보는 기준점이다. 70kg 기준으로 흔히
      // 인용되는 값이 300~400 사이다.
      expect(burnedAt(kph: 10, minutes: 30), closeTo(350, 60));
    });

    test('무거우면 더 태운다', () {
      final light = burnedAt(kph: 10, minutes: 30, weightKg: 55)!;
      final heavy = burnedAt(kph: 10, minutes: 30, weightKg: 85)!;

      expect(heavy, greaterThan(light));
      // 몸무게에 비례한다. 85/55 ≈ 1.55배.
      expect(heavy / light, closeTo(85 / 55, 0.05));
    });

    test('오래 달리면 더 태운다', () {
      expect(
        burnedAt(kph: 10, minutes: 60)!,
        greaterThan(burnedAt(kph: 10, minutes: 30)!),
      );
    });

    test('빠르면 더 태운다', () {
      // 같은 시간이면 빨리 달린 쪽이 많이 태운다.
      expect(
        burnedAt(kph: 14, minutes: 30)!,
        greaterThan(burnedAt(kph: 8, minutes: 30)!),
      );
    });

    test('⚠️ 같은 거리라면 속도에 크게 좌우되지 않는다', () {
      // 달리기의 에너지 소모는 거리에 거의 비례한다. 10km를 40분에 뛰든
      // 60분에 뛰든 태우는 양이 두 배씩 차이나면 식이 잘못된 것이다.
      final fast = burnedAt(kph: 15, minutes: 40)!; // 10km
      final slow = burnedAt(kph: 10, minutes: 60)!; // 10km

      expect(fast / slow, closeTo(1, 0.25));
    });
  });
}
