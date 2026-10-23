import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/domain/cadence_calculator.dart';
import 'package:runiverse/features/session/domain/step_repository.dart';

/// 케이던스 — **누적값의 차이로 내는가.**
///
/// 걸음 표본은 부팅 이후 누적이라 그 값 자체는 쓸 데가 없다. 두 표본의 차이로만
/// 뜻이 생기고, 그 뺄셈을 틀리면 **말도 안 되는 수가 화면에 뜬다.**
void main() {
  final start = DateTime(2026, 8, 28, 19);

  /// [seconds]초 시점에 누적 [steps]걸음.
  StepSample at(int seconds, int steps) => StepSample(
    steps: steps,
    at: start.add(Duration(seconds: seconds)),
  );

  group('낼 수 없을 때', () {
    test('표본이 없으면 null이다', () {
      expect(CadenceCalculator.recent([]), isNull);
    });

    test('표본이 하나면 null이다', () {
      // 누적값 하나로는 아무것도 모른다.
      expect(CadenceCalculator.recent([at(0, 1000)]), isNull);
    });

    test('⚠️ 창이 너무 짧으면 null이다', () {
      // 1초 사이의 3걸음으로 180spm이라고 말하지 않는다. 센서가 이벤트를
      // 묶어 보내면 그런 표본이 실제로 생긴다.
      expect(CadenceCalculator.recent([at(0, 1000), at(1, 1003)]), isNull);
    });

    test('⚠️ 걸음이 늘지 않았으면 null이다', () {
      // 서 있는 동안에도 센서는 같은 누적값을 보낼 수 있다.
      expect(CadenceCalculator.recent([at(0, 1000), at(30, 1000)]), isNull);
    });

    test('⚠️ 누적값이 줄면 null이다', () {
      // 기기를 재부팅하면 0으로 돌아간다. 음수 케이던스를 내지 않는다.
      expect(CadenceCalculator.recent([at(0, 5000), at(30, 12)]), isNull);
    });
  });

  group('사람이 낼 수 없는 값', () {
    test('⚠️ 너무 높으면 내지 않는다', () {
      // 30초에 200걸음이면 400spm이다. 센서가 튄 것이다.
      expect(CadenceCalculator.recent([at(0, 1000), at(30, 1200)]), isNull);
    });

    test('⚠️ 너무 낮으면 내지 않는다', () {
      // 30초에 10걸음이면 20spm이다. 달리는 중이 아니다.
      expect(CadenceCalculator.recent([at(0, 1000), at(30, 1010)]), isNull);
    });
  });

  group('값', () {
    test('30초에 90걸음이면 180spm이다', () {
      expect(CadenceCalculator.recent([at(0, 1000), at(30, 1090)]), 180);
    });

    test('10초에 26걸음이면 156spm이다', () {
      expect(CadenceCalculator.recent([at(0, 1000), at(10, 1026)]), 156);
    });

    test('⚠️ 창 밖의 오래된 표본은 보지 않는다', () {
      // 러닝 초반에 천천히 걸었다고 지금 케이던스가 낮게 나오면 안 된다.
      final samples = [
        at(0, 1000), // 창 밖 — 느리게 걷던 구간
        at(60, 1060),
        at(90, 1150), // 최근 30초에 90걸음 = 180spm
      ];

      expect(CadenceCalculator.recent(samples), 180);
    });

    test('창을 바꾸면 보는 구간이 바뀐다', () {
      final samples = [at(0, 1000), at(30, 1060), at(60, 1150)];

      // 최근 30초: 90걸음 → 180spm
      expect(CadenceCalculator.recent(samples), 180);
      // 최근 60초: 150걸음 → 150spm
      expect(
        CadenceCalculator.recent(samples, window: const Duration(seconds: 60)),
        150,
      );
    });
  });

  group('표본 정리', () {
    test('⚠️ 창 하나만큼은 남긴다', () {
      // 다 버리면 다음 계산이 시작점을 못 찾는다.
      final samples = [at(0, 1000), at(60, 1100), at(90, 1190)];

      final kept = CadenceCalculator.trimmed(samples);

      expect(kept.length, greaterThanOrEqualTo(2));
      // 남은 것만으로도 같은 답이 나와야 한다.
      expect(CadenceCalculator.recent(kept), CadenceCalculator.recent(samples));
    });

    test('⚠️ 오래된 것은 버린다. 30분을 달려도 쌓이지 않는다', () {
      final samples = [for (var i = 0; i <= 1800; i += 10) at(i, 1000 + i * 3)];

      final kept = CadenceCalculator.trimmed(samples);

      expect(samples.length, greaterThan(100));
      expect(kept.length, lessThan(10));
    });

    test('표본이 적으면 그대로 둔다', () {
      final samples = [at(0, 1000)];
      expect(CadenceCalculator.trimmed(samples), samples);
    });
  });
}
