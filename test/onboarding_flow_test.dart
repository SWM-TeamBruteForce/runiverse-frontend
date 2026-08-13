import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/core/storage/consent_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/onboarding/presentation/onboarding_intro_page.dart';
import 'package:runiverse/features/onboarding/presentation/splash_page.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/auth/presentation/sign_in_page.dart';
import 'package:runiverse/features/auth/presentation/sign_up_page.dart';
import 'package:runiverse/features/onboarding/presentation/terms_agreement_page.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/home/presentation/home_page.dart';
import 'package:runiverse/features/onboarding/presentation/profile_setup_page.dart';

/// 온보딩 흐름의 상태 전이 — 스플래시에서 소개를 거쳐 앱 본체로 들어가는가.
///
/// 화면의 생김새는 보지 않는다. 여기서 보는 건 **어디로 가느냐**다.
void main() {
  /// [repository]를 받는 것이 중요하다. `FakeAuthRepository`는 **자기가 발급한**
  /// 리프레시 토큰만 갱신해 준다. 저장소를 채운 인스턴스와 앱이 쓰는 인스턴스가
  /// 다르면 갱신이 만료로 답해서 엉뚱한 화면을 보게 된다.
  Future<void> pumpApp(
    WidgetTester tester, {
    TokenStore? store,
    FakeAuthRepository? repository,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 앱은 SecureTokenStore를 쓰는데 그것은 플랫폼 채널을 부른다.
          // 테스트에는 채널이 없어 스플래시가 갈림길을 정하지 못하고 멈춘다.
          tokenStoreProvider.overrideWithValue(store ?? InMemoryTokenStore()),
          // 약관 CTA가 동의를 기록한다. 이것을 빼면 **동의 화면을 지나는
          // 테스트만** MissingPluginException으로 죽는다 — 다른 경로는 저장소를
          // 건드리지 않아 멀쩡해 보인다.
          consentStoreProvider.overrideWithValue(InMemoryConsentStore()),
          authRepositoryProvider.overrideWithValue(
            repository ?? FakeAuthRepository(latency: Duration.zero),
          ),
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

  group('스플래시 갈림길', () {
    /// 이미 로그인해 둔 상태를 만든다.
    ///
    /// **저장소와 저장소 구현을 짝으로 돌려준다.** `FakeAuthRepository`는 자기가
    /// 발급한 토큰만 갱신해 주므로 같은 인스턴스를 앱에 넣어야 한다.
    /// ⚠️ `signIn()`을 쓰면 안 된다. `testWidgets`는 가짜 시간 위에서 도는데
    /// `pumpWidget` 전에 `Future.delayed`를 기다리면 시간을 진행시킬 `pump`가
    /// 없어 **테스트가 영원히 멈춘다.** `issueSession()`은 기다리지 않는다.
    Future<(TokenStore, FakeAuthRepository)> signedIn({
      required bool isOnboarded,
    }) async {
      final store = InMemoryTokenStore();
      final repository = FakeAuthRepository(latency: Duration.zero);
      // 씨앗 계정은 온보딩을 마친 것으로, 그 밖의 계정은 안 마친 것으로 발급된다.
      final session = repository.issueSession(
        email: isOnboarded ? FakeAuthRepository.seedEmail : 'new@example.com',
      );
      await store.saveSession(
        userId: session.userId,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        isOnboarded: session.isOnboarded,
      );
      return (store, repository);
    }

    testWidgets('토큰이 살아 있고 온보딩을 마쳤으면 홈으로 간다', (tester) async {
      final (store, repository) = await signedIn(isOnboarded: true);

      await pumpApp(tester, store: store, repository: repository);
      await tester.tap(find.byType(SplashPage));
      await tester.pumpAndSettle();

      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('온보딩을 안 마쳤으면 프로필 폼으로 간다', (tester) async {
      final (store, repository) = await signedIn(isOnboarded: false);

      await pumpApp(tester, store: store, repository: repository);
      await tester.tap(find.byType(SplashPage));
      await tester.pumpAndSettle();

      // 프로필은 **있어야 쓸 수 있다.** 매칭도 기록도 그 값들 위에 선다.
      // 로그인 화면 셋(이메일·카카오·스플래시)이 같은 기준을 쓴다.
      expect(find.byType(ProfileSetupPage), findsOneWidget);
      expect(find.byType(HomePage), findsNothing);
    });

    testWidgets('토큰이 만료됐으면 소개를 건너뛰고 로그인으로 간다', (tester) async {
      final store = InMemoryTokenStore();
      // 가짜 저장소가 발급한 적 없는 토큰이다. 갱신이 만료로 답한다.
      await store.saveSession(
        userId: 'u-1',
        accessToken: 'stale',
        refreshToken: 'stale',
        isOnboarded: true,
      );

      await pumpApp(tester, store: store);
      await tester.tap(find.byType(SplashPage));
      await tester.pumpAndSettle();

      // 이 사람은 처음 온 것이 아니다. 소개를 다시 보여주지 않는다.
      expect(find.byType(SignInPage), findsOneWidget);
      expect(find.byType(OnboardingIntroPage), findsNothing);
    });
  });
}
