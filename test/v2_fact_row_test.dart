import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/widgets/v2/fact_row.dart';

/// `FactRowV2`가 지키는 약속.
///
/// 매칭 완료·실패 카드가 `시작 시간 · 목표거리 · 시작까지`를 이걸로 보여준다.
void main() {
  Future<void> pump(WidgetTester tester, List<Fact> facts) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 352, child: FactRowV2(facts: facts)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const three = [
    Fact(label: '시작 시간', value: '19:00'),
    Fact(label: '목표거리', value: '5 km'),
    Fact(label: '시작까지', value: '01:19:00'),
  ];

  testWidgets('라벨과 값을 짝지어 보여준다', (tester) async {
    await pump(tester, three);

    for (final fact in three) {
      expect(find.text(fact.label), findsOneWidget);
      expect(find.text(fact.value), findsOneWidget);
    }
  });

  testWidgets('⚠️ 칸을 균등하게 나눈다', (tester) async {
    // 값 길이가 제각각이다. 내용에 맞춰 폭을 주면 1초마다 바뀌는 카운트다운
    // 때문에 **다른 칸까지 좌우로 흔들린다.**
    await pump(tester, three);

    final widths = three
        .map((f) => tester.getSize(find.text(f.label)).width)
        .toList();
    final centers = three
        .map((f) => tester.getRect(find.text(f.label)).center.dx)
        .toList();

    expect(widths[0], isNot(widths[2]), reason: '글자 폭은 달라야 정상이다');
    // 칸이 균등하면 가운데끼리의 간격도 균등하다.
    expect(centers[1] - centers[0], closeTo(centers[2] - centers[1], 1));
  });

  testWidgets('⚠️ 숫자가 자릿수대로 선다', (tester) async {
    // 안 주면 `01:19:00`이 `01:18:59`로 갈릴 때 글자가 춤춘다.
    await pump(tester, three);

    final value = tester.widget<Text>(find.text('01:19:00'));
    expect(
      value.style?.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
  });

  testWidgets('⚠️ 카운트다운이 바뀌어도 칸이 안 움직인다', (tester) async {
    await pump(tester, three);
    final before = tester.getRect(find.text('5 km'));

    await pump(tester, [
      three[0],
      three[1],
      const Fact(label: '시작까지', value: '00:09:08'),
    ]);

    expect(tester.getRect(find.text('5 km')), before, reason: '가운데 칸이 밀렸다');
  });

  testWidgets('두 칸만 줘도 된다', (tester) async {
    await pump(tester, three.take(2).toList());

    expect(find.text('시작 시간'), findsOneWidget);
    expect(find.text('시작까지'), findsNothing);
  });

  testWidgets('⚠️ 모르는 값은 부르는 쪽이 정한다', (tester) async {
    // 목표 거리는 서버가 안 줄 수 있다. 여기서 0 으로 메우면 **지어낸 값**이
    // 화면에 뜬다 — 이 부품은 받은 글자를 그대로 그린다.
    await pump(tester, [const Fact(label: '목표거리', value: '-')]);

    expect(find.text('-'), findsOneWidget);
  });

  testWidgets('⚠️ 라벨이 면에 묻히지 않는다', (tester) async {
    // 시안의 `#575757`(= `textTertiary`)을 그대로 쓰면 매칭 완료 카드의
    // 밝은 파란 면 위에서 대비가 **1.1:1**이다 — 글자가 없는 것과 같다.
    // 기기에서 재고 바꾼 것이라 여기서 못 박는다.
    await pump(tester, three);

    final colors = AppColorsV2.dark;
    final label = tester.widget<Text>(find.text('시작 시간'));
    expect(label.style?.color, isNot(colors.textTertiary));
    expect(label.style?.color, colors.textSecondary);
  });
}
