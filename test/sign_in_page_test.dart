// TextField를 이름으로 찾으려면 필요하다. flutter_test는 material을 재수출하지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/home/presentation/home_page.dart';

/// 로그인 화면 — 언제 버튼이 열리고, 실패했을 때 무엇이 보이는가.
///
/// 라우터를 태워서 띄운다. 성공했을 때 **홈으로 가는지**까지가 이 화면의 계약이라
/// 화면만 떼어놓으면 그 절반을 볼 수 없다.
void main() {
  Future<void> pumpSignIn(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 지연이 있으면 pumpAndSettle이 실제로 기다린다. 테스트에서는 뺀다.
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(latency: Duration.zero),
          ),
        ],
        child: const RuniverseApp(initialLocation: AppRoutes.signIn),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// CTA가 눌리는 상태인가. [AppButton]은 `onPressed`가 null이면 비활성이다.
  bool ctaEnabled(WidgetTester tester) {
    final cta = tester.widget<AppButton>(
      find.widgetWithText(AppButton, AppStrings.authSignInCta),
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

  testWidgets('아무것도 입력하지 않으면 로그인할 수 없다', (tester) async {
    await pumpSignIn(tester);

    expect(ctaEnabled(tester), isFalse);
  });

  testWidgets('이메일 형식이 아니면 로그인할 수 없다', (tester) async {
    await pumpSignIn(tester);
    await fill(tester, email: 'runner@', password: 'runi123!');

    expect(ctaEnabled(tester), isFalse);
  });

  testWidgets('이메일과 비밀번호가 채워지면 로그인할 수 있다', (tester) async {
    await pumpSignIn(tester);
    await fill(
      tester,
      email: FakeAuthRepository.seedEmail,
      password: FakeAuthRepository.seedPassword,
    );

    expect(ctaEnabled(tester), isTrue);
  });

  testWidgets('로그인 화면은 비밀번호 규칙을 따지지 않는다', (tester) async {
    await pumpSignIn(tester);
    // 규칙이 바뀌기 전에 만든 계정은 지금 규칙을 통과하지 못할 수 있다.
    // 로그인에서 규칙을 들이대면 그 사람은 자기 계정에 영영 못 들어간다.
    await fill(tester, email: FakeAuthRepository.seedEmail, password: 'a');

    expect(ctaEnabled(tester), isTrue);
  });

  testWidgets('비밀번호가 틀리면 실패 문구가 뜬다', (tester) async {
    await pumpSignIn(tester);
    await fill(
      tester,
      email: FakeAuthRepository.seedEmail,
      password: 'wrong123!',
    );

    await tester.tap(find.text(AppStrings.authSignInCta));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.authFailedCredentials), findsOneWidget);
    // 실패했는데 화면이 넘어가면 안 된다.
    expect(find.byType(HomePage), findsNothing);
  });

  testWidgets('로그인에 성공하면 홈으로 간다', (tester) async {
    await pumpSignIn(tester);
    await fill(
      tester,
      email: FakeAuthRepository.seedEmail,
      password: FakeAuthRepository.seedPassword,
    );

    await tester.tap(find.text(AppStrings.authSignInCta));
    await tester.pumpAndSettle();

    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('다시 입력하면 이전 실패 문구가 사라진다', (tester) async {
    await pumpSignIn(tester);
    await fill(
      tester,
      email: FakeAuthRepository.seedEmail,
      password: 'wrong123!',
    );
    await tester.tap(find.text(AppStrings.authSignInCta));
    await tester.pumpAndSettle();

    // 고치는 중에도 빨간 글씨가 남아 있으면 방금 고친 것이 반영됐는지 알 수 없다.
    await fill(
      tester,
      email: FakeAuthRepository.seedEmail,
      password: FakeAuthRepository.seedPassword,
    );

    expect(find.text(AppStrings.authFailedCredentials), findsNothing);
  });
}
