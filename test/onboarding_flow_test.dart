import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/onboarding/presentation/onboarding_intro_page.dart';
import 'package:runiverse/features/onboarding/presentation/splash_page.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/auth/presentation/sign_in_page.dart';
import 'package:runiverse/features/auth/presentation/sign_up_page.dart';
import 'package:runiverse/features/onboarding/presentation/terms_agreement_page.dart';

/// 온보딩 흐름의 상태 전이 — 스플래시에서 소개를 거쳐 앱 본체로 들어가는가.
///
/// 화면의 생김새는 보지 않는다. 여기서 보는 건 **어디로 가느냐**다.
void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 앱은 SecureTokenStore를 쓰는데 그것은 플랫폼 채널을 부른다.
          // 테스트에는 채널이 없어 스플래시가 갈림길을 정하지 못하고 멈춘다.
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        ],
        child: const RuniverseApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('앱의 첫 화면은 스플래시다', (tester) async {
    await pumpApp(tester);

    expect(find.byType(SplashPage), findsOneWidget);
    expect(find.text(AppStrings.brandName), findsOneWidget);
  });

  testWidgets('스플래시는 1.6초 뒤 저절로 온보딩으로 넘어간다', (tester) async {
    await pumpApp(tester);

    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingIntroPage), findsOneWidget);
  });

  testWidgets('스플래시를 누르면 기다리지 않고 넘어간다', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byType(SplashPage));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingIntroPage), findsOneWidget);
  });

  testWidgets('마지막 카드에서 버튼 라벨이 시작하기로 바뀐다', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byType(SplashPage));
    await tester.pumpAndSettle();

    // 1장 → 2장 → 3장
    expect(find.text(AppStrings.onboardingNext), findsOneWidget);
    await tester.tap(find.text(AppStrings.onboardingNext));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.onboardingNext));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.onboardingNext), findsNothing);
    expect(find.text(AppStrings.onboardingStart), findsOneWidget);
  });

  testWidgets('건너뛰기는 카드를 다 보지 않고 로그인으로 넘어간다', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byType(SplashPage));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.onboardingSkip));
    await tester.pumpAndSettle();

    // 소개는 건너뛸 수 있어도 로그인은 건너뛸 수 없다.
    // 약관(S03)은 **가입하는 사람만** 지나가므로 여기서 뜨지 않는다.
    expect(find.byType(SignInPage), findsOneWidget);
  });

  testWidgets('가입은 약관 동의부터 시작한다', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byType(SplashPage));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.onboardingSkip));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.authToSignUp));
    await tester.pumpAndSettle();

    // 이메일·비밀번호를 받기 **전에** 동의를 받는다.
    // 순서가 반대면 동의를 묻기도 전에 개인정보가 서버에 저장된다.
    expect(find.byType(TermsAgreementPage), findsOneWidget);
    expect(find.byType(SignUpPage), findsNothing);
  });

  testWidgets('약관에 동의하면 정보 입력으로 넘어간다', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byType(SplashPage));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.onboardingSkip));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.authToSignUp));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.termsAgreeAll));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.termsCta));
    await tester.pumpAndSettle();

    expect(find.byType(SignUpPage), findsOneWidget);
  });

  testWidgets('정보 입력에서 뒤로 가면 동의한 것이 남아 있다', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byType(SplashPage));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.onboardingSkip));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.authToSignUp));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.termsAgreeAll));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.termsCta));
    await tester.pumpAndSettle();

    // `pageBack()`은 AppBar의 기본 뒤로가기를 찾는다. 이 화면들은 직접 만든
    // IconButton을 쓰므로 그것을 누른다. 화면을 특정하지 않으면 아래에 깔린
    // 약관 화면의 뒤로가기까지 함께 잡힌다 — push로 쌓인 화면은 트리에 남아 있다.
    await tester.tap(
      find.descendant(
        of: find.byType(SignUpPage),
        matching: find.byTooltip(AppStrings.authBack),
      ),
    );
    await tester.pumpAndSettle();

    // 정보 입력이 사라진 것이 **되돌아왔다는 증거**다.
    // 약관 화면이 보이는 것만으로는 부족하다 — 쌓여 있는 동안에도 트리에 있다.
    expect(find.byType(SignUpPage), findsNothing);
    expect(find.byType(TermsAgreementPage), findsOneWidget);

    // 동의가 남아 있어야 한다. `go`로 넘어갔다면 약관 화면이 새로 만들어져
    // 체크가 풀리고, 사용자는 같은 일을 두 번 하게 된다.
    final cta = tester.widget<AppButton>(
      find.widgetWithText(AppButton, AppStrings.termsCta),
    );
    expect(cta.onPressed, isNotNull);
  });
}
