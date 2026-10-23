import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';

/// 새 타이포 토큰 — **시안의 수치가 그대로 들어왔는가.**
void main() {
  group('자간', () {
    test('⚠️ 퍼센트가 아니라 픽셀로 들어간다', () {
      // 시안의 `-2%`를 그대로 -0.02로 넣으면 24px 글자에서 자간이 0.02px이
      // 되어 **사실상 0**이다. 눈으로는 안 보이고 시안과만 어긋난다.
      expect(AppTypographyV2.body01.letterSpacing, closeTo(24 * -0.02, 1e-9));
      expect(AppTypographyV2.body22.letterSpacing, closeTo(12 * -0.02, 1e-9));
    });

    test('⚠️ 글자 크기에 비례한다', () {
      // 같은 -2%인데 크기가 다르면 자간도 달라야 한다. 한 값으로 굳히면
      // 큰 글자는 붙고 작은 글자는 벌어진다.
      expect(
        AppTypographyV2.body01.letterSpacing!.abs(),
        greaterThan(AppTypographyV2.body22.letterSpacing!.abs()),
      );
    });

    test('0인 스타일은 0이다', () {
      expect(AppTypographyV2.heading01.letterSpacing, 0);
      expect(AppTypographyV2.body02.letterSpacing, 0);
    });
  });

  group('전체 31개', () {
    test('⚠️ 하나도 빠지지 않았다', () {
      // 시안이 Heading 01–09 + Body 01–22 를 정의한다. 옮기다 빠뜨리면
      // 그 자리를 쓰려던 화면이 비슷한 다른 스타일로 때우게 된다.
      expect(AppTypographyV2.all, hasLength(31));
    });

    test('⚠️ 모두 SUIT를 쓴다', () {
      // 하나라도 빠지면 그 자리만 시스템 글꼴로 그려진다. 에뮬레이터에서
      // 한글은 비슷해 보여서 놓치기 쉽다.
      for (final entry in AppTypographyV2.all.entries) {
        expect(entry.value.fontFamily, 'SUIT', reason: entry.key);
      }
    });

    test('⚠️ 행간은 1.24 아니면 1.50이다', () {
      // 시안이 124% / 150% 둘만 쓴다. 다른 값이 있으면 옮기다 틀린 것이다.
      for (final entry in AppTypographyV2.all.entries) {
        expect(entry.value.height, anyOf(1.24, 1.50), reason: entry.key);
      }
    });

    test('크기와 굵기가 다 있다', () {
      for (final entry in AppTypographyV2.all.entries) {
        expect(entry.value.fontSize, isNotNull, reason: entry.key);
        expect(entry.value.fontWeight, isNotNull, reason: entry.key);
      }
    });
  });

  group('재수출', () {
    test('간격이 v2 경로로 나온다', () {
      // 화면이 `v2`만 import 하고도 간격을 쓸 수 있어야 한다. 이게 안 되면
      // 화면이 두 세대를 섞게 되고 세대 혼용 테스트가 막는다.
      expect(AppSpacing.space2, isA<double>());
    });

    test('반경도 v2 경로로 나온다', () {
      // 시안 배지가 12px이고 `md`가 그 값이다.
      expect(AppRadius.md.topLeft.x, 12);
    });
  });
}
