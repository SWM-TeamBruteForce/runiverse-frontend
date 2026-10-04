import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/domain/altitude_rule.dart';

/// `AltitudeRule`이 지키는 약속.
///
/// ## 왜 이 경계가 중요한가
///
/// 안드로이드는 고도를 못 구하면 `0.0`을 준다. 그대로 보내면 **서버가 실제
/// 고도로 보고 누적 상승을 계산하고, 기록은 저장 뒤에 고치지 않는다.**
///
/// 그렇다고 `altitude == 0`을 전부 버리면 **해발 0 m 에서 달린 기록**을
/// 잃는다. 이 테스트가 그 둘 사이의 선을 못 박는다.
void main() {
  group('못 믿을 값', () {
    test('⚠️ 정확도가 음수면 버린다', () {
      // 센서가 정확도를 못 구했다. 고도 값이 얼마든 근거가 없다.
      expect(AltitudeRule.trusted(altitude: 37.5, accuracy: -1), isNull);
    });

    test('⚠️ 고도와 정확도가 둘 다 0이면 버린다', () {
      // 안드로이드가 값을 못 채운 꼴이다. 이것이 누적 경사를 망친다.
      expect(AltitudeRule.trusted(altitude: 0, accuracy: 0), isNull);
    });
  });

  group('믿을 값', () {
    test('⚠️ 진짜 해수면(0 m)은 정확도가 있으면 살린다', () {
      // ⚠️ **여기가 핵심이다.** `altitude == 0`만 보고 버리면 해안을 달린
      // 기록이 통째로 사라진다. 정확도가 있으면 센서가 잰 것이다.
      expect(AltitudeRule.trusted(altitude: 0, accuracy: 3.2), 0);
    });

    test('평범한 값은 그대로 통과한다', () {
      expect(AltitudeRule.trusted(altitude: 37.5, accuracy: 3.2), 37.5);
    });

    test('⚠️ 해수면보다 낮아도 버리지 않는다', () {
      // 지하 구간·간척지가 있다. 음수라고 틀린 값이 아니다.
      expect(AltitudeRule.trusted(altitude: -4.1, accuracy: 2.0), -4.1);
    });

    test('정확도가 0이어도 고도가 0이 아니면 살린다', () {
      // 둘 다 0일 때만 "안 채운 것"으로 본다. 한쪽만 0인 것은 다른 사건이다.
      expect(AltitudeRule.trusted(altitude: 37.5, accuracy: 0), 37.5);
    });
  });
}
