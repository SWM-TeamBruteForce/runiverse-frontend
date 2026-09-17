import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/utils/kst_time.dart';

/// 서버 시각을 **기기가 어디에 있든 같은 순간으로** 읽는가.
///
/// ⚠️ 이 결함은 한국에서 돌리면 절대 안 보인다. 에뮬레이터가 GMT라 마감
/// 카운트다운이 9시간 어긋난 것을 보고 찾았다. 테스트도 기기 시간대와
/// 무관하게 성립하도록 **순간(UTC)으로 비교한다** — 로컬 벽시계로 비교하면
/// CI 시간대에 따라 답이 달라진다.
void main() {
  group('서버 문자열을 읽는다', () {
    test('오프셋이 없으면 한국 벽시계로 본다', () {
      // 19:00 KST = 10:00 UTC. 기기가 어디든 같은 순간이다.
      final read = KstTime.parse('2026-09-16T19:00:00')!;

      expect(read.toUtc(), DateTime.utc(2026, 9, 16, 10));
    });

    test('⚠️ 기기 시간대를 따라가지 않는다', () {
      // `DateTime.parse`를 그대로 쓰면 이 값이 기기 로컬 19:00이 된다 —
      // 런던에서는 실제보다 9시간 뒤를 가리킨다.
      final read = KstTime.parse('2026-09-16T18:50:00')!;

      expect(read.toUtc(), DateTime.utc(2026, 9, 16, 9, 50));
    });

    test('오프셋이 붙어 있으면 그대로 믿는다', () {
      // 서버가 언젠가 오프셋을 실어 주면 두 번 밀면 안 된다.
      final read = KstTime.parse('2026-09-16T10:00:00Z')!;

      expect(read.toUtc(), DateTime.utc(2026, 9, 16, 10));
    });

    test('읽을 수 없으면 null이다', () {
      expect(KstTime.parse(null), isNull);
      expect(KstTime.parse(''), isNull);
      expect(KstTime.parse('망가진 값'), isNull);
      expect(KstTime.parse(19), isNull);
    });
  });

  group('벽시계를 옮긴다', () {
    test('한국 벽시계를 그 순간으로 만든다', () {
      final at = KstTime.toLocal(DateTime(2026, 9, 16, 19));

      expect(at.toUtc(), DateTime.utc(2026, 9, 16, 10));
    });

    test('읽기와 쓰기가 맞물린다', () {
      const raw = '2026-09-16T21:30:00';

      expect(
        KstTime.parse(raw)!.toUtc(),
        KstTime.toLocal(DateTime(2026, 9, 16, 21, 30)).toUtc(),
      );
    });
  });

  group('서버 표기로 적는다', () {
    test('초 단위까지, 오프셋 없이', () {
      // ⚠️ `toIso8601String()`은 밀리초를 붙여 서버 형식과 어긋난다.
      expect(KstTime.format(DateTime(2026, 9, 16, 18)), '2026-09-16T18:00:00');
      expect(
        KstTime.format(DateTime(2026, 9, 16, 9, 5, 7)),
        '2026-09-16T09:05:07',
      );
    });
  });

  group('지금의 한국 벽시계', () {
    test('UTC보다 9시간 앞선다', () {
      // 기기가 어디에 있든 성립한다 — 그것이 이 함수의 존재 이유다.
      final wall = KstTime.nowWall();
      final utc = DateTime.now().toUtc();
      final gap =
          DateTime(
            wall.year,
            wall.month,
            wall.day,
            wall.hour,
            wall.minute,
          ).difference(
            DateTime(utc.year, utc.month, utc.day, utc.hour, utc.minute),
          );

      expect(gap, KstTime.offset);
    });
  });
}
