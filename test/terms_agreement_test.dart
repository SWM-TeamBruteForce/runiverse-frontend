import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/onboarding/presentation/terms_agreement_page.dart';

/// 약관 동의(S03)의 상태 전이 — 무엇을 눌렀을 때 계속하기가 열리는가.
///
/// 이 화면은 생김새보다 **규칙**이 중요하다. 필수 항목을 다 받지 않고 넘어가면
/// 동의 없이 개인정보를 수집하는 셈이 된다. 그 규칙만 본다.
///
/// 라우터를 태우지 않고 화면만 띄운다. 여기서 검증할 것은 이 화면 안의 규칙이고,
/// 화면 간 이동은 `onboarding_flow_test.dart`가 본다.
void main() {
  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const TermsAgreementPage()),
    );
    await tester.pumpAndSettle();
  }

  /// CTA가 눌리는 상태인가. [AppButton]은 `onPressed`가 null이면 비활성이다.
  bool ctaEnabled(WidgetTester tester) =>
      tester.widget<AppButton>(find.byType(AppButton)).onPressed != null;

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('아무것도 동의하지 않으면 계속할 수 없다', (tester) async {
    await pumpPage(tester);

    expect(ctaEnabled(tester), isFalse);
  });

  testWidgets('전체 동의를 누르면 계속할 수 있다', (tester) async {
    await pumpPage(tester);
    await tap(tester, AppStrings.termsAgreeAll);

    expect(ctaEnabled(tester), isTrue);
  });

  testWidgets('전체 동의를 한 번 더 누르면 전부 해제된다', (tester) async {
    await pumpPage(tester);
    await tap(tester, AppStrings.termsAgreeAll);
    await tap(tester, AppStrings.termsAgreeAll);

    expect(ctaEnabled(tester), isFalse);
  });

  testWidgets('개별 항목을 전부 동의해도 계속할 수 있다', (tester) async {
    await pumpPage(tester);

    await tap(tester, AppStrings.termsService);
    expect(ctaEnabled(tester), isFalse);

    await tap(tester, AppStrings.termsPrivacy);
    expect(ctaEnabled(tester), isFalse);

    // 마지막 하나가 채워지는 순간 열린다.
    await tap(tester, AppStrings.termsHealth);
    expect(ctaEnabled(tester), isTrue);
  });

  testWidgets('하나라도 해제하면 다시 계속할 수 없다', (tester) async {
    await pumpPage(tester);
    await tap(tester, AppStrings.termsAgreeAll);

    await tap(tester, AppStrings.termsPrivacy);

    expect(ctaEnabled(tester), isFalse);
  });

  testWidgets('일부만 동의한 상태에서 전체 동의를 누르면 나머지가 채워진다', (tester) async {
    await pumpPage(tester);

    // 3개 중 1개만 켠 상태.
    await tap(tester, AppStrings.termsService);
    expect(ctaEnabled(tester), isFalse);

    // 이때 전체 동의는 **해제가 아니라 전부 채우기**여야 한다.
    // 반대로 동작하면 사용자는 한 항목을 골랐다는 이유로 되레 뒤로 밀린다.
    await tap(tester, AppStrings.termsAgreeAll);
    expect(ctaEnabled(tester), isTrue);
  });
}
