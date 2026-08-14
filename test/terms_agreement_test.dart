import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/consent_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/onboarding/presentation/terms_agreement_page.dart';

/// 약관 동의(S03)의 상태 전이 — 무엇을 눌렀을 때 계속하기가 열리는가.
///
/// 이 화면은 생김새보다 **규칙**이 중요하다. 필수 항목을 다 받지 않고 넘어가면
/// 동의 없이 개인정보를 수집하는 셈이 된다. 그 규칙만 본다.
///
/// 라우터를 태우지 않고 화면만 띄운다. 여기서 검증할 것은 이 화면 안의 규칙이고,
/// 화면 간 이동은 `onboarding_flow_test.dart`와 `kakao_terms_test.dart`가 본다.
void main() {
  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        // 실제 구현은 플랫폼 채널을 부른다. 테스트 환경에는 채널이 없다.
        overrides: [
          consentStoreProvider.overrideWithValue(InMemoryConsentStore()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const TermsAgreementPage(),
        ),
      ),
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

  testWidgets('필수 항목을 전부 동의하면 계속할 수 있다', (tester) async {
    await pumpPage(tester);

    await tap(tester, AppStrings.termsService);
    expect(ctaEnabled(tester), isFalse);

    await tap(tester, AppStrings.termsPrivacy);
    expect(ctaEnabled(tester), isFalse);

    // 마지막 **필수** 하나가 채워지는 순간 열린다.
    // ⚠️ 선택 항목(마케팅)은 아직 꺼져 있다. 그래도 열려야 선택이다.
    await tap(tester, AppStrings.termsHealth);
    expect(ctaEnabled(tester), isTrue);
  });

  testWidgets('선택 항목은 CTA를 막지 않는다', (tester) async {
    await pumpPage(tester);
    await tap(tester, AppStrings.termsService);
    await tap(tester, AppStrings.termsPrivacy);
    await tap(tester, AppStrings.termsHealth);

    // 켜도 꺼도 열린 채다. 여기가 깨지면 그것은 선택 항목이 아니다.
    await tap(tester, AppStrings.termsMarketing);
    expect(ctaEnabled(tester), isTrue);

    await tap(tester, AppStrings.termsMarketing);
    expect(ctaEnabled(tester), isTrue);
  });

  testWidgets('선택 항목만 동의하면 계속할 수 없다', (tester) async {
    await pumpPage(tester);

    await tap(tester, AppStrings.termsMarketing);

    expect(ctaEnabled(tester), isFalse);
  });

  testWidgets('필수만 켜면 전체 동의는 켜지지 않는다', (tester) async {
    await pumpPage(tester);
    await tap(tester, AppStrings.termsService);
    await tap(tester, AppStrings.termsPrivacy);
    await tap(tester, AppStrings.termsHealth);

    // 전체 동의가 이미 켜져 있었다면 이 탭은 **전부 해제**로 동작해 CTA가 닫힌다.
    // 꺼져 있었으므로 '전부 채우기'가 되어 열린 채로 남는다.
    await tap(tester, AppStrings.termsAgreeAll);

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
