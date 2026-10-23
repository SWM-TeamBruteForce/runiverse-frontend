import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';

/// `AppButtonV2Variant.danger`가 지키는 약속.
///
/// 되돌릴 수 없는 것(탈퇴)에 쓴다. **취소 버튼과 다르게 보여야** 하는 것이
/// 전부인 변형이라, 그 "다름"을 여기서 못 박는다.
///
/// ⚠️ **시안에 이 변형이 없다.** 설정·탈퇴 화면이 시안에 없어서 색을
/// `AppColorsV2.error`로 정했다 — 디자인 확인이 필요하다.
void main() {
  // ⚠️ `onPressed` 를 `?? () {}` 로 받으면 **null 을 넘겨도 활성**이 된다.
  // 잠긴 상태를 시험할 수 없어 따로 받는다.
  Future<void> pump(
    WidgetTester tester,
    AppButtonV2Variant variant, {
    VoidCallback? onPressed,
    bool enabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: AppButtonV2(
              label: '탈퇴하기',
              variant: variant,
              onPressed: enabled ? (onPressed ?? () {}) : null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Color? surfaceOf(WidgetTester tester) =>
      tester.widget<Material>(find.byType(Material).last).color;

  testWidgets('⚠️ 면이 오류 색이다', (tester) async {
    await pump(tester, AppButtonV2Variant.danger);

    expect(surfaceOf(tester), AppColorsV2.dark.error);
  });

  testWidgets('⚠️ 주 버튼과 다르게 보인다', (tester) async {
    // 되돌릴 수 없는 것이 **평범한 확인 버튼과 같은 색**이면 손이 먼저 간다.
    await pump(tester, AppButtonV2Variant.danger);
    final dangerous = surfaceOf(tester);

    await pump(tester, AppButtonV2Variant.primary);

    expect(dangerous, isNot(surfaceOf(tester)));
  });

  testWidgets('⚠️ 테두리만 두르지 않는다 — 면을 채운다', (tester) async {
    // `secondary`처럼 테두리만 두면 취소와 무게가 같아진다.
    await pump(tester, AppButtonV2Variant.danger);
    final dangerous = surfaceOf(tester);

    await pump(tester, AppButtonV2Variant.secondary);

    expect(dangerous, isNot(surfaceOf(tester)));
    expect(dangerous, isNotNull);
  });

  testWidgets('글자가 면 위에서 읽힌다', (tester) async {
    await pump(tester, AppButtonV2Variant.danger);

    final label = tester.widget<Text>(find.text('탈퇴하기'));
    expect(label.style?.color, isNot(AppColorsV2.dark.error));
  });

  testWidgets('잠기면 오류 색이 사라진다', (tester) async {
    // 못 누르는데 빨갛게 두면 위험해 보이기만 하고 할 수 있는 것이 없다.
    await pump(tester, AppButtonV2Variant.danger, enabled: false);

    expect(surfaceOf(tester), isNot(AppColorsV2.dark.error));
  });

  testWidgets('눌린다', (tester) async {
    var tapped = 0;
    await pump(tester, AppButtonV2Variant.danger, onPressed: () => tapped++);

    await tester.tap(find.text('탈퇴하기'));
    await tester.pumpAndSettle();

    expect(tapped, 1);
  });
}
