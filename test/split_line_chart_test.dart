import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/session/domain/pace_calculator.dart';
import 'package:runiverse/features/record/presentation/split_line_chart.dart';

/// 구간 그래프 — **크기를 읽을 수 있는가.**
///
/// 전에는 격자선 셋이 `높이 × i/4`에 뜻 없이 그려져서, 들쭉날쭉이 10초
/// 차이인지 2분 차이인지 **집어보기 전에는 알 수 없었다.** 여기서 보는 것은
/// 선이 그려지는가가 아니라 **숫자가 화면에 있는가**다.
void main() {
  String pace(double seconds) =>
      PaceCalculator.format(Duration(seconds: seconds.round()));

  Future<void> pump(
    WidgetTester tester, {
    required List<double> values,
    List<double>? secondary,
    bool inverted = true,
    bool showPoints = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SplitLineChart(
            title: '구간별 페이스',
            unit: '/km',
            values: values,
            labels: [for (var i = 1; i <= values.length; i++) '${i}km'],
            format: pace,
            color: const Color(0xFF3B82F6),
            hint: '그래프를 누른 채 좌우로 밀어 구간별 기록을 확인하세요',
            secondary: secondary,
            secondaryColor: const Color(0xFFF59E0B),
            inverted: inverted,
            showPoints: showPoints,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('세로 눈금', () {
    testWidgets('⚠️ 최고·중간·최저가 숫자로 뜬다', (tester) async {
      // 300초(5\'00")~360초(6\'00"), 가운데는 330초(5\'30").
      await pump(tester, values: [300, 360, 330]);

      expect(find.text("5'00\""), findsOneWidget);
      expect(find.text("5'30\""), findsOneWidget);
      expect(find.text("6'00\""), findsOneWidget);
    });

    testWidgets('⚠️ 파티원을 넣으면 눈금이 두 사람을 합친 범위다', (tester) async {
      // 혼자면 5'00"~5'10"이지만, 상대가 6'00"까지 갔으므로 눈금도 거기까지
      // 가야 한다. 안 그러면 상대 선이 그림 밖으로 밀려난다.
      await pump(tester, values: [300, 310], secondary: [300, 360]);

      expect(find.text("6'00\""), findsOneWidget);
      // 가운데도 합친 범위의 중간값이다 — 내 값만이면 5'05"였다.
      expect(find.text("5'30\""), findsOneWidget);
    });

    testWidgets('값이 전부 같으면 눈금도 하나다', (tester) async {
      // 선 셋을 겹쳐 긋고 숫자를 세 번 적지 않는다.
      await pump(tester, values: [330, 330, 330]);

      expect(find.text("5'30\""), findsOneWidget);
    });

    testWidgets('케이던스처럼 뒤집지 않는 값도 같은 자리에 적는다', (tester) async {
      await pump(tester, values: [160, 180], inverted: false);

      expect(find.text("2'40\""), findsOneWidget);
      expect(find.text("3'00\""), findsOneWidget);
    });
  });

  testWidgets('x축 라벨도 거터만큼 비켜 선다', (tester) async {
    // 안 비키면 점과 라벨이 어긋나 **어느 구간인지 잘못 읽힌다.**
    await pump(tester, values: [300, 360, 330]);

    final cardLeft = tester.getTopLeft(find.byType(SplitLineChart)).dx;
    final labelLeft = tester.getTopLeft(find.text('1km')).dx;

    expect(labelLeft - cardLeft, greaterThan(40));
  });

  /// 집는 자리 — **거터를 빼는가.**
  ///
  /// 말풍선은 캔버스에 그려 위젯 트리에 남지 않는다. 그래서 눌러 보고 글자를
  /// 찾는 식으로는 **틀려도 통과한다** — 계산만 꺼내어 직접 잰다.
  group('집는 구간', () {
    /// 거터 48 · 양쪽 여백 16 · 그림 영역 216 → 점 사이 간격은 92다.
    int at(double dx, {int count = 3}) => focusedSplitOf(
      dx: dx,
      plotWidth: 216,
      gutter: 48,
      inset: 16,
      count: count,
    );

    test('⚠️ 거터 바로 오른쪽은 첫 구간이다', () {
      // 안 빼면 여기가 이미 두 번째 구간으로 계산된다.
      expect(at(48 + 16), 0);
    });

    test('그림 영역 오른쪽 끝은 마지막 구간이다', () {
      expect(at(48 + 216 - 16), 2);
    });

    test('가운데는 가운데 구간이다', () {
      expect(at(48 + 216 / 2), 1);
    });

    test('가까운 점으로 붙는다', () {
      // 두 점 사이를 짚어도 어느 한쪽으로 정해진다. 그 사이의 값을
      // 지어내지 않는다.
      expect(at(48 + 16 + 40), 0);
      expect(at(48 + 16 + 52), 1);
    });

    test('거터 위를 짚어도 첫 구간을 넘어가지 않는다', () {
      // 눈금 숫자를 누른 경우다. 음수 비율이 되지 않게 가둔다.
      expect(at(0), 0);
      expect(at(10), 0);
    });

    test('구간이 하나면 언제나 그것이다', () {
      expect(at(0, count: 1), 0);
      expect(at(999, count: 1), 0);
    });
  });
}
