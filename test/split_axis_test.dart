import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record/presentation/split_axis.dart';

/// 구간 그래프의 세로 자 — **두 사람이 같은 자로 재는가.**
///
/// 여기가 틀어지면 그래프가 거짓말을 한다. 눈금이 내 값만으로 잡히면 상대의
/// 느렸던 구간이 그림 밖으로 밀려나고, 같은 높이가 서로 다른 페이스를 뜻하게
/// 된다. **틀렸다는 것이 화면에 드러나지 않는다** — 선이 그럴듯하게 그려진다.
void main() {
  group('범위', () {
    test('⚠️ 파티원 값까지 합쳐 잡는다', () {
      // 상대가 나보다 느렸다(페이스가 크다). 내 값만 보면 그 구간이 그림
      // 밖으로 나간다.
      final axis = SplitAxis.of([300, 310], secondary: [280, 400]);

      expect(axis.lo, 280);
      expect(axis.hi, 400);
    });

    test('파티원이 없으면 내 값만으로 잡는다', () {
      final axis = SplitAxis.of([300, 310, 290]);

      expect(axis.lo, 290);
      expect(axis.hi, 310);
    });

    test('파티원이 더 짧아도 있는 만큼 센다', () {
      // 먼저 끝난 사람은 뒤 구간이 없다.
      final axis = SplitAxis.of([300, 310, 320], secondary: [250]);

      expect(axis.lo, 250);
      expect(axis.hi, 320);
    });

    test('그릴 것이 없어도 죽지 않는다', () {
      final axis = SplitAxis.of([]);

      expect(axis.isFlat, isTrue);
      expect(axis.ticks, [0]);
    });
  });

  group('눈금', () {
    test('최고·중간·최저 셋이다', () {
      final axis = SplitAxis.of([300, 400]);

      expect(axis.ticks, [400, 350, 300]);
    });

    test('⚠️ 가운데는 평균이 아니라 축의 중간값이다', () {
      // 300이 셋, 400이 하나다. 평균은 325지만 눈금은 350이어야 한다 —
      // 평균을 그리면 비교 중에 누구의 평균인지가 문제가 된다.
      final axis = SplitAxis.of([300, 300, 300, 400]);

      expect(axis.ticks[1], 350);
    });

    test('⚠️ 페이스는 작은 값이 위다', () {
      // 작을수록 빠르다. 위에서 아래 순서라 가장 빠른 구간이 먼저다.
      final axis = SplitAxis.of([300, 400], inverted: true);

      expect(axis.ticks, [300, 350, 400]);
    });

    test('값이 전부 같으면 눈금도 하나다', () {
      // 나눌 폭이 없다. 선 셋을 겹쳐 긋지 않는다.
      final axis = SplitAxis.of([330, 330, 330]);

      expect(axis.ticks, [330]);
    });
  });

  group('세로 좌표', () {
    const height = 100.0;

    test('가장 큰 값이 위, 작은 값이 아래다', () {
      final axis = SplitAxis.of([300, 400]);

      expect(axis.dy(400, height), lessThan(axis.dy(300, height)));
    });

    test('⚠️ 페이스는 뒤집힌다 — 빠를수록 위다', () {
      final axis = SplitAxis.of([300, 400], inverted: true);

      expect(axis.dy(300, height), lessThan(axis.dy(400, height)));
    });

    test('위아래에 15%씩 여백을 둔다', () {
      // 선이 천장과 바닥에 닿으면 값의 크기를 못 읽는다.
      final axis = SplitAxis.of([300, 400]);

      expect(axis.dy(400, height), closeTo(15, 0.001));
      expect(axis.dy(300, height), closeTo(85, 0.001));
    });

    test('중간값은 한가운데다', () {
      final axis = SplitAxis.of([300, 400]);

      expect(axis.dy(350, height), closeTo(50, 0.001));
    });

    test('평평하면 가운데에 눕힌다', () {
      // 0으로 나누지 않는다.
      final axis = SplitAxis.of([330, 330]);

      expect(axis.dy(330, height), 50);
    });

    test('⚠️ 두 선이 같은 자를 쓴다', () {
      // 같은 값이면 어느 선에서 왔든 같은 높이여야 한다. 비교의 전제다.
      final mine = SplitAxis.of([300, 310], secondary: [280, 400]);
      final theirs = SplitAxis.of([280, 400], secondary: [300, 310]);

      expect(mine.dy(300, height), theirs.dy(300, height));
      expect(mine, theirs);
    });
  });
}
