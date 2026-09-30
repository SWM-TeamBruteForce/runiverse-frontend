import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/v2/step_progress.dart';

/// `StepProgressV2`가 지키는 약속.
///
/// 이 막대가 거짓말을 하면 **몇 걸음 남았는지를 틀리게 알린다** — 가입을 그만두는
/// 사람이 생기는 자리다. 색이나 두께가 아니라 **비율**만 본다.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        // 폭을 고정한다. 비율을 재려면 트랙의 폭이 정해져 있어야 한다.
        home: Scaffold(
          body: Center(child: SizedBox(width: 364, child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double ratio(WidgetTester tester) {
    final track = tester.getSize(find.byKey(StepProgressV2.trackKey));
    final fill = tester.getSize(find.byKey(StepProgressV2.fillKey));
    return fill.width / track.width;
  }

  testWidgets('⚠️ 채움 폭이 단계에 비례한다', (tester) async {
    await pump(tester, const StepProgressV2(step: 2, total: 3));

    expect(ratio(tester), closeTo(2 / 3, 0.01));
  });

  testWidgets('첫 단계도 보인다', (tester) async {
    // 0으로 그리면 "아직 시작도 안 했다"로 읽힌다. 한 걸음은 들어와 있다.
    await pump(tester, const StepProgressV2(step: 1, total: 3));

    expect(ratio(tester), closeTo(1 / 3, 0.01));
  });

  testWidgets('마지막 단계는 꽉 찬다', (tester) async {
    await pump(tester, const StepProgressV2(step: 3, total: 3));

    expect(ratio(tester), closeTo(1, 0.01));
  });

  testWidgets('⚠️ 범위를 벗어난 값이 와도 막대가 넘치지 않는다', (tester) async {
    // 흐름이 늘거나 줄 때 부르는 쪽이 먼저 틀린다. 그때 레이아웃까지
    // 깨지면 무엇이 원인인지 찾기 어려워진다.
    await pump(tester, const StepProgressV2(step: 7, total: 3));

    expect(ratio(tester), closeTo(1, 0.01));
  });

  testWidgets('⚠️ 몇 걸음째인지 스크린리더가 읽는다', (tester) async {
    // 막대는 눈으로만 읽힌다. 값을 말로도 준다.
    //
    // 이름(label)이 아니라 값(value)으로 준다 — 진행 막대의 의미는 "무엇인가"가
    // 아니라 "얼마나 왔는가"다.
    final semantics = tester.ensureSemantics();
    await pump(tester, const StepProgressV2(step: 2, total: 3));

    expect(tester.getSemantics(find.byType(StepProgressV2)).value, '2 / 3');
    semantics.dispose();
  });
}
