import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/onboarding/presentation/profile_setup_page.dart';

/// 가입 2 · 정보 입력 — 규칙에 맞아야 버튼이 열리고, 성공하면 프로필로 간다.
///
/// 약관 동의는 이 화면 **앞**에 있다. 여기 온 사람은 이미 동의한 사람이다.
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

  testWidgets('한글만 친 비밀번호는 버튼이 잠긴다', (tester) async {
    await pumpSignUp(tester);
    await fill(tester, email: 'new@example.com', password: '러너러너러너');

    expect(ctaEnabled(tester), isFalse);
    // 길이가 아니라 **쓸 수 있는 글자**를 먼저 알린다.
    expect(find.text(AppStrings.authPasswordDisallowedChar), findsOneWidget);
  });

  testWidgets('한글이 한 글자만 섞여도 가입할 수 없다', (tester) async {
    await pumpSignUp(tester);
    // 나머지가 규칙을 다 채워도 소용없다.
    await fill(tester, email: 'new@example.com', password: '러너abc12!');

    expect(ctaEnabled(tester), isFalse);
    expect(find.text(AppStrings.authPasswordDisallowedChar), findsOneWidget);
  });

  testWidgets('가입에 성공하면 프로필 등록으로 간다', (tester) async {
    await pumpSignUp(tester);
    await fill(tester, email: 'new@example.com', password: 'runi123!');

    await tester.tap(find.text(AppStrings.authSignUpCta));
    await tester.pumpAndSettle();

    // 약관은 앞에서 받았다. 남은 것은 프로필뿐이다.
    expect(find.byType(ProfileSetupPage), findsOneWidget);
  });
}
