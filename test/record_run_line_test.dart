import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';

/// 기록 탭 그날 줄의 한 문장.
///
/// ## ⚠️ 기기에서야 드러난 것이다
///
/// 처음엔 시작 시각과 소요 시간을 **같은 포매터**로 찍었다. 테스트는 전부
/// 초록이었고 — 아무도 그 문장을 읽지 않았으니까 — 에뮬레이터에서
/// `6:40:00 시작 · 5.0 km · 19:00 소요`가 나왔다.
///
/// - 시작 시각에 **초는 뜻이 없다**
/// - `19:00 소요`는 **19분인지 19시간인지** 알 수가 없다
///
/// 둘은 다른 종류의 값이라 다른 꼴로 적는다.
void main() {
  String line(int hour, int minute, double km, Duration took) =>
      AppStrings.recordRunLine(DateTime(2026, 10, 4, hour, minute), km, took);

  group('시작 시각', () {
    test('⚠️ `HH:MM` 이다 — 초를 적지 않는다', () {
      expect(
        line(6, 40, 5.0, const Duration(minutes: 30)),
        startsWith('06:40 시작'),
      );
    });

    test('⚠️ 한 자리 시각에 0을 채운다', () {
      // `6:40`과 `19:10`이 섞이면 줄마다 글자가 어긋난다.
      expect(
        line(6, 5, 5.0, const Duration(minutes: 30)),
        startsWith('06:05 시작'),
      );
    });

    test('오후도 24시간제로 적는다', () {
      expect(
        line(19, 10, 3.2, const Duration(minutes: 19)),
        startsWith('19:10 시작'),
      );
    });
  });

  group('소요 시간', () {
    test('⚠️ 분을 말로 적는다 — `19:00` 은 19시간으로 읽힌다', () {
      expect(
        line(19, 10, 3.2, const Duration(minutes: 19)),
        endsWith('19분 소요'),
      );
    });

    test('한 시간을 넘으면 시간과 분을 함께 적는다', () {
      expect(
        line(6, 40, 12.0, const Duration(hours: 1, minutes: 5)),
        endsWith('1시간 5분 소요'),
      );
    });
  });

  test('거리는 소수 한 자리다', () {
    expect(line(6, 40, 5.02, const Duration(minutes: 30)), contains('5.0 km'));
  });

  test('세 토막이 가운뎃점으로 이어진다', () {
    expect(
      line(6, 40, 5.0, const Duration(minutes: 30)),
      '06:40 시작 · 5.0 km · 30분 소요',
    );
  });
}
