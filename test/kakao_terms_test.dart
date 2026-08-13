import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/storage/consent_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/data/fake_oauth_code_source.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/sign_in_page.dart';
import 'package:runiverse/features/onboarding/presentation/profile_setup_page.dart';
import 'package:runiverse/features/onboarding/presentation/terms_agreement_page.dart';

/// 카카오 로그인 앞에 약관이 서는가 — **이 PR의 이유 전부.**
///
/// 카카오 화면에서 받는 동의는 *카카오가 우리에게 이메일을 넘기는 것*에 대한
/// 동의다. 우리 약관을 갈음하지 못한다. 그래서 앱이 따로 받는다.
///
/// ⚠️ **인가가 끝나면 서버가 곧바로 계정을 만들고 이메일을 저장한다.**
/// 그러므로 "동의 전에 인가하지 않는다"가 여기서 가장 중요한 확인이다.
/// 그것이 새면 이 작업 전체가 무의미하다.
void main() {
  /// 로그인 화면을 띄운다. [agreed]가 이 기기가 이미 동의했는지다.
  ///
  /// 인가가 실제로 나갔는지는 [FakeOauthCodeSource.callCount]로 본다 —
  /// 화면에 무엇이 보이는가보다 **SDK를 불렀는가**가 정확한 질문이다.
  Future<({FakeOauthCodeSource kakao, InMemoryConsentStore consent})>
  pumpSignIn(WidgetTester tester, {required bool agreed}) async {
    final consent = InMemoryConsentStore();
    if (agreed) await consent.markTermsAgreed();
    final codeSource = FakeOauthCodeSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          consentStoreProvider.overrideWithValue(consent),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(latency: Duration.zero),
          ),
          oauthCodeSourceProvider.overrideWithValue(codeSource),
        ],
        child: const RuniverseApp(initialLocation: AppRoutes.signIn),
      ),
    );
    await tester.pumpAndSettle();
    return (kakao: codeSource, consent: consent);
  }

  Future<void> tapKakao(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(AppButton, AppStrings.authKakao));
    await tester.pumpAndSettle();
  }

  testWidgets('동의한 적이 없으면 약관 화면이 먼저 뜬다', (tester) async {
    await pumpSignIn(tester, agreed: false);

    await tapKakao(tester);

    expect(find.byType(TermsAgreementPage), findsOneWidget);
  });

  testWidgets('⚠️ 동의 전에는 카카오 인가를 부르지 않는다', (tester) async {
    final app = await pumpSignIn(tester, agreed: false);

    await tapKakao(tester);

    // 여기가 깨지면 동의를 묻는 사이에 이미 계정이 만들어진다.
    // 약관 화면이 보이는 것만으로는 부족하다 — 인가가 함께 나갔을 수 있다.
    expect(app.kakao.callCount, 0);
    expect(find.byType(ProfileSetupPage), findsNothing);
  });

  testWidgets('동의를 마치면 인가가 시작되고 프로필 폼으로 간다', (tester) async {
    final app = await pumpSignIn(tester, agreed: false);
    await tapKakao(tester);

    await tester.tap(find.text(AppStrings.termsAgreeAll));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.termsCta));
    await tester.pumpAndSettle();

    expect(app.kakao.callCount, 1);
    // 카카오 첫 로그인은 가입이다. 프로필을 채워야 앱을 쓸 수 있다.
    expect(find.byType(ProfileSetupPage), findsOneWidget);
  });

  testWidgets('약관에서 뒤로 나오면 인가하지 않는다', (tester) async {
    final app = await pumpSignIn(tester, agreed: false);
    await tapKakao(tester);

    // 동의하지 않고 물러났다. 그만둔 사람을 인가로 밀어 넣지 않는다.
    await tester.tap(find.byTooltip(AppStrings.authBack));
    await tester.pumpAndSettle();

    expect(app.kakao.callCount, 0);
    expect(find.byType(SignInPage), findsOneWidget);
  });

  testWidgets('이미 동의했으면 약관 없이 곧바로 인가한다', (tester) async {
    final app = await pumpSignIn(tester, agreed: true);

    await tapKakao(tester);

    // 같은 것을 두 번 묻지 않는다.
    expect(find.byType(TermsAgreementPage), findsNothing);
    expect(app.kakao.callCount, 1);
    // 카카오 첫 로그인은 가입이다. 프로필을 채워야 앱을 쓸 수 있다.
    expect(find.byType(ProfileSetupPage), findsOneWidget);
  });

  testWidgets('동의하면 기록이 남아 다음부터 묻지 않는다', (tester) async {
    final app = await pumpSignIn(tester, agreed: false);
    await tapKakao(tester);

    await tester.tap(find.text(AppStrings.termsAgreeAll));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.termsCta));
    await tester.pumpAndSettle();

    // 저장소를 직접 본다. 화면을 다시 띄워 확인하려 하면 라우터가 이미 홈에
    // 가 있어 로그인 화면으로 돌아오지 않는다 — 그 경로는 에뮬레이터가 본다.
    //
    // 여기가 깨지면 다음 로그인에서 약관을 또 보게 된다.
    expect(await app.consent.hasAgreedTerms(), isTrue);
  });

  testWidgets('동의하지 않고 물러나면 기록도 남지 않는다', (tester) async {
    final app = await pumpSignIn(tester, agreed: false);
    await tapKakao(tester);

    await tester.tap(find.byTooltip(AppStrings.authBack));
    await tester.pumpAndSettle();

    // 화면을 봤다는 것과 동의했다는 것은 다르다.
    expect(await app.consent.hasAgreedTerms(), isFalse);
  });

  testWidgets('마케팅에 동의하지 않아도 카카오로 들어갈 수 있다', (tester) async {
    final app = await pumpSignIn(tester, agreed: false);
    await tapKakao(tester);

    // 필수 3개만 켠다. 선택이 CTA를 막으면 그것은 선택이 아니다.
    await tester.tap(find.text(AppStrings.termsService));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.termsPrivacy));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.termsHealth));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.termsCta));
    await tester.pumpAndSettle();

    expect(app.kakao.callCount, 1);
    // 카카오 첫 로그인은 가입이다. 프로필을 채워야 앱을 쓸 수 있다.
    expect(find.byType(ProfileSetupPage), findsOneWidget);
  });
}
