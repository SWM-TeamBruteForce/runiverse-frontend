import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/onboarding/presentation/terms_agreement_page.dart';

/// 가입 화면 — 규칙에 맞아야 버튼이 열리고, 성공하면 약관으로 간다.
void main() {
  Future<void> pumpSignUp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(latency: Duration.zero),
          ),
        ],
        child: const RuniverseApp(initialLocation: AppRoutes.signUp),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool ctaEnabled(WidgetTester tester) {
    final cta = tester.widget<AppButton>(
      find.widgetWithText(AppButton, AppStrings.authSignUpCta),
    );
    return cta.onPressed != null;
  }

  Future<void> fill(
    WidgetTester tester, {
    required String email,
    required String password,
  }) async {
    await tester.enterText(find.byType(TextField).at(0), email);
    await tester.enterText(find.byType(TextField).at(1), password);
    await tester.pumpAndSettle();
  }

  testWidgets('규칙에 맞지 않는 비밀번호로는 가입할 수 없다', (tester) async {
    await pumpSignUp(tester);
    await fill(tester, email: 'new@example.com', password: 'abcdef');

    expect(ctaEnabled(tester), isFalse);
    expect(find.text(AppStrings.authPasswordMissingKind), findsOneWidget);
  });

  testWidgets('너무 짧으면 길이 문구가 먼저 뜬다', (tester) async {
    await pumpSignUp(tester);
    await fill(tester, email: 'new@example.com', password: 'ab!');

    expect(find.text(AppStrings.authPasswordTooShort), findsOneWidget);
    expect(find.text(AppStrings.authPasswordMissingKind), findsNothing);
  });

  testWidgets('규칙을 채우면 가입할 수 있다', (tester) async {
    await pumpSignUp(tester);
    await fill(tester, email: 'new@example.com', password: 'runi123!');

    expect(ctaEnabled(tester), isTrue);
  });

  testWidgets('이미 가입한 이메일이면 막힌다', (tester) async {
    await pumpSignUp(tester);
    await fill(
      tester,
      email: FakeAuthRepository.seedEmail,
      password: 'runi123!',
    );

    await tester.tap(find.text(AppStrings.authSignUpCta));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.authFailedEmailTaken), findsOneWidget);
  });

  testWidgets('한영 변환을 깜빡한 이메일은 버튼이 열리지 않는다', (tester) async {
    await pumpSignUp(tester);
    await fill(tester, email: 'ㄱㅕㅜㅜㄷㄱ@example.com', password: 'runi123!');

    expect(ctaEnabled(tester), isFalse);
    expect(find.text(AppStrings.authEmailInvalid), findsOneWidget);
  });

  testWidgets('한글만 친 비밀번호는 규칙 문구가 뜨고 버튼이 잠긴다', (tester) async {
    await pumpSignUp(tester);
    await fill(tester, email: 'new@example.com', password: '러너러너러너');

    expect(ctaEnabled(tester), isFalse);
    expect(find.text(AppStrings.authPasswordMissingKind), findsOneWidget);
  });

  testWidgets('한글이 섞인 비밀번호로도 가입할 수 있다', (tester) async {
    await pumpSignUp(tester);
    // 백엔드 정규식이 한글을 막지 않는다. 앱만 막으면 서버가 받는 값을 못 만든다.
    await fill(tester, email: 'new@example.com', password: '러너abc12!');

    expect(ctaEnabled(tester), isTrue);

    await tester.tap(find.text(AppStrings.authSignUpCta));
    await tester.pumpAndSettle();

    expect(find.byType(TermsAgreementPage), findsOneWidget);
  });

  testWidgets('가입에 성공하면 약관으로 간다', (tester) async {
    await pumpSignUp(tester);
    await fill(tester, email: 'new@example.com', password: 'runi123!');

    await tester.tap(find.text(AppStrings.authSignUpCta));
    await tester.pumpAndSettle();

    // 가입한 사람은 신규다. 약관 → 프로필을 거쳐야 홈에 닿는다.
    expect(find.byType(TermsAgreementPage), findsOneWidget);
  });
}
