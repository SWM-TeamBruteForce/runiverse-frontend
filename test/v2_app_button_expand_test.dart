import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';

/// `expand` — **가로를 꽉 채울 것인가.**
///
/// ## ⚠️ `false`가 듣지 않던 자리다
///
/// 안쪽 `Container`가 `alignment`를 갖고 있어서, **가로 제약이 유한하면 꽉
/// 채웠다.** `Column`도 `Center`도 유한한 제약을 준다 — 즉 `expand: false`는
/// 주 축 제약이 무한한 `Row` 안에서만 들었다.
///
/// 앱에서 `expand: false`를 쓰던 8곳 중 **7곳이 `Column` 안**이었다. 전부
/// 내용 크기를 바라고 쓴 것인데 화면 폭으로 늘어나 있었다.
///
/// 이 그물은 **제약이 유한한 두 자리**를 본다. `Row` 만 보면 고치기 전에도
/// 통과한다.
void main() {
  const label = '다시 시도';

  Future<Size> pump(WidgetTester tester, Widget Function(Widget) wrap) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: wrap(
            AppButtonV2(label: label, expand: false, onPressed: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getSize(find.text(label));
  }

  Future<Size> box(WidgetTester tester, Widget Function(Widget) wrap) async {
    await pump(tester, wrap);
    return tester.getSize(find.byType(InkWell));
  }

  testWidgets('⚠️ Center 안에서 내용 크기로 줄어든다', (tester) async {
    final button = await box(tester, (child) => Center(child: child));
    final text = await pump(tester, (child) => Center(child: child));

    // 글자 + 좌우 여백 24 씩. 화면 폭(800)이 나오면 안 된다.
    expect(button.width, lessThan(400));
    expect(button.width, greaterThan(text.width));
  });

  testWidgets('⚠️ Column 안에서도 줄어든다', (tester) async {
    // 앱의 `expand: false` 8곳 중 7곳이 이 모양이다.
    final button = await box(
      tester,
      (child) => Column(mainAxisSize: MainAxisSize.min, children: [child]),
    );

    expect(button.width, lessThan(400));
  });

  testWidgets('expand 가 참이면 꽉 채운다 — 기본 동작은 그대로다', (tester) async {
    final button = await box(
      tester,
      (child) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [AppButtonV2(label: label, onPressed: () {})],
      ),
    );

    expect(button.width, 800);
  });
}
