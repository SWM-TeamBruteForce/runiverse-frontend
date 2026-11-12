import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
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
    List<String>? labels,
    List<int>? axisMeters,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SplitLineChart(
            title: '구간별 페이스',
            unit: '/km',
            values: values,
            labels:
                labels ?? [for (var i = 1; i <= values.length; i++) '$i km'],
            axisMeters:
                axisMeters ??
                [for (var i = 1; i <= values.length; i++) i * 1000],
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
    final labelLeft = tester.getTopLeft(find.text('1 km')).dx;

    expect(labelLeft - cardLeft, greaterThan(40));
  });

  /// 끊어 긋기 — **모르는 구간을 가로지르지 않는가.**
  ///
  /// 선은 캔버스에 그려 위젯 트리에 남지 않는다. 이어 그었는지 끊어 그었는지는
  /// 화면에서 확인할 수 없어 계산을 직접 잰다.
  group('끊어 긋기', () {
    const a = Offset(0, 10);
    const b = Offset(10, 20);
    const c = Offset(20, 30);

    test('빈 자리가 없으면 한 토막이다', () {
      expect(lineRunsOf(const [a, b, c]), [
        [a, b, c],
      ]);
    });

    test('⚠️ 빈 자리에서 끊는다', () {
      // 이어 그으면 **모르는 구간을 잰 것처럼 보인다.**
      expect(lineRunsOf(const [a, null, b, c]), [
        [a],
        [b, c],
      ]);
    });

    test('앞뒤가 비어도 가운데만 긋는다', () {
      expect(lineRunsOf(const [null, a, b, null]), [
        [a, b],
      ]);
    });

    test('아는 구간이 없으면 그을 것도 없다', () {
      expect(lineRunsOf(const [null, null]), isEmpty);
    });
  });

  /// x축 라벨 — **딱 떨어지는 거리에, 고른 간격으로 찍는가.**
  ///
  /// 점 개수로 솎으면 50m 표본에서 `0.05 · 0.65 · 1.25 km`가 나온다. 총 거리를
  /// 끝에 따로 붙이면 앞 눈금과 붙어 하나를 버리게 되어 간격이 들쭉날쭉해진다.
  ///
  /// 테스트 글꼴은 글자 폭이 실제와 달라 어떤 간격이 뽑히는지는 보지 않는다.
  /// 뽑힌 간격이 고른지, 서로 닿지 않는지를 본다.
  group('가로 라벨', () {
    /// [total]m까지 50m씩 닿은 거리. 50의 배수가 아니면 마지막이 짧다.
    List<int> samplesTo(int total) => [
      for (var m = 50; m <= total; m += 50) m,
      if (total % 50 != 0) total,
    ];

    /// [meters]마다 점 하나. 라벨은 닿은 거리다.
    Future<void> pumpRun(WidgetTester tester, List<int> meters) => pump(
      tester,
      values: [for (final _ in meters) 300],
      labels: [
        for (final m in meters) AppStrings.runResultSampleLabel(m / 1000),
      ],
      axisMeters: meters,
    );

    /// 폰 폭(360).
    void narrow(WidgetTester tester) {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    /// 찍힌 x축 라벨, 왼쪽부터.
    List<({double km, Rect rect})> shown(WidgetTester tester) {
      final found = find.textContaining(RegExp(r'^[\d.]+ km$'));
      final count = found.evaluate().length;
      return [
        for (var i = 0; i < count; i++)
          (
            km: double.parse(
              tester.widget<Text>(found.at(i)).data!.split(' ').first,
            ),
            rect: tester.getRect(found.at(i)),
          ),
      ]..sort((a, b) => a.rect.left.compareTo(b.rect.left));
    }

    /// 첫 라벨이 간격이고, 그 뒤로 한 간격씩 늘어나 [totalKm] 앞까지 간다.
    void expectEvenSteps(
      List<({double km, Rect rect})> labels, {
      required double totalKm,
    }) {
      expect(labels, isNotEmpty);
      final step = labels.first.km;
      for (var k = 0; k < labels.length; k++) {
        expect(labels[k].km, closeTo(step * (k + 1), 1e-9));
      }
      // 끝 눈금이 빠지면 한 간격을 더해도 총 거리에 못 미친다.
      expect(labels.last.km + step, greaterThan(totalKm));
    }

    /// 라벨끼리 16 이상 떨어져 있다.
    void expectApart(List<({double km, Rect rect})> labels) {
      for (var k = 1; k < labels.length; k++) {
        expect(
          labels[k].rect.left - labels[k - 1].rect.right,
          greaterThanOrEqualTo(AppSpacing.space4),
        );
      }
    }

    testWidgets('⚠️ 딱 떨어지는 거리에 고른 간격으로 찍는다', (tester) async {
      // 5km에서 `4 km`가 빠져 `1 · 2 · 3 · 5 km`가 되던 자리다. 기본 폭(800)은
      // 점 사이가 넓어 예전 규칙으로도 안 빠지므로 폰 폭으로 줄인다.
      narrow(tester);
      await pumpRun(tester, samplesTo(5000));

      expectEvenSteps(shown(tester), totalKm: 5);
    });

    testWidgets('⚠️ 총 거리는 눈금이 아니면 찍지 않는다', (tester) async {
      // 끝에 붙이면 `3 km`와 붙어 둘 중 하나를 버려야 한다.
      await pumpRun(tester, samplesTo(3020));

      expect(find.text('3.02 km'), findsNothing);
      expect(find.text('3 km'), findsOneWidget);
    });

    testWidgets('⚠️ 좁아도 라벨끼리 16 이상 떨어진다', (tester) async {
      narrow(tester);
      await pumpRun(tester, samplesTo(20000));

      final labels = shown(tester);
      expectEvenSteps(labels, totalKm: 20);
      expectApart(labels);
    });

    testWidgets('⚠️ 긴 러닝은 글자를 키워도 축이 비지 않는다', (tester) async {
      // 간격 후보가 10km에서 끝나면 맞는 간격이 없어 라벨이 하나도 안 남는다.
      narrow(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpRun(tester, samplesTo(50000));

      final labels = shown(tester);
      expectEvenSteps(labels, totalKm: 50);
      expectApart(labels);
    });

    testWidgets('1km 그래프도 같은 규칙으로 솎는다', (tester) async {
      // 구간 번호를 개수로 솎으면 20km에서 `1 · 5 · 9 · 13 · 20 km`가 됐다.
      narrow(tester);
      await pump(tester, values: [for (var i = 0; i < 20; i++) 300]);

      expectEvenSteps(shown(tester), totalKm: 20);
    });

    testWidgets('⚠️ 1km 그래프의 자투리 끝은 눈금이 아니다', (tester) async {
      // 2.5km도 50m의 배수라, 이어짐을 보지 않으면 50m 간격에 같이 뽑혀
      // 총 거리가 찍힌다.
      await pump(
        tester,
        values: [300, 310, 320],
        labels: const ['1 km', '2 km', '2.50 km'],
        axisMeters: const [1000, 2000, 2500],
      );

      expect(find.text('2.50 km'), findsNothing);
      expect(find.text('2 km'), findsOneWidget);
    });
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
