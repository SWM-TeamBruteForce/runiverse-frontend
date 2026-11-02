import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';

/// 달린 거리는 반올림하지 않고 버린다.
///
/// 반올림하면 5km 목표에서 4,996m가 `5.00`으로 보인다 — 다 달린 줄 알았는데
/// 러닝이 끝나지 않는다(노션 「1.1.2 운영 전 앱 점검」 7번).
void main() {
  group('kmFloor', () {
    test('⚠️ 목표 직전은 목표로 보이지 않는다', () {
      expect(AppStrings.kmFloor(4996), '4.99');
      expect(AppStrings.kmFloor(4999.6), '4.99');
    });

    test('딱 떨어지는 거리는 그대로다', () {
      expect(AppStrings.kmFloor(5000), '5.00');
      expect(AppStrings.kmFloor(2030), '2.03');
      expect(AppStrings.kmFloor(0), '0.00');
    });

    test('소수 한 자리는 100m 단위로 버린다', () {
      expect(AppStrings.kmFloor(4950, digits: 1), '4.9');
      expect(AppStrings.kmFloor(5000, digits: 1), '5.0');
    });

    test('1·2 말고는 받지 않는다', () {
      expect(() => AppStrings.kmFloor(4996, digits: 0), throwsArgumentError);
    });
  });

  group('km로 받는 기록 거리', () {
    test('⚠️ 미터로 되돌린 뒤 버린다 — `2.03 * 1000` 은 `2029.99…` 다', () {
      expect(AppStrings.recordDistanceText(2030 / 1000), '2.03 km');
      expect(AppStrings.recordDistanceText(4996 / 1000), '4.99 km');
    });

    test('요약 줄은 소수 한 자리로 버린다', () {
      expect(AppStrings.recordSummaryDistanceText(14250 / 1000), '14.2 km');
    });
  });

  group('80%까지 남은 거리', () {
    String remaining(double km) => AppStrings.runFinishRemaining(km);

    test('⚠️ 4m 남아도 `0.00km`라고 하지 않는다 — 10m 단위로 올린다', () {
      expect(remaining(0.004), contains('0.01km'));
    });

    test('10m에 딱 맞으면 한 칸 더 올리지 않는다', () {
      expect(remaining(0.01), contains('0.01km'));
      expect(remaining(4020 / 1000), contains('4.02km'));
    });

    test('남아 있으면 1m 미만이어도 0이 아니다', () {
      expect(remaining(0.0002), contains('0.01km'));
    });
  });
}
